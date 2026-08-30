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
import '../data/models/reminder_status.dart';
import '../data/models/stats.dart';
import '../data/models/weather.dart';
import '../data/repositories/competition_repository.dart';
import '../data/repositories/content_repository.dart';
import '../data/repositories/follow_repository.dart';
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
      if (report.anySucceeded) {
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

/// Now, refreshed on demand. Widgets read this instead of calling
/// `DateTime.now()` so tests can pin the clock.
final nowProvider = Provider<DateTime>((ref) => DateTime.now().toUtc());

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

  /// A partial success is reported honestly rather than as a clean success.
  bool get isPartial =>
      lastReport?.anyFailed == true && lastReport?.anySucceeded == true;
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

    if (report.anySucceeded) {
      await prefs.setLastSuccessfulSyncAt(report.finishedAt);
    }

    state = SyncStatus(
      isSyncing: false,
      lastSuccessAt: report.anySucceeded
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
