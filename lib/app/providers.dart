import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics/analytics.dart';
import '../core/config/app_config.dart';
import '../core/database/database.dart';
import '../core/design_system/tokens.dart';
import '../core/network/http_client.dart';
import '../core/platform/notification_scheduler.dart';
import '../core/platform/notification_service.dart';
import '../core/platform/platform_services.dart';
import '../data/models/audience.dart';
import '../data/models/content.dart';
import '../data/models/domain.dart';
import '../data/models/game_log.dart';
import '../data/models/reminder_status.dart';
import '../data/models/stats.dart';
import '../data/models/weather.dart';
import '../data/export/game_log_export_service.dart';
import '../data/repositories/competition_repository.dart';
import '../data/repositories/content_repository.dart';
import '../data/repositories/follow_repository.dart';
import '../data/repositories/game_log_goal_repository.dart';
import '../data/repositories/game_log_repository.dart';
import '../data/repositories/game_repository.dart';
import '../data/repositories/preferences_repository.dart';
import '../data/repositories/search_repository.dart';
import '../data/repositories/team_repository.dart';
import '../data/repositories/weather_repository.dart';
import '../data/sources/adapters/permission_gated_adapters.dart';
import '../data/sources/bundled_seed_data_source.dart';
import '../data/sources/future_rest_api_data_source.dart';
import '../data/sources/sports_data_source.dart';
import '../data/sources/static_manifest_data_source.dart';
import '../data/sync/sync_contracts.dart';
import '../data/sync/sync_engine.dart';

/// Dependency graph.
///
/// Everything below the UI is constructed here, once, and overridden wholesale
/// in tests. Screens depend on repository *interfaces* through these providers
/// and never construct a data source, a Dio client, or a database themselves.

// --- infrastructure ---------------------------------------------------------

/// Overridden in `bootstrap.dart` with the resolved configuration.
final appConfigProvider = Provider<AppConfig>((ref) {
  throw UnimplementedError('appConfigProvider must be overridden in bootstrap');
});

final databaseProvider = Provider<WbDatabase>((ref) {
  throw UnimplementedError('databaseProvider must be overridden in bootstrap');
});

final preferencesProvider = Provider<PreferencesRepository>((ref) {
  throw UnimplementedError(
    'preferencesProvider must be overridden in bootstrap',
  );
});

final platformServicesProvider = Provider<PlatformServices>(
  (ref) => PlatformServices.forCurrentPlatform(),
);

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = LocalNotificationService(db: ref.watch(databaseProvider));
  return service;
});

final analyticsProvider = Provider<AnalyticsService>((ref) {
  // Local-only. No third-party SDK is wired in, and none may be enabled
  // without explicit consent plus a privacy policy.
  return LocalAnalyticsService(db: ref.watch(databaseProvider));
});

final httpClientProvider = Provider<WbHttpClient>((ref) {
  final client = WbHttpClient(config: ref.watch(appConfigProvider).sync);
  ref.onDispose(client.close);
  return client;
});

/// Where the static manifest source remembers ETags between launches.
final validatorStoreProvider = Provider<ValidatorStore>((ref) {
  return DriftValidatorStore(ref.watch(databaseProvider));
});

// --- data sources -----------------------------------------------------------

final seedSourceProvider = Provider<BundledSeedDataSource>((ref) {
  return BundledSeedDataSource(
    contract: ref.watch(appConfigProvider).dataContract,
  );
});

final manifestSourceProvider = Provider<StaticManifestDataSource>((ref) {
  final config = ref.watch(appConfigProvider);
  return StaticManifestDataSource(
    config: config.manifest,
    contract: config.dataContract,
    httpClient: ref.watch(httpClientProvider),
    validatorStore: ref.watch(validatorStoreProvider),
  );
});

