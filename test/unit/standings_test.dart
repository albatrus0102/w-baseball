import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/data/models/domain.dart';
import 'package:w_baseball/data/models/stats.dart';

/// Standings used to be whatever a source said, sorted by a `rank` field the
/// app never checked. These fixtures are small enough to work out by hand, so
/// the table can be compared against arithmetic rather than against itself.
void main() {
  Provenance prov() => Provenance(
    sourceName: 'test',
    sourceUrl: 'app://test',
    fetchedAt: DateTime.utc(2026, 8, 30),
  );

  StandingRow row(
    String name, {
    required int wins,
    required int losses,
    int draws = 0,
    int runsScored = 0,
    int runsAllowed = 0,
    int? sourceRank,
    int? played,
  }) {
    return StandingRow(
      team: Team(id: name, name: name, shortName: name, provenance: prov()),
      snapshot: StandingSnapshot(
        id: 'standing-$name',
        seasonId: 'season',
        teamId: name,
        capturedAt: DateTime.utc(2026, 8, 30),
        provenance: prov(),
        rank: sourceRank,
        played: played ?? wins + losses + draws,
        wins: wins,
        losses: losses,
        draws: draws,
        runsScored: runsScored,
        runsAllowed: runsAllowed,
      ),
    );
  }

  List<String> names(List<RankedStanding> r) =>
      r.map((e) => e.row.team.name).toList();

  group('승률 정렬', () {
    test('승률이 높은 팀이 위로 온다', () {
      // A 0.750, B 0.500, C 0.250 — 손으로 계산한 값과 일치해야 합니다.
      final ranked = Standings.rank(<StandingRow>[
        row('B', wins: 2, losses: 2),
        row('C', wins: 1, losses: 3),
        row('A', wins: 3, losses: 1),
      ]);
      expect(names(ranked), <String>['A', 'B', 'C']);
      expect(ranked.map((e) => e.rank), <int>[1, 2, 3]);
    });

    test('무승부는 분모에서 빠진다', () {
      // A: 3승 1패 1무 → 3/4 = 0.750
      // B: 3승 1패      → 3/4 = 0.750  → 동률
      final ranked = Standings.rank(<StandingRow>[
        row('A', wins: 3, losses: 1, draws: 1),
        row('B', wins: 3, losses: 1),
      ]);
      expect(ranked[0].rank, 1);
      expect(ranked[1].rank, 1);
      expect(ranked.every((e) => e.isTied), isTrue);
    });

    test('경기 수가 달라도 승률로 비교한다', () {
      // 2승 0패(1.000)가 8승 2패(0.800)보다 위. 경기 수 불균형에서
      // 승점제와 결과가 갈리는 지점입니다.
      final ranked = Standings.rank(<StandingRow>[
        row('많이', wins: 8, losses: 2),
        row('적게', wins: 2, losses: 0),
      ]);
      expect(names(ranked), <String>['적게', '많이']);
    });
  });

  group('동률 처리', () {
    test('득실차로 가린다', () {
      final ranked = Standings.rank(<StandingRow>[
        row('낮은득실', wins: 2, losses: 2, runsScored: 10, runsAllowed: 12),
        row('높은득실', wins: 2, losses: 2, runsScored: 15, runsAllowed: 5),
      ]);
      expect(names(ranked), <String>['높은득실', '낮은득실']);
      expect(ranked.every((e) => e.isTied), isFalse);
    });

    test('모든 기준이 같으면 순위를 공유하고 다음 순위를 소모한다', () {
      final ranked = Standings.rank(<StandingRow>[
        row('A', wins: 2, losses: 2, runsScored: 10, runsAllowed: 10),
        row('B', wins: 2, losses: 2, runsScored: 10, runsAllowed: 10),
        row('C', wins: 1, losses: 3),
      ]);
      expect(ranked[0].rank, 1);
      expect(ranked[1].rank, 1);
      expect(ranked[2].rank, 3, reason: '공동 1위 둘이 2위를 소모합니다');
    });
  });

  group('승점제', () {
    test('규정을 바꾸면 순서가 바뀐다', () {
      const points = StandingsRule(
        key: 'points',
        labelKo: '승점순',
        basis: StandingsBasis.points,
      );
      // 승률: 적게 1.000 > 많이 0.800
      // 승점: 많이 24 > 적게 6
      final rows = <StandingRow>[
        row('많이', wins: 8, losses: 2),
        row('적게', wins: 2, losses: 0),
      ];
      expect(names(Standings.rank(rows)), <String>['적게', '많이']);
      expect(names(Standings.rank(rows, rule: points)), <String>['많이', '적게']);
    });

    test('규정을 사람이 읽을 수 있게 설명한다', () {
      // The table must be able to say what produced its order.
      expect(StandingsRule.koreanDefault.explanationKo, contains('승률'));
      expect(StandingsRule.koreanDefault.explanationKo, contains('득실차'));
    });
  });

  group('놓칠 수 있는 경우', () {
    test('승패가 하나도 없는 팀은 순위를 만들어내지 않는다', () {
      // 0승 0패에 0.000을 주면 실제로 진 팀보다 아래로 밀립니다.
      final ranked = Standings.rank(<StandingRow>[
        row('무경기', wins: 0, losses: 0),
        row('전패', wins: 0, losses: 4),
      ]);
      expect(ranked.first.row.team.name, '전패');
      expect(ranked.first.rank, 1);
      expect(ranked.last.row.team.name, '무경기');
      expect(ranked.last.rank, isNull, reason: '순위를 매길 근거가 없습니다');
    });

    test('원천 순위와 계산이 다르면 표시한다', () {
      // A mismatch usually means the league applies a rule we do not know.
      final ranked = Standings.rank(<StandingRow>[
        row('A', wins: 3, losses: 1, sourceRank: 2),
        row('B', wins: 1, losses: 3, sourceRank: 1),
      ]);
      expect(ranked.every((e) => e.sourceRankDiffers), isTrue);
    });

    test('원천 순위가 계산과 같으면 표시하지 않는다', () {
      final ranked = Standings.rank(<StandingRow>[
        row('A', wins: 3, losses: 1, sourceRank: 1),
        row('B', wins: 1, losses: 3, sourceRank: 2),
      ]);
      expect(ranked.every((e) => e.sourceRankDiffers), isFalse);
    });

    test('빈 목록에도 견딘다', () {
      expect(Standings.rank(const <StandingRow>[]), isEmpty);
    });
  });
}
