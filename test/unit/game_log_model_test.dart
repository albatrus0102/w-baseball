import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/data/models/game_log.dart';

/// 포지션 히스토리 derivation.
///
/// The owner named this explicitly: "외야에서 포수로 전향" is an identity
/// event, not a statistic. These tests are the mutation check for that promise
/// — a position that never changes must never manufacture a "전향", and a
/// change three games apart must be found even when nothing else about the
/// entries is remarkable.
void main() {
  GameLogEntry entry({
    required int id,
    required DateTime date,
    List<GameLogPosition> positions = const <GameLogPosition>[],
  }) => GameLogEntry(
    id: id,
    playedAt: date,
    dayKey: '2026',
    positions: positions,
    createdAt: date,
  );

  group('derivePositionTimeline', () {
    test('빈 목록에서는 아무 것도 만들지 않는다', () {
      expect(derivePositionTimeline(const <GameLogEntry>[]), isEmpty);
    });

    test('포지션이 한 번도 안 바뀌면 이벤트가 하나뿐이다', () {
      final entries = <GameLogEntry>[
        entry(
          id: 1,
          date: DateTime.utc(2026, 7, 1),
          positions: const [GameLogPosition.centerField],
        ),
        entry(
          id: 2,
          date: DateTime.utc(2026, 7, 8),
          positions: const [GameLogPosition.centerField],
        ),
        entry(
          id: 3,
          date: DateTime.utc(2026, 7, 15),
          positions: const [GameLogPosition.centerField],
        ),
      ];

      final events = derivePositionTimeline(entries);
      expect(events, hasLength(1));
      expect(events.single.isFirst, isTrue);
      expect(events.single.positions, [GameLogPosition.centerField]);
    });

    test('외야에서 포수로 전향한 시점을 정확히 찾는다', () {
      final entries = <GameLogEntry>[
        entry(
          id: 1,
          date: DateTime.utc(2026, 6, 1),
          positions: const [GameLogPosition.leftField],
        ),
        entry(
          id: 2,
          date: DateTime.utc(2026, 6, 8),
          positions: const [GameLogPosition.leftField],
        ),
        entry(
          id: 3,
          date: DateTime.utc(2026, 7, 1),
          positions: const [GameLogPosition.catcher],
        ),
      ];

      final events = derivePositionTimeline(entries);
      expect(events, hasLength(2));
      expect(events[0].isFirst, isTrue);
      expect(events[0].positions, [GameLogPosition.leftField]);
      expect(events[1].isFirst, isFalse);
      expect(events[1].date, DateTime.utc(2026, 7, 1));
      expect(events[1].previousPositions, [GameLogPosition.leftField]);
      expect(events[1].positions, [GameLogPosition.catcher]);
    });

    test('입력 순서와 무관하게 실제 경기 날짜 순으로 판단한다', () {
      // Deliberately supplied out of order (as watchEntries() returns,
      // newest first) — the derivation must sort internally.
      final entries = <GameLogEntry>[
        entry(
          id: 3,
          date: DateTime.utc(2026, 7, 1),
          positions: const [GameLogPosition.catcher],
        ),
        entry(
          id: 1,
          date: DateTime.utc(2026, 6, 1),
          positions: const [GameLogPosition.leftField],
        ),
      ];

      final events = derivePositionTimeline(entries);
      expect(events, hasLength(2));
      expect(events[0].date, DateTime.utc(2026, 6, 1));
      expect(events[1].date, DateTime.utc(2026, 7, 1));
    });

    test('포지션이 없는 기록은 무시한다', () {
      final entries = <GameLogEntry>[
        entry(id: 1, date: DateTime.utc(2026, 6, 1)), // no positions
        entry(
          id: 2,
          date: DateTime.utc(2026, 6, 8),
          positions: const [GameLogPosition.shortstop],
        ),
      ];

      final events = derivePositionTimeline(entries);
      expect(events, hasLength(1));
      expect(events.single.positions, [GameLogPosition.shortstop]);
    });

    test('같은 포지션 집합이면 순서가 달라도 전향으로 보지 않는다', () {
      final entries = <GameLogEntry>[
        entry(
          id: 1,
          date: DateTime.utc(2026, 6, 1),
          positions: const [GameLogPosition.catcher, GameLogPosition.leftField],
        ),
        entry(
          id: 2,
          date: DateTime.utc(2026, 6, 8),
          positions: const [GameLogPosition.leftField, GameLogPosition.catcher],
        ),
      ];

      final events = derivePositionTimeline(entries);
      expect(events, hasLength(1));
    });
  });

  group('GameLogPosition 인코딩', () {
    test('목록을 comma-join 하고 되돌린다', () {
      const positions = <GameLogPosition>[
        GameLogPosition.pitcher,
        GameLogPosition.designatedHitter,
      ];
      final encoded = GameLogPosition.encodeList(positions);
      expect(encoded, 'pitcher,designatedHitter');
      expect(GameLogPosition.decodeList(encoded), positions);
    });

    test('빈 목록과 null을 안전하게 처리한다', () {
      expect(GameLogPosition.encodeList(const []), '');
      expect(GameLogPosition.decodeList(''), isEmpty);
      expect(GameLogPosition.decodeList(null), isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  // Stat aggregation (Stage 2)
  // ---------------------------------------------------------------------
  //
  // The four checks the build brief calls out by name, each proven with a
  // mutation: flipping any of these back to the "wrong but plausible"
  // version must break a test here.
  //   1. threshold 20 → 19
  //   2. denominator drops "− 희생번트"
  //   3. a null-스탯 game counts toward the aggregate
  //   4. (utf8.encode → .codeUnits is covered in game_log_export_test.dart,
  //      not here)
  group('BattingStatSummary — 출루율 공식', () {
    var nextId = 1;
    GameLogEntry battingEntry({
      int? plateAppearances,
      int? hits,
      int? walks,
      int? sacrificeBunts,
      int? strikeouts,
      int? runsBattedIn,
      int? runsScored,
      int? stolenBases,
    }) => GameLogEntry(
      id: nextId++,
      playedAt: DateTime.utc(2026, 7, nextId),
      dayKey: '2026-07-${nextId.toString().padLeft(2, '0')}',
      createdAt: DateTime.utc(2026, 7, nextId),
      plateAppearances: plateAppearances,
      hits: hits,
      walks: walks,
      sacrificeBunts: sacrificeBunts,
      strikeouts: strikeouts,
      runsBattedIn: runsBattedIn,
      runsScored: runsScored,
      stolenBases: stolenBases,
    );

    test('앱의 OBP 가이드와 같은 식으로 계산한다: (안타+볼넷) ÷ (타석−희생번트)', () {
      // The build brief's own worked example: 안타 14 · 볼넷 7, 48타석,
      // 희생번트 0. (14+7)/48 = 21/48 = .4375 — not the brief's mis-typed
      // 21/46 for this no-sac-bunt case.
      final entries = <GameLogEntry>[
        battingEntry(plateAppearances: 48, hits: 14, walks: 7),
      ];
      final batting = BattingStatSummary.from(entries)!;

      expect(batting.plateAppearances, 48);
      expect(batting.reachedBaseCount, 21);
      expect(batting.obpDenominator, 48); // no 희생번트 to subtract.
      expect(batting.onBasePercentage, closeTo(21 / 48, 1e-9));
    });

    test('희생번트는 타석에서 빠지지만 안타·볼넷에는 영향이 없다 (21÷46=.457, .447 아님)', () {
      // Same 21-times-on-base as above, but now 2 of the 48 타석 were
      // 희생번트: denominator becomes 48-2=46, not 48. 21/46 = .45652... —
      // the brief's own arithmetic check (its prose example had this as
      // .447, which is wrong; the correct value is .457).
      final entries = <GameLogEntry>[
        battingEntry(
          plateAppearances: 48,
          hits: 14,
          walks: 7,
          sacrificeBunts: 2,
        ),
      ];
      final batting = BattingStatSummary.from(entries)!;

      expect(batting.obpDenominator, 46);
      expect(batting.onBasePercentage, closeTo(21 / 46, 1e-9));
      expect(batting.onBasePercentage, isNot(closeTo(21 / 48, 1e-9)));
      // .457 rounds to 3 places — this is the number a screen would show.
      expect(double.parse(batting.onBasePercentage!.toStringAsFixed(3)), 0.457);
    });

    test('분모가 타석이 아니라 (타석−희생번트)로 계산되지 않으면 이 값이 달라진다', () {
      // Mutation target #2: if `obpDenominator` were ever changed back to
      // raw `plateAppearances` (dropping "− 희생번트"), this would read 48
      // instead of 46 and the test above would fail — this test pins the
      // getter directly so the failure is unambiguous.
      final batting = BattingStatSummary.from(<GameLogEntry>[
        battingEntry(plateAppearances: 20, hits: 0, sacrificeBunts: 2),
      ])!;
      expect(batting.obpDenominator, 18);
      expect(batting.plateAppearances, 20);
    });

    group('문턱: obpDenominator ≥ 20일 때만 출루율을 보여준다', () {
      test('분모 19 — 출루율을 보여주지 않는다 (mutation target #1)', () {
        final batting = BattingStatSummary.from(<GameLogEntry>[
          battingEntry(plateAppearances: 19, hits: 5),
        ])!;
        expect(batting.obpDenominator, 19);
        expect(batting.meetsThreshold, isFalse);
        expect(batting.onBasePercentage, isNull);
      });

      test('분모 20 — 출루율을 보여준다', () {
        final batting = BattingStatSummary.from(<GameLogEntry>[
          battingEntry(plateAppearances: 20, hits: 5),
        ])!;
        expect(batting.obpDenominator, 20);
        expect(batting.meetsThreshold, isTrue);
        expect(batting.onBasePercentage, isNotNull);
      });

      test('19에서 20으로 한 타석만 늘어도 문턱을 넘는다', () {
        final at19 = BattingStatSummary.from(<GameLogEntry>[
          battingEntry(plateAppearances: 19),
        ])!;
        final at20 = BattingStatSummary.from(<GameLogEntry>[
          battingEntry(plateAppearances: 20),
        ])!;
        expect(at19.meetsThreshold, isFalse);
        expect(at20.meetsThreshold, isTrue);
      });
    });

    test('성적 없는 경기(타석 null)는 집계에서 완전히 빠진다 (mutation target #3)', () {
      final entries = <GameLogEntry>[
        battingEntry(plateAppearances: null), // 접힌 채 저장된 경기.
        battingEntry(plateAppearances: 10, hits: 3, walks: 1),
      ];
      final batting = BattingStatSummary.from(entries)!;

      // Only the second entry counts — 1 game, not 2.
      expect(batting.gamesWithStats, 1);
      expect(batting.plateAppearances, 10);
      expect(batting.hits, 3);
      expect(batting.walks, 1);
    });

    test('타석이 있는 경기가 하나도 없으면 null을 돌려준다', () {
      final entries = <GameLogEntry>[
        battingEntry(plateAppearances: null),
        battingEntry(plateAppearances: null),
      ];
      expect(BattingStatSummary.from(entries), isNull);
    });

    test('희생번트를 적지 않은 경기는 0으로 계산하고, 그 경기 수를 센다', () {
      final entries = <GameLogEntry>[
        battingEntry(plateAppearances: 20, hits: 5, sacrificeBunts: null),
        battingEntry(plateAppearances: 20, hits: 5, sacrificeBunts: 1),
      ];
      final batting = BattingStatSummary.from(entries)!;

      expect(batting.gamesMissingSacrificeBunts, 1);
      // The null-희생번트 game contributes 0, not skipped — 타석 total is
      // still both games' 40, and 희생번트 total is only the known 1.
      expect(batting.plateAppearances, 40);
      expect(batting.sacrificeBunts, 1);
      expect(batting.obpDenominator, 39); // 40 − 1, never higher than true.
    });

    test('한 경기라도 야수 기록이 있으면 다른 경기의 개별 항목은 각각 null이 0으로 처리된다', () {
      // A counted game (plateAppearances set) that left every other field
      // untouched must not crash or silently propagate nulls into the sums.
      final batting = BattingStatSummary.from(<GameLogEntry>[
        battingEntry(plateAppearances: 20),
      ])!;
      expect(batting.hits, 0);
      expect(batting.walks, 0);
      expect(batting.strikeouts, 0);
      expect(batting.runsBattedIn, 0);
      expect(batting.runsScored, 0);
      expect(batting.stolenBases, 0);
    });
  });

  group('PitchingStatSummary', () {
    GameLogEntry pitchingEntry({
      required int id,
      int? outsPitched,
      int? pitchingStrikeouts,
      int? pitchingWalks,
      int? runsAllowed,
    }) => GameLogEntry(
      id: id,
      playedAt: DateTime.utc(2026, 7, id),
      dayKey: '2026-07-${id.toString().padLeft(2, '0')}',
      createdAt: DateTime.utc(2026, 7, id),
      outsPitched: outsPitched,
      pitchingStrikeouts: pitchingStrikeouts,
      pitchingWalks: pitchingWalks,
      runsAllowed: runsAllowed,
    );

    test('아웃카운트를 합산하고, 투구 기록 없는 경기는 제외한다', () {
      final entries = <GameLogEntry>[
        pitchingEntry(id: 1, outsPitched: 20, pitchingStrikeouts: 6),
        pitchingEntry(id: 2, outsPitched: 18, pitchingStrikeouts: 5),
        pitchingEntry(id: 3), // 투구 기록 없음 — outsPitched null.
      ];
      final pitching = PitchingStatSummary.from(entries)!;

      expect(pitching.gamesWithStats, 2);
      expect(pitching.outsPitched, 38); // 20 + 18, not the 3rd game.
      expect(pitching.strikeouts, 11);
    });

    test('투구 기록이 하나도 없으면 null을 돌려준다', () {
      final entries = <GameLogEntry>[pitchingEntry(id: 1)];
      expect(PitchingStatSummary.from(entries), isNull);
    });

    test('formatInningsPitched: 12⅔이닝처럼 아웃카운트를 이닝으로 표시한다', () {
      expect(formatInningsPitched(38), '12⅔이닝'); // 12*3+2
      expect(formatInningsPitched(36), '12이닝');
      expect(formatInningsPitched(37), '12⅓이닝');
      expect(formatInningsPitched(1), '⅓이닝');
      expect(formatInningsPitched(0), '0이닝');
    });
  });

  group('GameLogStatSummary', () {
    GameLogEntry entryWithResult(int id, GameLogResult result) => GameLogEntry(
      id: id,
      playedAt: DateTime.utc(2026, 7, id),
      dayKey: '2026-07-${id.toString().padLeft(2, '0')}',
      createdAt: DateTime.utc(2026, 7, id),
      result: result,
    );

    test('승·패·무 개수를 센다', () {
      final entries = <GameLogEntry>[
        entryWithResult(1, GameLogResult.win),
        entryWithResult(2, GameLogResult.win),
        entryWithResult(3, GameLogResult.loss),
        entryWithResult(4, GameLogResult.draw),
        entryWithResult(5, GameLogResult.unspecified),
      ];
      final summary = GameLogStatSummary.from(entries);

      expect(summary.totalGames, 5);
      expect(summary.wins, 2);
      expect(summary.losses, 1);
      expect(summary.draws, 1);
      expect(summary.hasAnyResult, isTrue);
    });

    test('기록된 결과가 하나도 없으면 hasAnyResult가 false다', () {
      final entries = <GameLogEntry>[
        entryWithResult(1, GameLogResult.unspecified),
      ];
      expect(GameLogStatSummary.from(entries).hasAnyResult, isFalse);
    });

    test('타격 기록이 없는 경기 수를 센다', () {
      final entries = <GameLogEntry>[
        GameLogEntry(
          id: 1,
          playedAt: DateTime.utc(2026, 7, 1),
          dayKey: '2026-07-01',
          createdAt: DateTime.utc(2026, 7, 1),
          plateAppearances: 10,
          hits: 3,
        ),
        GameLogEntry(
          id: 2,
          playedAt: DateTime.utc(2026, 7, 2),
          dayKey: '2026-07-02',
          createdAt: DateTime.utc(2026, 7, 2),
        ),
        GameLogEntry(
          id: 3,
          playedAt: DateTime.utc(2026, 7, 3),
          dayKey: '2026-07-03',
          createdAt: DateTime.utc(2026, 7, 3),
        ),
      ];
      final summary = GameLogStatSummary.from(entries);

      expect(summary.totalGames, 3);
      expect(summary.batting!.gamesWithStats, 1);
      expect(summary.gamesWithoutBattingStats, 2);
    });
  });
}