/// Every source the sync engine should try, in priority order.
///
/// Adding an official API later means appending one entry here. Adapters whose
/// feature flag is off report `isEnabled == false` and are skipped without
/// being an error.
final dataSourcesProvider = Provider<List<SportsDataSource>>((ref) {
  final config = ref.watch(appConfigProvider);
  return <SportsDataSource>[
    // A real official API, when one is configured, outranks everything.
    FutureRestApiDataSource(
      config: config.futureApi,
      contract: config.dataContract,
      httpClient: ref.watch(httpClientProvider),
    ),
    FutureGraphqlDataSource(
      config: config.futureApi,
      contract: config.dataContract,
    ),
    // Licence-gated adapters. Every one reports isEnabled == false unless its
    // flag is explicitly set, and the engine skips a disabled source without
    // recording an error.
    ...buildGatedAdapters(config.flags),
    ref.watch(manifestSourceProvider),
    // Seed data is applied last so a real source always wins on conflict
    // (see the `seed` entry in `source_policies`, rank 90).
    ref.watch(seedSourceProvider),
  ];
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    db: ref.watch(databaseProvider),
    config: ref.watch(appConfigProvider),
  );
});

// --- repositories -----------------------------------------------------------

final gameRepositoryProvider = Provider<GameRepository>((ref) {
  return DriftGameRepository(
    db: ref.watch(databaseProvider),
    onRefresh: (scope) async {
      final report = await ref
          .read(syncEngineProvider)
          .refreshAll(ref.read(dataSourcesProvider), scope: scope);
      if (_hasRealSyncSuccess(report)) {
        await ref
            .read(preferencesProvider)
            .setLastSuccessfulSyncAt(DateTime.now().toUtc());
      }
      return report.results.isEmpty
          ? SyncResult(
              sourceName: 'none',
              startedAt: DateTime.now().toUtc(),
              finishedAt: DateTime.now().toUtc(),
            )
          : report.results.first;
    },
  );
});

final teamRepositoryProvider = Provider<TeamRepository>((ref) {
  return DriftTeamRepository(
    db: ref.watch(databaseProvider),
    gameRepository: ref.watch(gameRepositoryProvider),
    clock: ref.watch(clockProvider),
  );
});

final competitionRepositoryProvider = Provider<CompetitionRepository>((ref) {
  return DriftCompetitionRepository(
    db: ref.watch(databaseProvider),
    gameRepository: ref.watch(gameRepositoryProvider),
  );
});

final contentRepositoryProvider = Provider<ContentRepository>((ref) {
  return DriftContentRepository(db: ref.watch(databaseProvider));
});

final followRepositoryProvider = Provider<FollowRepository>((ref) {
  return DriftFollowRepository(db: ref.watch(databaseProvider));
});

final gameLogRepositoryProvider = Provider<GameLogRepository>((ref) {
  return DriftGameLogRepository(
    db: ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
  );
});

final gameLogExportServiceProvider = Provider<GameLogExportService>(
  (ref) => const GameLogExportService(),
);

final gameLogGoalRepositoryProvider = Provider<GameLogGoalRepository>((ref) {
  return DriftGameLogGoalRepository(
    db: ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
  );
});

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return DriftWeatherRepository(db: ref.watch(databaseProvider));
});

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return DriftSearchRepository(
    db: ref.watch(databaseProvider),
    playerProfilesEnabled: ref
        .watch(appConfigProvider)
        .flags
        .playerProfilesEnabled,
  );
});

// --- preferences ------------------------------------------------------------

/// The user's audience mode, region, and spoiler policy.
final audiencePreferenceProvider = StreamProvider<AudiencePreference>((ref) {
  return ref.watch(preferencesProvider).watchAudience();
});

/// Synchronous access for widgets that must not wait a frame.
final audienceProvider = Provider<AudiencePreference>((ref) {
  return ref.watch(audiencePreferenceProvider).value ??
      ref.watch(preferencesProvider).audience;
});

final spoilerPolicyProvider = Provider<SpoilerPolicy>(
  (ref) => ref.watch(audienceProvider).spoilerPolicy,
);

final showBeginnerExplanationsProvider = Provider<bool>(
  (ref) => ref.watch(audienceProvider).showBeginnerExplanations,
);

/// The resolved information density: the user's explicit choice when they made
/// one, otherwise the default for their mode.
final densityProvider = Provider<WbDensity>(
  (ref) => ref.watch(audienceProvider).density,
);

final notificationPreferenceProvider = StreamProvider<NotificationPreference>((
  ref,
) {
  return ref.watch(preferencesProvider).watchNotifications();
});

/// Mutations for audience settings, so screens never touch the store directly.
class AudienceController {
  AudienceController(this._ref);

  final Ref _ref;

