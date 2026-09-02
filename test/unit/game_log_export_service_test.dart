import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/database/database.dart';
import 'package:w_baseball/core/platform/platform_services.dart';
import 'package:w_baseball/data/export/game_log_export.dart';
import 'package:w_baseball/data/export/game_log_export_service.dart';
import 'package:w_baseball/data/repositories/game_log_repository.dart';

/// The export pipeline, end to end through real production classes: a real
/// (in-memory) [WbDatabase], the real [DriftGameLogRepository], and the real
/// [GameLogExportService] — everything the "내보내기" button's `onPressed`
/// touches except the widget tree itself and the OS share sheet.
///
/// This is a plain `test()`, not `testWidgets()`, on purpose. Driving the
/// same real `dart:io` file write + `path_provider` platform-channel round
/// trip *through* an active widget tree inside `flutter test` — even wrapped
/// in `WidgetTester.runAsync` — was found to hang indefinitely (reproduced
/// in isolation and confirmed not specific to this feature's code); a plain
/// `test()` has no such fake-async widget-pump zone to fight, and the
/// button's `onPressed` itself is a one-line `exportGameLog(context, ref)`
/// call, so this still exercises the actual risk (does the wiring produce a
/// correct, round-trippable file?) without the flaky harness.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // No path_provider platform implementation is registered under
    // `flutter test` — only a running app has one. This stands in for it.
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getTemporaryDirectory') {
            return Directory.systemTemp.path;
          }
          return null;
        });
  });

  test('기록 저장소에 쓴 내용이 내보내기 서비스를 거쳐 그대로 파일로 나온다', () async {
    final db = WbDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = DriftGameLogRepository(
      db: db,
      clock: () => DateTime.utc(2026, 8, 30, 9),
    );

    await repository.addEntry(
      playedAt: DateTime.utc(2026, 8, 15),
      competitionLabel: '동호인 리그',
      opponentLabel: '한강 리버베어스',
      note: '병살 하나 잡음',
      plateAppearances: 4,
      hits: 2,
      walks: 1,
    );
    await repository.addEntry(playedAt: DateTime.utc(2026, 8, 22));

    final entries = await repository.watchEntries().first;
    expect(entries, hasLength(2));

    final sharing = _RecordingSharingService();
    await const GameLogExportService().export(
      entries: entries,
      sharing: sharing,
      now: DateTime.utc(2026, 9, 1),
    );

    expect(sharing.lastFiles, hasLength(2));
    final jsonFile = sharing.lastFiles!.firstWhere(
      (f) => f.path.endsWith('.json'),
    );
    final csvFile = sharing.lastFiles!.firstWhere(
      (f) => f.path.endsWith('.csv'),
    );

    final decoded = GameLogJsonCodec.decode(
      await File(jsonFile.path).readAsString(),
    );
    expect(decoded.isValid, isTrue);
    expect(decoded.entries, hasLength(2));
    expect(
      decoded.entries.map((e) => e.opponentLabel),
      containsAll(<String?>['한강 리버베어스', null]),
    );
    expect(decoded.entries.firstWhere((e) => e.note != null).note, '병살 하나 잡음');
    // The stat line survives the real write + reparse too, not just the
    // in-memory codec round trip already covered in game_log_export_test.dart.
    final withStats = decoded.entries.firstWhere(
      (e) => e.plateAppearances != null,
    );
    expect(withStats.plateAppearances, 4);
    expect(withStats.hits, 2);
    expect(withStats.walks, 1);

    final csvBytes = await File(csvFile.path).readAsBytes();
    // BOM so Excel on Windows opens the Korean header correctly.
    expect(csvBytes.take(3), <int>[0xEF, 0xBB, 0xBF]);
    final csvText = utf8.decode(csvBytes.skip(3).toList());
    expect(csvText, contains('한강 리버베어스'));
    expect(csvText, contains('타석'));
  });
}

class _RecordingSharingService implements SharingService {
  List<XFile>? lastFiles;

  @override
  Future<void> shareText({required String text, String? subject}) async {}

  @override
  Future<void> shareFiles({
    required List<XFile> files,
    String? text,
    String? subject,
  }) async {
    lastFiles = files;
  }
}
