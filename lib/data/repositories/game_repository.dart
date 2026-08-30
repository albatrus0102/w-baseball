import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../core/database/database.dart';
import '../mappers/row_mappers.dart';
import '../models/content.dart';
import '../models/domain.dart';
import '../models/weather.dart';
import '../sync/sync_contracts.dart';

/// Filter for a game list. Immutable so it can be stored in a provider and
/// restored verbatim when the user comes back from a detail screen.
@immutable
class GameQuery {
  const GameQuery({
    this.fromUtc,
    this.toUtc,
    this.dayKey,
    this.competitionIds = const <String>[],
    this.teamIds = const <String>[],
    this.statuses = const <GameStatus>[],
    this.level,
    this.favoritesOnly = false,
    this.regionCodes = const <String>[],
    this.includeDeleted = false,
    this.limit,
    this.ascending = true,
  });

  final DateTime? fromUtc;
  final DateTime? toUtc;

  /// `yyyy-MM-dd` in KST. Takes precedence over the range when set.
  final String? dayKey;

  final List<String> competitionIds;
  final List<String> teamIds;
  final List<GameStatus> statuses;
  final CompetitionLevel? level;
  final bool favoritesOnly;

  /// Venue region codes, used by the nearby-games screen.
  final List<String> regionCodes;

  final bool includeDeleted;
  final int? limit;
  final bool ascending;

  bool get hasActiveFilters =>
      competitionIds.isNotEmpty ||
      teamIds.isNotEmpty ||
      statuses.isNotEmpty ||
      level != null ||
      favoritesOnly ||
      regionCodes.isNotEmpty;

  /// Number of filter chips the UI should render as removable.
  int get activeFilterCount =>
      (competitionIds.isEmpty ? 0 : 1) +
      (teamIds.isEmpty ? 0 : 1) +
      (statuses.isEmpty ? 0 : 1) +
      (level == null ? 0 : 1) +
      (favoritesOnly ? 1 : 0) +
      (regionCodes.isEmpty ? 0 : 1);

  GameQuery copyWith({
    DateTime? fromUtc,
    DateTime? toUtc,
    String? dayKey,
    List<String>? competitionIds,
    List<String>? teamIds,
    List<GameStatus>? statuses,
    CompetitionLevel? level,
    bool? favoritesOnly,
    List<String>? regionCodes,
    bool? includeDeleted,
    int? limit,
    bool? ascending,
    bool clearDayKey = false,
    bool clearLevel = false,
    bool clearRange = false,
  }) {
    return GameQuery(
      fromUtc: clearRange ? null : (fromUtc ?? this.fromUtc),
      toUtc: clearRange ? null : (toUtc ?? this.toUtc),
      dayKey: clearDayKey ? null : (dayKey ?? this.dayKey),
      competitionIds: competitionIds ?? this.competitionIds,
      teamIds: teamIds ?? this.teamIds,
      statuses: statuses ?? this.statuses,
      level: clearLevel ? null : (level ?? this.level),
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      regionCodes: regionCodes ?? this.regionCodes,
      includeDeleted: includeDeleted ?? this.includeDeleted,
      limit: limit ?? this.limit,
      ascending: ascending ?? this.ascending,
    );
  }

  /// Drops every filter but keeps the date context, which is what a
  /// "필터 초기화" button should do.
  GameQuery cleared() => GameQuery(
    fromUtc: fromUtc,
    toUtc: toUtc,
    dayKey: dayKey,
    limit: limit,
    ascending: ascending,
  );

  /// Value equality is mandatory: this type is used as a Riverpod family key,
  /// and an identity-only key would create a fresh provider on every rebuild —
  /// which is an endless rebuild loop, not just a wasted cache.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GameQuery &&
          other.fromUtc == fromUtc &&
          other.toUtc == toUtc &&
          other.dayKey == dayKey &&
          const ListEquality<String>().equals(
            other.competitionIds,
            competitionIds,
          ) &&
          const ListEquality<String>().equals(other.teamIds, teamIds) &&
          const ListEquality<GameStatus>().equals(other.statuses, statuses) &&
          other.level == level &&
          other.favoritesOnly == favoritesOnly &&
          const ListEquality<String>().equals(other.regionCodes, regionCodes) &&
          other.includeDeleted == includeDeleted &&
          other.limit == limit &&
          other.ascending == ascending;