  PreferencesRepository get _prefs => _ref.read(preferencesProvider);
  AnalyticsService get _analytics => _ref.read(analyticsProvider);

  Future<void> setMode(AudienceMode mode) async {
    await _prefs.saveAudience(_prefs.audience.copyWith(mode: mode));
    await _analytics.log(
      AnalyticsEvent.audienceModeSelected,
      properties: <String, Object?>{'mode': mode.wireValue},
    );
  }

  Future<void> setRegion(String? code, String? label) async {
    await _prefs.saveAudience(
      code == null
          ? _prefs.audience.copyWith(clearRegion: true)
          : _prefs.audience.copyWith(regionCode: code, regionLabel: label),
    );
    await _analytics.log(
      AnalyticsEvent.regionSelected,
      properties: <String, Object?>{'has_region': code != null},
    );
  }

  Future<void> setSpoilerPolicy(SpoilerPolicy policy) =>
      _prefs.saveAudience(_prefs.audience.copyWith(spoilerPolicy: policy));

  Future<void> setBeginnerExplanations(bool value) => _prefs.saveAudience(
    _prefs.audience.copyWith(showBeginnerExplanations: value),
  );

  /// Passing null restores "follow my mode".
  Future<void> setDensity(WbDensity? density) => _prefs.saveAudience(
    _prefs.audience.copyWith(
      densityOverride: density,
      clearDensityOverride: density == null,
    ),
  );

  Future<void> setSearchRadius(int km) =>
      _prefs.saveAudience(_prefs.audience.copyWith(searchRadiusKm: km));

  Future<void> completeOnboarding() =>
      _prefs.saveAudience(_prefs.audience.copyWith(onboardingCompleted: true));

  Future<void> skipOnboarding() async {
    await _prefs.saveAudience(
      _prefs.audience.copyWith(
        onboardingCompleted: true,
        onboardingSkipped: true,
      ),
    );
    await _analytics.log(AnalyticsEvent.onboardingSkipped);
  }

  Future<void> toggleModuleCollapsed(String moduleKey) async {
    final current = _prefs.audience.collapsedModules.toSet();
    current.contains(moduleKey)
        ? current.remove(moduleKey)
        : current.add(moduleKey);
    await _prefs.saveAudience(
      _prefs.audience.copyWith(collapsedModules: current),
    );
  }

  Future<void> setHomeModuleOrder(List<String> order) =>
      _prefs.saveAudience(_prefs.audience.copyWith(homeModuleOrder: order));

  /// One-time dismissal of the home "모드 바꾸기" nudge, for someone who
  /// skipped onboarding and does not want the reminder any more. Does not
  /// touch onboarding state — 시작 화면과 지역 in 더보기 still opens the same
  /// picker, so this only removes the unsolicited banner, not the feature.
  Future<void> dismissModeNudge() =>
      _prefs.saveAudience(_prefs.audience.copyWith(modeNudgeDismissed: true));

  /// One-time dismissal of the 출전 일지 "경기 하고 오셨나요?" card for someone
  /// who has not logged a game yet and does not want the reminder. Logging a
  /// first entry makes the card disappear on its own (see `GameLogModule`);
  /// this only covers the "I saw it and don't want it right now" path.
  Future<void> dismissGameLogNudge() => _prefs.saveAudience(
    _prefs.audience.copyWith(gameLogNudgeDismissed: true),
  );

  /// One-way switch: once a player has saved a 경기 기록하기 entry with the
  /// 성적 section expanded, the sheet stops asking her to re-expand it every
  /// time. Never called with `false` — see `AudiencePreference
  /// .gameLogStatsExpanded`'s doc.
  Future<void> markGameLogStatsExpanded() =>
      _prefs.saveAudience(_prefs.audience.copyWith(gameLogStatsExpanded: true));
}

final audienceControllerProvider = Provider<AudienceController>(
  (ref) => AudienceController(ref),
);

// --- derived reads ----------------------------------------------------------

final nextGameProvider = StreamProvider<NextGameSummary?>((ref) {
  return ref.watch(gameRepositoryProvider).watchNextGame();
});

