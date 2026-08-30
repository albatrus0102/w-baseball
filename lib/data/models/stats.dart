import 'package:meta/meta.dart';

import 'content.dart' show DataCoverage;
import 'domain.dart';

/// Formats a rate stat the Korean way: `.333`, never `0.333`.
///
/// The leading zero is dropped only when there actually is one. `1.000` — an
/// undefeated team, a 3-for-3 afternoon — has to stay `1.000`; cutting the
/// first character unconditionally turns the best possible number into the
/// worst one, and it does so exactly when someone is proudest of it.
String formatRate(double? value, {int decimalPlaces = 3}) {
  if (value == null) return '-';
  final text = value.toStringAsFixed(decimalPlaces);
  if (decimalPlaces == 3 && text.startsWith('0.')) return text.substring(1);
  return text;
}
/// Which family a statistic belongs to.
enum StatCategory {
  batting,
  pitching,
  baserunning;

  static StatCategory parse(String? raw) => switch (raw) {
    'pitching' => StatCategory.pitching,
    'baserunning' => StatCategory.baserunning,
    _ => StatCategory.batting,
  };

  String get wireValue => name;

  String get labelKo => switch (this) {
    StatCategory.batting => '타격',
    StatCategory.pitching => '투구',
    StatCategory.baserunning => '주루',
  };
}

/// A statistic's definition, formula and sort direction.
///
/// Every leaderboard shows this. Composite "ratings" are deliberately absent:
/// we only publish figures that come from official public records, and we do
/// not invent an overall score or an AI player grade.
@immutable

class StatDefinition {
  const StatDefinition({
    required this.key,
    required this.category,
    required this.shortLabelKo,
    required this.fullLabelKo,
    required this.descriptionKo,
    required this.higherIsBetter,
    this.formulaKo,
    this.decimalPlaces = 0,
    this.qualification,
  });

  /// Stable key, e.g. `avg`, `era`, `hr`.
  final String key;
  final StatCategory category;

  /// Column header form.
  final String shortLabelKo;
  final String fullLabelKo;

  /// Plain-language explanation, shown in the "이 기록은 무엇인가요?" sheet.
  final String descriptionKo;

  final bool higherIsBetter;
  final String? formulaKo;
  final int decimalPlaces;

  /// Minimum plate appearances / innings to appear in the qualified ranking.
  final QualificationRule? qualification;

  String format(double? value) {
    if (value == null) return '-';
    if (decimalPlaces == 0) return value.round().toString();
    return formatRate(value, decimalPlaces: decimalPlaces);
  }

  static const List<StatDefinition> defaults = <StatDefinition>[
    StatDefinition(
      key: 'avg',
      category: StatCategory.batting,
      shortLabelKo: '타율',
      fullLabelKo: '타율 (AVG)',
      descriptionKo: '안타를 타수로 나눈 값입니다. 볼넷과 희생타는 타수에 포함되지 않습니다.',
      formulaKo: '안타 ÷ 타수',
      higherIsBetter: true,
      decimalPlaces: 3,
      qualification: QualificationRule(
        key: 'pa',
        minimum: 0,
        perTeamGame: 3.1,
        labelKo: '규정 타석',
        descriptionKo: '팀 경기 수 × 3.1 이상의 타석에 들어선 선수만 순위에 포함됩니다.',
      ),
    ),
    StatDefinition(
      key: 'hits',
      category: StatCategory.batting,
      shortLabelKo: '안타',
      fullLabelKo: '안타 (H)',
      descriptionKo: '타자가 안타로 출루한 횟수입니다.',
      higherIsBetter: true,
    ),
    StatDefinition(
      key: 'hr',
      category: StatCategory.batting,
      shortLabelKo: '홈런',
      fullLabelKo: '홈런 (HR)',
      descriptionKo: '타자가 한 번의 타격으로 홈까지 들어온 횟수입니다.',
      higherIsBetter: true,
    ),
    StatDefinition(
      key: 'rbi',
      category: StatCategory.batting,
      shortLabelKo: '타점',
      fullLabelKo: '타점 (RBI)',
      descriptionKo: '타자의 타격으로 득점이 만들어진 횟수입니다.',
      higherIsBetter: true,
    ),
    StatDefinition(
      key: 'era',
      category: StatCategory.pitching,
      shortLabelKo: '평균자책',
      fullLabelKo: '평균자책점 (ERA)',
      descriptionKo: '9이닝당 내준 자책점입니다. 낮을수록 좋습니다.',
      formulaKo: '자책점 × 9 ÷ 이닝',
      higherIsBetter: false,
      decimalPlaces: 2,
      qualification: QualificationRule(
        key: 'ip',
        minimum: 0,
        perTeamGame: 1.0,
        labelKo: '규정 이닝',
        descriptionKo: '팀 경기 수 × 1.0 이상을 던진 투수만 순위에 포함됩니다.',
      ),
    ),
    StatDefinition(
      key: 'strikeouts',
      category: StatCategory.pitching,
      shortLabelKo: '탈삼진',
      fullLabelKo: '탈삼진 (K)',
      descriptionKo: '투수가 타자를 삼진으로 처리한 횟수입니다.',
      higherIsBetter: true,
    ),
    StatDefinition(
      key: 'wins',
      category: StatCategory.pitching,
      shortLabelKo: '승',
      fullLabelKo: '승리 (W)',
      descriptionKo: '투수에게 승리가 기록된 경기 수입니다.',
      higherIsBetter: true,
    ),
    StatDefinition(
      key: 'sb',
      category: StatCategory.baserunning,
      shortLabelKo: '도루',
      fullLabelKo: '도루 (SB)',
      descriptionKo: '주자가 투구 중 다음 베이스를 성공적으로 훔친 횟수입니다.',
      higherIsBetter: true,
    ),
  ];

