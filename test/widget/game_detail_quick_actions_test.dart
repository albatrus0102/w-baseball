import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/app/providers.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/features/games/game_detail_screen.dart';

import 'harness.dart';

/// The contract `_QuickActionBar` declares in `game_detail_screen.dart`: its
/// button labels are never squeezed into a column narrower than the word.
///
/// Written because no existing check could see this defect. The row it
/// replaced was a `Row` of `Expanded` buttons, which never overflows —
/// `Expanded` absorbs the squeeze — so `test/audit/text_scale_probe_test.dart`
/// reported the screen clean at every scale while '캘린더' was drawing as
/// 캘/린/더. Line count, not overflow, is the thing that had to be asserted.
///
/// Both branches are covered because they fail differently, and because the
/// four-button one had never been rendered by any test in this repo: no
/// bundled fixture carries `officialDetailUrl`, so `공유`/`공식 기록` — the
/// button whose label column measured 0.0dp wide — only exists once synced
/// data supplies that field. This test supplies it the same way the sync
/// path would.
void main() {
  const player = AudiencePreference(
    mode: AudienceMode.player,
    onboardingCompleted: true,
    regionCode: '11',
    regionLabel: '서울',
  );

  const gameId = 'game-demo-20260902-23';

  /// The bundled September fixtures, optionally with an official record URL
  /// on [gameId] — the field that turns the bar's three buttons into four.
  Map<String, String> seed({required bool official}) {
    final documents = Map<String, String>.from(loadSeedFromDisk());
    if (!official) return documents;
    const key = 'games/2026-09.json';
    final doc = jsonDecode(documents[key]!) as Map<String, dynamic>;
    for (final item in (doc['items'] as List).cast<Map<String, dynamic>>()) {
      if (item['id'] == gameId) {
        item['officialDetailUrl'] = 'https://example.org/games/23';
      }
    }
    documents[key] = jsonEncode(doc);
    return documents;
  }

  /// The quick-action button carrying [label], addressed by its key rather
  /// than its text: '길찾기' and '공식 기록' each appear again further down
  /// this screen, so `find.text` would match two widgets and silently measure
  /// whichever came first.
  Finder actionButton(String label) =>
      find.byKey(ValueKey<String>('quickAction_$label'));

  /// Number of lines [label] actually occupies inside its own button.
  ///
  /// Read off the laid-out `RenderParagraph` rather than computed from the
  /// text, so it reports what the user sees: one box per line-run, of which
  /// the distinct `top` values are the lines.
  int renderedLines(WidgetTester tester, String label) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: actionButton(label), matching: find.text(label)),
    );
    return paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: label.length),
        )
        .map((box) => box.top.round())
        .toSet()
        .length;
  }

  // 360dp is the tightest width Android ships in any volume; 2.0 is the
  // ceiling `WbApp` allows, and 1.0 is here because this defect was never
  // confined to large text — the four-button bar broke at default size too.
  for (final scale in <double>[1.0, 1.3, 1.7, 2.0]) {
    for (final official in <bool>[false, true]) {
      final branch = official ? '4개' : '3개';
      testWidgets('빠른 실행 $branch 버튼 라벨이 ${scale}x에서 한 줄 (360dp)', (
        tester,
      ) async {
        final app = await buildTestApp(
          audience: player,
          frozenNow: DateTime.utc(2026, 9, 2, 9),
          documents: seed(official: official),
        );
        addTearDown(app.dispose);

        await pumpScreen(
          tester,
          app,
          const GameDetailScreen(gameId: gameId),
          phone: TestPhone('qa_$scale', const Size(360, 640), textScale: scale),
        );
        await settle(tester);

        final labels = <String>['캘린더', '알림', '길찾기', if (official) '공식 기록'];
        for (final label in labels) {
          expect(
            actionButton(label),
            findsOneWidget,
            reason: '$branch 버튼 배치에서 $label 버튼을 찾지 못했습니다',
          );
          expect(
            renderedLines(tester, label),
            1,
            reason:
                '$label 라벨이 ${scale}x/360dp($branch 버튼)에서 '
                '여러 줄로 쪼개졌습니다',
          );
        }
      });
    }
  }

  // The reminder is the one label whose length changes with state, which is
  // why `_QuickActions` reads that state where the measurement happens
  // instead of inside the button. Measuring only the '알림' state would leave
  // the longer one — the one that actually decides the column count — never
  // checked.
  for (final scale in <double>[1.0, 2.0]) {
    testWidgets('알림 켜짐 라벨이 ${scale}x에서 한 줄 (360dp, 4개 버튼)', (tester) async {
      final app = await buildTestApp(
        audience: player,
        frozenNow: DateTime.utc(2026, 9, 2, 9),
        documents: seed(official: true),
      );
      addTearDown(app.dispose);

      await app.container
          .read(followRepositoryProvider)
          .toggleSaved(SavedItemKind.game, gameId);

      await pumpScreen(
        tester,
        app,
        const GameDetailScreen(gameId: gameId),
        phone: TestPhone(
          'qa_on_$scale',
          const Size(360, 640),
          textScale: scale,
        ),
      );
      await settle(tester);

      expect(
        actionButton('알림 켜짐'),
        findsOneWidget,
        reason: '저장된 경기인데 알림 버튼이 켜짐 상태가 아닙니다',
      );
      expect(
        renderedLines(tester, '알림 켜짐'),
        1,
        reason: '알림 켜짐 라벨이 ${scale}x/360dp에서 여러 줄로 쪼개졌습니다',
      );
    });
  }
}
