import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/database/database.dart';
import '../data/repositories/preferences_repository.dart';
import '../data/sync/content_sync.dart';
import '../data/sync/sync_contracts.dart';
import 'app.dart';
import 'providers.dart';

/// Startup sequence.
///
/// Ordering is deliberate and is what makes "cached content before the network"
/// literally true:
///   1. Open the database and read preferences — both local, both fast.
///   2. Build the provider container and run the app. The first frame renders
///      from SQLite.
///   3. *After* the first frame, apply bundled seed data if the database is
///      empty, then refresh from the network in the background.
///
/// There is no splash screen that waits on a socket, and no code path where an
/// empty database plus no network produces a blank screen.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  final db = WbDatabase();
  final prefs = await SharedPrefsRepository.create();

  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(config),
      databaseProvider.overrideWithValue(db),
      preferencesProvider.overrideWithValue(prefs),
    ],
  );

  // Surface framework errors rather than letting a screen silently go blank.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      debugPrint('[wb] Flutter error: ${details.exceptionAsString()}');
    }
  };

  runApp(UncontrolledProviderScope(container: container, child: const WbApp()));

  // Everything below runs after the first frame has been scheduled.
  unawaited(_warmUp(container));
}

/// Post-first-frame work: seed, notifications, then a network refresh.
///
/// Every step is individually guarded. A failure here degrades a feature; it
/// never prevents the app from running on the data it already has.
Future<void> _warmUp(ProviderContainer container) async {
  try {
    await _applySeedIfEmpty(container);
  } on Object catch (e) {
    debugPrint('[wb] seed failed: $e');
  }

  try {
    await container.read(notificationServiceProvider).initialize();
  } on Object catch (e) {
    debugPrint('[wb] notifications unavailable: $e');
  }

  try {
    // Not forced: this respects the minimum auto-refresh interval, so
    // relaunching repeatedly does not hammer the static host.
    await container.read(syncControllerProvider.notifier).refresh();
  } on Object catch (e) {
    debugPrint('[wb] background refresh failed: $e');
  }
}

/// Loads the bundled data set the first time the app runs.
///
/// Only when the database has no teams: after that the published data set is
/// authoritative, and re-applying seed rows would resurrect demo records the
/// user has since replaced with real ones.
Future<void> _applySeedIfEmpty(ProviderContainer container) async {
  final db = container.read(databaseProvider);
  // A single cheap probe: the reference tables are small, and this avoids
  // pulling drift's aggregate helpers into a file that also imports Material
  // (both export a `Column`).
  final existing = await (db.select(db.teams)..limit(1)).get();
  if (existing.isNotEmpty) return;

  final engine = container.read(syncEngineProvider);
  final seed = container.read(seedSourceProvider);
  await engine.refreshSource(
    seed,
    // A wide window so the first launch has recent results and upcoming
    // fixtures, not just the current month.
    scope: GameSyncScope(
      months: _monthsAround(DateTime.now().toUtc(), before: 3, after: 3),
      fullRefresh: true,
    ),
    incremental: false,
  );

  // The discovery bundle (featured topics, programme, story clusters, guides,
  // weather) travels in one document and is applied by its own engine, which
  // reuses the same envelope, DTO and quarantine rules.
  final config = container.read(appConfigProvider);
  final contentEngine = ContentSyncEngine(
    db: db,
    supportsSchemaVersion: config.dataContract.supports,
  );
  await contentEngine.syncFrom(seed);
}

List<String> _monthsAround(
  DateTime now, {
  required int before,
  required int after,
}) {
  final base = DateTime(now.year, now.month);
  return <String>[
    for (var i = -before; i <= after; i++)
      _monthKey(DateTime(base.year, base.month + i)),
  ];
}

String _monthKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