  static StatDefinition? byKey(String key) {
    for (final d in defaults) {
      if (d.key == key) return d;
    }
    return null;
  }

  static List<StatDefinition> byCategory(StatCategory category) =>
      defaults.where((d) => d.category == category).toList(growable: false);
}

/// Minimum-workload rule separating a qualified ranking from a raw one.
@immutable
class QualificationRule {
  const QualificationRule({
    required this.key,
    required this.labelKo,
    required this.descriptionKo,
    this.minimum = 0,
    this.perTeamGame,
  });

  final String key;
  final String labelKo;
  final String descriptionKo;

  /// Absolute floor.
  final int minimum;

  /// Scaled floor, e.g. 3.1 plate appearances per team game.
  final double? perTeamGame;

  /// Null when we do not know how many games the team has played — in which
  /// case the UI shows the full list and says so, rather than guessing.
  int? threshold(int? teamGamesPlayed) {
    final scale = perTeamGame;
    if (scale == null) return minimum;
    if (teamGamesPlayed == null || teamGamesPlayed <= 0) return null;
    final scaled = (teamGamesPlayed * scale).ceil();
    return scaled > minimum ? scaled : minimum;
  }
}

/// One row of a leaderboard.
@immutable
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.personId,
    required this.playerName,
    required this.value,
    required this.qualifies,
    this.teamId,
    this.teamName,
    this.rank,
    this.qualifierValue,
    this.isTied = false,
    this.gamesCounted = 0,
  });

  final String personId;
  final String playerName;
  final String? teamId;
  final String? teamName;

  final double value;

  /// Whether the player met the qualification rule.
  final bool qualifies;

  /// Rank within the displayed list. Tied players share a rank.
  final int? rank;

  /// The workload figure (PA, IP) used for the qualification check.
  final double? qualifierValue;

  final bool isTied;

  /// How many games contributed to this figure.
  final int gamesCounted;
}

/// A ranked list for one stat, one competition/season, with its own coverage.
@immutable
class Leaderboard {
  const Leaderboard({
    required this.definition,
    required this.entries,
    required this.seasonId,
    required this.coverage,
    required this.provenance,
    this.stageId,
    this.teamFilterId,
    this.qualifiedOnly = true,
    this.qualificationThreshold,
    this.computedAt,
  });

  final StatDefinition definition;
  final List<LeaderboardEntry> entries;
  final String seasonId;
  final String? stageId;
  final String? teamFilterId;

  /// How much of the season's data actually fed this ranking.
  final DataCoverage coverage;

  final bool qualifiedOnly;
  final int? qualificationThreshold;
  final DateTime? computedAt;
  final Provenance provenance;

  List<LeaderboardEntry> get qualified =>
      entries.where((e) => e.qualifies).toList(growable: false);

  bool get isEmpty => entries.isEmpty;

