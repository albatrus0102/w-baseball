import 'package:drift/drift.dart';

import '../../core/database/database.dart';
import '../../core/platform/platform_services.dart';
import '../export/game_log_export.dart';
import '../mappers/row_mappers.dart';
import '../models/game_log.dart';

/// What picking + parsing a file for 출전 일지 가져오기 produced.
///
/// A sealed result rather than a nullable/exception pair: the caller (the UI)
/// has to handle "user picked nothing" and "the file itself was unreadable"
/// differently from "here is a preview, go show it" — see each subtype's doc.
sealed class GameLogImportPickResult {
  const GameLogImportPickResult();
}

/// The user backed out of the picker, or there was nothing to pick. Not an
/// error — the caller shows nothing and moves on.
class GameLogImportCancelled extends GameLogImportPickResult {
  const GameLogImportCancelled();
}

/// The picker returned a file, but it could not be trusted at all — wrong
/// envelope, wrong format tag, too large, or unreadable. Nothing was written;
/// [message] is ready to show the user as-is. See the feature brief's failure
/// table: every one of these is caught *before* any database write.
class GameLogImportFormatError extends GameLogImportPickResult {
  const GameLogImportFormatError(this.message);

  final String message;
}

/// The file parsed. [preview] is ready for the "가져오기 미리보기" screen —
/// nothing has touched the database yet.
class GameLogImportReady extends GameLogImportPickResult {
  const GameLogImportReady(this.preview);

  final GameLogImportPreview preview;
}

/// 출전 일지 가져오기 — restoring a player's own exported records, e.g. after
/// a phone change. Device-local like [GameLogRepository]; nothing here talks
/// to a server.
///
/// # Dedupe
///
/// A candidate entry is skipped as a duplicate only when **all three** of the
/// following already match an existing row: `createdAt` truncated to whole
/// seconds, `dayKey`, and the normalised `opponentLabel` (trimmed, internal
/// whitespace collapsed). All three, not `dayKey` + opponent alone, because a
/// double-header means two real games can share a day and an opponent —
/// `createdAt` is what tells them apart. Getting this wrong in the direction
/// of *more* duplicates surviving is the safe failure: a surviving duplicate
/// is visible in the list and deletable; a real game silently dropped as a
/// false "duplicate" is neither.
///
/// # Commit
///
/// [commit] is one `transaction()` — the batch row plus every entry and goal
/// it writes, all-or-nothing. A crash or error partway through leaves nothing
/// behind, never a partial import.
///
/// # Undo
///
/// [undo] deletes every row whose `importBatchId` equals the given batch and
/// stamps the batch's `undoneAt` — also one transaction. `importBatchId` is
/// null on every hand-typed entry, and SQL's `= X` can never match `NULL`, so
/// a hand-typed entry is structurally unreachable by this query — not merely
/// "expected to survive". There is no expiry: the batch row (and so the
/// undo option) lives forever, because these are records a player wrote
/// about her own games, and "재확인 못 함" here means "gone".
abstract interface class GameLogImportRepository {
  /// Opens the OS file picker and parses whatever comes back. Never writes
  /// anything to the database.
  Future<GameLogImportPickResult> pickAndPreview();

  /// Writes [preview] as one batch. See the class doc for the dedupe rule and
  /// the all-or-nothing commit.
  Future<GameLogImportCommitResult> commit(GameLogImportPreview preview);

  /// Reverses batch [batchId]. See the class doc.
  Future<void> undo(int batchId);

  /// Every batch ever committed, most recent first — "가져온 기록 관리".
  Stream<List<GameLogImportBatch>> watchBatches();
}

