import 'package:drift/drift.dart';

import '../../core/database/database.dart';
import '../mappers/row_mappers.dart';
import '../models/content.dart';
import '../models/domain.dart';
import '../models/stats.dart';
import 'game_repository.dart';

abstract interface class CompetitionRepository {
  Stream<List<Competition>> watchCompetitions({
    CompetitionLevel? level,
    CompetitionPhase? phase,
    int? year,
  });

  Stream<List<Season>> watchSeasons(String competitionId);

  Stream<CompetitionDetail?> watchCompetitionDetail(String seasonId);

  /// One-screen view of where a competition currently stands.
  Stream<LeaguePulse?> watchLeaguePulse(String seasonId);

  /// Per-stat rankings for a season, with qualification rules applied.
  Future<List<Leaderboard>> leaderboards(
    String seasonId, {
    StatCategory? category,
    String? teamId,
    bool qualifiedOnly = true,
  });

  /// Years that actually have seasons, for the season picker.
  Stream<List<int>> watchSeasonYears();
}

class DriftCompetitionRepository implements CompetitionRepository {
  DriftCompetitionRepository({
    required this.db,
    required this.gameRepository,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final WbDatabase db;
  final GameRepository gameRepository;
  final DateTime Function() _clock;

  @override
  Stream<List<Competition>> watchCompetitions({
    CompetitionLevel? level,
    CompetitionPhase? phase,
    int? year,
  }) {
    final select = db.select(db.competitions)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    if (level != null) {
      select.where((t) => t.level.equals(level.wireValue));
    }

    return select.watch().asyncMap((rows) async {
      if (phase == null && year == null) {
        return rows.map((r) => r.toDomain()).toList(growable: false);
      }
      // Phase and year live on seasons, so filter through them.
      final seasonSelect = db.select(db.seasons)
        ..where((t) => t.deletedAt.isNull());
      if (phase != null) {
        seasonSelect.where((t) => t.phase.equals(phase.wireValue));
      }
      if (year != null) {
        seasonSelect.where((t) => t.year.equals(year));
      }
      final seasons = await seasonSelect.get();
      final ids = seasons.map((s) => s.competitionId).toSet();
      return rows
          .where((r) => ids.contains(r.id))
          .map((r) => r.toDomain())
          .toList(growable: false);
    });
  }

  @override
  Stream<List<Season>> watchSeasons(String competitionId) {
    final select = db.select(db.seasons)
      ..where(
        (t) => t.competitionId.equals(competitionId) & t.deletedAt.isNull(),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.year)]);
    return select.watch().map(
      (rows) => rows.map((r) => r.toDomain()).toList(growable: false),
    );
  }

  @override
  Stream<List<int>> watchSeasonYears() {
    final query = db.selectOnly(db.seasons)
      ..addColumns([db.seasons.year])
      ..where(db.seasons.deletedAt.isNull())
      ..groupBy([db.seasons.year])
      ..orderBy([OrderingTerm.desc(db.seasons.year)]);
    return query.watch().map(
      (rows) => rows
          .map((r) => r.read(db.seasons.year))
          .whereType<int>()
          .toList(growable: false),
    );
  }

  @override
  Stream<CompetitionDetail?> watchCompetitionDetail(String seasonId) {
    final select = db.select(db.seasons)..where((t) => t.id.equals(seasonId));
    return select.watchSingleOrNull().asyncMap((seasonRow) async {
      if (seasonRow == null) return null;
      final competitionRow = await (db.select(
        db.competitions,
      )..where((t) => t.id.equals(seasonRow.competitionId))).getSingleOrNull();
      if (competitionRow == null) return null;

      final stages =
          (await (db.select(db.stages)
                    ..where(
                      (t) => t.seasonId.equals(seasonId) & t.deletedAt.isNull(),
                    )
                    ..orderBy([(t) => OrderingTerm(expression: t.ordering)]))
                  .get())
              .map((r) => r.toDomain())
              .toList(growable: false);

      final standings = await _standingRows(seasonId);

      final games = await gameRepository
          .watchGames(
            GameQuery(competitionIds: <String>[competitionRow.id], limit: 200),
          )
          .first;

      final isFollowed =
          await (db.select(db.localFollows)..where(
                (t) =>
                    t.kind.equals('competition') &
                    t.entityId.equals(competitionRow.id),
              ))
              .getSingleOrNull() !=
          null;

      return CompetitionDetail(
        competition: competitionRow.toDomain(),
        season: seasonRow.toDomain(),
        stages: stages,
        standings: standings,
        games: games,
        isFavorite: isFollowed,
      );
    });
  }

