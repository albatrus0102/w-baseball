import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/app/providers.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/features/home/home_screen.dart';

import 'harness.dart';

/// The home "모드 바꾸기" nudge used to render unconditionally, so a user who
/// finished onboarding — and therefore already chose a mode — carried
/// "지금 화면: 알아가는 중 — 바꾸기" at the very top of home forever. A prompt
/// that is right once and never re-checked has no business being permanent
/// furniture in the app's number-one position.
void main() {
  const configured = AudiencePreference(
    mode: AudienceMode.discover,
    onboardingCompleted: true,
    // onboardingSkipped defaults to false: this is the normal, completed path.
    regionCode: '11',
    regionLabel: '서울',
  );

  const skipped = AudiencePreference(
    mode: AudienceMode.discover,
    onboardingCompleted: true,
    onboardingSkipped: true,
    regionCode: '11',
    regionLabel: '서울',
  );

  group('온보딩을 마친 사용자', () {
    testWidgets('안내 배너가 보이지 않는다', (tester) async {
      final app = await buildTestApp(audience: configured);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const HomeScreen());

      expect(find.textContaining('지금 화면:'), findsNothing);
      expect(find.text('바꾸기'), findsNothing);
    });
  });

  group('온보딩을 건너뛴 사용자', () {
    testWidgets('안내 배너가 보인다', (tester) async {
      final app = await buildTestApp(audience: skipped);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const HomeScreen());

      expect(find.textContaining('지금 화면:'), findsOneWidget);
      expect(find.text('바꾸기'), findsOneWidget);
    });

    testWidgets('닫기를 누르면 사라지고, 다시 켜도 다시 나타나지 않는다', (tester) async {
      final app = await buildTestApp(audience: skipped);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const HomeScreen());
      expect(find.textContaining('지금 화면:'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('이 안내 닫기'));
      await tester.pump();

      expect(find.textContaining('지금 화면:'), findsNothing);
      // The dismissal is persisted, not just an in-memory widget state flip —
      // 시작 화면과 지역 in 더보기 still reaches the same picker, so nothing
      // about mode selection itself is lost by dismissing the banner.
      expect(app.container.read(audienceProvider).modeNudgeDismissed, isTrue);

      // Re-pumping the same screen (as a real navigation back to home would)
      // must not resurrect a banner the user already dismissed.
      await pumpScreen(tester, app, const HomeScreen());
      expect(find.textContaining('지금 화면:'), findsNothing);
    });

    testWidgets('배너를 통해 시작 화면을 고를 수 있다', (tester) async {
      // The nudge exists so a skipped-onboarding user still has a way in —
      // dismissing it must not be the only path away from the default mode.
      final app = await buildTestApp(audience: skipped);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const HomeScreen());
      await tester.tap(find.text('바꾸기'));
      await tester.pumpAndSettle();

      expect(find.text('시작 화면'), findsOneWidget);
      expect(find.text(AudienceMode.player.labelKo), findsOneWidget);
    });
  });
}
