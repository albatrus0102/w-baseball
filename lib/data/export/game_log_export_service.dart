import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/platform/platform_services.dart';
import '../models/game_log.dart';
import 'game_log_export.dart';

/// Writes both export files to a temp directory and hands them to the OS
/// share sheet.
///
/// `share_plus` needs a real file on disk for `XFile` on Android (unlike
/// `XFile.fromData`, which some platforms cannot receive as an attachment),
/// so the encoded text is written to the app's own temp directory first —
/// `getTemporaryDirectory()` needs no storage permission, which is what keeps
/// this feature off the privacy policy's permission table entirely.
class GameLogExportService {
  const GameLogExportService();

  Future<void> export({
    required List<GameLogEntry> entries,
    required SharingService sharing,
    required DateTime now,
    // 다음 경기에서 해볼 것 (Stage 3) — every goal ever written, not only the
    // open one; see `GameLogGoalRepository.allGoals`'s doc. Defaults to
    // empty so existing callers (and the export unit tests that predate
    // this field) keep working unchanged.
    List<GameLogGoal> goals = const <GameLogGoal>[],
  }) async {
    final dir = await getTemporaryDirectory();
    final stamp = _fileStamp(now);

    final jsonFile = File('${dir.path}/wb-myrecords-$stamp.json');
    await jsonFile.writeAsString(
      GameLogJsonCodec.encode(entries, exportedAt: now, goals: goals),
    );

    final csvFile = File('${dir.path}/wb-myrecords-$stamp.csv');
    // A leading BOM so Excel on Windows opens the Korean header correctly
    // instead of guessing the wrong codepage. `.codeUnits` would be wrong
    // here — those are UTF-16 code units, not UTF-8 bytes, and every 메모
    // or 대회 label with Korean text would come out corrupted the moment it
    // was written; `utf8.encode` is what actually produces the byte
    // sequence a CSV/BOM reader expects.
    await csvFile.writeAsBytes(<int>[
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode(GameLogCsvCodec.encode(entries)),
    ]);

    await sharing.shareFiles(
      files: <XFile>[
        XFile(jsonFile.path, mimeType: 'application/json'),
        XFile(csvFile.path, mimeType: 'text/csv'),
      ],
      subject: '내 출전 일지',
      text: '여자야구 앱에서 내보낸 출전 일지입니다 (${entries.length}건).',
    );
  }

  static String _fileStamp(DateTime now) {
    final u = now.toUtc();
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${u.year}${p2(u.month)}${p2(u.day)}-${p2(u.hour)}${p2(u.minute)}';
  }
}