  /// Ranks a set of raw values, assigning shared ranks to ties and applying
  /// the qualification rule.
  ///
  /// Values from different competitions are never combined — the caller must
  /// pass a single season/stage, because summing records across competitions
  /// with different rules would be meaningless.
  static List<LeaderboardEntry> rank(
    List<LeaderboardEntry> raw, {
    required bool higherIsBetter,
    int? threshold,
  }) {
    final scored = raw
        .map(
          (e) => LeaderboardEntry(
            personId: e.personId,
            playerName: e.playerName,
            teamId: e.teamId,
            teamName: e.teamName,
            value: e.value,
            qualifies:
                threshold == null || (e.qualifierValue ?? 0) >= threshold,
            qualifierValue: e.qualifierValue,
            gamesCounted: e.gamesCounted,
          ),
        )
        .toList();

    scored.sort((a, b) {
      // Qualified players always rank above unqualified ones.
      if (a.qualifies != b.qualifies) return a.qualifies ? -1 : 1;
      final cmp = higherIsBetter
          ? b.value.compareTo(a.value)
          : a.value.compareTo(b.value);
      if (cmp != 0) return cmp;
      return a.playerName.compareTo(b.playerName);
    });

    final out = <LeaderboardEntry>[];
    var currentRank = 0;
    double? lastValue;
    bool? lastQualifies;

    for (var i = 0; i < scored.length; i++) {
      final e = scored[i];
      final sameAsPrevious =
          lastValue != null &&
          e.value == lastValue &&
          e.qualifies == lastQualifies;
      if (!sameAsPrevious) currentRank = i + 1;

      final tiedWithNeighbour =
          sameAsPrevious ||
          (i + 1 < scored.length &&
              scored[i + 1].value == e.value &&
              scored[i + 1].qualifies == e.qualifies);

      out.add(
        LeaderboardEntry(
          personId: e.personId,
          playerName: e.playerName,
          teamId: e.teamId,
          teamName: e.teamName,
          value: e.value,
          qualifies: e.qualifies,
          rank: currentRank,
          qualifierValue: e.qualifierValue,
          isTied: tiedWithNeighbour,
          gamesCounted: e.gamesCounted,
        ),
      );
      lastValue = e.value;
      lastQualifies = e.qualifies;
    }
    return out;
  }
}

/// Result of one recent game from a team's point of view.
enum FormResult {
  win,
  loss,
  draw,
  noResult;

  String get labelKo => switch (this) {
    FormResult.win => '승',
    FormResult.loss => '패',
    FormResult.draw => '무',
    FormResult.noResult => '−',
  };

  /// Short glyph for the form strip. Paired with a label so colour is never
  /// the only carrier of meaning.
  String get glyph => switch (this) {
    FormResult.win => 'W',
    FormResult.loss => 'L',
    FormResult.draw => 'D',
    FormResult.noResult => '·',
  };
}

/// Recent form plus rank movement for a team.
@immutable
class TeamForm {
  const TeamForm({
    required this.teamId,
    required this.results,
    this.previousRank,
    this.currentRank,
  });

  final String teamId;

  /// Most recent first, capped at five by the caller.
  final List<FormResult> results;

  final int? previousRank;
  final int? currentRank;

  int get wins => results.where((r) => r == FormResult.win).length;
  int get losses => results.where((r) => r == FormResult.loss).length;
  int get draws => results.where((r) => r == FormResult.draw).length;

  /// Positive = moved up the table.
  int? get rankDelta {
    final prev = previousRank;
    final now = currentRank;
    if (prev == null || now == null) return null;
    return prev - now;
  }

  String get summaryKo => '$wins승 $losses패${draws > 0 ? ' $draws무' : ''}';

  static FormResult resultFor(Game game, String teamId) {
    if (!game.status.hasResult || !game.hasScore) return FormResult.noResult;
    if (game.isDraw) return FormResult.draw;
    return game.winnerTeamId == teamId ? FormResult.win : FormResult.loss;
  }
}

/// A team's standings row enriched with movement, form and its nearest rival.
@immutable
class TeamStandingDetail {
  const TeamStandingDetail({
    required this.row,
    required this.totalTeams,
    required this.form,
    required this.coverage,
    this.nextRival,
    this.rulesUrl,
    this.lastUpdatedAt,
  });

  final StandingRow row;
  final int totalTeams;
  final TeamForm form;
  final DataCoverage coverage;

  /// The team immediately adjacent in the table — "who I am chasing".
  final StandingRow? nextRival;

  /// Link to the competition's ranking / tie-break regulations.
  final String? rulesUrl;

