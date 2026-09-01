import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/app/providers.dart';
import 'package:w_baseball/core/design_system/components/primitives.dart';
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
      await tester.tap(find.byKey(const ValueKey('gameLogSaveButton')));
      await tester.pumpAndSettle();

      expect(find.text('1게임 기록'), findsOneWidget);
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
  // The export button's actual file output — real repository, real
  // `GameLogExportService`, real `dart:io` write, parsed back and checked
  // field-for-field — is covered in
  // `test/unit/game_log_export_service_test.dart` rather than here. Driving
  // that same real file write + platform-channel round trip from inside a
  // pumped widget tree (even via `WidgetTester.runAsync`) was found to hang
  // `flutter test` indefinitely; see that file's doc comment for why the
  // plain `test()` there is the right layer for it, not a widget test.
}
