import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/app/providers.dart';
import 'package:w_baseball/core/platform/platform_services.dart';
import 'package:w_baseball/data/export/game_log_export.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/data/models/game_log.dart';
import 'package:w_baseball/features/my_baseball/my_baseball_screen.dart';

import 'harness.dart';

/// A picker that hands back one canned file, so the widget tree never
/// touches a real platform channel. Mirrors
/// `test/unit/game_log_import_test.dart`'s fake of the same shape.
class _FakeFileOpenService implements FileOpenService {
  const _FakeFileOpenService({this.content});

  final String? content;

  @override
  Future<PickedTextFile?> openTextFile({
    List<String> mimeTypes = const <String>['application/json', '*/*'],
    int maxBytes = 5 * 1024 * 1024,
  }) async {
    if (content == null) return null;
    return PickedTextFile(
      content: content!,
      fileName: 'wb-myrecords-20260830-1412.json',
    );
  }
}

/// 출전 일지 가져오기 — the "⋮" menu, the preview screen, the result screen,
/// and "가져온 기록 관리". The repository's own dedupe/transaction/undo
/// guarantees are covered in `test/unit/game_log_import_test.dart`; this file
/// only exercises the screens wired on top of it.
void main() {
  const player = AudiencePreference(
    mode: AudienceMode.player,
    onboardingCompleted: true,
    regionCode: '11',
    regionLabel: '서울',
  );

  String fileFor(List<GameLogEntry> entries) =>
      GameLogJsonCodec.encode(entries, exportedAt: DateTime.utc(2026, 8, 30));

  group('⋮ 메뉴', () {
    testWidgets('가져오기 · 가져온 기록 관리 두 항목이 있다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());
      await tester.tap(find.byTooltip('더보기'));
      await tester.pumpAndSettle();

      expect(find.text('가져오기'), findsOneWidget);
      expect(find.text('가져온 기록 관리'), findsOneWidget);
    });

    testWidgets('기록이 없는 상태(재설치 직후)에도 메뉴가 보인다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());
      expect(find.byTooltip('더보기'), findsOneWidget);
    });
  });

  group('가져오기 미리보기 → 완료', () {
    testWidgets('정상 파일을 고르면 미리보기가 뜨고, 확정하면 목록에 배지와 함께 반영된다', (tester) async {
      final content = fileFor(<GameLogEntry>[
        GameLogEntry(
          id: 1,
          playedAt: DateTime.utc(2026, 8, 20),
          dayKey: '2026-08-20',
          opponentLabel: '한강 리버베어스',
          result: GameLogResult.win,
          createdAt: DateTime.utc(2026, 8, 20, 21),
        ),
      ]);
      final app = await buildTestApp(
        audience: player,
        seedAssets: false,
        platformServices: PlatformServices.noop().copyWith(
          fileOpen: _FakeFileOpenService(content: content),
        ),
      );
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());
      await tester.tap(find.byTooltip('더보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('가져오기'));
      await tester.pumpAndSettle();

      expect(find.text('가져오기 미리보기'), findsOneWidget);
      expect(find.textContaining('기록 1건'), findsOneWidget);
      expect(find.text('1건 가져오기'), findsOneWidget);

      await tester.tap(find.text('1건 가져오기'));
      await tester.pumpAndSettle();

      expect(find.text('가져오기 완료'), findsOneWidget);
      expect(find.text('1건을 추가했어요.'), findsOneWidget);

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      await settle(tester);

      expect(find.text('한강 리버베어스'), findsOneWidget);
      expect(find.text('가져옴'), findsOneWidget);
    });

    testWidgets('취소를 누르면 아무것도 쓰지 않고 돌아간다', (tester) async {
      final content = fileFor(<GameLogEntry>[
        GameLogEntry(
          id: 1,
          playedAt: DateTime.utc(2026, 8, 20),
          dayKey: '2026-08-20',
          createdAt: DateTime.utc(2026, 8, 20, 21),
        ),
      ]);
      final app = await buildTestApp(
        audience: player,
        seedAssets: false,
        platformServices: PlatformServices.noop().copyWith(
          fileOpen: _FakeFileOpenService(content: content),
        ),
      );
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());
      await tester.tap(find.byTooltip('더보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('가져오기'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      await settle(tester);

      expect(await app.db.select(app.db.gameLogEntries).get(), isEmpty);
      // Back on 내 기록, still showing the nudge card — nothing was written.
      expect(find.textContaining('경기 하고 오셨나요'), findsOneWidget);
    });

    testWidgets('형식이 다른 파일은 미리보기 없이 스낵바 오류로 끝난다', (tester) async {
      final app = await buildTestApp(
        audience: player,
        seedAssets: false,
        platformServices: PlatformServices.noop().copyWith(
          fileOpen: const _FakeFileOpenService(
            content: '{"format": "something-else"}',
          ),
        ),
      );
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());
      await tester.tap(find.byTooltip('더보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('가져오기'));
      await tester.pumpAndSettle();

      expect(find.text('가져오기 미리보기'), findsNothing);
      expect(find.textContaining('지원하지 않는 형식'), findsOneWidget);
      expect(await app.db.select(app.db.gameLogEntries).get(), isEmpty);
    });
  });

  group('가져온 기록 관리', () {
    testWidgets('아직 아무것도 가져오지 않았으면 빈 상태를 보여준다', (tester) async {
      final app = await buildTestApp(audience: player, seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());
      await tester.tap(find.byTooltip('더보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('가져온 기록 관리'));
      await tester.pumpAndSettle();

      expect(find.text('가져온 기록이 없습니다'), findsOneWidget);
    });

    testWidgets('가져온 뒤에는 배치가 보이고, 되돌리기가 수기 기록은 남긴다', (tester) async {
      final content = fileFor(<GameLogEntry>[
        GameLogEntry(
          id: 1,
          playedAt: DateTime.utc(2026, 8, 20),
          dayKey: '2026-08-20',
          opponentLabel: '가져온 경기',
          createdAt: DateTime.utc(2026, 8, 20, 21),
        ),
      ]);
      final app = await buildTestApp(
        audience: player,
        seedAssets: false,
        platformServices: PlatformServices.noop().copyWith(
          fileOpen: _FakeFileOpenService(content: content),
        ),
      );
      addTearDown(app.dispose);

      // A hand-typed entry already on the device.
      await app.container
          .read(gameLogRepositoryProvider)
          .addEntry(
            playedAt: DateTime.utc(2026, 7, 1),
            opponentLabel: '수기 입력 경기',
          );

      await pumpScreen(tester, app, const MyBaseballScreen());
      await settle(tester);
      await tester.tap(find.byTooltip('더보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('가져오기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1건 가져오기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      await settle(tester);

      await tester.tap(find.byTooltip('더보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('가져온 기록 관리'));
      await tester.pumpAndSettle();

      expect(find.text('되돌리기'), findsOneWidget);
      await tester.tap(find.text('되돌리기'));
      await tester.pumpAndSettle();
      // Confirm dialog.
      await tester.tap(find.widgetWithText(TextButton, '되돌리기').last);
      await tester.pumpAndSettle();
      await settle(tester);

      final entries = await app.db.select(app.db.gameLogEntries).get();
      expect(entries, hasLength(1));
      expect(entries.single.opponentLabel, '수기 입력 경기');
    });
  });
}
