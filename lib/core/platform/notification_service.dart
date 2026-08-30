import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../data/models/audience.dart';
import '../../data/models/domain.dart';
import '../database/database.dart';
import '../utils/kst.dart';
import 'notification_route.dart';

/// One alert we intend to place with the OS.
@immutable
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.category,
    required this.entityKind,
    required this.entityId,
    required this.scheduledForUtc,
    required this.title,
    required this.body,
    this.basisTimeUtc,
    this.spoilerLevel = SpoilerLevel.none,
  });

  final int id;
  final NotificationCategory category;
  final String entityKind;
  final String entityId;
  final DateTime scheduledForUtc;
  final DateTime? basisTimeUtc;
  final String title;
  final String body;
  final SpoilerLevel spoilerLevel;
}

/// Schedules local game alerts.
///
/// Design constraints this class exists to honour:
///  * **Category-level control.** Every alert belongs to a
///    [NotificationCategory] the user can switch off individually — the single
///    loudest complaint about the incumbent Korean baseball app is that its
///    notifications are all-or-nothing.
///  * **No invented alerts.** If there is nothing new, nothing is scheduled.
///  * **Reschedule, don't duplicate.** When a fixture moves, the old alert is
///    cancelled and replaced, keyed off `basisTimeUtc`.
///  * **Spoiler-aware.** A recap alert respects the user's spoiler policy in
///    its *body text*, not just in the app.
///  * **Quiet hours.** An alert that would land inside quiet hours is pushed
///    to the end of the window rather than dropped.
///  * **Ask once.** Permission is requested in context, and never re-requested
///    after a refusal.
abstract interface class NotificationService {
  Future<void> initialize();

  /// Requests permission at the moment the user enables their first alert.
  /// Returns whether we may post notifications.
  Future<bool> requestPermission();

  Future<bool> hasPermission();

  /// Reconciles the OS schedule with what [planned] says it should be.
  ///
  /// Cancels alerts that no longer apply, leaves unchanged ones alone, and
  /// schedules new ones. Idempotent: running it twice changes nothing.
  Future<void> reconcile(List<PlannedNotification> planned);

  Future<void> cancelForEntity(String entityKind, String entityId);

  Future<void> cancelAll();
}

class LocalNotificationService implements NotificationService {
  LocalNotificationService({
    required this.db,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String _channelId = 'wb_game_alerts';
  static const String _channelName = '경기 알림';
  static const String _channelDescription = '팔로우한 팀의 경기 일정, 일정 변경, 날씨 위험 알림';

  final WbDatabase db;
  final FlutterLocalNotificationsPlugin _plugin;

  bool _initialized = false;
  tz.Location? _seoul;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones();
      _seoul = tz.getLocation(Kst.zoneId);

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      // iOS: permissions are requested later, in context, not at startup.
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: darwin),
        // Without this the payload written at schedule time was never read:
        // tapping "1시간 전" opened the home screen and the user had to find
        // the fixture again.
        onDidReceiveNotificationResponse: (response) {
          PendingNotificationRoute.instance.offer(response.payload);
        },
      );

      // Cold start: the OS launched the app *because* of a tap, so the
      // response never reaches the callback above.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        PendingNotificationRoute.instance.offer(
          launch?.notificationResponse?.payload,
        );
      }

      _initialized = true;
    } on MissingPluginException {
      // Test host without the plugin. The app still runs; alerts are inert.
      _initialized = false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_initialized) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
    return false;
  }

  @override
  Future<bool> hasPermission() async {
    if (!_initialized) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.areNotificationsEnabled() ?? false;
      }
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
    return true;
  }

  @override
  Future<void> reconcile(List<PlannedNotification> planned) async {
    final existing = await db.select(db.scheduledNotifications).get();
    final existingById = {for (final r in existing) r.id: r};
    final plannedById = {for (final p in planned) p.id: p};

    // Cancel anything no longer planned, or whose underlying fixture moved.
    for (final row in existing) {
      final match = plannedById[row.id];
      final stillValid =
          match != null &&
          match.scheduledForUtc.isAtSameMomentAs(row.scheduledForUtc) &&
          _sameBasis(match.basisTimeUtc, row.basisTimeUtc) &&
          match.body == row.body;
      if (stillValid) continue;

      await _cancel(row.id);
      await (db.delete(
        db.scheduledNotifications,
      )..where((t) => t.id.equals(row.id))).go();
    }

    final now = DateTime.now().toUtc();
    for (final p in planned) {
      // Never schedule into the past, and never duplicate an identical alert.
      if (!p.scheduledForUtc.isAfter(now)) continue;
      final row = existingById[p.id];
      final unchanged =
          row != null &&
          row.scheduledForUtc.isAtSameMomentAs(p.scheduledForUtc) &&
          _sameBasis(p.basisTimeUtc, row.basisTimeUtc) &&
          row.body == p.body;
      if (unchanged) continue;

      await _schedule(p);
      await db
          .into(db.scheduledNotifications)
          .insertOnConflictUpdate(
            ScheduledNotificationsCompanion.insert(
              id: Value(p.id),
              category: p.category.wireValue,
              entityKind: p.entityKind,
              entityId: p.entityId,
              scheduledForUtc: p.scheduledForUtc,
              basisTimeUtc: Value(p.basisTimeUtc),
              title: p.title,
              body: p.body,
              spoilerLevel: Value(p.spoilerLevel.wireValue),
              createdAt: now,
            ),
          );
    }
  }

  static bool _sameBasis(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.isAtSameMomentAs(b);
  }

  Future<void> _schedule(PlannedNotification p) async {
    if (!_initialized) return;
    final location = _seoul;
    if (location == null) return;

    try {
      await _plugin.zonedSchedule(
        p.id,
        p.title,
        p.body,
        tz.TZDateTime.from(p.scheduledForUtc, location),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            // The reason line is part of the notification itself, so the user
            // can always tell why they received it.
            styleInformation: BigTextStyleInformation(
              '${p.body}\n\n${p.category.reasonKo}',
            ),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        // Exact timing matters: "1시간 전" that drifts is worthless.
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: '${p.entityKind}:${p.entityId}',
      );
    } on MissingPluginException {
      // Inert on a test host.
    } on PlatformException {
      // Exact-alarm permission revoked, or the OS refused. The row is not
      // written, so the next reconcile will retry.
    }
  }

  Future<void> _cancel(int id) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id);
    } on MissingPluginException {
      // Inert on a test host.
    } on PlatformException {
      // Already gone.
    }
  }

  @override
  Future<void> cancelForEntity(String entityKind, String entityId) async {
    final rows =
        await (db.select(db.scheduledNotifications)..where(
              (t) =>
                  t.entityKind.equals(entityKind) & t.entityId.equals(entityId),
            ))
            .get();
    for (final row in rows) {
      await _cancel(row.id);
    }
    await (db.delete(db.scheduledNotifications)..where(
          (t) => t.entityKind.equals(entityKind) & t.entityId.equals(entityId),
        ))
        .go();
  }

  @override
  Future<void> cancelAll() async {
    if (_initialized) {
      try {
        await _plugin.cancelAll();
      } on MissingPluginException {
        // Inert.
      } on PlatformException {
        // Inert.
      }
    }
    await db.delete(db.scheduledNotifications).go();
  }
}

