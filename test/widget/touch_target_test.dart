import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/design_system/tokens.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/features/discover/discover_screen.dart';
import 'package:w_baseball/features/games/game_detail_screen.dart';
import 'package:w_baseball/features/games/games_screen.dart';
import 'package:w_baseball/features/home/home_screen.dart';
import 'package:w_baseball/features/my_baseball/my_baseball_screen.dart';
import 'package:w_baseball/features/teams/teams_screen.dart';

import 'harness.dart';

/// Every control must be big enough to hit.
///
/// The density tokens already assert a 48dp floor, but a token is a promise
/// about geometry, not proof that any real control honours it. This walks the
/// actual rendered screens and measures what a finger would land on — which is
/// where the date strip and the filter chips live, neither of which is built
/// from the row tokens.
void main() {
  const player = AudiencePreference(
    mode: AudienceMode.player,
    onboardingCompleted: true,
    regionCode: '11',
    regionLabel: '서울',
  );
  const discover = AudiencePreference(
    mode: AudienceMode.discover,
    onboardingCompleted: true,
    regionCode: '11',
    regionLabel: '서울',
  );

  /// Material's own minimum. Anything smaller is a miss waiting to happen.
  const minSide = WbSize.minTap;

  /// Some controls are legitimately small in one axis — an inline text link,
  /// a chip whose height is capped by its row. The rule applied here is the
  /// practical one: a control must be at least [minSide] in *one* axis and
  /// never smaller than 32 in the other, which is what keeps a 4dp dot or a
  /// hairline from counting as a target.
  /// True when Material already guarantees a padded tap target for this ink
  /// area. `IconButton` renders a 40dp splash inside a 48dp gesture box, so
  /// measuring its `InkWell` reports a number no finger ever experiences.
  bool hasPaddedAncestor(Element element) {
    var padded = false;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is IconButton ||
          widget is Chip ||
          widget is RawChip ||
          widget is Switch ||
          widget is Radio ||
          widget is Checkbox) {
        padded = true;
        return false;
      }
      return true;
    });
    return padded;
  }

  void expectTappable(WidgetTester tester, Finder finder, String label) {
    final elements = finder.evaluate().toList();
    if (elements.isEmpty) return;

    for (final element in elements) {
      if (hasPaddedAncestor(element)) continue;
      final box = element.renderObject;
      if (box is! RenderBox || !box.hasSize) continue;
      final size = box.size;
      if (size.isEmpty) continue;
      // Off-screen items in a lazy list report a size but are not laid out for
      // touch; skip anything with a degenerate axis.
      if (size.width < 1 || size.height < 1) continue;

      final longest = size.longestSide;
      final shortest = size.shortestSide;
      expect(
        longest >= minSide && shortest >= 32,
        isTrue,
        reason:
            '$label: ${size.width.toStringAsFixed(1)}×'
            '${size.height.toStringAsFixed(1)} 은 누르기에 너무 작습니다 '
            '(최소 ${minSide.toInt()}dp)',
      );
    }
  }

  final screens = <(String, Widget, AudiencePreference)>[
    ('홈(현역)', const HomeScreen(), player),
    ('홈(입문자)', const HomeScreen(), discover),
    ('경기', const GamesScreen(), player),
    // Covers the game detail hero card's two team blocks, added alongside
    // making them tappable (`game_detail_screen.dart`).
    ('경기 상세', const GameDetailScreen(gameId: 'game-demo-20260831-01'), player),
    ('발견', const DiscoverScreen(), discover),
    ('마이야구', const MyBaseballScreen(), player),
    ('팀 찾기', const TeamsScreen(), discover),
  ];

  for (final (name, screen, audience) in screens) {
    for (final phone in <TestPhone>[TestPhone.small, TestPhone.regular]) {
      testWidgets('$name · ${phone.name} 의 탭 대상은 충분히 크다', (tester) async {
        final app = await buildTestApp(audience: audience);
        addTearDown(app.dispose);

        await pumpScreen(tester, app, screen, phone: phone);
        await settle(tester);

        expectTappable(tester, find.byType(InkWell), '$name InkWell');
        expectTappable(tester, find.byType(IconButton), '$name IconButton');
      });
    }
  }

  testWidgets('글자를 키워도 탭 대상이 줄지 않는다', (tester) async {
    // Scaling text must grow controls, never shrink them.
    final app = await buildTestApp(audience: player);
    addTearDown(app.dispose);

    await pumpScreen(
      tester,
      app,
      const GamesScreen(),
      phone: TestPhone('big', const Size(360, 640), textScale: 2.0),
    );
    await settle(tester);

    expectTappable(tester, find.byType(InkWell), '경기 @2.0x');
  });
}