  Future<List<StandingRow>> _standingRows(String seasonId) async {
    final rows = await (db.select(
      db.standings,
    )..where((t) => t.seasonId.equals(seasonId) & t.deletedAt.isNull())).get();
    if (rows.isEmpty) return const <StandingRow>[];

    // Standings are point-in-time captures; keep only the newest per team.
    final latest = <String, StandingRowData>{};
    for (final r in rows) {
      final existing = latest[r.teamId];
      if (existing == null || r.capturedAt.isAfter(existing.capturedAt)) {
        latest[r.teamId] = r;
      }
    }

    final teamIds = latest.keys.toSet();
    final teams = await (db.select(
      db.teams,
    )..where((t) => t.id.isIn(teamIds))).get();
    final teamById = {for (final t in teams) t.id: t.toDomain()};

    final followed =
        (await (db.select(
              db.localFollows,
            )..where((t) => t.kind.equals('team'))).get())
            .map((r) => r.entityId)
            .toSet();

    final out = <StandingRow>[];
    for (final r in latest.values) {
      final team = teamById[r.teamId];
      if (team == null) continue;
      out.add(
        StandingRow(
          snapshot: r.toDomain(),
          team: team,
          isFavorite: followed.contains(team.id),
        ),
      );
    }
    // Previously this trusted whatever `rank` the source sent and pushed rows
    // without one to 9999 — which meant a source that omits rank produced a
    // table in database order under a row of dashes. The order is now computed
    // from the recorded results against a stated rule.
    return Standings.rank(out)
        .map(
          (r) => r.row.withRanking(
            computedRank: r.rank,
            isTied: r.isTied,
            sourceRankDiffers: r.sourceRankDiffers,
          ),
        )
        .toList(growable: false);
  }

  @override
  Stream<LeaguePulse?> watchLeaguePulse(String seasonId) {
    final select = db.select(db.games)
      ..where((t) => t.seasonId.equals(seasonId) & t.deletedAt.isNull());

    return select.watch().asyncMap((rows) async {
      final seasonRow = await (db.select(
        db.seasons,
      )..where((t) => t.id.equals(seasonId))).getSingleOrNull();
      if (seasonRow == null) return null;
      final competitionRow = await (db.select(
        db.competitions,
      )..where((t) => t.id.equals(seasonRow.competitionId))).getSingleOrNull();
      if (competitionRow == null) return null;

      var completed = 0;
      var postponed = 0;
      var cancelled = 0;
      var undecided = 0;
      for (final r in rows) {
        final status = GameStatus.parse(r.status);
        if (status.hasResult) {
          completed++;
        } else if (status == GameStatus.postponed) {
          postponed++;
        } else if (status == GameStatus.cancelled) {
          cancelled++;
        } else if (status == GameStatus.unknown) {
          undecided++;
        }
      }

      final now = _clock().toUtc();

      // Most recent decisive results — what actually moved the table.
      final recentRows =
          rows.where((r) => GameStatus.parse(r.status).hasResult).toList()
            ..sort((a, b) => b.startTimeUtc.compareTo(a.startTimeUtc));

      final weekEnd = now.add(const Duration(days: 7));
      final weekRows =
          rows
              .where(
                (r) =>
                    r.startTimeUtc.isAfter(now) &&
                    r.startTimeUtc.isBefore(weekEnd),
              )
              .toList()
            ..sort((a, b) => a.startTimeUtc.compareTo(b.startTimeUtc));

      final recent = await _cardsFor(recentRows.take(3).toList());
      final week = await _cardsFor(weekRows.take(5).toList());

      // Current stage: the earliest stage that still has unplayed games.
      final stages =
          await (db.select(db.stages)
                ..where((t) => t.seasonId.equals(seasonId))
                ..orderBy([(t) => OrderingTerm(expression: t.ordering)]))
              .get();
      String? currentStage;
      for (final stage in stages) {
        final pending = rows.any(
          (r) => r.stageId == stage.id && !GameStatus.parse(r.status).hasResult,
        );
        if (pending) {
          currentStage = stage.name;
          break;
        }
      }
      currentStage ??= stages.isNotEmpty ? stages.last.name : null;

      return LeaguePulse(
        seasonId: seasonId,
        competitionName: competitionRow.name,
        completedGames: completed,
        totalScheduledGames: rows.length,
        currentStageName: currentStage,
        recentDecisiveResults: recent,
        thisWeekGames: week,
        postponedCount: postponed,
        cancelledCount: cancelled,
        undecidedCount: undecided,
        coverage: DataCoverage(
          observed: completed,
          expected: rows.length,
          lastComputedAt: now,
        ),
        lastUpdatedAt: now,
      );
    });
  }

