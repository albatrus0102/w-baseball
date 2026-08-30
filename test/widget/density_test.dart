import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/design_system/tokens.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/features/games/games_screen.dart';
import 'package:w_baseball/features/home/home_screen.dart';

import 'harness.dart';

/// Two densities, one design system.
///
/// The risk with a density setting is that it quietly becomes a feature switch:
/// the tight variant drops a line, and information the user could see yesterday
/// is gone today with no way to ask for it back. These tests hold the line —
/// compact may cost pixels, never content and never reachability.
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

  group('밀도 기본값', () {
    test('모드마다 기본 밀도가 다르다', () {
      expect(AudienceMode.discover.defaultDensity, WbDensity.comfortable);
      expect(AudienceMode.player.defaultDensity, WbDensity.compact);
    });

    test('사용자가 고르지 않았으면 모드를 따라간다', () {
      expect(discover.density, WbDensity.comfortable);
      expect(player.density, WbDensity.compact);
    });

    test('사용자가 고른 밀도는 모드를 바꿔도 유지된다', () {
      // Otherwise switching mode silently discards an explicit choice, which
      // reads as a bug even though each half behaves "correctly".
      final chosen = discover.copyWith(densityOverride: WbDensity.compact);
      expect(
        chosen.copyWith(mode: AudienceMode.player).density,
        WbDensity.compact,
      );
      expect(
        chosen.copyWith(mode: AudienceMode.both).density,
        WbDensity.compact,
      );
      expect(
        chosen.copyWith(clearDensityOverride: true).density,
        WbDensity.comfortable,
      );
    });
  });

  group('밀도 규약', () {
    test('조밀 모드도 최소 탭 크기를 줄이지 않는다', () {
      for (final density in WbDensity.values) {
        expect(
          density.listRowMinHeight,
          greaterThanOrEqualTo(WbSize.minTap),
          reason: '${density.name}: 밀도는 여백에서 공간을 벌지, 누를 수 있는 크기에서 벌지 않습니다',
        );
      }
    });

    test('조밀 모드가 실제로 더 조밀하다', () {
      const tight = WbDensity.compact;
      const roomy = WbDensity.comfortable;
      expect(tight.rowPadding.vertical, lessThan(roomy.rowPadding.vertical));
      expect(tight.cardPadding.vertical, lessThan(roomy.cardPadding.vertical));
      expect(tight.blockGap, lessThan(roomy.blockGap));
      expect(tight.sectionGap, lessThan(roomy.sectionGap));
      expect(tight.listRowMinHeight, lessThan(roomy.listRowMinHeight));
    });
  });

  group('밀도별 렌더링', () {
    for (final phone in <TestPhone>[TestPhone.small, TestPhone.regular]) {
      for (final audience in <AudiencePreference>[discover, player]) {
        testWidgets('홈 · ${audience.density.name} · ${phone.name} 넘침 없음', (
          tester,
        ) async {
          final app = await buildTestApp(audience: audience);
          addTearDown(app.dispose);
          await pumpScreen(tester, app, const HomeScreen(), phone: phone);
          await settle(tester);
          expectNoOverflow(tester);
        });

        testWidgets('경기 · ${audience.density.name} · ${phone.name} 넘침 없음', (
          tester,
        ) async {
          final app = await buildTestApp(audience: audience);
          addTearDown(app.dispose);
          await pumpScreen(tester, app, const GamesScreen(), phone: phone);
          await settle(tester);
          expectNoOverflow(tester);
        });
      }
    }

    testWidgets('조밀 모드에서도 경기 정보가 사라지지 않는다', (tester) async {
      // The same screen is rendered twice and the visible text compared. A row
      // that drops the venue or the competition in compact would show up here
      // as text present in one build and missing in the other.
      //
      // 홈, not 경기: the games list opens on today, and a day with no fixtures
      // would make this comparison pass by having nothing to compare.
      Future<Set<String>> textsFor(AudiencePreference audience) async {
        final app = await buildTestApp(audience: audience);
        addTearDown(app.dispose);
        await pumpScreen(tester, app, const HomeScreen());
        await settle(tester);
        return tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .where((s) => s.isNotEmpty)
            .toSet();
      }

      final roomy = await textsFor(
        discover.copyWith(densityOverride: WbDensity.comfortable),
      );
      final tight = await textsFor(
        discover.copyWith(densityOverride: WbDensity.compact),
      );

      expect(roomy, isNotEmpty, reason: '비교할 내용이 있어야 합니다');
      expect(
        roomy.difference(tight),
        isEmpty,
        reason: '조밀 모드에서 사라진 정보가 있습니다. 밀도는 여백만 바꿉니다',
      );
    });
  });
}
