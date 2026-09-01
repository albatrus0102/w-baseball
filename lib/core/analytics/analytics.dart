import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/database.dart';

/// Product events worth measuring.
///
/// These exist to answer "did the user complete the task?", not "how many
/// screens did we serve". Event *counts* are not the goal; task completion is.
enum AnalyticsEvent {
  onboardingSkipped,
  audienceModeSelected,
  regionSelected,
  teamFollowed,
  featuredTopicOpened,
  recapCompleted,
  spoilerRevealed,
  nearbyGameViewed,
  gameSaved,
  directionsOpened,
  calendarAdded,
  myBaseballConfigured,
  weatherRiskViewed,
  standingsViewed,
  leaderboardViewed,
  notificationCategoryEnabled,
  sourceOpened,
  correctionSubmitted,
  searchPerformed,
  taskCompleted,
  gameLogEntryAdded,
  gameLogEntryDeleted,
  gameLogExported;

  String get wireValue {
    // snake_case, matching the names in the product brief.
    final buffer = StringBuffer();
    for (var i = 0; i < name.length; i++) {
      final char = name[i];
      final lower = char.toLowerCase();
      if (char != lower && i > 0) buffer.write('_');
      buffer.write(lower);
    }
    return buffer.toString();
  }
}

/// Analytics sink.
///
/// There is deliberately no third-party SDK wired in. This interface exists so
/// one can be added later behind explicit consent and a privacy policy; until
/// then the only implementation writes to a local table that never leaves the
/// device.
abstract interface class AnalyticsService {
  /// Whether events are being recorded at all.
  bool get isEnabled;

  Future<void> log(AnalyticsEvent event, {Map<String, Object?> properties});

  /// Records that a benchmark task was completed, with the tap count it took.
  /// Feeds the table in `docs/task-benchmarks.md`.
  Future<void> logTaskCompletion({
    required String taskKey,
    required int taps,
    required Duration elapsed,
  });

  Future<List<AnalyticsRecord>> recent({int limit = 200});

  Future<void> clear();
}

@immutable
class AnalyticsRecord {
  const AnalyticsRecord({
    required this.name,
    required this.occurredAt,
    this.properties = const <String, Object?>{},
  });

  final String name;
  final DateTime occurredAt;
  final Map<String, Object?> properties;
}

/// Writes events to the local `journey_events` table.
///
/// Privacy rules enforced here, not left to callers:
///  * a strict allowlist of property keys — anything else is dropped,
///  * values are coerced to short primitives,
///  * coordinates, addresses, free text, and identifiers are never accepted.
class LocalAnalyticsService implements AnalyticsService {
  LocalAnalyticsService({
    required this.db,
    this.enabled = true,
    DateTime Function()? clock,
    this.maxRows = 1000,
  }) : _clock = clock ?? DateTime.now;

  /// Keys we are willing to store. Deliberately coarse and non-identifying.
  static const Set<String> _allowedKeys = <String>{
    'mode',
    'screen',
    'taps',
    'elapsed_ms',
    'task',
    'category',
    'source',
    'horizon',
    'result_count',
    'has_region',
    'is_demo',
    'spoiler_policy',
    'entity_kind',
  };

  final WbDatabase db;
  final bool enabled;
  final DateTime Function() _clock;

  /// Ring-buffer bound so a long-lived install cannot grow this unboundedly.
  final int maxRows;

  var _writesSinceTrim = 0;

  @override
  bool get isEnabled => enabled;

  @override
  Future<void> log(
    AnalyticsEvent event, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) async {
    if (!enabled) return;
    final sanitized = _sanitize(properties);
    await db
        .into(db.journeyEvents)
        .insert(
          JourneyEventsCompanion.insert(
            name: event.wireValue,
            occurredAt: _clock().toUtc(),
            properties: Value(sanitized.isEmpty ? null : jsonEncode(sanitized)),
          ),
        );
    await _maybeTrim();
  }

  @override
  Future<void> logTaskCompletion({
    required String taskKey,
    required int taps,
    required Duration elapsed,
  }) {
    return log(
      AnalyticsEvent.taskCompleted,
      properties: <String, Object?>{
        'task': taskKey,
        'taps': taps,
        'elapsed_ms': elapsed.inMilliseconds,
      },
    );
  }

  /// Drops disallowed keys and clamps values. Strings are truncated and only
  /// accepted for keys whose vocabulary is closed (mode, screen, category…).
  Map<String, Object?> _sanitize(Map<String, Object?> input) {
    final out = <String, Object?>{};
    input.forEach((key, value) {
      if (!_allowedKeys.contains(key)) return;
      if (value is num) {
        out[key] = value is int ? value : value.toDouble();
      } else if (value is bool) {
        out[key] = value;
      } else if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return;
        out[key] = trimmed.length > 40 ? trimmed.substring(0, 40) : trimmed;
      }
      // Everything else (lists, maps, objects) is dropped rather than encoded.
    });
    return out;
  }

  Future<void> _maybeTrim() async {
    if (++_writesSinceTrim < 50) return;
    _writesSinceTrim = 0;

    final countExp = db.journeyEvents.id.count();
    final countRow = await (db.selectOnly(
      db.journeyEvents,
    )..addColumns([countExp])).getSingle();
    final total = countRow.read(countExp) ?? 0;
    if (total <= maxRows) return;

    final cutoffRow =
        await (db.select(db.journeyEvents)
              ..orderBy([(t) => OrderingTerm.desc(t.id)])
              ..limit(1, offset: maxRows))
            .getSingleOrNull();
    if (cutoffRow == null) return;
    await (db.delete(
      db.journeyEvents,
    )..where((t) => t.id.isSmallerOrEqualValue(cutoffRow.id))).go();
  }

  @override
  Future<List<AnalyticsRecord>> recent({int limit = 200}) async {
    final rows =
        await (db.select(db.journeyEvents)
              ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
              ..limit(limit))
            .get();
    return rows
        .map((r) {
          Map<String, Object?> props = const <String, Object?>{};
          final raw = r.properties;
          if (raw != null && raw.isNotEmpty) {
            try {
              final decoded = jsonDecode(raw);
              if (decoded is Map) props = decoded.cast<String, Object?>();
            } on FormatException {
              props = const <String, Object?>{};
            }
          }
          return AnalyticsRecord(
            name: r.name,
            occurredAt: r.occurredAt,
            properties: props,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> clear() => db.delete(db.journeyEvents).go();
}

/// Used when analytics are switched off entirely.
class NoopAnalyticsService implements AnalyticsService {
  const NoopAnalyticsService();

  @override
  bool get isEnabled => false;

  @override
  Future<void> log(
    AnalyticsEvent event, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) async {}

  @override
  Future<void> logTaskCompletion({
    required String taskKey,
    required int taps,
    required Duration elapsed,
  }) async {}

  @override
  Future<List<AnalyticsRecord>> recent({int limit = 200}) async =>
      const <AnalyticsRecord>[];

  @override
  Future<void> clear() async {}
}