  @override
  int get hashCode => Object.hash(
    fromUtc,
    toUtc,
    dayKey,
    const ListEquality<String>().hash(competitionIds),
    const ListEquality<String>().hash(teamIds),
    const ListEquality<GameStatus>().hash(statuses),
    level,
    favoritesOnly,
    const ListEquality<String>().hash(regionCodes),
    includeDeleted,
    limit,
    ascending,
  );
}

/// Reads and refreshes games.
///
/// Everything here streams from SQLite. Screens never wait on the network to
/// render: a refresh writes to the database and the stream re-emits.
abstract interface class GameRepository {
  Stream<List<GameCard>> watchGames(GameQuery query);

  Stream<GameDetail?> watchGame(String canonicalId);

  /// The single most relevant upcoming fixture, preferring followed teams.
  /// Shared by the home hero card and, later, a home-screen widget.
  Stream<NextGameSummary?> watchNextGame();

  /// Days in [monthKey] that actually have games, for the calendar board.
  Stream<Set<String>> watchGameDays(String monthKey);

  /// The nearest day at or after [fromDayKey] that has at least one game.
  Future<String?> nextDayWithGames(String fromDayKey, {bool forward = true});

  Future<SyncResult> refresh(GameSyncScope scope);
}

class DriftGameRepository implements GameRepository {
  DriftGameRepository({
    required this.db,
    required this.onRefresh,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final WbDatabase db;

  /// Injected rather than depending on the sync engine directly, so the
  /// repository stays testable without a network stack.
  final Future<SyncResult> Function(GameSyncScope scope) onRefresh;
  final DateTime Function() _clock;

  @override
  Stream<List<GameCard>> watchGames(GameQuery query) {
    final select = db.select(db.games);

    if (!query.includeDeleted) {
      select.where((t) => t.deletedAt.isNull());
    }
    final day = query.dayKey;
    if (day != null) {
      select.where((t) => t.dayKey.equals(day));
    } else {
      final from = query.fromUtc;
      final to = query.toUtc;
      if (from != null) {
        select.where((t) => t.startTimeUtc.isBiggerOrEqualValue(from));
      }
      if (to != null) {
        select.where((t) => t.startTimeUtc.isSmallerThanValue(to));
      }
    }
    if (query.competitionIds.isNotEmpty) {
      select.where((t) => t.competitionId.isIn(query.competitionIds));
    }
    if (query.teamIds.isNotEmpty) {
      select.where(
        (t) =>
            t.homeTeamId.isIn(query.teamIds) | t.awayTeamId.isIn(query.teamIds),
      );
    }
    if (query.statuses.isNotEmpty) {
      final wire = query.statuses.map((s) => s.wireValue).toList();
      select.where((t) => t.status.isIn(wire));
    }

    select.orderBy([
      (t) => OrderingTerm(
        expression: t.startTimeUtc,
        mode: query.ascending ? OrderingMode.asc : OrderingMode.desc,
      ),
    ]);

    return select.watch().asyncMap((rows) => _decorate(rows, query));
  }

  /// Joins each game to its teams, venue and competition in bulk.
  ///
  /// Deliberately not a SQL join: the reference tables are small and cached in
  /// memory anyway, and doing it this way keeps one query per list refresh
  /// instead of N per row.
  Future<List<GameCard>> _decorate(List<GameRow> rows, GameQuery query) async {
    if (rows.isEmpty) return const <GameCard>[];

    final teamIds = <String>{};
    final venueIds = <String>{};
    final competitionIds = <String>{};
    final seasonIds = <String>{};
    for (final r in rows) {
      teamIds
        ..add(r.homeTeamId)
        ..add(r.awayTeamId);
      if (r.venueId != null) venueIds.add(r.venueId!);
      if (r.competitionId != null) competitionIds.add(r.competitionId!);
      if (r.seasonId != null) seasonIds.add(r.seasonId!);
    }

    final teams = await _teamsByIds(teamIds);
    final venues = await _venuesByIds(venueIds);
    final competitions = await _competitionsByIds(competitionIds);
    final seasons = await _seasonsByIds(seasonIds);
    final followed = await _followedTeamIds();

    final cards = <GameCard>[];
    for (final r in rows) {
      final home = teams[r.homeTeamId];
      final away = teams[r.awayTeamId];
      // A game whose teams we have not synced yet is not renderable. Skipping
      // is better than inventing a placeholder that looks like real data.
      if (home == null || away == null) continue;

      final venue = r.venueId == null ? null : venues[r.venueId!];
      if (query.regionCodes.isNotEmpty) {
        final region = venue?.region;
        if (region == null || !query.regionCodes.contains(region)) continue;
      }

      final competition = r.competitionId == null
          ? null
          : competitions[r.competitionId!];
      if (query.level != null && competition?.level != query.level) continue;

      final isHomeFav = followed.contains(home.id);
      final isAwayFav = followed.contains(away.id);
      if (query.favoritesOnly && !isHomeFav && !isAwayFav) continue;

      cards.add(
        GameCard(
          game: r.toDomain(),
          homeTeam: home,
          awayTeam: away,
          venue: venue,
          competition: competition,
          season: r.seasonId == null ? null : seasons[r.seasonId!],
          isHomeFavorite: isHomeFav,
          isAwayFavorite: isAwayFav,
        ),
      );
      if (query.limit != null && cards.length >= query.limit!) break;
    }
    return cards;
  }

  @override
  Stream<GameDetail?> watchGame(String canonicalId) {
    final select = db.select(db.games)..where((t) => t.id.equals(canonicalId));
    return select.watchSingleOrNull().asyncMap((row) async {
      if (row == null) return null;
      final cards = await _decorate(<GameRow>[
        row,
      ], const GameQuery(includeDeleted: true));
      if (cards.isEmpty) return null;

      final line = await (db.select(
        db.gameLineScores,
      )..where((t) => t.gameId.equals(canonicalId))).getSingleOrNull();

      final batting =
          await (db.select(db.battingStats)
                ..where((t) => t.gameId.equals(canonicalId))
                ..orderBy([
                  (t) => OrderingTerm(expression: t.teamId),
                  (t) => OrderingTerm(expression: t.battingOrder),
                ]))
              .get();

      final pitching =
          await (db.select(db.pitchingStats)
                ..where((t) => t.gameId.equals(canonicalId))
                ..orderBy([
                  (t) => OrderingTerm(expression: t.teamId),
                  (t) => OrderingTerm(
                    expression: t.outsRecorded,
                    mode: OrderingMode.desc,
                  ),
                ]))
              .get();

      // Related coverage: anything tagged with either club.
      final teamIds = <String>[row.homeTeamId, row.awayTeamId];
      final articles = await _relatedArticles(teamIds);
      final videos = await _relatedVideos(teamIds);

      return GameDetail(
        card: cards.first,
        lineScore: line?.toDomain(),
        batting: batting.map((b) => b.toDomain()).toList(growable: false),
        pitching: pitching.map((p) => p.toDomain()).toList(growable: false),
        articles: articles,
        videos: videos,
      );
    });
  }

  @override
  Stream<NextGameSummary?> watchNextGame() {
    final now = _clock().toUtc();
    // Include games that started recently so a match in progress still leads,
    // rather than the card jumping to tomorrow the moment first pitch passes.
    final since = now.subtract(const Duration(hours: 4));

    final select = db.select(db.games)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.startTimeUtc.isBiggerOrEqualValue(since) &
            t.status.isNotIn(<String>[
              GameStatus.cancelled.wireValue,
              GameStatus.postponed.wireValue,
            ]),
      )
      ..orderBy([(t) => OrderingTerm(expression: t.startTimeUtc)])
      ..limit(40);

    return select.watch().asyncMap((rows) async {
      final cards = await _decorate(rows, const GameQuery());
      if (cards.isEmpty) return null;
      // A followed team's fixture outranks a merely-sooner one; that is the
      // whole point of following.
      for (final card in cards) {
        if (card.involvesFavorite) {
          return NextGameSummary(card: card, isFavoriteDriven: true);
        }
      }
      return NextGameSummary(card: cards.first, isFavoriteDriven: false);
    });
  }

  @override
  Stream<Set<String>> watchGameDays(String monthKey) {
    final query = db.selectOnly(db.games)
      ..addColumns([db.games.dayKey])
      ..where(db.games.monthKey.equals(monthKey) & db.games.deletedAt.isNull())
      ..groupBy([db.games.dayKey]);
    return query.watch().map(
      (rows) => rows.map((r) => r.read(db.games.dayKey)!).toSet(),
    );
  }

  @override
  Future<String?> nextDayWithGames(
    String fromDayKey, {
    bool forward = true,
  }) async {
    final query = db.selectOnly(db.games)
      ..addColumns([db.games.dayKey])
      ..where(
        db.games.deletedAt.isNull() &
            (forward
                ? db.games.dayKey.isBiggerThanValue(fromDayKey)
                : db.games.dayKey.isSmallerThanValue(fromDayKey)),
      )
      ..groupBy([db.games.dayKey])
      ..orderBy([
        OrderingTerm(
          expression: db.games.dayKey,
          mode: forward ? OrderingMode.asc : OrderingMode.desc,
        ),
      ])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row?.read(db.games.dayKey);
  }

  @override
  Future<SyncResult> refresh(GameSyncScope scope) => onRefresh(scope);

  // --- lookups -------------------------------------------------------------

  Future<Map<String, Team>> _teamsByIds(Set<String> ids) async {
    if (ids.isEmpty) return const <String, Team>{};
    final rows = await (db.select(
      db.teams,
    )..where((t) => t.id.isIn(ids))).get();
    return {for (final r in rows) r.id: r.toDomain()};
  }

  Future<Map<String, Venue>> _venuesByIds(Set<String> ids) async {
    if (ids.isEmpty) return const <String, Venue>{};
    final rows = await (db.select(
      db.venues,
    )..where((t) => t.id.isIn(ids))).get();
    return {for (final r in rows) r.id: r.toDomain()};
  }

  Future<Map<String, Competition>> _competitionsByIds(Set<String> ids) async {
    if (ids.isEmpty) return const <String, Competition>{};
    final rows = await (db.select(
      db.competitions,
    )..where((t) => t.id.isIn(ids))).get();
    return {for (final r in rows) r.id: r.toDomain()};
  }

  Future<Map<String, Season>> _seasonsByIds(Set<String> ids) async {
    if (ids.isEmpty) return const <String, Season>{};
    final rows = await (db.select(
      db.seasons,
    )..where((t) => t.id.isIn(ids))).get();
    return {for (final r in rows) r.id: r.toDomain()};
  }

  Future<Set<String>> _followedTeamIds() async {
    final rows = await (db.select(
      db.localFollows,
    )..where((t) => t.kind.equals('team'))).get();
    return rows.map((r) => r.entityId).toSet();
  }

  Future<List<Article>> _relatedArticles(List<String> teamIds) async {
    final rows =
        await (db.select(db.articles)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.desc(t.publishedAt)])
              ..limit(40))
            .get();
    return rows
        .map((r) => r.toDomain())
        .where((a) => a.teamIds.any(teamIds.contains))
        .take(5)
        .toList(growable: false);
  }

  Future<List<Video>> _relatedVideos(List<String> teamIds) async {
    final rows =
        await (db.select(db.videos)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.desc(t.publishedAt)])
              ..limit(40))
            .get();
    return rows
        .map((r) => r.toDomain())
        .where((v) => v.teamIds.any(teamIds.contains))
        .take(5)
        .toList(growable: false);
  }
}

/// A game plus everything the "watch it in person" experience needs.
@immutable
class NearbyGame {
  const NearbyGame({
    required this.card,
    required this.attendance,
    required this.weatherRisk,
    this.distanceKm,
    this.isSaved = false,
    this.whyWatch,
  });

  final GameCard card;
  final AttendanceInfo? attendance;
  final WeatherRisk weatherRisk;

  /// Straight-line distance from the user's chosen region centre or, with
  /// permission, their device position. Computed on-device only.
  final double? distanceKm;

  final bool isSaved;

  /// One-line "why this game is worth seeing", only when we actually have a
  /// factual reason (a derby, a title decider) — never invented.
  final String? whyWatch;

  AttendanceStatus get attendanceStatus =>
      attendance?.status ?? AttendanceStatus.needsConfirmation;

  String get distanceLabelKo {
    final d = distanceKm;
    if (d == null) return '';
    if (d < 1) return '1km 이내';
    return '약 ${d.round()}km';
  }
}