/// Turns follows, saved games and notification preferences into a real
/// platform schedule.
///
/// The whole schedule is recomputed whenever any input changes. That is
/// deliberate: an incremental edit has to be right every time to stay correct,
/// while a full reconcile only has to run at all. The service diffs against
/// what is already registered, so re-running costs nothing.
final notificationSchedulerProvider = Provider<NotificationScheduler>((ref) {
  return NotificationScheduler(
    games: ref.watch(gameRepositoryProvider),
    follows: ref.watch(followRepositoryProvider),
    notifications: ref.watch(notificationServiceProvider),
  );
});

/// Why reminders would not arrive, and how many are scheduled.
///
/// One judgement for every screen that reports on alerts. Two screens deciding
/// this separately is how the app came to blame the notification categories
/// for a denial the user had just made at the OS level.
final reminderStatusProvider = FutureProvider<ReminderStatus>((ref) async {
  final preference = ref.watch(notificationPreferenceProvider).value;
  if (preference == null) {
    return const ReminderStatus(
      blocker: ReminderBlocker.nothingToAlertAbout,
      scheduledCount: 0,
    );
  }

  final followedTeams = ref.watch(followedTeamIdsProvider).value ?? const {};
  final savedGames = ref.watch(savedGameIdsProvider).value ?? const {};
  final hasPermission = await ref
      .watch(notificationServiceProvider)
      .hasPermission();

  return ReminderStatus(
    blocker: ReminderBlocker.evaluate(
      hasPermission: hasPermission,
      preference: preference,
      countdownCategories: NotificationPlanner.leadTimes.keys.toSet(),
      hasSomethingFollowed: followedTeams.isNotEmpty || savedGames.isNotEmpty,
    ),
    scheduledCount: await ref.watch(scheduledNotificationCountProvider.future),
  );
});

/// How many alerts are currently scheduled.
///
/// Watching this provider is what *causes* the scheduling — the count is the
/// by-product. Keeping it that way means no screen has to remember to call a
/// reschedule after changing a follow, which is exactly the kind of thing every
/// screen eventually forgets.
final scheduledNotificationCountProvider = FutureProvider<int>((ref) async {
  final preference = ref.watch(notificationPreferenceProvider).value;
  if (preference == null) return 0;

  // Watched for their change signal, not their values: the scheduler reads
  // both itself. Listing them here is what makes a new follow reschedule.
  ref.watch(followedTeamIdsProvider);
  ref.watch(savedGameIdsProvider);

  return ref.watch(notificationSchedulerProvider).reschedule(preference);
});

final followedTeamIdsProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(followRepositoryProvider).watchFollowedIds(FollowKind.team);
});

final savedGameIdsProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(followRepositoryProvider).watchSavedIds(SavedItemKind.game);
});

/// The player's own 출전 일지, most recent game first. Watched rather than
/// fetched once, so a new entry (or a deletion) updates the module, the
/// count, and the derived 포지션 히스토리 in the same frame.
final gameLogEntriesProvider = StreamProvider<List<GameLogEntry>>((ref) {
  return ref.watch(gameLogRepositoryProvider).watchEntries();
});

/// The player's one open "다음 경기에서 해볼 것" goal, if any — null once it
/// has been closed one way or another. See `GameLogGoalRepository`.
final gameLogOpenGoalProvider = StreamProvider<GameLogGoal?>((ref) {
  return ref.watch(gameLogGoalRepositoryProvider).watchOpenGoal();
});

final featuredProvider = StreamProvider<List<FeaturedItem>>((ref) {
  return ref.watch(contentRepositoryProvider).watchFeatured();
});

final topStoriesProvider = StreamProvider<List<StoryCluster>>((ref) {
  return ref.watch(contentRepositoryProvider).watchTopStories();
});

final storiesForYouProvider = StreamProvider<List<StoryCluster>>((ref) {
  return ref.watch(contentRepositoryProvider).watchStoriesForYou();
});

final gamesProvider = StreamProvider.family<List<GameCard>, GameQuery>((
  ref,
  query,
) {
  return ref.watch(gameRepositoryProvider).watchGames(query);
});

final gameDetailProvider = StreamProvider.family<GameDetail?, String>((
  ref,
  gameId,
) {
  return ref.watch(gameRepositoryProvider).watchGame(gameId);
});

final teamsProvider = StreamProvider.family<List<Team>, TeamQuery>((
  ref,
  query,
) {
  return ref.watch(teamRepositoryProvider).watchTeams(query);
});

