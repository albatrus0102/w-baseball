import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/app/app.dart';
import 'package:w_baseball/app/router.dart';
import 'package:w_baseball/core/design_system/components/game_widgets.dart';
import 'package:w_baseball/core/design_system/theme.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/features/games/game_detail_screen.dart';
import 'package:w_baseball/features/teams/team_detail_screen.dart';

import 'harness.dart';

/// Regression test for the literal no-op at
/// `game_detail_screen.dart:125` — tapping either club on the game detail
/// screen's hero card used to do nothing at all.
///
/// A team is the subject on this screen (unlike a fixture row, where the
/// whole row is one target to the game and the team name is not separately
/// tappable — see `WbGameRow`, deliberately left alone). So each team block
/// here must open that team, while the rest of the card keeps doing exactly
/// what it did before: nothing, since this page already *is* the game.
void main() {
  Future<TestApp> pumpApp(WidgetTester tester) async {
    const audience = AudiencePreference(
      mode: AudienceMode.player,
      onboardingCompleted: true,
      regionCode: '11',
      regionLabel: '서울',
    );
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
            builder: (context, widget) => WbDensityHost(
              child: WbFreshnessHost(child: widget ?? const SizedBox.shrink()),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return app;
  }

  /// Index of the 경기 destination in the bottom `NavigationBar`.
  int? selectedTabIndex(WidgetTester tester) {
    final finder = find.byType(NavigationBar);
    if (finder.evaluate().isEmpty) return null;
    return tester.widget<NavigationBar>(finder).selectedIndex;
  }

  // Seeded demo fixture: 남산 스카이라크스 (원정) @ 한강 리버베어스 (홈). See
  // `assets/seed/games/2026-08.json` and `assets/seed/teams.json`.
  const gameId = 'game-demo-20260831-01';
  const awayTeam = '남산 스카이라크스';
  const homeTeam = '한강 리버베어스';

  Finder teamBlockText(String name) => find.descendant(
    of: find.byType(WbHeroGameCard),
    matching: find.text(name),
  );

  testWidgets('팀 블록에 팀 상세 보기 접근성 레이블이 붙는다', (tester) async {
    // `WbCard.semanticLabel` normally collapses a whole card into one spoken
    // sentence via `ExcludeSemantics`, which would swallow a label placed on
    // anything nested inside it — including these two team buttons. This
    // guards that `WbHeroGameCard` actually skips that collapse once
    // `onTeamTap` is set, rather than silently building an inert label.
    final handle = tester.ensureSemantics();

    final app = await pumpApp(tester);
    app.container.read(routerProvider).go('/games/$gameId');
    await settle(tester);

    expect(find.bySemanticsLabel('$awayTeam 팀 상세 보기'), findsOneWidget);
    expect(find.bySemanticsLabel('$homeTeam 팀 상세 보기'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('경기 상세의 팀을 누르면 그 팀 상세로 이동한다 (원정)', (tester) async {
    final app = await pumpApp(tester);
    app.container.read(routerProvider).go('/games/$gameId');
    await settle(tester);

    expect(find.byType(GameDetailScreen), findsOneWidget);
    final tabBefore = selectedTabIndex(tester);

    await tester.tap(teamBlockText(awayTeam));
    await settle(tester);

    expect(find.byType(TeamDetailScreen), findsOneWidget);
    final pushed = tester.widget<TeamDetailScreen>(
      find.byType(TeamDetailScreen),
    );
    expect(pushed.teamId, 'team-demo-namsan');
    // `/team/:id` pushes over the shell, so its bar disappears while shown —
    // same as any other root-navigated detail route in this app.
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(
      selectedTabIndex(tester),
      tabBefore,
      reason: '팀 상세를 보고 돌아와도 하단 탭(경기)이 그대로여야 합니다',
    );
    expect(find.byType(GameDetailScreen), findsOneWidget);
  });

  testWidgets('경기 상세의 팀을 누르면 그 팀 상세로 이동한다 (홈)', (tester) async {
    final app = await pumpApp(tester);
    app.container.read(routerProvider).go('/games/$gameId');
    await settle(tester);

    await tester.tap(teamBlockText(homeTeam));
    await settle(tester);

    expect(find.byType(TeamDetailScreen), findsOneWidget);
    final pushed = tester.widget<TeamDetailScreen>(
      find.byType(TeamDetailScreen),
    );
    expect(pushed.teamId, 'team-demo-hangang');
  });

  testWidgets('카드의 다른 곳을 눌러도 예전처럼 아무 일도 일어나지 않는다', (tester) async {
    final app = await pumpApp(tester);
    app.container.read(routerProvider).go('/games/$gameId');
    await settle(tester);
    final tabBefore = selectedTabIndex(tester);

    // Tap the venue/source area of the hero card — part of the card, but not
    // either team block. This must stay inert: the card is not allowed to
    // become one big team-sized (or game-sized) target.
    await tester.tap(
      find.descendant(
        of: find.byType(WbHeroGameCard),
        matching: find.byIcon(Icons.place_outlined),
      ),
    );
    await settle(tester);

    expect(find.byType(GameDetailScreen), findsOneWidget);
    expect(find.byType(TeamDetailScreen), findsNothing);
    expect(selectedTabIndex(tester), tabBefore);
  });

  testWidgets('팀 탭 대상은 48dp 이상이다', (tester) async {
    final app = await pumpApp(tester);
    app.container.read(routerProvider).go('/games/$gameId');
    await settle(tester);

    for (final name in <String>[awayTeam, homeTeam]) {
      final element = teamBlockText(name).evaluate().single;
      var box = element.findRenderObject();
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is InkWell) {
          box = ancestor.findRenderObject();
          return false;
        }
        return true;
      });
      final size = (box as RenderBox).size;
      expect(
        size.width >= 48 && size.height >= 48,
        isTrue,
        reason: '$name 탭 대상: ${size.width}×${size.height}',
      );
    }
  });
}
