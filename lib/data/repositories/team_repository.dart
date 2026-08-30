import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../core/database/database.dart';
import '../../core/utils/korean_text.dart';
import '../mappers/row_mappers.dart';
import '../models/content.dart';
import '../models/domain.dart';
import '../models/stats.dart';
import 'game_repository.dart';

@immutable
class TeamQuery {
  const TeamQuery({
    this.text = '',
    this.regions = const <String>[],
    this.recruitingOnly = false,
    this.followedOnly = false,
    this.limit,
  });

  final String text;
  final List<String> regions;
  final bool recruitingOnly;
  final bool followedOnly;
  final int? limit;

  bool get hasFilters =>
      text.trim().isNotEmpty ||
      regions.isNotEmpty ||
      recruitingOnly ||
      followedOnly;

  TeamQuery copyWith({
    String? text,
    List<String>? regions,
    bool? recruitingOnly,
    bool? followedOnly,
    int? limit,
  }) => TeamQuery(
    text: text ?? this.text,
    regions: regions ?? this.regions,
    recruitingOnly: recruitingOnly ?? this.recruitingOnly,
    followedOnly: followedOnly ?? this.followedOnly,
    limit: limit ?? this.limit,
  );

  /// Value equality, for the same reason as [GameQuery]: this is a Riverpod
  /// family key.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeamQuery &&
          other.text == text &&
          const ListEquality<String>().equals(other.regions, regions) &&
          other.recruitingOnly == recruitingOnly &&
          other.followedOnly == followedOnly &&
          other.limit == limit;

  @override
  int get hashCode => Object.hash(
    text,
    const ListEquality<String>().hash(regions),
    recruitingOnly,
    followedOnly,
    limit,
  );
}

abstract interface class TeamRepository {
  Stream<List<Team>> watchTeams(TeamQuery query);

  Stream<TeamDetail?> watchTeam(String teamId);

  /// Distinct region codes that actually have teams, for the filter chips.
  Stream<List<String>> watchRegions();

  /// Recent form plus rank movement for a team in a season.
  Future<TeamStandingDetail?> standingDetail(String teamId, String seasonId);

  /// Resolves any known spelling of a team name to its canonical id.
  Future<String?> resolveAlias(String name);
}

class DriftTeamRepository implements TeamRepository {
  DriftTeamRepository({
    required this.db,
    required this.gameRepository,
    required this.clock,
  });

  final WbDatabase db;
  final GameRepository gameRepository;

  /// Injected rather than `DateTime.now()`, because "next three fixtures" is
  /// defined by where the clock sits: let it run and a fixture crosses the
  /// boundary mid-test, so the same screen renders differently one hour later.
  final DateTime Function() clock;

  @override
  Stream<List<Team>> watchTeams(TeamQuery query) {
    final select = db.select(db.teams)..where((t) => t.deletedAt.isNull());

    if (query.regions.isNotEmpty) {
      select.where((t) => t.region.isIn(query.regions));
    }
    if (query.recruitingOnly) {
      select.where(
        (t) => t.recruitment.equals(RecruitmentStatus.open.wireValue),
      );
    }

    // Both the plain name and its 초성 live in `searchKey`, so one indexed
    // LIKE covers "서울", "서울다이아", and "ㅅㅇ".
    final q = KoreanText.queryKey(query.text);
    if (q.isNotEmpty) {
      select.where((t) => t.searchKey.like('%$q%'));
    }

    select.orderBy([
      (t) => OrderingTerm(expression: t.region),
      (t) => OrderingTerm(expression: t.name),
    ]);

    final base = select.watch();
    if (!query.followedOnly) {
      return base.map((rows) => _limit(rows, query));
    }

    final follows =
        (db.select(db.localFollows)..where((t) => t.kind.equals('team')))
            .watch()
            .map((rows) => rows.map((r) => r.entityId).toSet());

    return base.asyncMap((rows) async {
      final ids = await follows.first;
      return _limit(rows.where((r) => ids.contains(r.id)).toList(), query);
    });
  }

  List<Team> _limit(List<TeamRow> rows, TeamQuery query) {
    final mapped = rows.map((r) => r.toDomain()).toList(growable: false);
    if (query.limit == null || mapped.length <= query.limit!) return mapped;
    return mapped.sublist(0, query.limit!);
  }

