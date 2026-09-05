import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/database/database.dart';
import 'package:w_baseball/core/platform/platform_services.dart';
import 'package:w_baseball/data/export/game_log_export.dart';
import 'package:w_baseball/data/models/game_log.dart';
import 'package:w_baseball/data/repositories/game_log_import_repository.dart';

/// A picker that hands back canned content (or throws) instead of ever
/// touching a real file or platform channel.
class _FakeFileOpenService implements FileOpenService {
  _FakeFileOpenService({this.content, this.fileName, this.errorToThrow});

  final String? content;
  final String? fileName;
  final Object? errorToThrow;

  /// Records what the repository actually asked for, so a test can assert
  /// the 5MB cap is really the value passed down — see the "5MB 상한" test.
  int? lastRequestedMaxBytes;

  @override
  Future<PickedTextFile?> openTextFile({
    List<String> mimeTypes = const <String>['application/json', '*/*'],
    int maxBytes = 5 * 1024 * 1024,
  }) async {
    lastRequestedMaxBytes = maxBytes;
    if (errorToThrow != null) throw errorToThrow!;
    if (content == null) return null;
    return PickedTextFile(content: content!, fileName: fileName);
  }
}

/// 출전 일지 가져오기.
///
/// The rule that matters most here: **되돌리기 must never touch a hand-typed
/// row.** `importBatchId` is null on everything typed by hand, and SQL's
/// `= X` structurally cannot match `NULL` — the "수기 기록 보존" test below is
/// the one proving that in practice, not just by reading the SQL.
void main() {
  late WbDatabase db;
  final now = DateTime.utc(2026, 9, 1, 12);

  DriftGameLogImportRepository repoWith(FileOpenService fileOpen) =>
      DriftGameLogImportRepository(
        db: db,
        fileOpen: fileOpen,
        clock: () => now,
      );

  setUp(() {
    db = WbDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  GameLogEntry entry({
    required int id,
    required DateTime playedAt,
    required DateTime createdAt,
    String? opponentLabel,
    String? note,
    GameLogResult result = GameLogResult.unspecified,
  }) {
    return GameLogEntry(
      id: id,
      playedAt: playedAt,
      dayKey:
          '${playedAt.year}-${playedAt.month.toString().padLeft(2, '0')}-'
          '${playedAt.day.toString().padLeft(2, '0')}',
      opponentLabel: opponentLabel,
      note: note,
      result: result,
      createdAt: createdAt,
    );
  }

  group('파일 선택', () {
    test('취소하면(파일을 고르지 않으면) 아무것도 하지 않는다', () async {
      final repo = repoWith(_FakeFileOpenService(content: null));
      final result = await repo.pickAndPreview();
      expect(result, isA<GameLogImportCancelled>());
      expect(await db.select(db.gameLogEntries).get(), isEmpty);
    });

    test('봉투 형식이 다르면 쓰기 전에 오류로 막는다', () async {
      final repo = repoWith(
        _FakeFileOpenService(content: '{"format": "something-else"}'),
      );
      final result = await repo.pickAndPreview();
      expect(result, isA<GameLogImportFormatError>());
      expect(
        (result as GameLogImportFormatError).message,
        contains('지원하지 않는 형식'),
      );
      // Nothing was written — the format check happens before any DB call.
      expect(await db.select(db.gameLogEntries).get(), isEmpty);
    });

    test('플랫폼 실패(5MB 초과 등)도 미리보기 없이 오류로 막는다', () async {
      final repo = repoWith(
        _FakeFileOpenService(
          errorToThrow: const FileOpenFailure('파일이 너무 커서 열 수 없습니다. (5MB 초과)'),
        ),
      );
      final result = await repo.pickAndPreview();
      expect(result, isA<GameLogImportFormatError>());
      expect((result as GameLogImportFormatError).message, contains('5MB'));
    });

    test('이 기기에서 지원하지 않으면(iOS 등) 명시적인 오류로 알린다', () async {
      final repo = repoWith(
        _FakeFileOpenService(
          errorToThrow: const FileOpenUnsupportedException(),
        ),
      );
      final result = await repo.pickAndPreview();
      expect(result, isA<GameLogImportFormatError>());
    });

    test('5MB 상한을 그대로 플랫폼에 전달한다', () async {
      final fake = _FakeFileOpenService(content: null);
      final repo = repoWith(fake);
      await repo.pickAndPreview();
      expect(fake.lastRequestedMaxBytes, 5 * 1024 * 1024);
    });

    test('정상 파일은 기간·첫/마지막 기록·메모 예시를 담은 미리보기로 반환된다', () async {
      final entries = <GameLogEntry>[
        entry(
          id: 1,
          playedAt: DateTime.utc(2026, 4, 12),
          createdAt: DateTime.utc(2026, 4, 12, 21),
          opponentLabel: 'OO클럽',
          result: GameLogResult.win,
        ),
        entry(
          id: 2,
          playedAt: DateTime.utc(2026, 8, 30),
          createdAt: DateTime.utc(2026, 8, 30, 21),
          opponentLabel: '△△클럽',
          note: '첫 도루 성공',
          result: GameLogResult.loss,
        ),
      ];
      final encoded = GameLogJsonCodec.encode(
        entries,
        exportedAt: DateTime.utc(2026, 8, 30, 5),
      );
      final repo = repoWith(
        _FakeFileOpenService(
          content: encoded,
          fileName: 'wb-myrecords-20260830-1412.json',
        ),
      );

      final result = await repo.pickAndPreview();
      expect(result, isA<GameLogImportReady>());
      final preview = (result as GameLogImportReady).preview;

      expect(preview.entries, hasLength(2));
      expect(preview.fileLabel, 'wb-myrecords-20260830-1412.json');
      expect(preview.fileExportedAt, DateTime.utc(2026, 8, 30, 5));
      expect(preview.firstByPlayedAt?.opponentLabel, 'OO클럽');
      expect(preview.lastByPlayedAt?.opponentLabel, '△△클럽');
      expect(preview.sampleNote, '첫 도루 성공');
      // Nothing written yet — a preview is read-only.
      expect(await db.select(db.gameLogEntries).get(), isEmpty);
    });
  });

  group('commit — 기록과 목표를 한 배치로 남긴다', () {
    test('가져온 행에 배치 id가 남고, 배치 자체의 집계도 맞는다', () async {
      final repo = repoWith(_FakeFileOpenService());
      final preview = GameLogImportPreview(
        entries: <GameLogEntry>[
          entry(
            id: 1,
            playedAt: DateTime.utc(2026, 8, 20),
            createdAt: DateTime.utc(2026, 8, 20, 21),
            opponentLabel: '한강 리버베어스',
          ),
          entry(
            id: 2,
            playedAt: DateTime.utc(2026, 8, 27),
            createdAt: DateTime.utc(2026, 8, 27, 21),
            opponentLabel: '남산 호크스',
          ),
        ],
        goals: const <GameLogGoal>[],
        skippedCount: 1,
      );

      final result = await repo.commit(preview);
      expect(result.insertedCount, 2);
      expect(result.duplicateCount, 0);
      expect(result.invalidCount, 1);

      final rows = await db.select(db.gameLogEntries).get();
      expect(rows, hasLength(2));
      expect(rows.every((r) => r.importBatchId == result.batchId), isTrue);

      final batch = (await db.select(db.gameLogImportBatches).get()).single;
      expect(batch.insertedCount, 2);
      expect(batch.invalidCount, 1);
      expect(batch.undoneAt, isNull);
    });

    test('exportedAt이 없는 파일(구버전 내보내기)도 배치에는 그대로 null로 남는다', () async {
      final repo = repoWith(_FakeFileOpenService());
      final result = await repo.commit(
        GameLogImportPreview(
          entries: <GameLogEntry>[
            entry(
              id: 1,
              playedAt: DateTime.utc(2026, 8, 20),
              createdAt: DateTime.utc(2026, 8, 20, 21),
            ),
          ],
          skippedCount: 0,
        ),
      );
      final batch = await (db.select(
        db.gameLogImportBatches,
      )..where((t) => t.id.equals(result.batchId))).getSingle();
      expect(batch.fileExportedAt, isNull);
    });
  });

  group('중복 판정 — createdAt(초) + dayKey + 정규화한 상대만 모두 같을 때', () {
    test('기존 기록과 세 값이 모두 같으면 건너뛴다', () async {
      final repo = repoWith(_FakeFileOpenService());
      // A hand-typed row already on the device.
      await db
          .into(db.gameLogEntries)
          .insert(
            GameLogEntriesCompanion.insert(
              playedAt: DateTime.utc(2026, 8, 20),
              dayKey: '2026-08-20',
              opponentLabel: const Value('한강 리버베어스'),
              createdAt: DateTime.utc(2026, 8, 20, 21, 5, 30),
            ),
          );

      final result = await repo.commit(
        GameLogImportPreview(
          entries: <GameLogEntry>[
            entry(
              id: 1,
              playedAt: DateTime.utc(2026, 8, 20),
              // Same second, sub-second differs — still the same
              // fingerprint (truncated to whole seconds).
              createdAt: DateTime.utc(2026, 8, 20, 21, 5, 30, 900),
              // Extra/irregular whitespace — normalisation must still match.
              opponentLabel: '  한강   리버베어스 ',
            ),
          ],
          skippedCount: 0,
        ),
      );

      expect(result.insertedCount, 0);
      expect(result.duplicateCount, 1);
      expect(await db.select(db.gameLogEntries).get(), hasLength(1));
    });

    test('상대가 다르면(같은 날, 같은 시각이라도) 중복이 아니다', () async {
      final repo = repoWith(_FakeFileOpenService());
      await db
          .into(db.gameLogEntries)
          .insert(
            GameLogEntriesCompanion.insert(
              playedAt: DateTime.utc(2026, 8, 20),
              dayKey: '2026-08-20',
              opponentLabel: const Value('한강 리버베어스'),
              createdAt: DateTime.utc(2026, 8, 20, 21),
            ),
          );

      final result = await repo.commit(
        GameLogImportPreview(
          entries: <GameLogEntry>[
            entry(
              id: 1,
              playedAt: DateTime.utc(2026, 8, 20),
              createdAt: DateTime.utc(2026, 8, 20, 21),
              opponentLabel: '남산 호크스',
            ),
          ],
          skippedCount: 0,
        ),
      );
      expect(result.insertedCount, 1);
      expect(result.duplicateCount, 0);
    });

    test('더블헤더 — 같은 날 같은 상대라도 createdAt이 다르면 두 경기 모두 살아남는다', () async {
      final repo = repoWith(_FakeFileOpenService());
      final result = await repo.commit(
        GameLogImportPreview(
          entries: <GameLogEntry>[
            entry(
              id: 1,
              playedAt: DateTime.utc(2026, 8, 20),
              createdAt: DateTime.utc(2026, 8, 20, 14),
              opponentLabel: '한강 리버베어스',
            ),
            entry(
              id: 2,
              playedAt: DateTime.utc(2026, 8, 20),
              createdAt: DateTime.utc(2026, 8, 20, 18),
              opponentLabel: '한강 리버베어스',
            ),
          ],
          skippedCount: 0,
        ),
      );
      // If a bug ever narrows the fingerprint to dayKey + opponent alone
      // (dropping createdAt), this collapses to insertedCount 1 — see the
      // repository's class doc for why that direction is the unsafe one.
      expect(result.insertedCount, 2);
      expect(result.duplicateCount, 0);
    });
  });

  group('열린 목표 충돌', () {
    test('기기에 열린 목표가 없으면 파일의 열린 목표가 그대로 열린 채 들어온다', () async {
      final repo = repoWith(_FakeFileOpenService());
      await repo.commit(
        GameLogImportPreview(
          entries: const <GameLogEntry>[],
          goals: <GameLogGoal>[
            GameLogGoal(id: 1, body: '초구 공략', createdAt: now),
          ],
          skippedCount: 0,
        ),
      );
      final goals = await db.select(db.gameLogGoals).get();
      expect(goals, hasLength(1));
      expect(goals.single.closedAt, isNull);
    });

    test('이미 열린 목표가 있으면 파일의 열린 목표는 닫힌 채로(outcome null) 들어온다', () async {
      final repo = repoWith(_FakeFileOpenService());
      await db
          .into(db.gameLogGoals)
          .insert(GameLogGoalsCompanion.insert(body: '기존 목표', createdAt: now));

      await repo.commit(
        GameLogImportPreview(
          entries: const <GameLogEntry>[],
          goals: <GameLogGoal>[
            GameLogGoal(id: 1, body: '초구 공략', createdAt: now),
          ],
          skippedCount: 0,
        ),
      );

      final goals = await db.select(db.gameLogGoals).get();
      expect(goals, hasLength(2));
      final imported = goals.firstWhere((g) => g.body == '초구 공략');
      expect(imported.closedAt, isNotNull);
      expect(imported.outcome, isNull); // silently superseded, not "carried".
      final existing = goals.firstWhere((g) => g.body == '기존 목표');
      expect(existing.closedAt, isNull); // untouched.
    });
  });

  group('되돌리기', () {
    test('이 배치가 넣은 행만 지우고, 배치 행 자체는 undoneAt만 남긴다', () async {
      final repo = repoWith(_FakeFileOpenService());
      final result = await repo.commit(
        GameLogImportPreview(
          entries: <GameLogEntry>[
            entry(
              id: 1,
              playedAt: DateTime.utc(2026, 8, 20),
              createdAt: DateTime.utc(2026, 8, 20, 21),
            ),
          ],
          skippedCount: 0,
        ),
      );

      await repo.undo(result.batchId);

      expect(await db.select(db.gameLogEntries).get(), isEmpty);
      final batch = await (db.select(
        db.gameLogImportBatches,
      )..where((t) => t.id.equals(result.batchId))).getSingle();
      expect(batch.undoneAt, isNotNull);
      expect(batch.insertedCount, 1); // the batch's own history is kept.
    });

    // The single most important guarantee in this feature: undo is a
    // data-loss path if it ever reaches a hand-typed row. `importBatchId`
    // is null on every such row, and SQL's `= X` can never match `NULL` —
    // this test proves that holds in practice, not just on paper.
    test('되돌려도 수기로 입력한 기록과 목표는 지워지지 않는다', () async {
      final repo = repoWith(_FakeFileOpenService());

      final handTypedEntryId = await db
          .into(db.gameLogEntries)
          .insert(
            GameLogEntriesCompanion.insert(
              playedAt: DateTime.utc(2026, 7, 1),
              dayKey: '2026-07-01',
              opponentLabel: const Value('수기 입력 경기'),
              createdAt: DateTime.utc(2026, 7, 1, 21),
            ),
          );
      final handTypedGoalId = await db
          .into(db.gameLogGoals)
          .insert(GameLogGoalsCompanion.insert(body: '수기 목표', createdAt: now));

      final result = await repo.commit(
        GameLogImportPreview(
          entries: <GameLogEntry>[
            entry(
              id: 1,
              playedAt: DateTime.utc(2026, 8, 20),
              createdAt: DateTime.utc(2026, 8, 20, 21),
              opponentLabel: '가져온 경기',
            ),
          ],
          goals: <GameLogGoal>[
            GameLogGoal(id: 1, body: '가져온 목표', createdAt: now),
          ],
          skippedCount: 0,
        ),
      );

      await repo.undo(result.batchId);

      final entries = await db.select(db.gameLogEntries).get();
      expect(entries, hasLength(1));
      expect(entries.single.id, handTypedEntryId);
      expect(entries.single.opponentLabel, '수기 입력 경기');

      final goals = await db.select(db.gameLogGoals).get();
      expect(goals, hasLength(1));
      expect(goals.single.id, handTypedGoalId);
      expect(goals.single.body, '수기 목표');
    });

    test('가져온 기록 관리 목록은 최신순이고, 되돌린 배치도 계속 보인다', () async {
      final repo = repoWith(_FakeFileOpenService());
      final first = await repo.commit(
        GameLogImportPreview(
          entries: <GameLogEntry>[
            entry(
              id: 1,
              playedAt: DateTime.utc(2026, 8, 20),
              createdAt: DateTime.utc(2026, 8, 20, 21),
            ),
          ],
          skippedCount: 0,
        ),
      );
      await repo.undo(first.batchId);

      final batches = await repo.watchBatches().first;
      expect(batches, hasLength(1));
      expect(batches.single.isUndone, isTrue);
    });
  });

  group('트랜잭션 원자성 — 하나라도 실패하면 전부 되돌아간다', () {
    test('두 번째 항목(목표) 처리 중 실패하면, 먼저 들어간 기록도 함께 사라진다', () async {
      // A trigger that raises a real SQLite error the instant a goal with
      // this exact body is inserted — a deterministic way to force a
      // mid-commit failure without touching the repository's own code.
      // `commit` inserts every entry *before* any goal (see its source), so
      // by the time this fires, the entry below has already been written
      // inside the same transaction — the only question this test answers
      // is whether that already-written row survives the later failure.
      await db.customStatement('''
        CREATE TRIGGER poison_goal
        BEFORE INSERT ON game_log_goals
        WHEN NEW.body = 'POISON'
        BEGIN
          SELECT RAISE(ABORT, 'induced failure for atomicity test');
        END;
      ''');

      final repo = repoWith(_FakeFileOpenService());
      final preview = GameLogImportPreview(
        entries: <GameLogEntry>[
          entry(
            id: 1,
            playedAt: DateTime.utc(2026, 8, 20),
            createdAt: DateTime.utc(2026, 8, 20, 21),
          ),
        ],
        goals: <GameLogGoal>[
          GameLogGoal(id: 1, body: 'POISON', createdAt: now),
        ],
        skippedCount: 0,
      );

      await expectLater(repo.commit(preview), throwsA(anything));

      // The whole batch — the entry included — must be gone, not just the
      // goal that triggered the failure. A version of `commit` that forgot
      // to wrap this in `db.transaction()` would leave the entry behind.
      expect(await db.select(db.gameLogEntries).get(), isEmpty);
      expect(await db.select(db.gameLogGoals).get(), isEmpty);
      expect(await db.select(db.gameLogImportBatches).get(), isEmpty);
    });
  });
}
