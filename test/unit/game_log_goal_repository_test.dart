import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/database/database.dart';
import 'package:w_baseball/data/models/game_log.dart';
import 'package:w_baseball/data/repositories/game_log_goal_repository.dart';

/// "다음 경기에서 해볼 것" — the player's own goal, reflected back unedited.
///
/// The rule this file exists to pin: the app never decides whether she did
/// the thing. Every outcome here (`done`/`carried`/`dropped`/null) is the
/// direct result of one specific repository call, mirroring exactly one
/// button on the reflection card (or, for null, no button at all — see
/// [setGoal]'s doc). If any of these ever produced the wrong outcome, or a
/// second goal ever stayed open alongside a first, that would be the app
/// quietly judging her ("carried" where it should be silent, or vice versa)
/// rather than just holding her words.
void main() {
  late WbDatabase db;
  late DriftGameLogGoalRepository repo;
  var clockValue = DateTime.utc(2026, 8, 23, 21);

  setUp(() {
    db = WbDatabase(NativeDatabase.memory());
    repo = DriftGameLogGoalRepository(db: db, clock: () => clockValue);
  });

  tearDown(() => db.close());

  group('setGoal', () {
    test('빈 문자열은 아무 것도 쓰지 않는다', () async {
      await repo.setGoal(body: '   ');
      expect(await repo.watchOpenGoal().first, isNull);
      expect(await repo.allGoals(), isEmpty);
    });

    test('처음 쓴 목표는 열린 채로 저장된다', () async {
      await repo.setGoal(body: '초구 공략', entryId: 7);
      final open = await repo.watchOpenGoal().first;
      expect(open, isNotNull);
      expect(open!.body, '초구 공략');
      expect(open.entryId, 7);
      expect(open.isOpen, isTrue);
      expect(open.outcome, isNull);
    });

    test('앞뒤 공백은 저장 전에 잘려나간다', () async {
      await repo.setGoal(body: '  초구 공략  ');
      expect((await repo.watchOpenGoal().first)!.body, '초구 공략');
    });

    test('이미 열린 목표가 있을 때 새로 쓰면, 이전 것은 물어보지 않고 outcome null로 닫힌다', () async {
      // Mutation target: if this ever wrote `outcome: 'carried'` here
      // instead of leaving it null, a silently-superseded goal would read
      // exactly like one she explicitly chose to carry forward — the two
      // must stay distinguishable in the data even though neither is shown
      // as a list on screen.
      await repo.setGoal(body: '초구 공략');
      final firstOpen = (await repo.allGoals()).single;

      clockValue = DateTime.utc(2026, 8, 30, 21);
      await repo.setGoal(body: '병살 완성', entryId: 12);

      final all = await repo.allGoals();
      expect(all, hasLength(2));

      final closed = all.firstWhere((g) => g.id == firstOpen.id);
      expect(closed.isOpen, isFalse);
      expect(closed.closedAt!.toUtc(), clockValue);
      expect(closed.outcome, isNull);

      final open = await repo.watchOpenGoal().first;
      expect(open!.body, '병살 완성');
      expect(open.entryId, 12);
    });

    test('열린 목표는 언제나 하나뿐이다', () async {
      await repo.setGoal(body: '하나');
      await repo.setGoal(body: '둘');
      await repo.setGoal(body: '셋');

      final all = await repo.allGoals();
      final open = all.where((g) => g.isOpen).toList();
      expect(open, hasLength(1));
      expect(open.single.body, '셋');
    });
  });

  group('markDone — 했어요', () {
    test('outcome done으로 닫히고, 새 목표는 열리지 않는다', () async {
      await repo.setGoal(body: '초구 공략');
      final goal = (await repo.watchOpenGoal().first)!;

      clockValue = DateTime.utc(2026, 8, 24);
      await repo.markDone(goal.id);

      expect(await repo.watchOpenGoal().first, isNull);
      final closed = (await repo.allGoals()).single;
      expect(closed.outcome, GameLogGoalOutcome.done);
      expect(closed.closedAt!.toUtc(), clockValue);
    });
  });

  group('dropGoal — 지우기', () {
    test('outcome dropped으로 닫히고, 새 목표는 열리지 않는다', () async {
      await repo.setGoal(body: '초구 공략');
      final goal = (await repo.watchOpenGoal().first)!;

      await repo.dropGoal(goal.id);

      expect(await repo.watchOpenGoal().first, isNull);
      final closed = (await repo.allGoals()).single;
      expect(closed.outcome, GameLogGoalOutcome.dropped);
    });
  });

  group('carryForward — 다음에도', () {
    test('outcome carried로 닫히고, 같은 문장으로 새 목표가 열린다', () async {
      // Mutation target: if this ever failed to open a new goal, "다음에도"
      // would behave exactly like "지우기" — the one distinction the
      // feature brief calls out by name ("계속 가져가는 것").
      await repo.setGoal(body: '초구 공략', entryId: 3);
      final goal = (await repo.watchOpenGoal().first)!;

      clockValue = DateTime.utc(2026, 8, 30, 21);
      await repo.carryForward(id: goal.id, body: goal.body);

      final all = await repo.allGoals();
      expect(all, hasLength(2));

      final closed = all.firstWhere((g) => g.id == goal.id);
      expect(closed.outcome, GameLogGoalOutcome.carried);
      expect(closed.closedAt!.toUtc(), clockValue);

      final reopened = await repo.watchOpenGoal().first;
      expect(reopened, isNotNull);
      expect(reopened!.body, '초구 공략');
      // Not tied to the original game any more — see `GameLogGoals.entryId`.
      expect(reopened.entryId, isNull);
      expect(reopened.id, isNot(goal.id));
    });
  });

  group('watchOpenGoal', () {
    test('아무 것도 쓴 적이 없으면 null이다', () async {
      expect(await repo.watchOpenGoal().first, isNull);
    });
  });
}
