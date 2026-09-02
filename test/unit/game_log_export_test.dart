import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/data/export/game_log_export.dart';
import 'package:w_baseball/data/models/game_log.dart';

/// Round-trips 출전 일지's export format.
///
/// This is the layer that protects a season of someone's own work when there
/// is no server and no account — see the feature brief's "phone-change
/// problem". If a field silently drops on the way out (or back in), a
/// reinstalled app loses it for good, so every field is asserted here, not
/// just the ones that happen to be convenient to check.
void main() {
  final entries = <GameLogEntry>[
    GameLogEntry(
      id: 1,
      playedAt: DateTime.utc(2026, 8, 15),
      dayKey: '2026-08-15',
      gameId: 'game-demo-1',
      competitionLabel: '동호인 리그',
      opponentLabel: '한강 리버베어스',
      venueLabel: '잠실보조경기장',
      positions: const <GameLogPosition>[
        GameLogPosition.catcher,
        GameLogPosition.leftField,
      ],
      result: GameLogResult.win,
      note: '병살 하나 잡음, "좋았다"',
      createdAt: DateTime.utc(2026, 8, 15, 21, 5),
      updatedAt: DateTime.utc(2026, 8, 16, 8),
      plateAppearances: 4,
      hits: 2,
      walks: 1,
      sacrificeBunts: 0,
      strikeouts: 1,
      runsBattedIn: 2,
      runsScored: 1,
      stolenBases: 1,
      outsPitched: 38,
      pitchingStrikeouts: 6,
      pitchingWalks: 2,
      runsAllowed: 3,
    ),
    // Every optional field left unset — the far more common real entry,
    // since 대회/상대/구장 and 메모 are all free text a first-time user may
    // skip entirely.
    GameLogEntry(
      id: 2,
      playedAt: DateTime.utc(2026, 8, 22),
      dayKey: '2026-08-22',
      createdAt: DateTime.utc(2026, 8, 22, 20),
    ),
  ];

  group('JSON 왕복', () {
    test('내보낸 뒤 다시 읽으면 모든 필드가 그대로 남는다', () {
      final encoded = GameLogJsonCodec.encode(
        entries,
        exportedAt: DateTime.utc(2026, 9, 1),
      );
      final result = GameLogJsonCodec.decode(encoded);

      expect(result.isValid, isTrue);
      expect(result.skippedCount, 0);
      expect(result.entries, hasLength(2));

      final full = result.entries.firstWhere((e) => e.id == 1);
      expect(full.playedAt, entries[0].playedAt);
      expect(full.dayKey, '2026-08-15');
      expect(full.gameId, 'game-demo-1');
      expect(full.competitionLabel, '동호인 리그');
      expect(full.opponentLabel, '한강 리버베어스');
      expect(full.venueLabel, '잠실보조경기장');
      expect(full.positions, <GameLogPosition>[
        GameLogPosition.catcher,
        GameLogPosition.leftField,
      ]);
      expect(full.result, GameLogResult.win);
      expect(full.note, '병살 하나 잡음, "좋았다"');
      expect(full.createdAt, entries[0].createdAt);
      expect(full.updatedAt, entries[0].updatedAt);
      // Stat line (Stage 2) — every one of the 12 columns round-trips too.
      expect(full.plateAppearances, 4);
      expect(full.hits, 2);
      expect(full.walks, 1);
      expect(full.sacrificeBunts, 0);
      expect(full.strikeouts, 1);
      expect(full.runsBattedIn, 2);
      expect(full.runsScored, 1);
      expect(full.stolenBases, 1);
      expect(full.outsPitched, 38);
      expect(full.pitchingStrikeouts, 6);
      expect(full.pitchingWalks, 2);
      expect(full.runsAllowed, 3);

      final sparse = result.entries.firstWhere((e) => e.id == 2);
      expect(sparse.gameId, isNull);
      expect(sparse.competitionLabel, isNull);
      expect(sparse.positions, isEmpty);
      expect(sparse.result, GameLogResult.unspecified);
      expect(sparse.note, isNull);
      expect(sparse.updatedAt, isNull);
      // No stat line at all — every stat field decodes to null, never 0.
      expect(sparse.plateAppearances, isNull);
      expect(sparse.hits, isNull);
      expect(sparse.outsPitched, isNull);
    });

    test('성적 키가 아예 없는 옛 내보내기 파일도 null로 읽힌다 (하위 호환)', () {
      // Simulates a Stage-1 export written before these keys existed —
      // `formatTag` never bumped for this, so an old file must still
      // decode cleanly. See this file's class doc and `formatTag`'s doc.
      const raw = '''
      {
        "format": "wb-myrecords-v1",
        "exportedAt": "2026-09-01T00:00:00.000Z",
        "entries": [
          {
            "id": 9,
            "playedAt": "2026-08-15T00:00:00.000Z",
            "dayKey": "2026-08-15",
            "createdAt": "2026-08-15T21:00:00.000Z"
          }
        ]
      }
      ''';
      final result = GameLogJsonCodec.decode(raw);
      expect(result.isValid, isTrue);
      final entry = result.entries.single;
      expect(entry.plateAppearances, isNull);
      expect(entry.hits, isNull);
      expect(entry.outsPitched, isNull);
    });

    test('형식 태그를 담는다', () {
      final encoded = GameLogJsonCodec.encode(
        entries,
        exportedAt: DateTime.utc(2026, 9, 1),
      );
      expect(encoded, contains('"format": "wb-myrecords-v1"'));
    });

    test('알 수 없는 형식은 항목 없이 오류로 보고한다', () {
      final result = GameLogJsonCodec.decode(
        '{"format": "something-else", "entries": []}',
      );
      expect(result.isValid, isFalse);
      expect(result.entries, isEmpty);
    });

    test('깨진 JSON은 오류로 보고하고 던지지 않는다', () {
      final result = GameLogJsonCodec.decode('not json at all {{{');
      expect(result.isValid, isFalse);
      expect(result.entries, isEmpty);
    });

    test('한 항목이 깨져도 나머지는 살아남는다', () {
      final encoded = GameLogJsonCodec.encode(
        entries,
        exportedAt: DateTime.utc(2026, 9, 1),
      );
      // Corrupt one entry's `id` (a required field) so it is unparsable,
      // without touching the envelope or the other entry.
      final corrupted = encoded.replaceFirst('"id": 2,', '"id": "oops",');
      final result = GameLogJsonCodec.decode(corrupted);

      expect(result.isValid, isTrue);
      expect(result.entries, hasLength(1));
      expect(result.skippedCount, 1);
    });

    test('알 수 없는 포지션 값은 조용히 걸러진다', () {
      final encoded = GameLogJsonCodec.encode(
        entries,
        exportedAt: DateTime.utc(2026, 9, 1),
      ).replaceFirst('"catcher"', '"someNewPositionFromTheFuture"');
      final result = GameLogJsonCodec.decode(encoded);

      final full = result.entries.firstWhere((e) => e.id == 1);
      expect(full.positions, <GameLogPosition>[GameLogPosition.leftField]);
    });
  });

  group('목표 (다음 경기에서 해볼 것) 왕복', () {
    final goals = <GameLogGoal>[
      GameLogGoal(
        id: 1,
        body: '초구 공략',
        entryId: 5,
        createdAt: DateTime.utc(2026, 8, 23, 21),
      ),
      // Closed, carried forward — no entryId, has an outcome.
      GameLogGoal(
        id: 2,
        body: '병살 완성, "확실하게"',
        createdAt: DateTime.utc(2026, 8, 16, 21),
        closedAt: DateTime.utc(2026, 8, 23, 21),
        outcome: GameLogGoalOutcome.carried,
      ),
    ];

    test('내보낸 뒤 다시 읽으면 목표가 그대로 남는다', () {
      final encoded = GameLogJsonCodec.encode(
        entries,
        exportedAt: DateTime.utc(2026, 9, 1),
        goals: goals,
      );
      final result = GameLogJsonCodec.decode(encoded);

      expect(result.isValid, isTrue);
      expect(result.goals, hasLength(2));

      final open = result.goals.firstWhere((g) => g.id == 1);
      expect(open.body, '초구 공략');
      expect(open.entryId, 5);
      expect(open.createdAt, goals[0].createdAt);
      expect(open.closedAt, isNull);
      expect(open.outcome, isNull);
      expect(open.isOpen, isTrue);

      final closed = result.goals.firstWhere((g) => g.id == 2);
      expect(closed.body, '병살 완성, "확실하게"');
      expect(closed.entryId, isNull);
      expect(closed.closedAt, goals[1].closedAt);
      expect(closed.outcome, GameLogGoalOutcome.carried);
      expect(closed.isOpen, isFalse);
    });

    test('목표 없이 내보내도 빈 배열로 왕복한다', () {
      final encoded = GameLogJsonCodec.encode(
        entries,
        exportedAt: DateTime.utc(2026, 9, 1),
      );
      final result = GameLogJsonCodec.decode(encoded);
      expect(result.isValid, isTrue);
      expect(result.goals, isEmpty);
    });

    test('goals 키가 아예 없는 옛 내보내기 파일도 빈 배열로 읽힌다 (하위 호환)', () {
      // Simulates a pre-Stage-3 export, written before this key existed.
      // `formatTag` never bumped for it — see this file's class doc.
      const raw = '''
      {
        "format": "wb-myrecords-v1",
        "exportedAt": "2026-09-01T00:00:00.000Z",
        "entries": []
      }
      ''';
      final result = GameLogJsonCodec.decode(raw);
      expect(result.isValid, isTrue);
      expect(result.goals, isEmpty);
    });
  });

  group('CSV 내보내기', () {
    test('머리글과 한 항목당 한 행을 만든다', () {
      final csv = GameLogCsvCodec.encode(entries);
      final lines = csv.trim().split('\n');
      expect(lines, hasLength(3)); // header + 2 entries
      expect(lines.first, contains('날짜'));
      expect(lines.first, contains('메모'));
    });

    test('쉼표와 따옴표가 든 메모를 안전하게 인용한다', () {
      final csv = GameLogCsvCodec.encode(entries);
      // The first entry's note contains a comma and embedded quotes.
      expect(csv, contains('"병살 하나 잡음, ""좋았다"""'));
    });

    test('성적 칼럼이 머리글과 각 행에 더해진다', () {
      final csv = GameLogCsvCodec.encode(entries);
      final lines = csv.trim().split('\n');
      expect(lines.first, contains('타석'));
      expect(lines.first, contains('희생번트'));
      expect(lines.first, contains('투구아웃수'));

      // First entry's row carries its stat line as plain numbers.
      final firstRow = lines[1];
      expect(firstRow, contains('4')); // 타석
      expect(firstRow, contains('38')); // outsPitched, raw — see the codec's
      // doc comment on why this is a plain number, not `12⅔이닝`.

      // Second entry has no stat line: those columns are empty, not "0".
      final secondRow = lines[2];
      final cells = secondRow.split(',');
      // 날짜,대회,상대,구장,포지션,결과,메모 = 7 leading columns, then 타석 is next.
      expect(cells[7], ''); // 타석
    });
  });
}