  Future<List<GameCard>> _cardsFor(List<GameRow> rows) async {
    if (rows.isEmpty) return const <GameCard>[];
    final ids = rows.map((r) => r.id).toSet();
    final all = await gameRepository
        .watchGames(const GameQuery(limit: 500))
        .first;
    final byId = {for (final c in all) c.game.id: c};
    return ids
        .map((id) => byId[id])
        .whereType<GameCard>()
        .toList(growable: false);
  }

  @override
  Future<List<Leaderboard>> leaderboards(
    String seasonId, {
    StatCategory? category,
    String? teamId,
    bool qualifiedOnly = true,
  }) async {
    // Only games belonging to this season contribute. Records are never summed
    // across competitions, whose rules and schedules differ.
    final gameRows = await (db.select(
      db.games,
    )..where((t) => t.seasonId.equals(seasonId) & t.deletedAt.isNull())).get();
    if (gameRows.isEmpty) return const <Leaderboard>[];

    final gameIds = gameRows.map((g) => g.id).toSet();
    final finishedIds = gameRows
        .where((g) => GameStatus.parse(g.status).hasResult)
        .map((g) => g.id)
        .toSet();

    final batting = await (db.select(
      db.battingStats,
    )..where((t) => t.gameId.isIn(gameIds))).get();
    final pitching = await (db.select(
      db.pitchingStats,
    )..where((t) => t.gameId.isIn(gameIds))).get();

    if (batting.isEmpty && pitching.isEmpty) return const <Leaderboard>[];

    // Games per team, needed for "규정 타석 = 팀 경기수 × 3.1".
    final teamGames = <String, int>{};
    for (final g in gameRows) {
      if (!GameStatus.parse(g.status).hasResult) continue;
      teamGames[g.homeTeamId] = (teamGames[g.homeTeamId] ?? 0) + 1;
      teamGames[g.awayTeamId] = (teamGames[g.awayTeamId] ?? 0) + 1;
    }

    final teamRows = await db.select(db.teams).get();
    final teamNames = {
      for (final t in teamRows)
        t.id: (t.shortName?.isNotEmpty ?? false) ? t.shortName! : t.name,
    };

    final coverage = DataCoverage(
      // How many finished games we actually hold a box score for.
      observed: <String>{
        ...batting.map((b) => b.gameId),
        ...pitching.map((p) => p.gameId),
      }.where(finishedIds.contains).length,
      expected: finishedIds.length,
      note: finishedIds.isEmpty ? '종료된 경기가 아직 없습니다.' : null,
      lastComputedAt: _clock().toUtc(),
    );

    // A ranking is only as real as what it was computed from. The stat rows
    // themselves carry no provenance, so it comes from the games that produced
    // them: if any contributing fixture is demo, the leaderboard is demo and
    // says so. Hard-coding `isDemo: false` here made an aggregate of entirely
    // demo data present itself as genuine.
    final contributingIds = <String>{
      ...batting.map((b) => b.gameId),
      ...pitching.map((p) => p.gameId),
    };
    final anyDemo = gameRows
        .where((g) => contributingIds.contains(g.id))
        .any((g) => g.isDemo);

    final provenance = Provenance(
      sourceName: 'derived',
      sourceUrl: 'app://derived/leaderboard',
      fetchedAt: _clock().toUtc(),
      qualityStatus: QualityStatus.autoVerified,
      isDemo: anyDemo,
    );

    final accB = <String, _BattingAcc>{};
    for (final b in batting) {
      if (teamId != null && b.teamId != teamId) continue;
      final acc = accB.putIfAbsent(
        b.personId,
        () => _BattingAcc(b.personId, b.playerName, b.teamId),
      );
      acc.add(b);
    }

    final accP = <String, _PitchingAcc>{};
    for (final p in pitching) {
      if (teamId != null && p.teamId != teamId) continue;
      final acc = accP.putIfAbsent(
        p.personId,
        () => _PitchingAcc(p.personId, p.playerName, p.teamId),
      );
      acc.add(p);
    }

    final out = <Leaderboard>[];

    for (final def in StatDefinition.defaults) {
      if (category != null && def.category != category) continue;

      final raw = <LeaderboardEntry>[];
      if (def.category == StatCategory.batting ||
          def.category == StatCategory.baserunning) {
        for (final acc in accB.values) {
          final value = acc.valueFor(def.key);
          if (value == null) continue;
          raw.add(
            LeaderboardEntry(
              personId: acc.personId,
              playerName: acc.playerName,
              teamId: acc.teamId,
              teamName: teamNames[acc.teamId],
              value: value,
              qualifies: true,
              qualifierValue: acc.plateAppearances.toDouble(),
              gamesCounted: acc.games,
            ),
          );
        }
      } else {
        for (final acc in accP.values) {
          final value = acc.valueFor(def.key);
          if (value == null) continue;
          raw.add(
            LeaderboardEntry(
              personId: acc.personId,
              playerName: acc.playerName,
              teamId: acc.teamId,
              teamName: teamNames[acc.teamId],
              value: value,
              qualifies: true,
              qualifierValue: acc.outsRecorded / 3.0,
              gamesCounted: acc.games,
            ),
          );
        }
      }

      if (raw.isEmpty) continue;

      // Threshold scales with the team's game count; unknown means we show
      // everyone and say so rather than guessing a cut-off.
      int? threshold;
      final rule = def.qualification;
      if (rule != null && qualifiedOnly) {
        final sample = raw.first.teamId;
        threshold = rule.threshold(teamGames[sample]);
      }

      out.add(
        Leaderboard(
          definition: def,
          entries: Leaderboard.rank(
            raw,
            higherIsBetter: def.higherIsBetter,
            threshold: threshold,
          ),
          seasonId: seasonId,
          coverage: coverage,
          provenance: provenance,
          teamFilterId: teamId,
          qualifiedOnly: qualifiedOnly,
          qualificationThreshold: threshold,
          computedAt: _clock().toUtc(),
        ),
      );
    }

    return out;
  }
}

