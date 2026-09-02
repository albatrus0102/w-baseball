import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/app/providers.dart';
import 'package:w_baseball/core/design_system/components/primitives.dart';
import 'package:w_baseball/data/mappers/row_mappers.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/data/models/game_log.dart';
import 'package:w_baseball/features/my_baseball/my_baseball_screen.dart';

import 'harness.dart';

/// 내 기록 (출전 일지) — Stage 1.
///
/// Covers the two "both directions" checks the feature brief calls out by
/// name: the module appears in player/both mode and never in discover mode,
/// and the "경기 하고 오셨나요?" nudge shows before the first entry and not
/// after one exists. It also exercises the entry sheet's remembered defaults.
/// The export button's actual file output is covered separately — see the
/// doc comment at the bottom of this file.
void main() {
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
  const both = AudiencePreference(
    mode: AudienceMode.both,
    onboardingCompleted: true,
    regionCode: '11',
    regionLabel: '서울',
  );

  group('모드에 따른 노출', () {
    testWidgets('발견 모드에서는 내 기록이 보이지 않는다', (tester) async {
      final app = await buildTestApp(audience: discover, seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());

      expect(find.text('내 기록'), findsNothing);
      expect(find.textContaining('경기 하고 오셨나요'), findsNothing);
    });

    testWidgets('현역 모드에서는 내 기록이 보인다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());

      expect(find.text('내 기록'), findsOneWidget);
    });

    testWidgets('둘 다 모드에서도 내 기록이 보인다', (tester) async {
      final app = await buildTestApp(audience: both, seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());

      expect(find.text('내 기록'), findsOneWidget);
    });
  });

  group('첫 기록 전 안내 카드', () {
    testWidgets('기록이 없으면 안내 카드가 보인다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());

      expect(find.textContaining('경기 하고 오셨나요'), findsOneWidget);
    });

    testWidgets('기록이 하나라도 있으면 안내 카드가 사라진다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await app.container
          .read(gameLogRepositoryProvider)
          .addEntry(playedAt: DateTime.utc(2026, 8, 20));

      await pumpScreen(tester, app, const MyBaseballScreen());
      await settle(tester);

      expect(find.textContaining('경기 하고 오셨나요'), findsNothing);
      expect(find.text('1게임 기록'), findsOneWidget);
    });

    testWidgets('닫기를 누르면 사라지고, 다시 열어도 나타나지 않는다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());
      expect(find.textContaining('경기 하고 오셨나요'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('이 안내 닫기'));
      await tester.pump();

      expect(find.textContaining('경기 하고 오셨나요'), findsNothing);
      // Still reachable — just no longer asking.
      expect(find.text('출전 기록 추가하기'), findsOneWidget);
      expect(
        app.container.read(audienceProvider).gameLogNudgeDismissed,
        isTrue,
      );

      await pumpScreen(tester, app, const MyBaseballScreen());
      expect(find.textContaining('경기 하고 오셨나요'), findsNothing);
    });
  });

  group('기록 추가', () {
    testWidgets('안내 카드로 기록을 추가하면 목록과 개수에 반영된다', (tester) async {
      final app = await buildTestApp(
        audience: player,
        seedAssets: false,
        frozenNow: DateTime.utc(2026, 8, 30, 9),
      );
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());
      await tester.tap(find.textContaining('경기 하고 오셨나요'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('gameLogField_상대')),
        '한강 리버베어스',
      );
      await tester.tap(find.text('승').last);
      await tester.tap(find.text('포수'));
      await tester.enterText(
        find.byKey(const ValueKey('gameLogNoteField')),
        '병살 하나 잡음',
      );
      // The 성적 (선택사항) section (collapsed, unused here) pushes 저장 far
      // enough down the sheet that it needs a real scroll to reach now —
      // see `_scrollSheetTo`'s doc.
      await _scrollSheetTo(
        tester,
        find.byKey(const ValueKey('gameLogSaveButton')),
      );
      await tester.tap(find.byKey(const ValueKey('gameLogSaveButton')));
      await tester.pumpAndSettle();
      await settle(tester);

      // '승' was tapped above, so the header now carries the W-L-D suffix
      // too (see `_GameLogSummary._headerTextKo`) — not a bare "1게임 기록".
      expect(find.text('1게임 기록 · 1승 0패 0무'), findsOneWidget);
      expect(find.text('한강 리버베어스'), findsOneWidget);
      expect(find.textContaining('병살 하나 잡음'), findsWidgets);
    });

    testWidgets('직전 기록의 대회·상대·포지션이 다음 입력의 기본값으로 채워진다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await app.container
          .read(gameLogRepositoryProvider)
          .addEntry(
            playedAt: DateTime.utc(2026, 8, 20),
            competitionLabel: '동호인 리그',
            opponentLabel: '남산 호크스',
            positions: const <GameLogPosition>[GameLogPosition.shortstop],
          );

      await pumpScreen(tester, app, const MyBaseballScreen());
      await settle(tester);
      await tester.tap(find.text('기록 추가'));
      await tester.pumpAndSettle();

      final competitionField = tester.widget<TextField>(
        find.byKey(const ValueKey('gameLogField_대회')),
      );
      expect(competitionField.controller!.text, '동호인 리그');

      final opponentField = tester.widget<TextField>(
        find.byKey(const ValueKey('gameLogField_상대')),
      );
      expect(opponentField.controller!.text, '남산 호크스');

      // The shortstop chip from the last entry is pre-selected.
      final chip = tester.widget<WbFilterChip>(
        find.byKey(const ValueKey('gameLogPositionChip_shortstop')),
      );
      expect(chip.selected, isTrue);
    });
  });

  group('내보내기', () {
    testWidgets('내보내기 버튼과 안내 문구가 기록이 있을 때만 보인다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());
      await settle(tester);
      expect(find.text('내보내기'), findsNothing);

      await app.container
          .read(gameLogRepositoryProvider)
          .addEntry(playedAt: DateTime.utc(2026, 8, 20));
      await settle(tester);

      expect(find.text('내보내기'), findsOneWidget);
      expect(find.textContaining('이 기기에만 저장됩니다'), findsOneWidget);
    });
  });

  group('성적 섹션 — 입력 시트', () {
    testWidgets('기본적으로 접혀 있고, 접힘 안내 문구가 보인다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());
      await tester.tap(find.textContaining('경기 하고 오셨나요'));
      await tester.pumpAndSettle();

      expect(find.text('성적 (선택사항)'), findsOneWidget);
      expect(
        find.text('타석 수가 기억 안 나면 접어 두세요. 접힌 경기는 집계에서 뺍니다.'),
        findsOneWidget,
      );
      // Collapsed: no stepper rows rendered at all.
      expect(find.text('타석'), findsNothing);
      expect(find.text('안타'), findsNothing);
    });

    testWidgets('펼치면 스테퍼가 나타나고, 접었을 때 저장하면 성적이 전부 null이다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());
      await tester.tap(find.textContaining('경기 하고 오셨나요'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('타석 늘리기'), findsNothing);

      await _scrollSheetTo(
        tester,
        find.byKey(const ValueKey('gameLogSaveButton')),
      );
      await tester.tap(find.byKey(const ValueKey('gameLogSaveButton')));
      await tester.pumpAndSettle();

      final entries = await _currentEntries(app);
      expect(entries.single.plateAppearances, isNull);
      expect(entries.single.hits, isNull);

      // A game with no stat line produces no batting block on the summary
      // card at all — Stage 1's shape is preserved for a 1단계-only user.
      // No extra settle()/pump() here: the `pumpAndSettle()` right after
      // tapping 저장 already drove every rebuild this assertion needs, and
      // an additional guarded pump call at this point was found to corrupt
      // a later test's zone (see `_scrollSheetTo`'s doc for the same class
      // of issue) — awaiting the repository stream above is enough on its
      // own to let the widget tree catch up.
      expect(find.textContaining('타격 기록이 있는'), findsNothing);
    });

    testWidgets('펼쳐서 값을 채우고 저장하면 그 값 그대로 기록되고 집계에 반영된다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());
      await tester.tap(find.textContaining('경기 하고 오셨나요'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('성적 (선택사항)'));
      await tester.pumpAndSettle();
      await _scrollSheetTo(tester, find.bySemanticsLabel('타석 늘리기'));

      // 타석 4, 안타 2, 볼넷 1 — via the stepper's + button (steppers and
      // chips only, never a keyboard, per the feature brief). A `pump()`
      // after every tap, not just at the end: `_StatStepper.onChanged`'s
      // closure captures `value` from the *last build*, so without
      // rebuilding between taps every repeated tap recomputes the same
      // `value + 1` off the stale count instead of advancing — confirmed by
      // this exact sequence landing on 1 instead of 4 the first time it was
      // tried without an intervening pump.
      await tester.tap(find.bySemanticsLabel('타석 늘리기'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('타석 늘리기'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('타석 늘리기'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('타석 늘리기'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('안타 늘리기'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('안타 늘리기'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('볼넷 (몸에 맞는 공 포함) 늘리기'));
      await tester.pump();

      await _scrollSheetTo(
        tester,
        find.byKey(const ValueKey('gameLogSaveButton')),
      );
      await tester.tap(find.byKey(const ValueKey('gameLogSaveButton')));
      await tester.pumpAndSettle();

      final entries = await _currentEntries(app);
      expect(entries.single.plateAppearances, 4);
      expect(entries.single.hits, 2);
      expect(entries.single.walks, 1);
      // Untouched fields on the same expanded save are 0, not null — the
      // section was expanded, so every batting field was written.
      expect(entries.single.sacrificeBunts, 0);

      await settle(tester);
      await scrollToEnd(tester);
      // Below threshold (denominator 4 < 20): count shown, no rate.
      expect(find.textContaining('4타석 중 3번 나갔어요'), findsOneWidget);
      expect(find.textContaining('출루율 .'), findsNothing);
    });

    testWidgets('투구 섹션은 포지션에 투수를 고른 경우에만 나타난다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());
      await tester.tap(find.textContaining('경기 하고 오셨나요'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('성적 (선택사항)'));
      await tester.pumpAndSettle();
      expect(find.text('투구'), findsNothing);
      expect(find.text('탈삼진'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('gameLogPositionChip_pitcher')),
      );
      await tester.pumpAndSettle();
      await _scrollSheetTo(tester, find.text('탈삼진'));

      expect(find.text('투구'), findsOneWidget);
      expect(find.text('탈삼진'), findsOneWidget);
      await _scrollSheetTo(tester, find.text('실점'));
      expect(find.text('실점'), findsOneWidget);
    });

    testWidgets('한 번 펼쳐서 저장하면, 다음에 열 때는 기본으로 펼쳐져 있다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());
      await tester.tap(find.textContaining('경기 하고 오셨나요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('성적 (선택사항)'));
      await tester.pumpAndSettle();
      await _scrollSheetTo(
        tester,
        find.byKey(const ValueKey('gameLogSaveButton')),
      );
      await tester.tap(find.byKey(const ValueKey('gameLogSaveButton')));
      await tester.pumpAndSettle();

      expect(app.container.read(audienceProvider).gameLogStatsExpanded, isTrue);

      // Open the sheet again — no tap on the toggle this time.
      await settle(tester);
      await tester.tap(find.text('기록 추가'));
      await tester.pumpAndSettle();

      expect(find.text('타석'), findsOneWidget);
      expect(find.text('타석 수가 기억 안 나면 접어 두세요. 접힌 경기는 집계에서 뺍니다.'), findsNothing);
    });
  });

  group('성적 집계 카드 — 문턱', () {
    testWidgets('(타석−희생번트) 19에서는 출루율을 보여주지 않는다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await app.container
          .read(gameLogRepositoryProvider)
          .addEntry(
            playedAt: DateTime.utc(2026, 8, 20),
            plateAppearances: 19,
            hits: 5,
          );

      await pumpScreen(tester, app, const MyBaseballScreen());
      await settle(tester);
      await scrollToEnd(tester);

      expect(find.textContaining('19타석 중 5번 나갔어요'), findsOneWidget);
      expect(find.textContaining('출루율 .'), findsNothing);
      expect(find.textContaining('지금 19번이에요'), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('(타석−희생번트) 20에서는 출루율을 보여준다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await app.container
          .read(gameLogRepositoryProvider)
          .addEntry(
            playedAt: DateTime.utc(2026, 8, 20),
            plateAppearances: 20,
            hits: 5,
          );

      await pumpScreen(tester, app, const MyBaseballScreen());
      await settle(tester);
      await scrollToEnd(tester);

      expect(find.textContaining('출루율 .250 (20타석 중 5번)'), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('희생번트가 있으면 괄호 안내가 바뀌고, 분모에서 빠진다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await app.container
          .read(gameLogRepositoryProvider)
          .addEntry(
            playedAt: DateTime.utc(2026, 8, 20),
            plateAppearances: 48,
            hits: 14,
            walks: 7,
            sacrificeBunts: 2,
          );

      await pumpScreen(tester, app, const MyBaseballScreen());
      await settle(tester);
      await scrollToEnd(tester);

      expect(
        find.textContaining('출루율 .457 (희생번트 2번 제외, 46번 중 21번)'),
        findsOneWidget,
      );
      expectNoOverflow(tester);
    });

    testWidgets('희생번트를 적지 않은 경기가 있으면 0으로 계산했다는 안내가 보인다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await app.container
          .read(gameLogRepositoryProvider)
          .addEntry(
            playedAt: DateTime.utc(2026, 8, 20),
            plateAppearances: 20,
            hits: 5,
            // sacrificeBunts left null — never recorded for this game.
          );

      await pumpScreen(tester, app, const MyBaseballScreen());
      await settle(tester);
      await scrollToEnd(tester);

      expect(
        find.textContaining('희생번트를 적지 않은 경기 1경기는 0으로 계산했어요'),
        findsOneWidget,
      );
      expectNoOverflow(tester);
    });

    testWidgets('모든 집계 카드에 공식 기록이 아니라는 고정 문구가 들어간다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      // No stat line at all — the original Stage 1 shape.
      await app.container
          .read(gameLogRepositoryProvider)
          .addEntry(playedAt: DateTime.utc(2026, 8, 20));

      await pumpScreen(tester, app, const MyBaseballScreen());
      await settle(tester);
      await scrollToEnd(tester);

      expect(find.text('직접 기록한 개인 집계입니다. 공식 기록이 아닙니다.'), findsOneWidget);
      expectNoOverflow(tester);
    });
  });

  // The export button's actual file output — real repository, real
  // `GameLogExportService`, real `dart:io` write, parsed back and checked
  // field-for-field — is covered in
  // `test/unit/game_log_export_service_test.dart` rather than here. Driving
  // that same real file write + platform-channel round trip from inside a
  // pumped widget tree (even via `WidgetTester.runAsync`) was found to hang
  // `flutter test` indefinitely; see that file's doc comment for why the
  // plain `test()` there is the right layer for it, not a widget test.
}

/// Scrolls *only* the 경기 기록하기 sheet's own list until [target] is found.
///
/// The generic [scrollToEnd] drags every `Scrollable` in the tree — every
/// open `TextField`'s internal `EditableText` scrollable included, plus the
/// whole `MyBaseballScreen` still mounted underneath the modal sheet — which
/// on this sheet's much longer content (12 stat fields added) produced
/// hundreds of "did not hit test" warnings and never converged within a
/// normal test timeout. Targeting the sheet's own `ListView` (keyed
/// `gameLogEntrySheetList`) with `dragUntilVisible` scrolls exactly the one
/// scrollable that matters and stops as soon as [target] exists.
/// A one-shot read of every 출전 일지 entry, straight off `app.db` — not
/// `GameLogRepository.watchEntries()`. That method's `.watch()` stream is
/// backed by drift's table-change notification bus, which (unlike a plain
/// one-shot `select().get()`, proven fine elsewhere in this file via
/// `countEntries()`) never delivered its first event under `flutter test`'s
/// fake-async zone in one specific test here — confirmed by that test
/// hanging indefinitely (5+ real minutes, zero progress) with nothing else
/// in it changed. A one-shot select needs no such notification and reads
/// the value directly.
Future<List<GameLogEntry>> _currentEntries(TestApp app) async {
  final rows = await app.db.select(app.db.gameLogEntries).get();
  return rows.map((r) => r.toDomain()).toList();
}

Future<void> _scrollSheetTo(WidgetTester tester, Finder target) async {
  // Deliberately NOT `WidgetTester.dragUntilVisible`, and deliberately NOT
  // finishing with `tester.pumpAndSettle()` — see `settle()`'s own doc
  // comment above in this file: `pumpAndSettle` is not safe to call in this
  // app's widget tests in general (something in the tree never stops
  // scheduling frames), which is exactly why the harness ships a bounded,
  // fixed-round `settle()` instead. Confirmed by running the affected test
  // alone: with a trailing `pumpAndSettle()` here it never completed even
  // after 5 real minutes, with 0 assertions run. A fixed number of dragged
  // rounds, each settled with the same bounded `settle()`, reveals the
  // target without that open-ended wait.
  final list = find.byKey(const ValueKey('gameLogEntrySheetList'));
  for (var i = 0; i < 15 && target.evaluate().isEmpty; i++) {
    await tester.drag(list, const Offset(0, -250));
    await settle(tester, rounds: 2);
  }
  // Once found, nudge a little further so it sits well inside the viewport
  // rather than right at the edge — a tap computed at the very edge of a
  // `DraggableScrollableSheet` can silently miss (the same non-fatal "did
  // not hit test" outcome `find.byType(Scrollable)`-based dragging showed
  // elsewhere in this file).
  if (target.evaluate().isNotEmpty) {
    await tester.drag(list, const Offset(0, -80));
    await settle(tester, rounds: 2);
  }
}
