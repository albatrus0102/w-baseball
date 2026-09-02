import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

/// The app's local source of truth.
///
/// Every screen reads from here and only from here. Network responses are
/// validated, normalised, and committed in a transaction *before* anything is
/// shown, so a failed or partial sync can never leave the UI showing a
/// half-applied state — and the app works identically with no network at all.
@DriftDatabase(
  tables: <Type>[
    // --- core sport (schema v1) ---
    Organizations,
    Competitions,
    Seasons,
    Stages,
    Teams,
    TeamAliases,
    TeamSeasons,
    People,
    PersonAliases,
    RosterEntries,
    Venues,
    Games,
    GameLineScores,
    BattingStats,
    PitchingStats,
    Standings,
    Articles,
    Videos,
    // --- identity / audit / sync bookkeeping (v1) ---
    ExternalIdentities,
    FieldProvenances,
    SourcePolicies,
    EntityRevisions,
    SyncRuns,
    SyncErrors,
    Corrections,
    DataCoverages,
    SyncStates,
    // --- device-local state (v1) ---
    LocalFollows,
    SavedItems,
    ScheduledNotifications,
    // --- discovery / editorial content (schema v2) ---
    FeaturedTopics,
    Programs,
    ProgramSeasons,
    Episodes,
    EpisodeRecaps,
    OfficialClips,
    Storylines,
    FeaturedPeople,
    StoryClusters,
    StorySources,
    ContentEntityLinks,
    BeginnerGuides,
    AttendanceInfos,
    WeatherForecasts,
    SeenItems,
    JourneyEvents,
    // --- device-local state (schema v3) ---
    GameLogEntries,
    // --- device-local state (schema v5) ---
    GameLogGoals,
  ],
)
class WbDatabase extends _$WbDatabase {
  WbDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'w_baseball'));

  /// Schema history
  ///  * v1 — core sport data, news/video, sync bookkeeping, local follows and
  ///    scheduled notifications.
  ///  * v2 — discovery layer: featured topics, programmes/episodes/recaps,
  ///    story clusters, beginner guides, attendance info, weather forecasts,
  ///    seen items and local journey events. Adds `articles.story_cluster_id`
  ///    and `standings.previous_rank`.
  ///  * v3 — 출전 일지: `game_log_entries`, a device-local table for the
  ///    player's own game log. Purely additive, like v2.
  ///  * v4 — 출전 일지 stat line: 12 nullable columns added to
  ///    `game_log_entries` (plate appearances, hits, walks, sacrifice
  ///    bunts, strikeouts, RBI, runs, stolen bases, and the pitching
  ///    equivalents). Purely additive — every existing row gets all-null
  ///    columns, which reads as "no stat line for this game", not a false
  ///    zero. See `GameLogEntries` in `tables.dart`.
  ///  * v5 — `game_log_goals`: the player's own "다음 경기에서 해볼 것" note,
  ///    written in her own words and only ever reflected back to her — see
  ///    `GameLogGoals` in `tables.dart` and `game_log_widgets.dart`'s module
  ///    doc for why the app never authors this text itself. Purely
  ///    additive, like v2 and v3.
  ///
  /// Upgrades are strictly additive. User-owned rows — follows, saved items,
  /// scheduled notification settings, (from v3) game log entries, and (from
  /// v5) game log goals — are never dropped or recreated;
  /// `test/unit/migration_test.dart` asserts exactly that.
  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createIndexes(m);
      await _seedSourcePolicies();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        // v1 → v2: add the discovery layer. Nothing existing is touched.
        for (final table in <TableInfo<Table, dynamic>>[
          featuredTopics,
          programs,
          programSeasons,
          episodes,
          episodeRecaps,
          officialClips,
          storylines,
          featuredPeople,
          storyClusters,
          storySources,
          contentEntityLinks,
          beginnerGuides,
          attendanceInfos,
          weatherForecasts,
          seenItems,
          journeyEvents,
        ]) {
          await m.createTable(table);
        }
        await m.addColumn(articles, articles.storyClusterId);
        await m.addColumn(standings, standings.previousRank);
      }
      if (from < 3) {
        // v2 → v3: the player's own game log. One new table, nothing
        // existing is touched. `createTable` builds it from the *current*
        // table definition — which already includes v4's stat columns —
        // so an install this old lands on v4's full shape in one step and
        // must not also hit the `addColumn` branch below for the same
        // columns (that would be "add a column that already exists").
        // Hence `else if`, not a second `if`: exactly one of these two
        // branches ever runs for a given `from`.
        await m.createTable(gameLogEntries);
      } else if (from < 4) {
        // v3 → v4: the player's own stat line, added to the game log entry
        // she already has. Reached only when `game_log_entries` already
        // existed *without* these columns (from == 3) — see the branch
        // above. 12 nullable columns, nothing existing is touched — every
        // pre-existing row reads as "no stat line" once this runs, never a
        // false zero. See `GameLogEntries` in `tables.dart` for why each
        // column is nullable.
        await m.addColumn(gameLogEntries, gameLogEntries.plateAppearances);
        await m.addColumn(gameLogEntries, gameLogEntries.hits);
        await m.addColumn(gameLogEntries, gameLogEntries.walks);
        await m.addColumn(gameLogEntries, gameLogEntries.sacrificeBunts);
        await m.addColumn(gameLogEntries, gameLogEntries.strikeouts);
        await m.addColumn(gameLogEntries, gameLogEntries.runsBattedIn);
        await m.addColumn(gameLogEntries, gameLogEntries.runsScored);
        await m.addColumn(gameLogEntries, gameLogEntries.stolenBases);
        await m.addColumn(gameLogEntries, gameLogEntries.outsPitched);
        await m.addColumn(gameLogEntries, gameLogEntries.pitchingStrikeouts);
        await m.addColumn(gameLogEntries, gameLogEntries.pitchingWalks);
        await m.addColumn(gameLogEntries, gameLogEntries.runsAllowed);
      }
      if (from < 5) {
        // v4 → v5: the player's own "다음 경기에서 해볼 것" note. One new
        // table, nothing existing is touched — independent of whichever
        // branch above ran, so this is a separate top-level `if`, not
        // folded into the `else if` chain above it.
        await m.createTable(gameLogGoals);
      }
      await _createIndexes(m);
    },
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = OFF');
      // WAL keeps a background sync write from blocking a UI read.
      await customStatement('PRAGMA journal_mode = WAL');
      if (details.wasCreated) return;
      await _seedSourcePolicies();
    },
  );

  /// Indexes that back the queries the UI actually makes.
  ///
  /// `IF NOT EXISTS` so this is safe to run after both create and upgrade.
  Future<void> _createIndexes(Migrator m) async {
    const statements = <String>[
      // Games: the day/month board, team schedules, and dedupe lookups.
      'CREATE INDEX IF NOT EXISTS idx_games_day ON games (day_key)',
      'CREATE INDEX IF NOT EXISTS idx_games_month ON games (month_key)',
      'CREATE INDEX IF NOT EXISTS idx_games_start ON games (start_time_utc)',
      'CREATE INDEX IF NOT EXISTS idx_games_home ON games (home_team_id, start_time_utc)',
      'CREATE INDEX IF NOT EXISTS idx_games_away ON games (away_team_id, start_time_utc)',
      'CREATE INDEX IF NOT EXISTS idx_games_season ON games (season_id)',
      'CREATE INDEX IF NOT EXISTS idx_games_competition ON games (competition_id)',
      'CREATE INDEX IF NOT EXISTS idx_games_dedupe ON games (dedupe_key)',
      'CREATE INDEX IF NOT EXISTS idx_games_venue ON games (venue_id)',
      // Teams / venues: search and the region filter.
      'CREATE INDEX IF NOT EXISTS idx_teams_region ON teams (region)',
      'CREATE INDEX IF NOT EXISTS idx_teams_search ON teams (search_key)',
      'CREATE INDEX IF NOT EXISTS idx_team_aliases_norm ON team_aliases (normalized)',
      'CREATE INDEX IF NOT EXISTS idx_people_search ON people (search_key)',
      'CREATE INDEX IF NOT EXISTS idx_venues_region ON venues (region)',
      // Standings and rosters.
      'CREATE INDEX IF NOT EXISTS idx_standings_season ON standings (season_id, rank)',
      'CREATE INDEX IF NOT EXISTS idx_standings_team ON standings (team_id)',
      'CREATE INDEX IF NOT EXISTS idx_roster_team_season ON roster_entries (team_season_id)',
      'CREATE INDEX IF NOT EXISTS idx_team_seasons_team ON team_seasons (team_id)',
      'CREATE INDEX IF NOT EXISTS idx_team_seasons_season ON team_seasons (season_id)',
      // Content.
      'CREATE INDEX IF NOT EXISTS idx_articles_published ON articles (published_at)',
      'CREATE INDEX IF NOT EXISTS idx_articles_cluster ON articles (story_cluster_id)',
      'CREATE INDEX IF NOT EXISTS idx_videos_published ON videos (published_at)',
      'CREATE INDEX IF NOT EXISTS idx_clusters_updated ON story_clusters (last_updated_at)',
      'CREATE INDEX IF NOT EXISTS idx_cluster_sources ON story_sources (story_cluster_id)',
      'CREATE INDEX IF NOT EXISTS idx_links_from ON content_entity_links (from_kind, from_id)',
      'CREATE INDEX IF NOT EXISTS idx_links_to ON content_entity_links (to_kind, to_id)',
      'CREATE INDEX IF NOT EXISTS idx_episodes_season ON episodes (program_season_id, episode_number)',
      'CREATE INDEX IF NOT EXISTS idx_recaps_episode ON episode_recaps (episode_id)',
      'CREATE INDEX IF NOT EXISTS idx_guides_anchor ON beginner_guides (anchor_key)',
      // Weather: one lookup per game card.
      'CREATE INDEX IF NOT EXISTS idx_weather_game ON weather_forecasts (game_id)',
      'CREATE INDEX IF NOT EXISTS idx_weather_venue_time ON weather_forecasts (venue_id, target_time_utc)',
      // Bookkeeping.
      'CREATE INDEX IF NOT EXISTS idx_external_canonical ON external_identities (canonical_id)',
      'CREATE INDEX IF NOT EXISTS idx_revisions_entity ON entity_revisions (entity_type, entity_id)',
      'CREATE INDEX IF NOT EXISTS idx_sync_errors_run ON sync_errors (sync_run_id)',
      'CREATE INDEX IF NOT EXISTS idx_sync_runs_source ON sync_runs (source_name, started_at)',
      'CREATE INDEX IF NOT EXISTS idx_notifications_entity ON scheduled_notifications (entity_kind, entity_id)',
      'CREATE INDEX IF NOT EXISTS idx_journey_time ON journey_events (occurred_at)',
      // 출전 일지: the timeline view and 포지션 히스토리 both read in day order.
      'CREATE INDEX IF NOT EXISTS idx_game_log_day ON game_log_entries (day_key)',
      // 다음 경기에서 해볼 것: finding the one open goal (closed_at IS NULL).
      'CREATE INDEX IF NOT EXISTS idx_game_log_goals_open ON game_log_goals (closed_at)',
    ];
    for (final sql in statements) {
      await customStatement(sql);
    }
  }

  /// Default conflict-resolution ranking.
  ///
  /// Inserted with `DoNothing` so an operator-supplied override that arrives
  /// through the published data set is never clobbered on the next launch.
  Future<void> _seedSourcePolicies() async {
    const defaults = <({String name, int rank, bool human})>[
      // Governing bodies rank highest.
      (name: 'wbak', rank: 0, human: true),
      (name: 'kbsa', rank: 1, human: true),
      (name: 'wbsc', rank: 2, human: true),
      (name: 'wpbl', rank: 3, human: true),
      // Curated static publication.
      (name: 'static-manifest', rank: 10, human: true),
      // Human submissions outrank scraped guesses but not official records.
      (name: 'manual-submission', rank: 20, human: true),
      // Bundled demo data must lose to everything real.
      (name: 'seed', rank: 90, human: false),
    ];
    await batch((b) {
      b.insertAll(
        sourcePolicies,
        defaults
            .map(
              (d) => SourcePoliciesCompanion.insert(
                sourceName: d.name,
                officialRank: Value(d.rank),
                trustsHumanReview: Value(d.human),
              ),
            )
            .toList(growable: false),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  /// Wipes only synced content, keeping device-local state.
  ///
  /// Used by "데이터 다시 받기" in settings. Follows, saved items, seen state,
  /// and scheduled notifications survive deliberately — they are the user's,
  /// not the publisher's.
  Future<void> clearSyncedData() async {
    await transaction(() async {
      for (final table in <TableInfo<Table, dynamic>>[
        games,
        gameLineScores,
        battingStats,
        pitchingStats,
        standings,
        teamSeasons,
        rosterEntries,
        teamAliases,
        personAliases,
        teams,
        people,
        venues,
        stages,
        seasons,
        competitions,
        organizations,
        articles,
        videos,
        featuredTopics,
        programs,
        programSeasons,
        episodes,
        episodeRecaps,
        officialClips,
        storylines,
        featuredPeople,
        storyClusters,
        storySources,
        contentEntityLinks,
        beginnerGuides,
        attendanceInfos,
        weatherForecasts,
        externalIdentities,
        fieldProvenances,
        dataCoverages,
        syncStates,
      ]) {
        await delete(table).go();
      }
    });
  }
}
