import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/data/models/content.dart';
import 'package:w_baseball/data/models/provenance.dart';
import 'package:w_baseball/data/models/stats.dart';

/// 규정 타석 is each player's own team's games times 3.1.
///
/// The cut-off used to be computed once, from `raw.first.teamId` — one
/// arbitrary player's team, picked by whatever order the accumulator map
/// happened to iterate in — and then applied to every player in the league.
/// Teams do not play the same number of games. Rain-outs, uneven schedules and
/// the opening weeks all guarantee they do not.
///
/// So a player on a team that had played ten games was judged against a bar
/// set by a team that had played twenty, and dropped off the leaderboard while
/// genuinely qualifying. The reverse happened too: with the sampled team
/// behind, the bar fell for everyone and unqualified players ranked as leaders.
/// Which team set it could change between runs without any data changing.
void main() {
  LeaderboardEntry entry(
    String name, {
    required String teamId,
    required double value,
    required double plateAppearances,
  }) => LeaderboardEntry(
    personId: name,
    playerName: name,
    teamId: teamId,
    value: value,
    qualifies: true,
    qualifierValue: plateAppearances,
  );

  // 20 games → 62 PA. 10 games → 31 PA.
  const rule = QualificationRule(
    key: 'pa',
    labelKo: '규정 타석',
    descriptionKo: '팀 경기 수 × 3.1 이상',
    perTeamGame: 3.1,
  );
  const teamGames = <String, int>{'busy': 20, 'quiet': 10};

  int? thresholdFor(LeaderboardEntry e) => rule.threshold(teamGames[e.teamId]);

  group('팀별 규정 타석', () {
    test('경기를 적게 치른 팀 선수는 자기 팀 기준으로 판정된다', () {
      // 40 plate appearances. Against their own team's ten games the bar is
      // 31, so they qualify. Against the other team's twenty it is 62, and
      // they vanish from the leaderboard for playing on a rained-out schedule.
      final ranked = Leaderboard.rank(
        <LeaderboardEntry>[
          entry('많이뛴팀선수', teamId: 'busy', value: 0.310, plateAppearances: 70),
          entry('적게뛴팀선수', teamId: 'quiet', value: 0.400, plateAppearances: 40),
        ],
        higherIsBetter: true,
        thresholdFor: thresholdFor,
      );

      final quiet = ranked.firstWhere((e) => e.teamId == 'quiet');
      expect(quiet.qualifies, isTrue, reason: '자기 팀 10경기 × 3.1 = 31타석을 넘겼습니다');
      expect(quiet.rank, 1, reason: '자격을 갖췄고 타율이 더 높습니다');
    });

    test('자기 팀 기준에도 미달하면 여전히 아래로 내려간다', () {
      final ranked = Leaderboard.rank(
        <LeaderboardEntry>[
          entry('규정충족', teamId: 'busy', value: 0.280, plateAppearances: 70),
          entry('표본부족', teamId: 'quiet', value: 0.900, plateAppearances: 5),
        ],
        higherIsBetter: true,
        thresholdFor: thresholdFor,
      );

      expect(ranked.first.playerName, '규정충족');
      expect(ranked.last.qualifies, isFalse, reason: '10경기 팀 기준 31타석에도 못 미칩니다');
    });

    test('많이 치른 팀 선수는 낮아진 기준의 덕을 보지 않는다', () {
      // The other direction of the same bug: sampling the quiet team set the
      // bar at 31 for everyone, and a busy-team player with 40 PA — short of
      // their own 62 — ranked as a league leader.
      final ranked = Leaderboard.rank(
        <LeaderboardEntry>[
          entry('기준미달', teamId: 'busy', value: 0.500, plateAppearances: 40),
          entry('기준충족', teamId: 'quiet', value: 0.300, plateAppearances: 40),
        ],
        higherIsBetter: true,
        thresholdFor: thresholdFor,
      );

      expect(ranked.first.playerName, '기준충족');
      expect(
        ranked.firstWhere((e) => e.teamId == 'busy').qualifies,
        isFalse,
        reason: '20경기 팀 소속이면 62타석이 필요합니다',
      );
    });

    test('팀 경기 수를 모르면 잘라내지 않는다', () {
      // Not knowing is not a reason to exclude someone. The board shows
      // everyone and the label says why.
      final ranked = Leaderboard.rank(
        <LeaderboardEntry>[
          entry(
            '소속불명',
            teamId: 'unknown-team',
            value: 0.4,
            plateAppearances: 1,
          ),
        ],
        higherIsBetter: true,
        thresholdFor: thresholdFor,
      );

      expect(ranked.single.qualifies, isTrue);
    });

    test('규칙이 없으면 모두 자격을 갖춘 것으로 본다', () {
      final ranked = Leaderboard.rank(<LeaderboardEntry>[
        entry('아무나', teamId: 'busy', value: 3, plateAppearances: 1),
      ], higherIsBetter: true);
      expect(ranked.single.qualifies, isTrue);
    });
  });

  group('기준 표기', () {
    Leaderboard board({int? threshold, bool varies = false}) => Leaderboard(
      definition: StatDefinition.byKey('avg')!,
      entries: const <LeaderboardEntry>[],
      seasonId: 'season-1',
      coverage: DataCoverage.unknown,
      provenance: Provenance(
        sourceName: 's',
        sourceUrl: 'https://example.org',
        fetchedAt: DateTime.utc(2026),
      ),
      qualificationThreshold: threshold,
      qualificationVariesByTeam: varies,
    );

    test('모르는 것과 팀마다 다른 것을 구분한다', () {
      // Both leave `qualificationThreshold` null, and they call for opposite
      // sentences: one says we cannot compute a cut-off yet, the other says we
      // computed several. Collapsing them would print "팀 경기 수가 확인되면
      // 계산됩니다" above a table where it already was.
      expect(board().qualificationVariesByTeam, isFalse);
      expect(board(varies: true).qualificationVariesByTeam, isTrue);
      expect(board(varies: true).qualificationThreshold, isNull);
    });

    test('모든 팀이 같은 기준이면 숫자 하나로 말한다', () {
      expect(board(threshold: 62).qualificationThreshold, 62);
      expect(board(threshold: 62).qualificationVariesByTeam, isFalse);
    });
  });
}