class _BattingAcc {
  _BattingAcc(this.personId, this.playerName, this.teamId);

  final String personId;
  final String playerName;
  final String teamId;

  int games = 0;
  int atBats = 0;
  int hits = 0;
  int homeRuns = 0;
  int rbi = 0;
  int walks = 0;
  int stolenBases = 0;

  /// Approximated as AB + BB: the public feeds do not consistently publish
  /// sacrifices or HBP, and inventing them would corrupt the qualifier.
  int get plateAppearances => atBats + walks;

  void add(BattingStatRow r) {
    games++;
    atBats += r.atBats;
    hits += r.hits;
    homeRuns += r.homeRuns;
    rbi += r.rbi;
    walks += r.walks;
    stolenBases += r.stolenBases;
  }

  double? valueFor(String key) => switch (key) {
    'avg' => atBats == 0 ? null : hits / atBats,
    'hits' => hits.toDouble(),
    'hr' => homeRuns.toDouble(),
    'rbi' => rbi.toDouble(),
    'sb' => stolenBases.toDouble(),
    _ => null,
  };
}

class _PitchingAcc {
  _PitchingAcc(this.personId, this.playerName, this.teamId);

  final String personId;
  final String playerName;
  final String teamId;

  int games = 0;
  int outsRecorded = 0;
  int earnedRuns = 0;
  int strikeouts = 0;
  int wins = 0;

  void add(PitchingStatRow r) {
    games++;
    outsRecorded += r.outsRecorded;
    earnedRuns += r.earnedRuns;
    strikeouts += r.strikeouts;
    if (r.decision == 'W') wins++;
  }

  double? valueFor(String key) => switch (key) {
    'era' => outsRecorded == 0 ? null : earnedRuns * 27 / outsRecorded,
    'strikeouts' => strikeouts.toDouble(),
    'wins' => wins.toDouble(),
    _ => null,
  };
}