  @override
  Stream<List<String>> watchRegions() {
    final query = db.selectOnly(db.teams)
      ..addColumns([db.teams.region])
      ..where(db.teams.deletedAt.isNull() & db.teams.region.isNotNull())
      ..groupBy([db.teams.region])
      ..orderBy([OrderingTerm(expression: db.teams.region)]);
    return query.watch().map(
      (rows) => rows
          .map((r) => r.read(db.teams.region))
          .whereType<String>()
          .toList(growable: false),
    );
  }

  @override
  Stream<TeamDetail?> watchTeam(String teamId) {
    final select = db.select(db.teams)..where((t) => t.id.equals(teamId));
    return select.watchSingleOrNull().asyncMap((row) async {
      if (row == null) return null;
      final team = row.toDomain();

      final venue = team.homeVenueId == null
          ? null
          : await (db.select(
              db.venues,
            )..where((t) => t.id.equals(team.homeVenueId!))).getSingleOrNull();

      // Next and recent fixtures come from the game repository so the join
      // logic and favourite marking stay in exactly one place.
      final next = await gameRepository
          .watchGames(
            GameQuery(
              teamIds: <String>[teamId],
              fromUtc: clock(),
              limit: 3,
            ),
          )
          .first;

      final recent = await gameRepository
          .watchGames(
            GameQuery(
              teamIds: <String>[teamId],
              toUtc: clock(),
              ascending: false,
              limit: 5,
            ),
          )
          .first;

      final teamSeasonRows = await (db.select(
        db.teamSeasons,
      )..where((t) => t.teamId.equals(teamId))).get();
      final seasonIds = teamSeasonRows.map((r) => r.seasonId).toSet();
      final seasons = seasonIds.isEmpty
          ? <Season>[]
          : (await (db.select(
                  db.seasons,
                )..where((t) => t.id.isIn(seasonIds))).get())
                .map((r) => r.toDomain())
                .toList(growable: false);

      final roster = await _roster(teamSeasonRows.map((r) => r.id).toList());

      final standings =
          (await (db.select(db.standings)
                    ..where((t) => t.teamId.equals(teamId))
                    ..orderBy([(t) => OrderingTerm.desc(t.capturedAt)])
                    ..limit(5))
                  .get())
              .map((r) => r.toDomain())
              .toList(growable: false);

      final isFollowed =
          await (db.select(db.localFollows)..where(
                (t) => t.kind.equals('team') & t.entityId.equals(teamId),
              ))
              .getSingleOrNull() !=
          null;

      return TeamDetail(
        team: team,
        homeVenue: venue?.toDomain(),
        nextGames: next,
        recentGames: recent,
        seasons: seasons,
        roster: roster,
        standings: standings,
        isFavorite: isFollowed,
      );
    });
  }

  Future<List<RosterMember>> _roster(List<String> teamSeasonIds) async {
    if (teamSeasonIds.isEmpty) return const <RosterMember>[];
    final entries =
        await (db.select(db.rosterEntries)..where(
              (t) => t.teamSeasonId.isIn(teamSeasonIds) & t.deletedAt.isNull(),
            ))
            .get();
    if (entries.isEmpty) return const <RosterMember>[];

    final personIds = entries.map((e) => e.personId).toSet();
    final people = await (db.select(
      db.people,
    )..where((t) => t.id.isIn(personIds) & t.deletedAt.isNull())).get();
    final byId = {for (final p in people) p.id: p.toDomain()};

    final members = <RosterMember>[];
    for (final e in entries) {
      final person = byId[e.personId];
      if (person == null) continue;
      members.add(RosterMember(entry: e.toDomain(), person: person));
    }
    members.sort((a, b) {
      final an = int.tryParse(a.entry.jerseyNumber ?? '');
      final bn = int.tryParse(b.entry.jerseyNumber ?? '');
      if (an != null && bn != null) return an.compareTo(bn);
      if (an != null) return -1;
      if (bn != null) return 1;
      return a.person.name.compareTo(b.person.name);
    });
    return members;
  }

  @override
  Future<TeamStandingDetail?> standingDetail(
    String teamId,
    String seasonId,
  ) async {
    final rows =
        await (db.select(db.standings)
              ..where((t) => t.seasonId.equals(seasonId) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm(expression: t.rank)]))
            .get();
    if (rows.isEmpty) return null;

