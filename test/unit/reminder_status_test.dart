import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/data/models/reminder_status.dart';

/// Two screens used to answer "why won't I get an alert?" separately, and
/// disagreed. These pin the single answer — in particular that a denied OS
/// permission outranks everything, because switching a category on while
/// permission is denied changes nothing.
void main() {
  const countdown = <NotificationCategory>{
    NotificationCategory.myTeamGameWeek,
    NotificationCategory.myTeamGameDay,
    NotificationCategory.myTeamGameHour,
  };

  const allOn = NotificationPreference(
    enabled: countdown,
    permissionRequested: true,
  );
  const allOff = NotificationPreference(
    enabled: <NotificationCategory>{},
    permissionRequested: true,
  );

  ReminderBlocker evaluate({
    bool hasPermission = true,
    NotificationPreference preference = allOn,
    bool hasSomethingFollowed = true,
  }) => ReminderBlocker.evaluate(
    hasPermission: hasPermission,
    preference: preference,
    countdownCategories: countdown,
    hasSomethingFollowed: hasSomethingFollowed,
  );

  group('원인 판정', () {
    test('모두 갖춰졌으면 막는 것이 없다', () {
      expect(evaluate(), ReminderBlocker.none);
    });

    test('권한이 없으면 권한을 지목한다', () {
      expect(evaluate(hasPermission: false), ReminderBlocker.permissionDenied);
    });

    test('권한이 카테고리보다 우선한다', () {
      // The bug this replaces: with permission denied *and* categories off,
      // the app told the user to turn categories on — which would not have
      // helped.
      expect(
        evaluate(hasPermission: false, preference: allOff),
        ReminderBlocker.permissionDenied,
      );
    });

    test('권한이 있고 카테고리가 모두 꺼져 있으면 카테고리를 지목한다', () {
      expect(evaluate(preference: allOff), ReminderBlocker.categoriesOff);
    });

    test('팔로우한 것이 없으면 그렇게 말한다', () {
      expect(
        evaluate(hasSomethingFollowed: false),
        ReminderBlocker.nothingToAlertAbout,
      );
    });
  });

  group('안내와 행동', () {
    test('막는 원인마다 문구가 있다', () {
      for (final blocker in ReminderBlocker.values) {
        expect(blocker.messageKo, isNotEmpty, reason: blocker.name);
      }
    });

    test('사용자가 할 수 있는 일이 있을 때만 버튼을 준다', () {
      // A button that cannot fix the cause is worse than no button.
      expect(ReminderBlocker.permissionDenied.actionLabelKo, isNotNull);
      expect(ReminderBlocker.categoriesOff.actionLabelKo, isNotNull);
      expect(ReminderBlocker.none.actionLabelKo, isNull);
      expect(ReminderBlocker.nothingToAlertAbout.actionLabelKo, isNull);
    });

    test('권한 거부 안내가 카테고리를 탓하지 않는다', () {
      expect(
        ReminderBlocker.permissionDenied.messageKo.contains('종류'),
        isFalse,
      );
      expect(ReminderBlocker.permissionDenied.messageKo, contains('휴대폰'));
    });
  });

  group('요약 줄', () {
    test('막는 것이 없으면 예약 건수를 보고한다', () {
      const status = ReminderStatus(
        blocker: ReminderBlocker.none,
        scheduledCount: 3,
      );
      expect(status.summaryKo, contains('3건'));
    });

    test('막는 것이 있으면 건수 대신 원인을 말한다', () {
      const status = ReminderStatus(
        blocker: ReminderBlocker.permissionDenied,
        scheduledCount: 0,
      );
      expect(status.summaryKo, ReminderBlocker.permissionDenied.messageKo);
    });
  });
}
