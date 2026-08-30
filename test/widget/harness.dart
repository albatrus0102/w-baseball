import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/app/app.dart';
import 'package:w_baseball/app/providers.dart';
import 'package:w_baseball/core/analytics/analytics.dart';
import 'package:w_baseball/core/config/app_config.dart';
import 'package:w_baseball/core/database/database.dart';
import 'package:w_baseball/core/design_system/theme.dart';
import 'package:w_baseball/core/platform/platform_services.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/data/repositories/preferences_repository.dart';
import 'package:w_baseball/data/sources/bundled_seed_data_source.dart';
import 'package:w_baseball/data/sync/content_sync.dart';
import 'package:w_baseball/data/sync/sync_contracts.dart';
import 'package:w_baseball/data/sync/sync_engine.dart';

/// Shared widget-test scaffolding.
///
/// Gives every test a real database, real repositories, and the real design
/// system — only the platform edges (notifications, maps, share, calendar) and
/// the preferences store are replaced. That way a widget test exercises the
/// same code path the app does, rather than a mock of it.

/// Device sizes the visual review covers.
class TestPhone {
  const TestPhone(this.name, this.size, {this.textScale = 1.0});

  final String name;
  final Size size;
  final double textScale;

  /// A small phone. The tightest layout the app must survive.
  static const small = TestPhone('small_360x640', Size(360, 640));

  /// A typical modern phone.
  static const regular = TestPhone('regular_412x915', Size(412, 915));

  /// A large phone.
  static const large = TestPhone('large_480x1040', Size(480, 1040));

  /// Accessibility: 130% text on the smallest screen is the hard case.
  static const largeText = TestPhone(
    'small_360x640_text130',
    Size(360, 640),
    textScale: 1.3,
  );

  static const all = <TestPhone>[small, regular, large, largeText];
}

/// A preferences store that lives in memory.
class FakePreferences implements PreferencesRepository {
  FakePreferences({
    AudiencePreference? audience,
    NotificationPreference? notifications,
    this.lastSuccessfulSyncAt,
  }) : _audience =
           audience ??
           const AudiencePreference(
             onboardingCompleted: true,
             regionCode: '11',
             regionLabel: '서울',
           ),
       _notifications = notifications ?? const NotificationPreference();

  AudiencePreference _audience;
  NotificationPreference _notifications;
  final List<String> _recent = <String>[];

  @override
  DateTime? lastSuccessfulSyncAt;

  @override
  AudiencePreference get audience => _audience;

  @override
  NotificationPreference get notifications => _notifications;

  @override
  List<String> get recentSearches => List<String>.unmodifiable(_recent);

  @override
  Future<void> addRecentSearch(String term) async => _recent.insert(0, term);

  @override
  Future<void> clearRecentSearches() async => _recent.clear();

  @override
  Future<void> reset() async {
    _audience = const AudiencePreference();
    _notifications = const NotificationPreference();
    _recent.clear();
  }

  @override
  Future<void> saveAudience(AudiencePreference preference) async {
    _audience = preference;
    _audienceController.add(preference);
  }

  @override
  Future<void> saveNotifications(NotificationPreference preference) async {
    _notifications = preference;
    _notificationController.add(preference);
  }

  @override
  Future<void> setLastSuccessfulSyncAt(DateTime value) async =>
      lastSuccessfulSyncAt = value;

  final _audienceController = StreamController<AudiencePreference>.broadcast();
  final _notificationController =
      StreamController<NotificationPreference>.broadcast();

  @override
  Stream<AudiencePreference> watchAudience() async* {
    yield _audience;
    yield* _audienceController.stream;
  }

  @override
  Stream<NotificationPreference> watchNotifications() async* {
    yield _notifications;
    yield* _notificationController.stream;
  }
}

/// A fully assembled app-under-test.
class TestApp {
  TestApp({
    required this.db,
    required this.container,
    required this.preferences,
  });

  final WbDatabase db;
  final ProviderContainer container;
  final FakePreferences preferences;

  Future<void> dispose() async {
    container.dispose();
    // Deliberately not awaited. `close()` waits for every open stream query to
    // unwind, and a provider container torn down mid-emission can leave one
    // pending forever — which hangs the test rather than failing it. The
    // in-memory database is discarded with the test isolate anyway.
    unawaited(db.close().catchError((Object _) {}));
  }
}