  final DateTime? lastUpdatedAt;

  double? get gamesBehindRival {
    final rival = nextRival;
    if (rival == null) return null;
    final a = row.snapshot;
    final b = rival.snapshot;
    return ((b.wins - a.wins) + (a.losses - b.losses)) / 2.0;
  }
}

/// One-screen view of where a competition currently stands.
@immutable
class LeaguePulse {
  const LeaguePulse({
    required this.seasonId,
    required this.competitionName,
    required this.completedGames,
    required this.totalScheduledGames,
    required this.coverage,
    this.currentStageName,
    this.recentDecisiveResults = const <GameCard>[],
    this.thisWeekGames = const <GameCard>[],
    this.postponedCount = 0,
    this.cancelledCount = 0,
    this.undecidedCount = 0,
    this.lastUpdatedAt,
  });

  final String seasonId;
  final String competitionName;
  final int completedGames;
  final int totalScheduledGames;

  /// e.g. `조별리그`, `본선 토너먼트`.
  final String? currentStageName;

  final List<GameCard> recentDecisiveResults;
  final List<GameCard> thisWeekGames;

  final int postponedCount;
  final int cancelledCount;

  /// Games with no confirmed date yet.
  final int undecidedCount;

  final DataCoverage coverage;
  final DateTime? lastUpdatedAt;

  double? get progress {
    if (totalScheduledGames <= 0) return null;
    return (completedGames / totalScheduledGames).clamp(0.0, 1.0);
  }

  String get progressLabelKo => totalScheduledGames <= 0
      ? '전체 일정 확인 중'
      : '$totalScheduledGames경기 중 $completedGames경기 종료';

  bool get hasDisruptions =>
      postponedCount > 0 || cancelledCount > 0 || undecidedCount > 0;

  /// A factual one-line summary generated from counts only.
  ///
  /// It never claims qualification or elimination, because that requires the
  /// competition's tie-break regulations, which we do not model.
  String get headlineKo {
    final parts = <String>[];
    if (currentStageName != null) parts.add(currentStageName!);
    parts.add(progressLabelKo);
    if (postponedCount > 0) parts.add('연기 $postponedCount경기');
    if (cancelledCount > 0) parts.add('취소 $cancelledCount경기');
    return parts.join(' · ');
  }
}

/// How a competition decides the order of its table.
///
/// Kept as data rather than hard-coded because amateur leagues differ: some
/// rank on 승률, some on points, and the tie-breaker order is a league rule
/// rather than a property of baseball. A wrong assumption here is invisible —
/// the table still looks authoritative — so the rule is stated explicitly and
/// shown to the reader.
@immutable
class StandingsRule {
  const StandingsRule({
    required this.key,
    required this.labelKo,
    this.basis = StandingsBasis.winPct,
    this.pointsForWin = 3,
    this.pointsForDraw = 1,
    this.pointsForLoss = 0,
    this.tieBreakers = const <StandingsTieBreaker>[
      StandingsTieBreaker.runDifferential,
      StandingsTieBreaker.runsScored,
      StandingsTieBreaker.fewerLosses,
    ],
  });

  /// KBO-style default: 승률 = 승 / (승 + 패), draws excluded from the
  /// denominator rather than counted as half a win.
  static const koreanDefault = StandingsRule(
    key: 'winPct',
    labelKo: '승률순 (무승부 제외)',
  );

  final String key;
  final String labelKo;
  final StandingsBasis basis;
  final int pointsForWin;
  final int pointsForDraw;
  final int pointsForLoss;
  final List<StandingsTieBreaker> tieBreakers;

  int pointsOf(StandingSnapshot s) =>
      s.wins * pointsForWin +
      s.draws * pointsForDraw +
      s.losses * pointsForLoss;

  /// The primary sort value. Null when it cannot be computed — a team with no
  /// decided games has no win rate, and inventing 0.000 would rank them below
  /// teams that actually lost.
  double? primaryValue(StandingSnapshot s) => switch (basis) {
    StandingsBasis.winPct => s.winRate,
    StandingsBasis.points => s.played == 0 ? null : pointsOf(s).toDouble(),
  };