final teamDetailProvider = StreamProvider.family<TeamDetail?, String>((
  ref,
  teamId,
) {
  return ref.watch(teamRepositoryProvider).watchTeam(teamId);
});

final competitionDetailProvider =
    StreamProvider.family<CompetitionDetail?, String>((ref, seasonId) {
      return ref
          .watch(competitionRepositoryProvider)
          .watchCompetitionDetail(seasonId);
    });

final leaguePulseProvider = StreamProvider.family<LeaguePulse?, String>((
  ref,
  seasonId,
) {
  return ref.watch(competitionRepositoryProvider).watchLeaguePulse(seasonId);
});

final leaderboardsProvider = FutureProvider.family<List<Leaderboard>, String>((
  ref,
  seasonId,
) {
  return ref.watch(competitionRepositoryProvider).leaderboards(seasonId);
});

/// The season used by the games tab's 순위 section: the ongoing domestic
/// season with standings if one exists, otherwise the most recent season
/// (any level) that has standings, otherwise null.
///
/// Unlike `_mySeasonProvider` in `my_baseball_screen.dart`, this must resolve
/// with no followed team at all — 순위 is a always-present sibling of 일정/결과
/// on the 경기 tab, not something gated on having followed a team.
///
/// `availableStandingSeasons()` lists which seasons the bundled seed ships a
/// standings partition for; each candidate is then read back from the synced
/// database (via `competitionDetailProvider`) to get its level/phase and to
/// skip a season whose file listed it but which produced no rows. A real
/// source, once connected, would extend this by also reading
/// `manifestSourceProvider.availableStandingSeasons()` the same way.
final standingsSeasonProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final seasonIds = await ref
      .watch(seedSourceProvider)
      .availableStandingSeasons();
  if (seasonIds.isEmpty) return null;

  Season? ongoingDomestic;
  Season? mostRecentWithStandings;
  for (final id in seasonIds) {
    final detail = await ref.watch(competitionDetailProvider(id).future);
    if (detail == null || detail.standings.isEmpty) continue;
    final season = detail.season;
    if (mostRecentWithStandings == null ||
        season.year > mostRecentWithStandings.year) {
      mostRecentWithStandings = season;
    }
    if (ongoingDomestic == null &&
        detail.competition.level == CompetitionLevel.domestic &&
        season.phase == CompetitionPhase.ongoing) {
      ongoingDomestic = season;
    }
  }
  return (ongoingDomestic ?? mostRecentWithStandings)?.id;
});

final teamRegionsProvider = StreamProvider<List<String>>((ref) {
  return ref.watch(teamRepositoryProvider).watchRegions();
});

final competitionsProvider = StreamProvider<List<Competition>>((ref) {
  return ref.watch(competitionRepositoryProvider).watchCompetitions();
});

/// Identifies a set of (game, kick-off) pairs by value.
///
/// A Riverpod family key must have real equality. Keying this by a raw `Map`
/// would create a brand-new provider on every rebuild — which cascades into an
/// endless rebuild loop, not merely a cache miss.
@immutable
class WeatherRiskQuery {
  const WeatherRiskQuery._(this.encoded);

  factory WeatherRiskQuery.of(Map<String, DateTime> gameTimes) {
    final parts =
        gameTimes.entries
            .map((e) => '${e.key}@${e.value.toUtc().millisecondsSinceEpoch}')
            .toList()
          ..sort();
    return WeatherRiskQuery._(parts.join(','));
  }

  final String encoded;

