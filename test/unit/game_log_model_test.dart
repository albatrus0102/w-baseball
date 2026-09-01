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
}
