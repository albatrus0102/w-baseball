import 'package:meta/meta.dart';

import 'audience.dart';

/// Why a game reminder would not arrive.
///
/// Two screens were answering this question separately and disagreeing. The
/// game detail blamed the notification categories even when the OS permission
/// had just been denied, and the settings screen said "예약된 알림이 없습니다"
/// with no hint that following a team would not help. One judgement, used by
/// both.
enum ReminderBlocker {
  /// Alerts will arrive.
  none,

  /// The OS permission was refused. Android will not let the app ask again,
  /// so the only way forward is the system settings screen.
  permissionDenied,

  /// Permission is fine but every countdown category is switched off.
  categoriesOff,

  /// Nothing is followed or saved, so there is nothing to alert about.
  nothingToAlertAbout;

  bool get blocks => this != ReminderBlocker.none;

  /// What the user is told. States the cause, never guesses at it.
  String get messageKo => switch (this) {
    ReminderBlocker.none => '경기 전에 알려드릴게요.',
    ReminderBlocker.permissionDenied => '휴대폰에서 이 앱의 알림이 꺼져 있어 알림이 가지 않습니다.',
    ReminderBlocker.categoriesOff => '알림 종류가 모두 꺼져 있어 알림이 가지 않습니다.',
    ReminderBlocker.nothingToAlertAbout => '팀을 팔로우하거나 경기에서 알림을 켜면 예약됩니다.',
  };

  /// The one action that actually resolves this cause, or null when there is
  /// nothing for the user to do.
  String? get actionLabelKo => switch (this) {
    ReminderBlocker.none => null,
    ReminderBlocker.permissionDenied => '휴대폰 설정 열기',
    ReminderBlocker.categoriesOff => '알림 설정',
    ReminderBlocker.nothingToAlertAbout => null,
  };

  /// Decides the cause from what is known.
  ///
  /// Order matters: the OS permission outranks everything, because switching a
  /// category on while permission is denied changes nothing and telling the
  /// user otherwise sends them in a circle.
  static ReminderBlocker evaluate({
    required bool hasPermission,
    required NotificationPreference preference,
    required Set<NotificationCategory> countdownCategories,
    required bool hasSomethingFollowed,
  }) {
    if (!hasPermission) return ReminderBlocker.permissionDenied;
    if (!countdownCategories.any(preference.isEnabled)) {
      return ReminderBlocker.categoriesOff;
    }
    if (!hasSomethingFollowed) return ReminderBlocker.nothingToAlertAbout;
    return ReminderBlocker.none;
  }
}

/// The reminder situation, ready for a screen to render.
@immutable
class ReminderStatus {
  const ReminderStatus({required this.blocker, required this.scheduledCount});

  final ReminderBlocker blocker;

  /// Alerts currently registered with the platform.
  final int scheduledCount;

  /// The line to show. When nothing blocks, reports what is scheduled rather
  /// than claiming success in the abstract.
  String get summaryKo =>
      blocker.blocks ? blocker.messageKo : '알림 $scheduledCount건이 예약되어 있습니다.';
}