/// Turns followed games into a concrete alert schedule.
///
/// Pure and side-effect free, so the scheduling rules — lead times, quiet
/// hours, disrupted-fixture suppression, spoiler masking — are unit-testable
/// without any plugin or database.
class NotificationPlanner {
  const NotificationPlanner();

  /// Lead times, in the order they appear in settings.
  static const Map<NotificationCategory, Duration> leadTimes =
      <NotificationCategory, Duration>{
        NotificationCategory.myTeamGameWeek: Duration(days: 7),
        NotificationCategory.myTeamGameDay: Duration(hours: 24),
        NotificationCategory.myTeamGameHour: Duration(hours: 1),
      };

  /// Builds the full desired schedule.
  ///
  /// [games] should already be limited to fixtures the user follows or saved.
  List<PlannedNotification> plan({
    required List<GameCard> games,
    required NotificationPreference preference,
    required DateTime nowUtc,
  }) {
    final out = <PlannedNotification>[];

    for (final card in games) {
      final game = card.game;

      // A cancelled or postponed fixture gets no countdown alerts; if the user
      // has the schedule-change category on, that is what tells them.
      if (game.status == GameStatus.cancelled ||
          game.status == GameStatus.postponed) {
        continue;
      }
      if (!game.startTimeUtc.isAfter(nowUtc)) continue;

      leadTimes.forEach((category, lead) {
        if (!preference.isEnabled(category)) return;
        final fireAt = game.startTimeUtc.subtract(lead);
        if (!fireAt.isAfter(nowUtc)) return;

        final adjusted = _applyQuietHours(fireAt, preference);
        // Pushing out of quiet hours must not push past the game itself.
        if (!adjusted.isBefore(game.startTimeUtc)) return;

        out.add(
          PlannedNotification(
            id: notificationId(category, game.id),
            category: category,
            entityKind: 'game',
            entityId: game.id,
            scheduledForUtc: adjusted,
            basisTimeUtc: game.startTimeUtc,
            title:
                '${card.homeTeam.displayName} vs ${card.awayTeam.displayName}',
            body: _countdownBody(card, lead),
          ),
        );
      });
    }

    return out;
  }

  String _countdownBody(GameCard card, Duration lead) {
    final when = KoDate.dateTime(card.game.startTimeUtc);
    final venue = card.venue?.name;
    final leadLabel = switch (lead.inHours) {
      >= 168 => '7일 뒤',
      >= 24 => '내일',
      _ => '1시간 뒤',
    };
    final competition = card.competition?.displayName;
    return <String?>[
      '$leadLabel 경기가 있습니다.',
      when,
      venue,
      competition,
    ].whereType<String>().join(' · ');
  }

  /// Moves an alert to the end of quiet hours rather than dropping it.
  ///
  /// All arithmetic stays in KST wall-clock components. `Kst.toKst` returns a
  /// UTC-flagged instant carrying Korean wall time, so the end-of-window must
  /// be built with `DateTime.utc` too — building it with `DateTime()` would
  /// mix in the device's own zone and shift the result by that offset.
  DateTime _applyQuietHours(DateTime fireAtUtc, NotificationPreference p) {
    if (!p.hasQuietHours) return fireAtUtc;
    final local = Kst.toKst(fireAtUtc);
    if (!p.isWithinQuietHours(local)) return fireAtUtc;

    final endMinute = p.quietHoursEndMinute!;
    var end = DateTime.utc(
      local.year,
      local.month,
      local.day,
    ).add(Duration(minutes: endMinute));
    if (!end.isAfter(local)) end = end.add(const Duration(days: 1));
    return Kst.fromKst(end);
  }

  /// Stable, collision-resistant id per (category, entity).
  ///
  /// Must be deterministic so a reschedule replaces the same OS alert instead
  /// of stacking a second one.
  static int notificationId(NotificationCategory category, String entityId) {
    final hash = Object.hash(category.wireValue, entityId);
    // Android notification ids are 32-bit signed; keep it positive.
    return hash & 0x7FFFFFFF;
  }
}
