import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/app/app.dart';
import 'package:w_baseball/app/router.dart';
import 'package:w_baseball/core/design_system/theme.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/features/games/game_detail_screen.dart';
import 'package:w_baseball/features/onboarding/onboarding_screen.dart';

import '../widget/harness.dart';

/// Regression test for the deep-link destination surviving onboarding.
///
/// The manifest registers `wbaseball://app/...` and the app builds share links
/// from it, so the promise is that a shared game link reopens that game. A
/// first-run user is redirected to onboarding before any screen exists, and the
/// destination used to be dropped there — which broke the app's main growth
/// path: shared link → install → open → wrong screen.
///
/// Started as an audit probe that only printed what happened. Now it asserts.
void main() {
  Future<TestApp> pumpApp(
    WidgetTester tester, {
    required AudiencePreference audience,
  }) async {
    final app = await buildTestApp(audience: audience);
    addTearDown(app.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: app.container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: ref.watch(routerProvider),
            theme: WbTheme.light(),
            locale: const Locale('ko', 'KR'),
            supportedLocales: const <Locale>[Locale('ko', 'KR')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, widget) =>
                WbDensityHost(child: widget ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
    await settle(tester);
    return app;
  }

  const fresh = AudiencePreference();
  const configured = AudiencePreference(
    mode: AudienceMode.player,
    onboardingCompleted: true,
    regionCode: '11',
    regionLabel: '서울',
  );

  testWidgets('설정을 마친 사용자의 딥링크는 해당 경기를 연다', (tester) async {
    final app = await pumpApp(tester, audience: configured);
    app.container.read(routerProvider).go('/games/game-demo-20260831-01');
    await settle(tester);

    debugPrint(
      'PROBE|configured|detail=${find.byType(GameDetailScreen).evaluate().length}',
    );
    expect(find.byType(GameDetailScreen), findsOneWidget);
  });

  testWidgets('갓 설치한 사용자도 온보딩을 마치면 원래 링크로 간다', (tester) async {
    final app = await pumpApp(tester, audience: fresh);
    app.container.read(routerProvider).go('/games/game-demo-20260831-01');
    await settle(tester);

    // The redirect still fires — onboarding is not skipped for a new user.
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(GameDetailScreen), findsNothing);

    // Skipping counts: someone who skips still wants the game they tapped.
    await tester.tap(find.text('건너뛰기'));
    await settle(tester);

    final detail = find.byType(GameDetailScreen).evaluate().length;
    debugPrint('PROBE|fresh-after-onboarding|detail=$detail');
    expect(
      find.byType(GameDetailScreen),
      findsOneWidget,
      reason: '온보딩을 마치면 원래 가려던 경기로 가야 합니다',
    );
  });

  testWidgets('딥링크 없이 온보딩을 마치면 홈으로 간다', (tester) async {
    // The pending destination must not leak between sessions, and "no link"
    // must still land somewhere sensible.
    await pumpApp(tester, audience: fresh);
    await settle(tester);

    expect(find.byType(OnboardingScreen), findsOneWidget);
    await tester.tap(find.text('건너뛰기'));
    await settle(tester);

    expect(find.byType(GameDetailScreen), findsNothing);
    expect(find.byType(OnboardingScreen), findsNothing);
  });
}
