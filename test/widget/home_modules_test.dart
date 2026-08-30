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
      HomeModule.myStanding,
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
