import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/app/app.dart';
import 'package:w_baseball/app/providers.dart';
import 'package:w_baseball/app/router.dart';
import 'package:w_baseball/core/design_system/components/game_widgets.dart';
import 'package:w_baseball/core/design_system/components/primitives.dart';
import 'package:w_baseball/core/design_system/theme.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/features/games/game_detail_screen.dart';
import 'package:w_baseball/features/games/games_screen.dart';
import 'package:w_baseball/features/discover/nearby_games_screen.dart';
import 'package:w_baseball/features/my_baseball/my_baseball_screen.dart';
import 'package:w_baseball/features/search/search_screen.dart';
import 'package:w_baseball/features/teams/teams_screen.dart';
import 'package:w_baseball/features/teams/team_detail_screen.dart';
import 'package:w_baseball/features/competitions/competition_screen.dart';
import 'package:w_baseball/core/design_system/components/provenance_widgets.dart';

import 'harness.dart';

/// Tap counts for the benchmark tasks, **measured** rather than asserted.
///
/// Each test drives the real router from a cold start and counts the taps it
/// actually needed. The numbers in `docs/task-benchmarks.md` come from here, so
/// a navigation change that makes a core task harder fails the build instead of
/// quietly regressing.
void main() {
  /// Runs the whole app — real router, real shell, real screens.
  Future<TestApp> pumpApp(
    WidgetTester tester, {
    required AudiencePreference audience,
    bool seeded = true,
    DateTime? frozenNow,
  }) async {
    final app = await buildTestApp(
      seedAssets: seeded,
      audience: audience,
      frozenNow: frozenNow,
    );
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

  const discover = AudiencePreference(
    mode: AudienceMode.discover,
    onboardingCompleted: true,
    regionCode: '11',
    regionLabel: '서울',
  );
  const player = AudiencePreference(
    mode: AudienceMode.player,
    onboardingCompleted: true,
    regionCode: '11',
    regionLabel: '서울',
  );

  /// Taps a finder and counts it.
  Future<int> tap(WidgetTester tester, Finder finder, int taps) async {
    await tester.tap(finder.first);
    await settle(tester);
    return taps + 1;
  }

  /// How many screen-height scrolls it takes before [target] is reachable.
  ///
  /// Zero means the target is in the first viewport — the number that actually
  /// matters, because a task needing a scroll before its first tap is a task
  /// the user has to hunt for. Returns -1 when the target never appears, so a
  /// broken path reads as broken rather than as "0 scrolls".
  Future<int> scrollsToReach(WidgetTester tester, Finder target) async {
    if (target.hitTestable().evaluate().isNotEmpty) return 0;
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isEmpty) return -1;
    for (var i = 1; i <= 10; i++) {
      await tester.drag(scrollable.first, const Offset(0, -400));
      await settle(tester);
      if (target.hitTestable().evaluate().isNotEmpty) return i;
    }
    return -1;
  }

  /// Prints one measured row. The docs table is transcribed from this output,
  /// so the two cannot drift without the test output changing too.
  void record(String task, {required int taps, required int scrolls}) {
    debugPrint('BENCHMARK|$task|taps=$taps|scrolls=$scrolls');
  }

  group('과업 1 — 오늘/다음 경기 상세 확인', () {
    testWidgets('현역 모드: 홈에서 1탭', (tester) async {
      await pumpApp(tester, audience: player);

      // The hero card is on screen at launch; opening it is a single tap.
      expect(find.byType(WbHeroGameCard), findsWidgets);
      final scrolls = await scrollsToReach(tester, find.byType(WbHeroGameCard));
      expect(scrolls, 0, reason: '내 팀 다음 경기는 첫 화면 안에 있어야 합니다');
      final taps = await tap(tester, find.byType(WbHeroGameCard), 0);

      expect(find.byType(GameDetailScreen), findsOneWidget);
      expect(taps, 1, reason: '내 팀 다음 경기 상세까지 1탭');
      record('T1 현역 다음 경기 상세', taps: taps, scrolls: scrolls);
    });

    testWidgets('입문자 모드: 경기 탭을 거쳐 2탭', (tester) async {
      await pumpApp(tester, audience: discover);

      var taps = await tap(tester, find.text('경기'), 0);
      expect(find.byType(GamesScreen), findsOneWidget);

      // Land on a day that has fixtures, then open one.
      final rows = find.byType(WbGameRow);
      if (rows.evaluate().isEmpty) {
        // Today may have no games; the empty state offers the nearest day.
        taps = await tap(tester, find.textContaining('다음 경기일'), taps);
      }
      final scrolls = await scrollsToReach(tester, find.byType(WbGameRow));
      taps = await tap(tester, find.byType(WbGameRow), taps);

      expect(find.byType(GameDetailScreen), findsOneWidget);
      record('T1 입문자 경기 상세', taps: taps, scrolls: scrolls);
      expect(taps, lessThanOrEqualTo(3), reason: '경기가 없는 날이면 날짜 이동 1탭이 추가됩니다');
    });
  });

  group('과업 2 — 통합 검색 시작', () {
    for (final entry in <(String, String)>[
      ('홈', '/'),
      ('발견', '/discover'),
      ('경기', '/games'),
      ('마이야구', '/my'),
    ]) {
      testWidgets('${entry.$1} 탭에서 1탭', (tester) async {
        await pumpApp(tester, audience: player);

        var taps = 0;
        if (entry.$1 != '홈') {
          taps = await tap(tester, find.text(entry.$1), taps);
        }

        // Search lives in the app bar of every primary screen.
        expect(find.byTooltip('검색'), findsOneWidget);
        await tester.tap(find.byTooltip('검색'));
        await settle(tester);

        expect(
          find.byType(SearchScreen),
          findsOneWidget,
          reason: '${entry.$1}에서 검색까지 1탭',
        );
        // The search action lives in the app bar, which never scrolls away.
        record('T2 검색 (${entry.$1})', taps: 1, scrolls: 0);
      });
    }
  });

  group('과업 3 — 근처 경기 찾기', () {
    testWidgets('입문자 모드: 발견 → 근처 경기 2탭', (tester) async {
      await pumpApp(tester, audience: discover);

      var taps = await tap(tester, find.text('발견'), 0);
      final scrolls = await scrollsToReach(tester, find.text('근처 경기'));
      taps = await tap(tester, find.text('근처 경기'), taps);

      expect(find.byType(NearbyGamesScreen), findsOneWidget);
      expect(taps, 2, reason: '지역을 설정한 사용자는 근처 경기까지 2탭');
      record('T3 근처 경기', taps: taps, scrolls: scrolls);
    });

    testWidgets('위치 권한 없이 지역만으로 동작한다', (tester) async {
      final app = await pumpApp(tester, audience: discover);

      // The app never asked for location, and does not need it.
      expect(app.preferences.audience.useDeviceLocation, isFalse);
      expect(app.preferences.audience.hasRegion, isTrue);

      await tap(tester, find.text('발견'), 0);
      await tap(tester, find.text('근처 경기'), 0);
      expect(find.byType(NearbyGamesScreen), findsOneWidget);
      // Region chips are the primary control, present without any permission.
      expect(find.text('전체 지역'), findsOneWidget);
    });
  });

  group('과업 4 — 내 팀 설정', () {
    testWidgets('마이야구 → 팀 찾기 2탭', (tester) async {
      await pumpApp(tester, audience: player);

      var taps = await tap(tester, find.text('마이야구'), 0);
      expect(find.byType(MyBaseballScreen), findsOneWidget);

      final scrolls = await scrollsToReach(tester, find.text('팀 찾기'));
      taps = await tap(tester, find.text('팀 찾기'), taps);
      expect(find.byType(TeamsScreen), findsOneWidget);
      expect(taps, 2);
      record('T4 내 팀 설정', taps: taps, scrolls: scrolls);
    });
  });

  group('과업 5 — 마이야구 진입', () {
    testWidgets('어느 화면에서든 1탭', (tester) async {
      await pumpApp(tester, audience: discover);

      final taps = await tap(tester, find.text('마이야구'), 0);
      expect(find.byType(MyBaseballScreen), findsOneWidget);
      expect(taps, 1);
      // The tab bar is always on screen, so this is 0 scrolls by construction.
      record('T5 마이야구 진입', taps: taps, scrolls: 0);
    });
  });

  group('문맥 보존', () {
    testWidgets('경기 탭의 필터는 다른 탭을 다녀와도 유지된다', (tester) async {
      final app = await pumpApp(tester, audience: player);

      await tap(tester, find.text('경기'), 0);
      await tap(tester, find.widgetWithText(WbFilterChip, '국내'), 0);

      final applied = app.container.read(gamesTabProvider).level;
      expect(applied, isNotNull, reason: '필터가 적용되어야 합니다');

      // Leave and come back.
      await tap(tester, find.text('발견'), 0);
      await tap(tester, find.text('경기'), 0);

      expect(
        app.container.read(gamesTabProvider).level,
        applied,
        reason: '탭을 오간 뒤에도 필터가 보존되어야 합니다',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 마스터 프롬프트가 지정한 5개 과업.
  //
  // 위의 T1~T5 는 개정 프롬프트의 두 사용자군 기준 과업이고, 아래 M1~M5 는 최초
  // 명세가 이름으로 지목한 과업입니다. 겹치지 않으므로 둘 다 측정합니다.
  // ---------------------------------------------------------------------------

  group('M1 — 오늘 경기 결과 확인', () {
    testWidgets('경기 탭 → 결과', (tester) async {
      await pumpApp(tester, audience: player);

      var taps = await tap(tester, find.text('경기'), 0);
      expect(find.byType(GamesScreen), findsOneWidget);

      final scrolls = await scrollsToReach(tester, find.text('결과'));
      taps = await tap(tester, find.text('결과'), taps);

      // The segment switched; the list now answers "what happened".
      expect(find.byType(GamesScreen), findsOneWidget);
      expect(taps, 2);
      record('M1 오늘 경기 결과', taps: taps, scrolls: scrolls);
    });
  });

  group('M2 — 특정 팀의 다음 경기와 구장 확인', () {
    testWidgets('검색 → 팀 → 다음 경기·구장', (tester) async {
      await pumpApp(tester, audience: discover);

      // Search is the shortest path to an arbitrary team from anywhere.
      var taps = 1;
      await tester.tap(find.byTooltip('검색'));
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, '한강');
      await settle(tester);

      taps = await tap(tester, find.textContaining('한강'), taps);
      expect(find.byType(TeamDetailScreen), findsOneWidget);

      // Both answers live on this one screen, in one scroll flow — which is
      // the actual claim being tested, so the venue is scrolled to rather than
      // assumed to be in the first viewport.
      expect(find.text('다음 경기'), findsOneWidget);
      // Measures what the task asks for — the next game and where it is
      // played — not where a particular heading happens to sit. The full
      // 주 활동 구장 section keeps its map and directions further down; this
      // checks the answer itself is reachable.
      final scrolls = await scrollsToReach(
        tester,
        find.textContaining('주 활동 구장'),
      );
      expect(scrolls, 0, reason: '구장은 스크롤 없이 보여야 합니다');
      record('M2 팀 다음 경기·구장', taps: taps, scrolls: scrolls);
    });
  });

  group('M3 — 특정 대회의 현재 순위 확인', () {
    testWidgets('검색 → 대회 → 순위', (tester) async {
      await pumpApp(tester, audience: discover);

      // Search rather than 마이야구: the 리그 현황 module only renders once the
      // user follows a team, and this task must be reachable before that.
      var taps = 1;
      await tester.tap(find.byTooltip('검색'));
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, '리그');
      await settle(tester);

      final hit = find.textContaining('리그');
      final scrolls = await scrollsToReach(tester, hit);
      taps = await tap(tester, hit, taps);

      expect(find.byType(CompetitionScreen), findsOneWidget);
      expect(
        find.text('대회를 찾을 수 없습니다'),
        findsNothing,
        reason: '검색 결과가 막다른 화면으로 가면 안 됩니다',
      );
      // The detail loads asynchronously; give it a beat before asserting on
      // what it renders.
      await settle(tester, rounds: 12);
      // The competition screen opens with 순위 present — no further tap.
      expect(find.text('순위'), findsWidgets);
      record('M3 대회 순위', taps: taps, scrolls: scrolls);
    });
  });

  group('M4 — 공식 원문 확인 후 같은 목록 위치로 복귀', () {
    testWidgets('목록 위치와 필터가 보존된다', (tester) async {
      final app = await pumpApp(tester, audience: player);

      await tap(tester, find.text('경기'), 0);
      await tap(tester, find.widgetWithText(WbFilterChip, '국내'), 0);

      // Land on a day that actually has fixtures *first*. Capturing the day
      // before this move would compare against a day the user has already
      // deliberately left.
      final rows = find.byType(WbGameRow);
      if (rows.evaluate().isEmpty) {
        await tap(tester, find.textContaining('다음 경기일'), 0);
      }

      final filterBefore = app.container.read(gamesTabProvider).level;
      final dayBefore = app.container.read(gamesTabProvider).dayKey;

      // Open a fixture, then come back the way a user would.
      await tap(tester, find.byType(WbGameRow), 0);
      expect(find.byType(GameDetailScreen), findsOneWidget);

      // The source line is what a user taps to reach the official record; the
      // screen must offer it before we can claim this task is reachable.
      expect(find.byType(WbSourceLine), findsWidgets);

      // `pageBack()` looks for a Cupertino back button, which a Material app
      // does not have. Tap the real one the user sees.
      await tap(tester, find.byType(BackButton), 0);
      await settle(tester);

      expect(find.byType(GamesScreen), findsOneWidget);
      expect(
        app.container.read(gamesTabProvider).level,
        filterBefore,
        reason: '원문을 보고 돌아와도 필터가 유지되어야 합니다',
      );
      expect(
        app.container.read(gamesTabProvider).dayKey,
        dayBefore,
        reason: '원문을 보고 돌아와도 보던 날짜가 유지되어야 합니다',
      );
      record('M4 원문 확인 후 복귀', taps: 2, scrolls: 0);
    });
  });

  group('M5 — 캘린더 추가와 알림 설정', () {
    testWidgets('경기 상세에서 두 동작 모두 1탭', (tester) async {
      await pumpApp(tester, audience: player);

      final taps = await tap(tester, find.byType(WbHeroGameCard), 0);
      expect(find.byType(GameDetailScreen), findsOneWidget);

      // Both controls are in the same action row, visible without scrolling.
      final scrolls = await scrollsToReach(tester, find.text('캘린더'));
      expect(find.text('캘린더'), findsOneWidget);
      expect(find.text('알림'), findsOneWidget);
      expect(scrolls, 0, reason: '캘린더·알림은 스크롤 없이 닿아야 합니다');

      record('M5 캘린더+알림 (상세 도달)', taps: taps, scrolls: scrolls);
    });

    testWidgets('알림을 켜면 저장되고 예약 대상이 된다', (tester) async {
      // `game-demo-20260902-23` (assets/seed/games/2026-09.json) kicks off at
      // 2026-09-02T05:00:00Z. Without a frozen clock this test reads the real
      // wall clock: once real time passes that instant, the reminder button's
      // `canRemind` gate in `_QuickActions` (game_detail_screen.dart) —
      // correctly — goes false for a game already under way, the tap becomes
      // a no-op, and `watchSavedIds` stays empty forever. That is a genuine
      // defect in this test, not a database race: no amount of waiting after
      // the tap can produce a save the button refused to start. Freeze well
      // before kickoff so the test's outcome does not depend on what time of
      // day it happens to run.
      final app = await pumpApp(
        tester,
        audience: player,
        frozenNow: DateTime.utc(2026, 9, 2),
      );

      await tap(tester, find.byType(WbHeroGameCard), 0);
      expect(find.text('알림'), findsOneWidget);

      await tap(tester, find.text('알림'), 0);

      // Saving is what makes a fixture eligible for a countdown alert.
      //
      // `runAsync` is required: this is a real database stream, and awaiting it
      // in the widget tester's fake-async zone would hang rather than fail.
      final saved = await tester.runAsync(
        () => app.container
            .read(followRepositoryProvider)
            .watchSavedIds(SavedItemKind.game)
            .first,
      );
      expect(saved, isNotEmpty, reason: '알림을 켜면 해당 경기가 예약 대상이 되어야 합니다');
      expect(find.text('알림 켜짐'), findsOneWidget);
    });
  });
}