/// Builds an app with an in-memory database.
///
/// [seedAssets] loads the real bundled seed set, so tests exercise the same
/// data the first launch shows. Pass `false` for the empty-state tests.
Future<TestApp> buildTestApp({
  bool seedAssets = true,
  AppConfig? config,
  AudiencePreference? audience,
  NotificationPreference? notifications,
  DateTime? lastSync,
  Map<String, String>? documents,
  DateTime? frozenNow,
}) async {
  final resolvedConfig = config ?? AppConfig.fromEnvironment();
  final db = WbDatabase(NativeDatabase.memory());
  final preferences = FakePreferences(
    audience: audience,
    notifications: notifications,
    lastSuccessfulSyncAt: lastSync,
  );

  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(resolvedConfig),
      databaseProvider.overrideWithValue(db),
      preferencesProvider.overrideWithValue(preferences),
      // Platform edges are inert: no channels exist in a widget test.
      platformServicesProvider.overrideWithValue(PlatformServices.noop()),
      analyticsProvider.overrideWithValue(const NoopAnalyticsService()),
      // No network source, so nothing in a widget test can reach out.
      dataSourcesProvider.overrideWithValue(const []),
      // Pins every screen's clock. Screens ask `clockProvider` rather than
      // `DateTime.now()`, so this is what keeps a golden containing "방금 확인"
      // from becoming "5시간 전 확인" as the afternoon wears on.
      if (frozenNow != null)
        clockProvider.overrideWithValue(() => frozenNow),
    ],
  );

  if (seedAssets || documents != null) {
    // Seed files are read straight from disk rather than through `rootBundle`.
    // The asset channel resolves only once per test isolate, so a second
    // widget test that touched it would hang instead of failing.
    final source = BundledSeedDataSource(
      contract: resolvedConfig.dataContract,
      bundle: MapAssetBundle(documents ?? loadSeedFromDisk()),
    );

    final engine = SyncEngine(db: db, config: resolvedConfig);
    await engine.refreshSource(
      source,
      // Frozen too: months are derived from the clock, so a real-time month
      // boundary would silently change which fixtures a golden contains.
      scope: GameSyncScope(
        months: _monthsAround(frozenNow ?? DateTime.now().toUtc()),
      ),
      incremental: false,
    );
    final contentEngine = ContentSyncEngine(
      db: db,
      supportsSchemaVersion: resolvedConfig.dataContract.supports,
    );
    await contentEngine.syncFrom(source);

    if (frozenNow != null) {
      await _freezeProvenanceClocks(db, frozenNow);
    }
  }

  return TestApp(db: db, container: container, preferences: preferences);
}

/// Pins every stored provenance timestamp to [instant].
///
/// The sync engine stamps `fetched_at` with the wall clock, so a source line
/// renders "방금 확인" on one run and "7분 전 확인" on the next. That is fine in
/// the app and fatal in a golden: the image differs from itself with no code
/// change, which trains everyone to ignore golden failures.
///
/// Driven off `pragma table_info` rather than a hard-coded table list, so a new
/// table with provenance columns is covered without anyone remembering to add
/// it here.
Future<void> _freezeProvenanceClocks(WbDatabase db, DateTime instant) async {
  final seconds = instant.toUtc().millisecondsSinceEpoch ~/ 1000;
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      )
      .get();

  for (final table in tables) {
    final name = table.read<String>('name');
    final columns = await db.customSelect('PRAGMA table_info($name)').get();
    final has = columns.map((c) => c.read<String>('name')).toSet();
    final assignments = <String>[
      if (has.contains('fetched_at')) 'fetched_at = $seconds',
      if (has.contains('verified_at'))
        'verified_at = CASE WHEN verified_at IS NULL THEN NULL ELSE $seconds END',
    ];
    if (assignments.isEmpty) continue;
    await db.customStatement('UPDATE $name SET ${assignments.join(', ')}');
  }
}

List<String> _monthsAround(DateTime now) {
  final base = DateTime(now.year, now.month);
  return <String>[
    for (var i = -3; i <= 3; i++)
      '${DateTime(base.year, base.month + i).year.toString().padLeft(4, '0')}-'
          '${DateTime(base.year, base.month + i).month.toString().padLeft(2, '0')}',
  ];
}

/// Wraps a screen in the app's real theme and localisations, at a given size.
Future<void> pumpScreen(
  WidgetTester tester,
  TestApp app,
  Widget child, {
  TestPhone phone = TestPhone.regular,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = phone.size * tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = phone.size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: app.container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: brightness == Brightness.light
            ? WbTheme.light()
            : WbTheme.dark(),
        locale: const Locale('ko', 'KR'),
        supportedLocales: const <Locale>[Locale('ko', 'KR')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(phone.textScale)),
          // Mirrors `WbApp`: density comes from the preference under test, so a
          // screen pumped here lays out exactly as it does in the real app.
          child: WbDensityHost(child: widget ?? const SizedBox.shrink()),
        ),
        home: child,
      ),
    ),
  );

  // Let streams and futures settle without waiting on real timers forever.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Serves in-memory documents as if they were bundled assets.
class MapAssetBundle extends CachingAssetBundle {
  MapAssetBundle(this.documents, {this.prefix = 'assets/seed/'});

  final Map<String, String> documents;
  final String prefix;

  @override
  Future<ByteData> load(String key) async {
    final body = await loadString(key);
    return ByteData.view(Uint8List.fromList(utf8.encode(body)).buffer);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final path = key.startsWith(prefix) ? key.substring(prefix.length) : key;
    final body = documents[path];
    if (body == null) throw FlutterError('Asset not found: $key');
    return body;
  }
}

/// Pumps repeatedly so database streams and provider futures resolve.
///
/// `pumpAndSettle` is unusable here: the skeleton placeholders animate
/// continuously by design, so it would never settle.
Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Asserts nothing overflows at the current size — the check that catches
/// clipped Korean text and cramped cards on a small screen.
void expectNoOverflow(WidgetTester tester) {
  final exception = tester.takeException();
  if (exception != null) {
    fail('Layout threw: $exception');
  }
}

Map<String, String>? _seedCache;

/// Reads `assets/seed/**` from the working tree, keyed by the same relative
/// paths the app uses. Cached, because every test needs the same bytes.
Map<String, String> loadSeedFromDisk() {
  final cached = _seedCache;
  if (cached != null) return cached;

  const root = 'assets/seed';
  final dir = Directory(root);
  final out = <String, String>{};
  if (dir.existsSync()) {
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final relative = entity.path.replaceAll(r'\', '/').split('$root/').last;
      out[relative] = entity.readAsStringSync();
    }
  }
  return _seedCache = out;
}
