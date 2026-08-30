import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/platform/notification_scheduler.dart';
import 'package:w_baseball/core/platform/notification_service.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/data/models/domain.dart';
import 'package:w_baseball/data/repositories/follow_repository.dart';
import 'package:w_baseball/data/repositories/game_repository.dart';

/// The scheduler is the seam between a pure planner and a platform plugin, and
/// seams are where behaviour goes missing without anything failing loudly.
///
/// The planner's own rules (lead times, quiet hours, spoiler masking) are
/// covered in `rules_test.dart`. What matters here is narrower and easier to
/// get wrong: *which fixtures* reach the planner at all.
void main() {
  Provenance provenance() => Provenance(
    sourceName: 'demo-fixture',
    sourceUrl: 'app://demo/fixture',
    fetchedAt: DateTime.utc(2026, 8, 30),
    isDemo: true,
  );

  Team team(String id) =>
      Team(id: id, name: id, shortName: id, provenance: provenance());

  GameCard card(String id, String homeId, String awayId, DateTime startUtc) {
    return GameCard(
      game: Game(
        id: id,
        startTimeUtc: startUtc,
        status: GameStatus.scheduled,
        homeTeamId: homeId,
        awayTeamId: awayId,
        provenance: provenance(),
      ),
      homeTeam: team(homeId),
      awayTeam: team(awayId),
    );
  }

  const allCategoriesOn = NotificationPreference(
    enabled: <NotificationCategory>{
      NotificationCategory.myTeamGameWeek,
      NotificationCategory.myTeamGameDay,
      NotificationCategory.myTeamGameHour,
    },
    permissionRequested: true,
  );

  late _FakeGames games;
  late _FakeFollows follows;
  late _RecordingService service;
  late NotificationScheduler scheduler;

  setUp(() {
    final soon = DateTime.now().toUtc().add(const Duration(days: 3));
    games = _FakeGames(<GameCard>[
      card('game-1', 'team-a', 'team-b', soon),
      card('game-2', 'team-c', 'team-d', soon.add(const Duration(days: 1))),
    ]);
    follows = _FakeFollows();
    service = _RecordingService();
    scheduler = NotificationScheduler(
      games: games,
      follows: follows,
      notifications: service,
    );
  });

  test('팔로우도 저장도 없으면 아무것도 예약하지 않는다', () async {
    final count = await scheduler.reschedule(allCategoriesOn);

    expect(count, 0);
    // The empty reconcile still has to happen: it is what cancels alerts left
    // over from a team the user has since unfollowed.
    expect(service.calls, 1);
    expect(service.lastPlan, isEmpty);
    // The critical part. An empty `teamIds` means "every team" to the query, so
    // querying at all here would schedule an alert for every fixture in the
    // league — the loudest possible bug.
    expect(games.queries, isEmpty, reason: '아무 것도 조회하지 않아야 합니다');
  });

  test('팔로우한 팀의 경기만 조회한다', () async {
    await follows.follow(FollowKind.team, 'team-a');

    await scheduler.reschedule(allCategoriesOn);

    expect(games.queries, hasLength(1));
    expect(games.queries.single.teamIds, <String>['team-a']);
    expect(service.lastPlan, isNotEmpty);
  });

  test('저장한 경기는 팀을 팔로우하지 않아도 예약 대상이 된다', () async {
    // Wanting one fixture is not the same as adopting a team's whole schedule.
    await follows.toggleSaved(SavedItemKind.game, 'game-2');

    await scheduler.reschedule(allCategoriesOn);

    final entityIds = service.lastPlan.map((p) => p.entityId).toSet();
    expect(entityIds, contains('game-2'));
    expect(entityIds, isNot(contains('game-1')));
  });

  test('팔로우와 저장이 겹쳐도 중복 예약하지 않는다', () async {
    await follows.follow(FollowKind.team, 'team-a');
    await follows.toggleSaved(SavedItemKind.game, 'game-1');

    await scheduler.reschedule(allCategoriesOn);

    final ids = service.lastPlan.map((p) => p.id).toList();
    expect(ids.length, ids.toSet().length, reason: '같은 알림이 두 번 예약되면 안 됩니다');
  });

  test('카테고리를 모두 끄면 예약이 사라진다', () async {
    await follows.follow(FollowKind.team, 'team-a');

    const nothingOn = NotificationPreference(
      enabled: <NotificationCategory>{},
      permissionRequested: true,
    );
    final count = await scheduler.reschedule(nothingOn);

    expect(count, 0);
    expect(service.lastPlan, isEmpty);
  });

  test('예보 지평 밖의 경기는 조회 범위에 들어오지 않는다', () async {
    await follows.follow(FollowKind.team, 'team-a');

    await scheduler.reschedule(allCategoriesOn);

    final query = games.queries.single;
    final span = query.toUtc!.difference(query.fromUtc!);
    expect(
      span.inDays,
      lessThanOrEqualTo(31),
      reason: '플랫폼 예약 한도를 넘지 않도록 창을 제한해야 합니다',
    );
  });
}

/// Returns a fixed fixture list and records every query it was asked.
class _FakeGames implements GameRepository {
  _FakeGames(this._cards);

  final List<GameCard> _cards;
  final List<GameQuery> queries = <GameQuery>[];

  @override
  Stream<List<GameCard>> watchGames(GameQuery query) {
    queries.add(query);
    if (query.teamIds.isEmpty) return Stream<List<GameCard>>.value(_cards);
    return Stream<List<GameCard>>.value(
      _cards
          .where(
            (c) =>
                query.teamIds.contains(c.game.homeTeamId) ||
                query.teamIds.contains(c.game.awayTeamId),
          )
          .toList(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

/// In-memory follows and saves.
class _FakeFollows implements FollowRepository {
  final Map<FollowKind, Set<String>> _follows = <FollowKind, Set<String>>{};
  final Map<SavedItemKind, Set<String>> _saved = <SavedItemKind, Set<String>>{};

  @override
  Future<void> follow(FollowKind kind, String entityId, {String? label}) async {
    _follows.putIfAbsent(kind, () => <String>{}).add(entityId);
  }

  @override
  Stream<Set<String>> watchFollowedIds(FollowKind kind) =>
      Stream<Set<String>>.value(_follows[kind] ?? const <String>{});

  @override
  Future<bool> toggleSaved(
    SavedItemKind kind,
    String entityId, {
    String? note,
  }) async {
    final set = _saved.putIfAbsent(kind, () => <String>{});
    if (!set.add(entityId)) {
      set.remove(entityId);
      return false;
    }
    return true;
  }

  @override
  Stream<Set<String>> watchSavedIds(SavedItemKind kind) =>
      Stream<Set<String>>.value(_saved[kind] ?? const <String>{});

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

/// Captures what the scheduler asked the platform to do.
class _RecordingService implements NotificationService {
  int calls = 0;
  List<PlannedNotification> lastPlan = const <PlannedNotification>[];

  @override
  Future<void> reconcile(List<PlannedNotification> planned) async {
    calls++;
    lastPlan = planned;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
