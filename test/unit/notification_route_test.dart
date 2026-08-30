import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/platform/notification_route.dart';

/// The notification tap path cannot be exercised without a device, so the part
/// that decides *where* a tap goes is kept free of the plugin and tested here.
void main() {
  group('알림 payload → 경로', () {
    test('경기 알림은 해당 경기 상세로 간다', () {
      expect(NotificationRoute.resolve('game:game-1'), '/games/game-1');
    });

    test('팀·대회·소식도 각자의 화면으로 간다', () {
      expect(NotificationRoute.resolve('team:team-1'), '/team/team-1');
      expect(
        NotificationRoute.resolve('competition:season-1'),
        '/competition/season-1',
      );
      expect(
        NotificationRoute.resolve('storyCluster:story-1'),
        '/discover/story/story-1',
      );
    });

    test('id에 콜론이 들어 있어도 첫 콜론만 구분자로 쓴다', () {
      // Ids come from external sources; one of them will contain a colon.
      expect(NotificationRoute.resolve('game:a:b'), '/games/a:b');
    });

    test('모르는 종류는 추측하지 않고 null을 준다', () {
      // Guessing would open the wrong screen, which is worse than staying put.
      expect(NotificationRoute.resolve('unknown:1'), isNull);
    });

    test('망가진 payload는 전부 null', () {
      for (final bad in <String?>[null, '', 'game', 'game:', ':id', ':']) {
        expect(NotificationRoute.resolve(bad), isNull, reason: 'payload=$bad');
      }
    });
  });

  group('대기 중인 알림 경로', () {
    test('한 번만 소비된다', () {
      // Reading twice would re-navigate on the next rebuild.
      PendingNotificationRoute.instance.offer('game:game-9');
      expect(PendingNotificationRoute.instance.take(), '/games/game-9');
      expect(PendingNotificationRoute.instance.take(), isNull);
    });

    test('열 수 없는 payload는 저장하지 않는다', () {
      PendingNotificationRoute.instance.offer('nonsense');
      expect(PendingNotificationRoute.instance.take(), isNull);
    });
  });
}