    // One capture per team: standings are snapshots, so we keep the latest.
    final latestByTeam = <String, StandingRowData>{};
    for (final r in rows) {
      final existing = latestByTeam[r.teamId];
      if (existing == null || r.capturedAt.isAfter(existing.capturedAt)) {
        latestByTeam[r.teamId] = r;
      }
    }

    final ordered = latestByTeam.values.toList()
      ..sort((a, b) => (a.rank ?? 9999).compareTo(b.rank ?? 9999));

    final index = ordered.indexWhere((r) => r.teamId == teamId);
    if (index < 0) return null;

    final teamIds = ordered.map((r) => r.teamId).toSet();
    final teams = await (db.select(
      db.teams,
    )..where((t) => t.id.isIn(teamIds))).get();
    final teamById = {for (final t in teams) t.id: t.toDomain()};

    final me = ordered[index];
    final myTeam = teamById[me.teamId];
    if (myTeam == null) return null;

    // "Who am I chasing" — the team directly above, or below if we lead.
    final rivalRow = index > 0
        ? ordered[index - 1]
        : (ordered.length > 1 ? ordered[1] : null);
    final rivalTeam = rivalRow == null ? null : teamById[rivalRow.teamId];

    final form = await _recentForm(teamId, me);

    final competition = await _competitionForSeason(seasonId);

    // Coverage: how many of the season's games actually have a final result.
    final total = await _countGames(seasonId, finalOnly: false);
    final played = await _countGames(seasonId, finalOnly: true);

    return TeamStandingDetail(
      row: StandingRow(snapshot: me.toDomain(), team: myTeam, isFavorite: true),
      totalTeams: ordered.length,
      form: form,
      coverage: DataCoverage(
        observed: played,
        expected: total,
        note: total == 0 ? '전체 일정이 아직 확인되지 않았습니다.' : null,
        lastComputedAt: me.capturedAt,
      ),
      nextRival: (rivalRow != null && rivalTeam != null)
          ? StandingRow(snapshot: rivalRow.toDomain(), team: rivalTeam)
          : null,
      rulesUrl: competition?.regulationsUrl,
      lastUpdatedAt: me.capturedAt,
    );
  }

  Future<TeamForm> _recentForm(String teamId, StandingRowData standing) async {
    final rows =
        await (db.select(db.games)
              ..where(
                (t) =>
                    t.deletedAt.isNull() &
                    (t.homeTeamId.equals(teamId) |
                        t.awayTeamId.equals(teamId)) &
                    t.status.isIn(<String>[
                      GameStatus.finalized.wireValue,
                      GameStatus.forfeit.wireValue,
                    ]),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.startTimeUtc)])
              ..limit(5))
            .get();

    return TeamForm(
      teamId: teamId,
      results: rows
          .map((r) => TeamForm.resultFor(r.toDomain(), teamId))
          .toList(growable: false),
      currentRank: standing.rank,
      previousRank: standing.previousRank,
    );
  }

  Future<Competition?> _competitionForSeason(String seasonId) async {
    final season = await (db.select(
      db.seasons,
    )..where((t) => t.id.equals(seasonId))).getSingleOrNull();
    if (season == null) return null;
    final competition = await (db.select(
      db.competitions,
    )..where((t) => t.id.equals(season.competitionId))).getSingleOrNull();
    return competition?.toDomain();
  }

  Future<int> _countGames(String seasonId, {required bool finalOnly}) async {
    final count = db.games.id.count();
    final query = db.selectOnly(db.games)
      ..addColumns([count])
      ..where(
        db.games.seasonId.equals(seasonId) &
            db.games.deletedAt.isNull() &
            (finalOnly
                ? db.games.status.isIn(<String>[
                    GameStatus.finalized.wireValue,
                    GameStatus.forfeit.wireValue,
                  ])
                : const Constant(true)),
      );
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  @override
  Future<String?> resolveAlias(String name) async {
    final normalized = KoreanText.normalize(name);
    if (normalized.isEmpty) return null;
    final row =
        await (db.select(db.teamAliases)
              ..where((t) => t.normalized.equals(normalized))
              ..limit(1))
            .getSingleOrNull();
    return row?.teamId;
  }
}
