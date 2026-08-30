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
  ///
  /// Upgrades are strictly additive. User-owned rows — follows, saved items,
  /// and scheduled notification settings — are never dropped or recreated;
  /// `test/unit/migration_test.dart` asserts exactly that.
  @override
  int get schemaVersion => 2;

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