class DriftGameLogImportRepository implements GameLogImportRepository {
  DriftGameLogImportRepository({
    required this.db,
    required this.fileOpen,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final WbDatabase db;
  final FileOpenService fileOpen;
  final DateTime Function() _clock;

  static const int _maxBytes = 5 * 1024 * 1024;

  @override
  Future<GameLogImportPickResult> pickAndPreview() async {
    final PickedTextFile? file;
    try {
      file = await fileOpen.openTextFile(
        mimeTypes: const <String>['application/json', '*/*'],
        maxBytes: _maxBytes,
      );
    } on FileOpenUnsupportedException {
      return const GameLogImportFormatError('이 기기에서는 파일 가져오기를 지원하지 않습니다.');
    } on FileOpenFailure catch (e) {
      return GameLogImportFormatError(e.messageKo);
    }
    if (file == null) return const GameLogImportCancelled();

    final decoded = GameLogJsonCodec.decode(file.content);
    if (!decoded.isValid) {
      return GameLogImportFormatError(decoded.formatError!);
    }
    return GameLogImportReady(
      GameLogImportPreview(
        fileLabel: file.fileName,
        fileExportedAt: decoded.exportedAt,
        entries: decoded.entries,
        goals: decoded.goals,
        skippedCount: decoded.skippedCount,
      ),
    );
  }

  @override
  Future<GameLogImportCommitResult> commit(GameLogImportPreview preview) async {
    final now = _clock().toUtc();

    return db.transaction(() async {
      // The batch row is inserted first so every entry/goal it writes can
      // carry its id — its own counts are filled in with an UPDATE once the
      // real numbers are known, at the end of this same transaction.
      final batchId = await db
          .into(db.gameLogImportBatches)
          .insert(
            GameLogImportBatchesCompanion.insert(
              importedAt: now,
              sourceKind: 'json',
              fileLabel: Value(preview.fileLabel),
              fileExportedAt: Value(preview.fileExportedAt),
            ),
          );

      final existingEntryFingerprints = <String>{
        for (final row in await db.select(db.gameLogEntries).get())
          _entryFingerprint(
            createdAt: row.createdAt,
            dayKey: row.dayKey,
            opponentLabel: row.opponentLabel,
          ),
      };

      var inserted = 0;
      var duplicate = 0;
      // Maps the imported file's own entry ids to the row ids this device
      // just assigned them — a goal's `entryId` (from the same file) has to
      // be remapped through this, since the file's ids mean nothing on this
      // device's table.
      final remappedEntryIds = <int, int>{};

      for (final entry in preview.entries) {
        final fingerprint = _entryFingerprint(
          createdAt: entry.createdAt,
          dayKey: entry.dayKey,
          opponentLabel: entry.opponentLabel,
        );
        if (!existingEntryFingerprints.add(fingerprint)) {
          duplicate++;
          continue;
        }
        final newId = await db
            .into(db.gameLogEntries)
            .insert(
              GameLogEntriesCompanion.insert(
                playedAt: entry.playedAt,
                dayKey: entry.dayKey,
                gameId: Value(entry.gameId),
                competitionLabel: Value(entry.competitionLabel),
                opponentLabel: Value(entry.opponentLabel),
                venueLabel: Value(entry.venueLabel),
                positions: Value(GameLogPosition.encodeList(entry.positions)),
                result: Value(entry.result.wireValue),
                note: Value(entry.note),
                createdAt: entry.createdAt,
                updatedAt: Value(entry.updatedAt),
                plateAppearances: Value(entry.plateAppearances),
                hits: Value(entry.hits),
                walks: Value(entry.walks),
                sacrificeBunts: Value(entry.sacrificeBunts),
                strikeouts: Value(entry.strikeouts),
                runsBattedIn: Value(entry.runsBattedIn),
                runsScored: Value(entry.runsScored),
                stolenBases: Value(entry.stolenBases),
                outsPitched: Value(entry.outsPitched),
                pitchingStrikeouts: Value(entry.pitchingStrikeouts),
                pitchingWalks: Value(entry.pitchingWalks),
                runsAllowed: Value(entry.runsAllowed),
                importBatchId: Value(batchId),
              ),
            );
        remappedEntryIds[entry.id] = newId;
        inserted++;
      }

      // Goals: deduped the same shape (createdAt second + trimmed body) so a
      // re-import of the same file never doubles a note up, but never
      // counted in the entry-focused result screen — see the class doc.
      final existingGoalFingerprints = <String>{
        for (final row in await db.select(db.gameLogGoals).get())
          _goalFingerprint(createdAt: row.createdAt, body: row.body),
      };
      var deviceHasOpenGoal =
          await (db.select(db.gameLogGoals)..where((t) => t.closedAt.isNull()))
              .get()
              .then((rows) => rows.isNotEmpty);

      for (final goal in preview.goals) {
        final fingerprint = _goalFingerprint(
          createdAt: goal.createdAt,
          body: goal.body,
        );
        if (!existingGoalFingerprints.add(fingerprint)) continue;

        final remappedEntryId = goal.entryId == null
            ? null
            : remappedEntryIds[goal.entryId];

        if (goal.isOpen && deviceHasOpenGoal) {
          // A goal is already open on this device (or earlier in this same
          // file) — the incoming open goal is filed as silently superseded,
          // mirroring `GameLogGoalRepository.setGoal`'s own "outcome: null"
          // rule for the exact same situation.
          await db
              .into(db.gameLogGoals)
              .insert(
                GameLogGoalsCompanion.insert(
                  body: goal.body,
                  entryId: Value(remappedEntryId),
                  createdAt: goal.createdAt,
                  closedAt: Value(now),
                  importBatchId: Value(batchId),
                ),
              );
        } else {
          await db
              .into(db.gameLogGoals)
              .insert(
                GameLogGoalsCompanion.insert(
                  body: goal.body,
                  entryId: Value(remappedEntryId),
                  createdAt: goal.createdAt,
                  closedAt: Value(goal.closedAt),
                  outcome: Value(goal.outcome?.wireValue),
                  importBatchId: Value(batchId),
                ),
              );
          if (goal.isOpen) deviceHasOpenGoal = true;
        }
      }

      await (db.update(
        db.gameLogImportBatches,
      )..where((t) => t.id.equals(batchId))).write(
        GameLogImportBatchesCompanion(
          insertedCount: Value(inserted),
          duplicateCount: Value(duplicate),
          invalidCount: Value(preview.skippedCount),
        ),
      );

      return GameLogImportCommitResult(
        batchId: batchId,
        insertedCount: inserted,
        duplicateCount: duplicate,
        invalidCount: preview.skippedCount,
      );
    });
  }

  @override
  Future<void> undo(int batchId) async {
    final now = _clock().toUtc();
    await db.transaction(() async {
      // `import_batch_id = batchId` — a hand-typed row's `NULL` can never
      // satisfy this, so nothing outside this one batch is ever at risk.
      // See the class doc.
      await (db.delete(
        db.gameLogEntries,
      )..where((t) => t.importBatchId.equals(batchId))).go();
      await (db.delete(
        db.gameLogGoals,
      )..where((t) => t.importBatchId.equals(batchId))).go();
      await (db.update(db.gameLogImportBatches)
            ..where((t) => t.id.equals(batchId)))
          .write(GameLogImportBatchesCompanion(undoneAt: Value(now)));
    });
  }

  @override
  Stream<List<GameLogImportBatch>> watchBatches() {
    final select = db.select(db.gameLogImportBatches)
      ..orderBy([(t) => OrderingTerm.desc(t.importedAt)]);
    return select.watch().map(
      (rows) => rows.map((r) => r.toDomain()).toList(growable: false),
    );
  }

  static String _entryFingerprint({
    required DateTime createdAt,
    required String dayKey,
    required String? opponentLabel,
  }) {
    final seconds = createdAt.toUtc().millisecondsSinceEpoch ~/ 1000;
    return '$seconds|$dayKey|${_normalizeLabel(opponentLabel) ?? ''}';
  }

  static String _goalFingerprint({
    required DateTime createdAt,
    required String body,
  }) {
    final seconds = createdAt.toUtc().millisecondsSinceEpoch ~/ 1000;
    return '$seconds|${body.trim()}';
  }

  /// Trims and collapses internal whitespace — "한강 리버베어스" and
  /// "한강  리버베어스 " must fingerprint identically, since both describe the
  /// same opponent typed by the same person on two different occasions.
  static String? _normalizeLabel(String? raw) {
    if (raw == null) return null;
    final collapsed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    return collapsed.isEmpty ? null : collapsed;
  }
}
