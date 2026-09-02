import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/design_system/components/stat_strip_widgets.dart';
import 'package:w_baseball/core/design_system/theme.dart';
import 'package:w_baseball/core/design_system/tokens.dart';

/// `WbStatStrip` decides row-vs-2x2-grid by measuring the four cells with
/// [TextPainter] against the width it is actually given (see the widget's
/// own doc) — never a fixed text-scale cutoff. This file proves that
/// directly, at the component level, rather than relying on
/// `test/audit/text_scale_probe_test.dart`'s "마이야구" probe: that probe
/// renders `MyBaseballScreen` against `buildTestApp`'s default seed, which
/// has zero game-log entries (game-log data is entirely player-written,
/// never seeded — see the feature brief), so it only ever exercises the
/// empty-state nudge card and never builds a `WbStatStrip` at all. A probe
/// reporting "OK" while never constructing the widget under test would be
/// exactly the "measured nothing, called it a pass" mistake this repo's
/// own culture warns against.
void main() {
  const cells = <WbStatCell>[
    WbStatCell(value: '2', label: '게임'),
    WbStatCell(value: '1', label: '승'),
    WbStatCell(value: '1', label: '패'),
    WbStatCell(value: '0', label: '무'),
  ];

  Widget harness({
    required double width,
    double textScale = 1.0,
    WbDensity density = WbDensity.comfortable,
  }) {
    return MaterialApp(
      theme: WbTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: WbDensityScope(
          density: density,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: const WbStatStrip(
                  cells: cells,
                  semanticLabel: '2게임 기록 · 1승 1패 0무',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The vertical divider between cells is only drawn in the single-row
  /// layout — see `WbStatStrip._buildRow`'s `dividers` argument and the
  /// task's "접힌 상태에서는 세로 구분선을 그리지 마세요" requirement.
  bool hasDivider(WidgetTester tester) => tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(WbStatStrip),
          matching: find.byType(Container),
        ),
      )
      .where((c) => c.color != null)
      .isNotEmpty;

  testWidgets('넓은 폭·기본 배율에서는 한 줄로, 칸 사이 구분선과 함께 보인다', (tester) async {
    await tester.pumpWidget(harness(width: 360));

    expect(tester.takeException(), isNull);
    expect(find.text('게임'), findsOneWidget);
    expect(find.text('승'), findsOneWidget);
    expect(find.text('패'), findsOneWidget);
    expect(find.text('무'), findsOneWidget);
    expect(hasDivider(tester), isTrue);

    // One row: every label sits at the same vertical offset.
    final tops = <double>{
      tester.getTopLeft(find.text('게임')).dy,
      tester.getTopLeft(find.text('승')).dy,
      tester.getTopLeft(find.text('패')).dy,
      tester.getTopLeft(find.text('무')).dy,
    };
    expect(tops, hasLength(1));
  });

  testWidgets('너무 좁은 폭에서는 2x2 로 접히고, 구분선이 없다', (tester) async {
    await tester.pumpWidget(harness(width: 140));

    expect(tester.takeException(), isNull);
    expect(hasDivider(tester), isFalse);

    // Two rows: 게임/승 share one row, 패/무 share a second, lower row.
    final gameTop = tester.getTopLeft(find.text('게임')).dy;
    final winTop = tester.getTopLeft(find.text('승')).dy;
    final lossTop = tester.getTopLeft(find.text('패')).dy;
    final drawTop = tester.getTopLeft(find.text('무')).dy;
    expect(gameTop, winTop);
    expect(lossTop, drawTop);
    expect(lossTop, greaterThan(gameTop));
  });

  testWidgets('같은 폭이라도 글자 배율이 커지면 2x2 로 접힌다 — 배율 상수가 아니라 실측', (tester) async {
    // 260dp fits all four cells in one row up to 1.7x (checked below) but no
    // longer at 2.0x — same width, only the scale changed, which is what
    // proves the fold is driven by measuring the actual text at the current
    // `TextScaler` rather than a width threshold picked once and baked in.
    await tester.pumpWidget(harness(width: 260, textScale: 1.7));
    expect(tester.takeException(), isNull);
    expect(hasDivider(tester), isTrue);

    await tester.pumpWidget(harness(width: 260, textScale: 2.0));
    expect(tester.takeException(), isNull);
    expect(hasDivider(tester), isFalse);
    final gameTop = tester.getTopLeft(find.text('게임')).dy;
    final lossTop = tester.getTopLeft(find.text('패')).dy;
    expect(lossTop, greaterThan(gameTop));
  });

  testWidgets('compact 밀도에서도 접히지 않고 렌더링된다', (tester) async {
    await tester.pumpWidget(harness(width: 360, density: WbDensity.compact));

    expect(tester.takeException(), isNull);
    expect(find.text('게임'), findsOneWidget);
  });

  testWidgets('시맨틱 라벨이 전체 문장으로 노출되고, 칸 텍스트는 별도로 읽히지 않는다', (tester) async {
    await tester.pumpWidget(harness(width: 360));

    expect(find.bySemanticsLabel('2게임 기록 · 1승 1패 0무'), findsOneWidget);
  });
}
