import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/design_system/components/provenance_widgets.dart';
import 'package:w_baseball/core/design_system/theme.dart';
import 'package:w_baseball/core/design_system/typography.dart';

/// The spoiler veil used to answer "not enough room" with
/// `FittedBox(fit: scaleDown)`, which cancels the system font-size setting —
/// the same thing this design system never allows for body text — and, over a
/// one-line teaser, squeezed icon + explanation + reveal action into that one
/// line's height until none of it was legible.
///
/// The fix drops straight to the reveal chip alone when the full explanation
/// does not fit at its real size, instead of shrinking anything. These tests
/// hold both directions: a real, unreviewed result still gets veiled (the
/// feature is not disabled), and neither layout ever scales text down.
void main() {
  /// Pumps [child] inside a [WbSpoilerVeil] constrained to [height], at
  /// [textScale], so the "not enough room" branch can be reached
  /// deterministically instead of depending on incidental card sizes.
  Future<void> pump(
    WidgetTester tester, {
    required double height,
    double textScale = 1.0,
    Widget? child,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WbTheme.light(),
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: widget!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              height: height,
              child: WbSpoilerVeil(
                masked: true,
                child: child ?? const Text('실제 결과 텍스트'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('텍스트를 축소하지 않는다', () {
    testWidgets('FittedBox를 쓰지 않는다', (tester) async {
      await pump(tester, height: 28);
      expect(
        find.byType(FittedBox),
        findsNothing,
        reason: 'FittedBox는 텍스트를 축소해 접근성 글자 크기 설정을 무력화합니다',
      );
    });

    testWidgets('큰 시스템 글자 크기에서도 안내 문구가 원래 크기로 표시된다', (tester) async {
      // A tall enough box for the full explanation even at 150% text.
      await pump(tester, height: 260, textScale: 1.5);

      final revealText = tester.widget<Text>(find.text('결과 보기'));
      expect(
        revealText.style?.fontSize,
        WbType.captionStrong.fontSize,
        reason: '축소되었다면 실제 fontSize보다 작게 렌더링됩니다',
      );
    });
  });

  group('공간이 좁으면 칩만 남긴다', () {
    testWidgets('한 줄짜리 좁은 공간에서는 결과 보기 칩만 보인다', (tester) async {
      // One line worth of height: not enough for icon + explanation + chip.
      await pump(tester, height: 26);

      expect(find.text('결과 보기'), findsOneWidget);
      expect(
        find.text('결과 스포일러가 포함되어 있습니다'),
        findsNothing,
        reason: '좁은 공간에서는 설명 문장을 그리지 않고 칩만 남깁니다',
      );
      expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
    });

    testWidgets('충분히 넓은 공간에서는 아이콘과 설명, 칩이 모두 보인다', (tester) async {
      await pump(tester, height: 220);

      expect(find.text('결과 보기'), findsOneWidget);
      expect(find.text('결과 스포일러가 포함되어 있습니다'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });
  });

  group('스크린리더는 레이아웃과 무관하게 같은 설명을 듣는다', () {
    testWidgets('좁은 레이아웃에서도 전체 설명이 Semantics에 남는다', (tester) async {
      await pump(tester, height: 26);
      final semantics = tester.getSemantics(find.byType(WbSpoilerVeil));
      expect(semantics.label, contains('결과 스포일러가 포함되어 있습니다'));
      expect(semantics.label, contains('결과 보기하려면 두 번 탭하세요'));
    });

    testWidgets('넓은 레이아웃과 문구가 동일하다', (tester) async {
      await pump(tester, height: 220);
      final semantics = tester.getSemantics(find.byType(WbSpoilerVeil));
      expect(semantics.label, contains('결과 스포일러가 포함되어 있습니다'));
      expect(semantics.label, contains('결과 보기하려면 두 번 탭하세요'));
    });
  });

  group('가리기 자체는 계속 동작한다', () {
    testWidgets('좁은 레이아웃에서도 탭하면 실제 내용이 드러난다', (tester) async {
      await pump(tester, height: 26);
      // The real content stays laid out underneath (so revealing does not
      // shift anything) but at near-zero opacity while masked.
      final before = tester.widget<Opacity>(find.byType(Opacity));
      expect(before.opacity, lessThan(0.1));
      expect(find.text('결과 보기'), findsOneWidget);

      await tester.tap(find.byType(WbSpoilerVeil));
      await tester.pump();

      // Revealed: the child renders directly, with no Opacity wrapper or
      // veil chip left over it.
      expect(find.byType(Opacity), findsNothing);
      expect(find.text('실제 결과 텍스트'), findsOneWidget);
      expect(find.text('결과 보기'), findsNothing);
    });
  });
}