  /// One line the UI can show so the reader knows what produced the order.
  String get explanationKo => switch (basis) {
    StandingsBasis.winPct =>
      '승률(승 ÷ (승+패)) 순으로 정렬하고, 같으면 '
          '${tieBreakers.map((t) => t.labelKo).join(' → ')} 순으로 가립니다.',
    StandingsBasis.points =>
      '승점(승 $pointsForWin · 무 $pointsForDraw · 패 $pointsForLoss) '
          '순으로 정렬하고, 같으면 '
          '${tieBreakers.map((t) => t.labelKo).join(' → ')} 순으로 가립니다.',
  };
}

enum StandingsBasis { winPct, points }

enum StandingsTieBreaker {
  runDifferential,
  runsScored,
  fewerLosses,
  morePlayed;

  String get labelKo => switch (this) {
    StandingsTieBreaker.runDifferential => '득실차',
    StandingsTieBreaker.runsScored => '다득점',
    StandingsTieBreaker.fewerLosses => '적은 패',
    StandingsTieBreaker.morePlayed => '많은 경기 수',
  };

  int compare(StandingSnapshot a, StandingSnapshot b) => switch (this) {
    StandingsTieBreaker.runDifferential => b.runDifferential.compareTo(
      a.runDifferential,
    ),
    StandingsTieBreaker.runsScored => b.runsScored.compareTo(a.runsScored),
    StandingsTieBreaker.fewerLosses => a.losses.compareTo(b.losses),
    StandingsTieBreaker.morePlayed => b.played.compareTo(a.played),
  };
}

/// One team's place in the table, after the rule has been applied.
@immutable
class RankedStanding {
  const RankedStanding({
    required this.row,
    required this.rank,
    required this.isTied,
    required this.sourceRankDiffers,
  });

  final StandingRow row;

  /// Null when the rule cannot place this team — no decided games yet.
  final int? rank;

  /// Shares its rank with at least one other team.
  final bool isTied;

  /// The source published a rank and it disagrees with the computed one.
  /// Surfaced rather than silently preferred either way: a mismatch usually
  /// means the league applies a rule we do not know about, and the reader
  /// deserves to know the two disagree.
  final bool sourceRankDiffers;
}

/// Computes a table from the recorded results.
///
/// Nothing is invented: wins, losses, draws and runs all come from the source
/// snapshots. What this adds is a *stated*, testable ordering — previously the
/// app trusted whatever `rank` a source happened to send and, when none was
/// sent, listed teams in database order under a `-`.
@immutable
class Standings {
  const Standings._();

  static List<RankedStanding> rank(
    List<StandingRow> rows, {
    StandingsRule rule = StandingsRule.koreanDefault,
  }) {
    final placeable = <StandingRow>[];
    final unplaceable = <StandingRow>[];
    for (final row in rows) {
      (rule.primaryValue(row.snapshot) == null ? unplaceable : placeable).add(
        row,
      );
    }

    placeable.sort((a, b) {
      final primary = rule
          .primaryValue(b.snapshot)!
          .compareTo(rule.primaryValue(a.snapshot)!);
      if (primary != 0) return primary;
      for (final breaker in rule.tieBreakers) {
        final result = breaker.compare(a.snapshot, b.snapshot);
        if (result != 0) return result;
      }
      // Still level after every stated rule: order by name so the table is at
      // least stable between runs, and report the tie.
      return a.team.displayName.compareTo(b.team.displayName);
    });

    /// Two teams share a rank only when every stated criterion is equal.
    bool level(StandingRow a, StandingRow b) {
      if (rule.primaryValue(a.snapshot) != rule.primaryValue(b.snapshot)) {
        return false;
      }
      return rule.tieBreakers.every(
        (t) => t.compare(a.snapshot, b.snapshot) == 0,
      );
    }

    final out = <RankedStanding>[];
    var rank = 0;
    for (var i = 0; i < placeable.length; i++) {
      final row = placeable[i];
      final tiedWithPrevious = i > 0 && level(placeable[i - 1], row);
      if (!tiedWithPrevious) rank = i + 1;
      final tiedWithNext =
          i + 1 < placeable.length && level(row, placeable[i + 1]);
      out.add(
        RankedStanding(
          row: row,
          rank: rank,
          isTied: tiedWithPrevious || tiedWithNext,
          sourceRankDiffers:
              row.snapshot.rank != null && row.snapshot.rank != rank,
        ),
      );
    }

    for (final row in unplaceable) {
      out.add(
        RankedStanding(
          row: row,
          rank: null,
          isTied: false,
          sourceRankDiffers: false,
        ),
      );
    }
    return out;
  }
}