  Map<String, DateTime> decode() {
    if (encoded.isEmpty) return const <String, DateTime>{};
    return <String, DateTime>{
      for (final part in encoded.split(','))
        part.substring(
          0,
          part.lastIndexOf('@'),
        ): DateTime.fromMillisecondsSinceEpoch(
          int.parse(part.substring(part.lastIndexOf('@') + 1)),
          isUtc: true,
        ),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeatherRiskQuery && other.encoded == encoded;

  @override
  int get hashCode => encoded.hashCode;
}

/// Weather risk for a set of games, keyed by game id.
final weatherRisksProvider =
    FutureProvider.family<Map<String, WeatherRisk>, WeatherRiskQuery>((
      ref,
      query,
    ) {
      return ref.watch(weatherRepositoryProvider).risksForGames(query.decode());
    });

final gameWeatherProvider = StreamProvider.family<WeatherForecast?, String>((
  ref,
  gameId,
) {
  return ref.watch(weatherRepositoryProvider).watchForecast(gameId);
});

/// The current instant, as a function.
///
/// Screens call `ref.watch(clockProvider)()` instead of `DateTime.now()`, so a
/// test can pin the clock: a screenshot taken at 09:00 and the same screenshot
/// taken at 14:00 then render identically. Without this every golden that
/// prints a relative time ("방금 확인", "3분 전") drifts on its own.
///
/// A function rather than a `Provider<DateTime>`. A cached instant is read once
/// and never moves, so "3분 전" would still read "3분 전" an hour later. The
/// closure's identity is stable, so watching it costs no extra rebuilds — each
/// build just asks the clock again, exactly as `DateTime.now()` did.
typedef WbClock = DateTime Function();

final clockProvider = Provider<WbClock>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

/// Drift-backed implementation of the manifest source's validator store.
class DriftValidatorStore implements ValidatorStore {
  DriftValidatorStore(this.db);

  final WbDatabase db;

  @override
  Future<SyncValidators> load(String key) async {
    final row = await (db.select(
      db.syncStates,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    if (row == null) return const SyncValidators();
    return SyncValidators(etag: row.etag, lastModified: row.lastModified);
  }

  @override
  Future<String?> loadHash(String key) async {
    final row = await (db.select(
      db.syncStates,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.contentHash;
  }

  @override
  Future<void> save(
    String key,
    SyncValidators validators, {
    String? sha256,
  }) async {
    await db
        .into(db.syncStates)
        .insertOnConflictUpdate(
          SyncStatesCompanion.insert(
            key: key,
            etag: Value(validators.etag),
            lastModified: Value(validators.lastModified),
            contentHash: Value(sha256),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  @override
  Future<void> clear() async {
    await db.delete(db.syncStates).go();
  }
}

/// Sync status shown in the app bar and the settings screen.
@immutable
class SyncStatus {
  const SyncStatus({
    required this.isSyncing,
    this.lastSuccessAt,
    this.lastReport,
  });

  final bool isSyncing;
  final DateTime? lastSuccessAt;
  final SyncReport? lastReport;

  bool isStale(DateTime now, Duration threshold) {
    final last = lastSuccessAt;
    if (last == null) return true;
    return now.difference(last) > threshold;
  }

  /// A partial success is reported honestly rather than as a clean success —
  /// but only when a *real* source actually contributed something.
  ///
  /// The bundled seed always succeeds, so `lastReport.anySucceeded` alone is
  /// always true whenever the seed is in the source list — which is always.
  /// Gated on that, `isPartial` collapsed to plain `anyFailed`: a remote
  /// source configured and completely unreachable would still show "일부
  /// 데이터만 갱신됨", because the seed's re-read (not a sync in any sense a
  /// user cares about) was propping up `anySucceeded`. That is the exact
  /// overstatement `_hasRealSyncSuccess` exists to prevent for
  /// `lastSuccessAt`, one screen over — so the same predicate applies here.
  /// When no real source succeeds, this is not a partial sync; it is a sync
  /// that did not happen, and showing no badge (rather than inventing a
  /// "failed" one) is the same fail-safe-silence choice the rest of this
  /// feature makes.
  bool get isPartial {
    final report = lastReport;
    if (report == null) return false;
    return report.anyFailed && _hasRealSyncSuccess(report);
  }
}

class SyncController extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => SyncStatus(
    isSyncing: false,
    lastSuccessAt: ref.read(preferencesProvider).lastSuccessfulSyncAt,
  );

  /// Refreshes every enabled source. Never throws: a failure becomes state the
  /// UI can explain, because the cached data is still on screen.
  Future<SyncReport> refresh({GameSyncScope? scope, bool force = false}) async {
    if (state.isSyncing) return SyncReport.empty(DateTime.now().toUtc());

    final prefs = ref.read(preferencesProvider);
    final config = ref.read(appConfigProvider);
    final now = DateTime.now().toUtc();

    // Rate-limit automatic refreshes; an explicit pull-to-refresh forces.
    if (!force) {
      final last = prefs.lastSuccessfulSyncAt;
      if (last != null &&
          now.difference(last) < config.sync.minAutoRefreshInterval) {
        return SyncReport.empty(now);
      }
    }

    state = SyncStatus(
      isSyncing: true,
      lastSuccessAt: state.lastSuccessAt,
      lastReport: state.lastReport,
    );

    final report = await ref
        .read(syncEngineProvider)
        .refreshAll(ref.read(dataSourcesProvider), scope: scope);

    if (_hasRealSyncSuccess(report)) {
      await prefs.setLastSuccessfulSyncAt(report.finishedAt);
    }

    state = SyncStatus(
      isSyncing: false,
      lastSuccessAt: _hasRealSyncSuccess(report)
          ? report.finishedAt
          : state.lastSuccessAt,
      lastReport: report,
    );
    return report;
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

/// True when [report] contains a success from something other than the
/// bundled seed.
///
/// `report.anySucceeded` alone is not enough to advance `lastSuccessfulSyncAt`
/// — re-reading the seed bundle always "succeeds" (the asset shipped inside
/// the APK cannot fail to load) and is not a sync in the sense a user cares
/// about, since nothing left the device. Counting it here was reproduced as
/// the cause of the app bar claiming "방금 갱신" seconds after a fresh install
/// with no remote configured at all: `dataSourcesProvider` still contains the
/// seed source, `refreshAll` re-reads it, and `anySucceeded` was true.
bool _hasRealSyncSuccess(SyncReport report) => report.results.any(
  (r) => r.isSuccess && r.sourceName != BundledSeedDataSource.seedSourceName,
);

/// True when at least one source other than the bundled seed could ever
/// succeed — a static manifest URL, a future official API, or a licence-
/// gated adapter.
///
/// The seed reports `isEnabled == true` unconditionally, so it can never be
/// what distinguishes "there is somewhere real to sync from" versus "this
/// install is running on nothing but what shipped in the APK". Only the
/// *other* sources' own configuration answers that.
final hasRemoteSourceConfiguredProvider = Provider<bool>((ref) {
  final config = ref.watch(appConfigProvider);
  return config.manifest.isConfigured ||
      config.futureApi.isConfigured ||
      config.flags.wbakAdapterEnabled ||
      config.flags.kbsaAdapterEnabled ||
      config.flags.wbscAdapterEnabled ||
      config.flags.wpblAdapterEnabled;
});

/// The threshold `WbFreshnessScope` should carry, or null when no source line
/// anywhere may currently render a freshness verdict.
///
/// A verdict needs two things to both be true: somewhere real to sync from,
/// and a real sync having actually succeeded at least once. Neither alone is
/// sufficient — a configured-but-unreachable manifest must not silently
/// borrow the "fresh" reading a previous, different remote earned, and an
/// unconfigured install must not read `lastSuccessAt` (which the seed can
/// never set — see `_hasRealSyncSuccess`) as proof of anything.
final freshnessThresholdProvider = Provider<Duration?>((ref) {
  final hasRemote = ref.watch(hasRemoteSourceConfiguredProvider);
  final everSynced = ref.watch(syncControllerProvider).lastSuccessAt != null;
  return hasRemote && everSynced
      ? ref.watch(appConfigProvider).sync.staleAfter
      : null;
});

/// The three states any freshness-reporting surface can be in.
///
/// Kept as one enum rather than each screen re-deriving it from
/// `hasRemoteSourceConfiguredProvider` and `SyncStatus.lastSuccessAt`
/// separately: that duplication is exactly how the app bar came to announce
/// "방금 갱신" for a bundle re-read that never left the device — two call
/// sites asking a subtly different question and agreeing only by accident.
enum FreshnessState {
  /// Nothing has ever been configured to sync from. Not a temporary
  /// condition the user is waiting out — there is nothing to wait for.
  noRemoteConfigured,

  /// A remote source is configured but has never actually synced yet.
  neverSynced,

  /// A remote source is configured and has synced at least once.
  synced;

  static FreshnessState resolve({
    required bool hasRemoteConfigured,
    required DateTime? lastSuccessAt,
  }) {
    if (!hasRemoteConfigured) return FreshnessState.noRemoteConfigured;
    return lastSuccessAt == null
        ? FreshnessState.neverSynced
        : FreshnessState.synced;
  }
}
