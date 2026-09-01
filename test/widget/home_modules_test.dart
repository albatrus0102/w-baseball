import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/features/home/home_modules.dart';
import 'package:w_baseball/features/home/home_screen.dart';

import 'harness.dart';

/// A section heading with nothing under it reads as a broken app.
///
/// Eleven home modules could render one: the heading was drawn by the parent
/// and the body by the module, so a module with no content produced a title
/// followed by blank space. This holds the line for every mode, with data and
/// without.
void main() {
  AudiencePreference audience(AudienceMode mode) => AudiencePreference(
    mode: mode,
    onboardingCompleted: true,
    regionCode: '11',
    regionLabel: '서울',
  );

  /// Section headings currently on screen.
  Set<String> headings(WidgetTester tester) {
    final titles = HomeModule.values
        .map((m) => m.titleKo)
        .where((t) => t.isNotEmpty)
        .toSet();
    return tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where(titles.contains)
        .toSet();
  }

  /// Every visible heading must be followed by something.
  ///
  /// Measured geometrically rather than by inspecting widgets: whatever a
  /// module draws, it has to occupy space between its own heading and the next
  /// one. That catches an empty body regardless of which widget produced it.
  void expectNoEmptySections(WidgetTester tester) {
    final visible = headings(tester);
    for (final title in visible) {
      final finder = find.text(title);
      if (finder.evaluate().isEmpty) continue;
      final box = tester.renderObject<RenderBox>(finder.first);
      final headingBottom = box.localToGlobal(Offset(0, box.size.height)).dy;

      // The nearest content below this heading, if any.
      final others =
          visible
              .where((t) => t != title)
              .map((t) => find.text(t))
              .where((f) => f.evaluate().isNotEmpty)
              .map((f) {
                final b = tester.renderObject<RenderBox>(f.first);
                return b.localToGlobal(Offset.zero).dy;
              })
              .where((y) => y > headingBottom)
              .toList()
            ..sort();

      // Last heading on screen: nothing below it to compare against.
      if (others.isEmpty) {
        continue;
      }
      final gap = others.first - headingBottom;
      expect(
        gap,
        greaterThan(24.0),
        reason: '"$title" 아래에 내용 없이 다음 섹션이 바로 옵니다',
      );
    }
  }

  for (final mode in AudienceMode.values) {
    testWidgets('${mode.name} 모드: 내용 없는 섹션 헤더가 없다', (tester) async {
      final app = await buildTestApp(audience: audience(mode));
      addTearDown(app.dispose);
      await pumpScreen(tester, app, const HomeScreen());
      await settle(tester);
      expectNoEmptySections(tester);
    });

    testWidgets('${mode.name} 모드: 데이터가 하나도 없어도 마찬가지', (tester) async {
      // The harsher case. With nothing seeded, most modules have nothing, and
      // this is where a heading-only section used to appear.
      final app = await buildTestApp(
        seedAssets: false,
        audience: audience(mode),
      );
      addTearDown(app.dispose);
      await pumpScreen(tester, app, const HomeScreen());
      await settle(tester);
      expectNoEmptySections(tester);
      expectNoOverflow(tester);
    });
  }

  /// Modules whose data the seed actually contains. A module missing from the
  /// home is either genuinely empty or broken, and the two used to look the
  /// same: reading `AsyncValue.value` treated "still loading" as "nothing to
  /// show", so a section that needed two async hops never appeared at all.
  const mustRender = <AudienceMode, List<HomeModule>>{
    AudienceMode.discover: <HomeModule>[
      HomeModule.featuredTopic,
      HomeModule.weekendNearby,
      HomeModule.beginnerGuide,
      HomeModule.upcomingGames,
      HomeModule.recentResults,
    ],
    AudienceMode.player: <HomeModule>[
      HomeModule.myNextGame,
      HomeModule.weatherOutlook,
      HomeModule.scheduleSummary,
      HomeModule.myStanding,
      HomeModule.leaguePulse,
      HomeModule.leaderboardHighlights,
    ],
    AudienceMode.both: <HomeModule>[
      HomeModule.myNextGame,
      HomeModule.weekendNearby,
      // Not myStanding here: this fixture follows no team, so myStanding has
      // no standings to show in any mode — it only ever renders its "팀을
      // 선택하면..." absence, never real content. In `bothOrder` that absence
      // lands right after weekendNearby's own (this fixture has no weekend
      // games either), so the consecutive-empty-state cap — home_screen.dart's
      // `_EmptyRun` — correctly collapses it to a heading-less line instead of
      // its own "내 팀 순위" heading. That is the intended behaviour, not a
      // regression: capping the run is the whole point of that mechanism. In
      // `playerOrder` nothing empty precedes it, so it keeps its heading
      // there, which is why it still appears in the player-mode list above.
      HomeModule.leaguePulse,
    ],
  };

  mustRender.forEach((mode, modules) {
    testWidgets('${mode.name} 모드: 데이터가 있는 모듈은 실제로 나타난다', (tester) async {
      final app = await buildTestApp(audience: audience(mode));
      addTearDown(app.dispose);
      await pumpScreen(tester, app, const HomeScreen(), phone: TestPhone.large);
      await settle(tester);

      // Accumulate while scrolling: a lazy list unmounts what leaves the
      // viewport, so a single read reports the bottom of the page.
      final seen = <String>{};
      void collect() => seen.addAll(
        tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? ''),
      );
      collect();
      for (var i = 0; i < 10; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await settle(tester);
        collect();
      }

      for (final module in modules) {
        expect(
          seen,
          contains(module.titleKo),
          reason: '${module.name}: 시드에 데이터가 있는데 홈에 나타나지 않습니다',
        );
      }
    });
  });

  group('연속된 빈 상태 압축', () {
    // Designed by Fable: three (or more) fully-illustrated "없습니다" cards in
    // a row read as "this app knows nothing" three times over. Only the first
    // empty module in a run keeps its icon, message and heading; every
    // consecutive one after it collapses to one heading-less line.
    testWidgets('빈 상태 화면에서 첫 번째만 큰 카드로, 나머지는 한 줄로 압축된다', (tester) async {
      final app = await buildTestApp(
        seedAssets: false,
        audience: audience(AudienceMode.discover),
      );
      addTearDown(app.dispose);
      await pumpScreen(tester, app, const HomeScreen());
      await settle(tester);

      final seen = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toSet();

      // featuredTopic is the first module in `discoverOrder`, so it alone
      // keeps its heading, icon-card message and primary action.
      expect(seen, contains('지금 화제'));
      expect(seen, contains('지금 진행 중인 화제 콘텐츠가 없습니다'));
      expect(seen, contains('경기 보기'));

      // weekendNearby, upcomingGames and recentResults are each empty too
      // (nothing seeded, and this fixture sets a region), but none of them is
      // first in the run any more — each shows one compact, self-naming line
      // instead of its own heading and illustrated card.
      expect(seen, contains('이번 주말 서울 경기 없음'));
      expect(seen, contains('다가오는 경기 없음'));
      expect(seen, contains('최근 결과 없음'));

      expect(
        seen,
        isNot(contains('이번 주말 가까운 경기')),
        reason: '두 번째 이후 빈 모듈은 자기 헤딩을 다시 보여주면 안 됩니다',
      );
      expect(seen, isNot(contains('다가오는 경기')));
      expect(seen, isNot(contains('최근 결과')));
      // Only the first module's full explanation and button carry over — a
      // second "경기 보기"/"근처 경기 찾기" primary action would mean a later
      // module was not actually compacted.
      expect(seen, isNot(contains('근처 경기 찾기')));
      expect(seen, isNot(contains('전체 일정 보기')));
    });

    testWidgets('실제 콘텐츠가 사이에 있으면 압축이 이어지지 않는다', (tester) async {
      // both 모드: myNextGame과 featuredTopic이 실제 콘텐츠를 갖고 있어, 그 사이/이후의
      // 빈 모듈이 앞선 빈 모듈과 하나로 묶여 계속 압축되면 안 됩니다.
      final app = await buildTestApp(audience: audience(AudienceMode.both));
      addTearDown(app.dispose);
      await pumpScreen(tester, app, const HomeScreen(), phone: TestPhone.large);
      await settle(tester);

      final seen = <String>{};
      void collect() => seen.addAll(
        tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? ''),
      );
      collect();
      for (var i = 0; i < 10; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await settle(tester);
        collect();
      }

      // weekendNearby is the first empty module in `bothOrder` (myNextGame
      // and weatherOutlook, both before it, have real seeded content), so it
      // keeps its own heading and full card.
      expect(seen, contains('이번 주말 가까운 경기'));
      expect(seen, contains('서울에 이번 주말 경기가 없습니다'));
      // myStanding follows it with no real content of its own (no team is
      // followed in this fixture) and no real content in between, so it is
      // the second empty module in that same run — compacted, no heading.
      expect(seen, contains('팔로우한 팀 없음'));
      expect(seen, isNot(contains('내 팀 순위')));
    });
  });

  group('빈 상태 규칙', () {
    test('없다는 사실이 답인 모듈만 부재를 말한다', () {
      // Housekeeping absences stay silent; the ones a user came to ask about
      // answer out loud.
      expect(HomeModule.weekendNearby.statesItsAbsence, isTrue);
      expect(HomeModule.myNextGame.statesItsAbsence, isTrue);
      expect(HomeModule.officialVideos.statesItsAbsence, isFalse);
      expect(HomeModule.programRecap.statesItsAbsence, isFalse);
    });

    test('부재를 말하는 모듈은 할 말을 갖고 있다', () {
      for (final module in HomeModule.values) {
        if (!module.statesItsAbsence) continue;
        expect(
          module.emptyMessageKo,
          isNotEmpty,
          reason: '${module.name}: 부재를 말한다면서 문구가 없습니다',
        );
      }
    });
  });
}
