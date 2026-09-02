import 'package:meta/meta.dart';

/// 출전 일지 — a player's own record of the games she played.
///
/// Stage 1 of the feature is the log entry itself. Stage 2 (below) adds an
/// optional stat line per entry and the aggregation built from it
/// ([GameLogStatSummary]). Still deliberately narrow: no 타율, no earned-run
/// average, no comparison against anyone else, and nothing the app itself
/// authors as advice — see the feature brief for why each of those is a hard
/// line, not an oversight.

/// A position played during a logged game.
///
/// Multiple positions can be selected on one entry: moving positions
/// mid-game happens, and recording that is the point of
/// [derivePositionTimeline] below — "외야에서 포수로 전향" is an identity
/// event the app surfaces, not a statistic it computes.
enum GameLogPosition {
  pitcher,
  catcher,
  firstBase,
  secondBase,
  thirdBase,
  shortstop,
  leftField,
  centerField,
  rightField,
  designatedHitter,
  other;

  static GameLogPosition? parse(String? raw) {
    for (final p in GameLogPosition.values) {
      if (p.name == raw) return p;
    }
    return null;
  }

  String get wireValue => name;

  String get labelKo => switch (this) {
    GameLogPosition.pitcher => '투수',
    GameLogPosition.catcher => '포수',
    GameLogPosition.firstBase => '1루수',
    GameLogPosition.secondBase => '2루수',
    GameLogPosition.thirdBase => '3루수',
    GameLogPosition.shortstop => '유격수',
    GameLogPosition.leftField => '좌익수',
    GameLogPosition.centerField => '중견수',
    GameLogPosition.rightField => '우익수',
    GameLogPosition.designatedHitter => '지명타자',
    GameLogPosition.other => '기타',
  };

  /// Serialises a chip selection as `positions` storage: a comma-joined list
  /// of [wireValue]s. Order is preserved — the first tap is treated as the
  /// primary position for [derivePositionTimeline].
  static String encodeList(List<GameLogPosition> positions) =>
      positions.map((p) => p.wireValue).join(',');

  static List<GameLogPosition> decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <GameLogPosition>[];
    return raw
        .split(',')
        .map((token) => GameLogPosition.parse(token.trim()))
        .whereType<GameLogPosition>()
        .toList(growable: false);
  }
}

/// The result the player recorded for the game, in her own words.
///
/// A fixed short list — chips, not a text field — and never computed from
/// anything else. Nothing here is ever compared against another player's
/// entries; see the feature brief's leaderboard prohibition.
enum GameLogResult {
  win,
  loss,
  draw,
  unspecified;

  static GameLogResult parse(String? raw) => switch (raw) {
    'win' => GameLogResult.win,
    'loss' => GameLogResult.loss,
    'draw' => GameLogResult.draw,
    _ => GameLogResult.unspecified,
  };

  String get wireValue => name;

  String get labelKo => switch (this) {
    GameLogResult.win => '승',
    GameLogResult.loss => '패',
    GameLogResult.draw => '무',
    GameLogResult.unspecified => '기록 안 함',
  };
}

/// One 출전 일지 entry.
@immutable
class GameLogEntry {
  const GameLogEntry({
    required this.id,
    required this.playedAt,
    required this.dayKey,
    required this.createdAt,
    this.gameId,
    this.competitionLabel,
    this.opponentLabel,
    this.venueLabel,
    this.positions = const <GameLogPosition>[],
    this.result = GameLogResult.unspecified,
    this.note,
    this.updatedAt,
    this.plateAppearances,
    this.hits,
    this.walks,
    this.sacrificeBunts,
    this.strikeouts,
    this.runsBattedIn,
    this.runsScored,
    this.stolenBases,
    this.outsPitched,
    this.pitchingStrikeouts,
    this.pitchingWalks,
    this.runsAllowed,
  });

  /// Local autoincrement id. Never shown to the user, never leaves the
  /// device except inside the export file, where it exists purely so a
  /// future import can de-duplicate re-imports of the same export.
  final int id;

  final DateTime playedAt;
  final String dayKey;

  /// Null until a real fixture exists to bind to — see the table doc.
  final String? gameId;

  final String? competitionLabel;
  final String? opponentLabel;
  final String? venueLabel;
  final List<GameLogPosition> positions;
  final GameLogResult result;
  final String? note;

  final DateTime createdAt;
  final DateTime? updatedAt;

  // --- stat line (Stage 2) --------------------------------------------
  //
  // All nullable, and null ≠ 0 — see `GameLogEntries` in `tables.dart`.
  // `plateAppearances` null means "no stat line for this game"; every other
  // field here is only meaningful when it is not.
  final int? plateAppearances; // 타석
  final int? hits; // 안타
  final int? walks; // 볼넷 + 몸에 맞는 공
  final int? sacrificeBunts; // 희생번트
  final int? strikeouts; // 삼진 (타자)
  final int? runsBattedIn; // 타점
  final int? runsScored; // 득점
  final int? stolenBases; // 도루
  final int? outsPitched; // 이닝 × 3
  final int? pitchingStrikeouts; // 탈삼진
  final int? pitchingWalks; // 볼넷 + 몸에 맞힘 (투구)
  final int? runsAllowed; // 실점

  /// Whether this game has a batting stat line at all. See
  /// `BattingStatSummary.from` — this is the same gate the aggregate uses.
  bool get hasBattingStats => plateAppearances != null;

  /// Whether this game has a pitching stat line at all.
  bool get hasPitchingStats => outsPitched != null;

  String get positionsLabelKo =>
      positions.isEmpty ? '포지션 없음' : positions.map((p) => p.labelKo).join('·');

  GameLogEntry copyWith({
    DateTime? playedAt,
    String? dayKey,
    String? gameId,
    String? competitionLabel,
    String? opponentLabel,
    String? venueLabel,
    List<GameLogPosition>? positions,
    GameLogResult? result,
    String? note,
    DateTime? updatedAt,
    bool clearGameId = false,
    bool clearNote = false,
    int? plateAppearances,
    int? hits,
    int? walks,
    int? sacrificeBunts,
    int? strikeouts,
    int? runsBattedIn,
    int? runsScored,
    int? stolenBases,
    int? outsPitched,
    int? pitchingStrikeouts,
    int? pitchingWalks,
    int? runsAllowed,
  }) {
    return GameLogEntry(
      id: id,
      playedAt: playedAt ?? this.playedAt,
      dayKey: dayKey ?? this.dayKey,
      gameId: clearGameId ? null : (gameId ?? this.gameId),
      competitionLabel: competitionLabel ?? this.competitionLabel,
      opponentLabel: opponentLabel ?? this.opponentLabel,
      venueLabel: venueLabel ?? this.venueLabel,
      positions: positions ?? this.positions,
      result: result ?? this.result,
      note: clearNote ? null : (note ?? this.note),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      plateAppearances: plateAppearances ?? this.plateAppearances,
      hits: hits ?? this.hits,
      walks: walks ?? this.walks,
      sacrificeBunts: sacrificeBunts ?? this.sacrificeBunts,
      strikeouts: strikeouts ?? this.strikeouts,
      runsBattedIn: runsBattedIn ?? this.runsBattedIn,
      runsScored: runsScored ?? this.runsScored,
      stolenBases: stolenBases ?? this.stolenBases,
      outsPitched: outsPitched ?? this.outsPitched,
      pitchingStrikeouts: pitchingStrikeouts ?? this.pitchingStrikeouts,
      pitchingWalks: pitchingWalks ?? this.pitchingWalks,
      runsAllowed: runsAllowed ?? this.runsAllowed,
    );
  }
}

/// One point where the recorded position(s) changed from the entry before —
/// "외야에서 포수로 전향" made visible.
///
/// Derived, never stored: recomputing from the entries themselves means a
/// deleted or edited entry can never leave a stale transition behind.
@immutable
class PositionTimelineEvent {
  const PositionTimelineEvent({
    required this.date,
    required this.positions,
    required this.previousPositions,
  });

  final DateTime date;
  final List<GameLogPosition> positions;

  /// Null for the very first recorded position(s) — there is nothing to have
  /// "changed" from yet.
  final List<GameLogPosition>? previousPositions;

  bool get isFirst => previousPositions == null;

  String get positionsLabelKo => positions.map((p) => p.labelKo).join('·');

  String get previousLabelKo =>
      previousPositions?.map((p) => p.labelKo).join('·') ?? '';
}

/// Builds the position history from a set of entries, in date order.
///
/// Entries with no position recorded are skipped — they say nothing about
/// where she played. Consecutive entries with the *same* position set never
/// produce a second event: only an actual change is a transition worth
/// naming, which is what keeps "3연속 포수 출전" from reading as three
/// separate "전향" events.
List<PositionTimelineEvent> derivePositionTimeline(
  Iterable<GameLogEntry> entries,
) {
  final sorted = entries.where((e) => e.positions.isNotEmpty).toList()
    ..sort((a, b) => a.playedAt.compareTo(b.playedAt));

  final events = <PositionTimelineEvent>[];
  List<GameLogPosition>? previous;
  for (final entry in sorted) {
    if (previous != null && _samePositionSet(previous, entry.positions)) {
      continue;
    }
    events.add(
      PositionTimelineEvent(
        date: entry.playedAt,
        positions: entry.positions,
        previousPositions: previous,
      ),
    );
    previous = entry.positions;
  }
  return events;
}

bool _samePositionSet(List<GameLogPosition> a, List<GameLogPosition> b) {
  if (a.length != b.length) return false;
  final setA = a.map((p) => p.wireValue).toSet();
  final setB = b.map((p) => p.wireValue).toSet();
  return setA.length == setB.length && setA.containsAll(setB);
}

// ---------------------------------------------------------------------------
// Stat aggregation (Stage 2)
// ---------------------------------------------------------------------------

/// `N⅔이닝` — innings pitched, built from an outs count (innings × 3). See
/// `GameLogEntry.outsPitched`'s doc for why outs are stored instead of a
/// fractional innings number.
String formatInningsPitched(int outs) {
  final whole = outs ~/ 3;
  final remainder = outs % 3;
  final frac = switch (remainder) {
    1 => '⅓',
    2 => '⅔',
    _ => '',
  };
  if (whole == 0 && frac.isNotEmpty) return '$frac이닝';
  return '$whole$frac이닝';
}

/// The player's own aggregated batting line, built only from games that
/// actually have one. See [from] for the exclusion rule.
@immutable
class BattingStatSummary {
  const BattingStatSummary({
    required this.gamesWithStats,
    required this.plateAppearances,
    required this.hits,
    required this.walks,
    required this.strikeouts,
    required this.runsBattedIn,
    required this.runsScored,
    required this.stolenBases,
    required this.sacrificeBunts,
    required this.gamesMissingSacrificeBunts,
  });

  /// How many logged games actually carry a batting stat line — see [from].
  final int gamesWithStats;

  final int plateAppearances;
  final int hits;
  final int walks;
  final int strikeouts;
  final int runsBattedIn;
  final int runsScored;
  final int stolenBases;

  /// Sum of 희생번트 across [gamesWithStats], treating a game whose
  /// 희생번트 was left null as 0 — see [gamesMissingSacrificeBunts] for why
  /// that direction is safe and [obpDenominator] for where it matters.
  final int sacrificeBunts;

  /// How many of [gamesWithStats] have a batting line but no 희생번트 value
  /// (null, not 0). Treating those as 0 in [sacrificeBunts] can only make
  /// [obpDenominator] larger than the true value, which can only push
  /// [onBasePercentage] *down*, never up — an unrecorded 희생번트 can never
  /// make the shown rate look better than it really is. This is the number
  /// behind the "희생번트를 적지 않은 경기 N경기는 0으로 계산했어요" note.
  final int gamesMissingSacrificeBunts;

  /// Only games with a stat line at all count here — a game logged with the
  /// 성적 section left collapsed (`plateAppearances == null`) says nothing
  /// about her at-bats and must not be silently read as a 0-for-0. This is
  /// the exclusion the "null 성적 경기를 집계에 넣기" mutation test targets.
  static BattingStatSummary? from(Iterable<GameLogEntry> entries) {
    var games = 0;
    var pa = 0;
    var hits = 0;
    var walks = 0;
    var strikeouts = 0;
    var rbi = 0;
    var runs = 0;
    var stolenBases = 0;
    var sacBunts = 0;
    var missingSacBunts = 0;

    for (final e in entries) {
      final entryPa = e.plateAppearances;
      if (entryPa == null) continue; // no stat line for this game at all.
      games++;
      pa += entryPa;
      hits += e.hits ?? 0;
      walks += e.walks ?? 0;
      strikeouts += e.strikeouts ?? 0;
      rbi += e.runsBattedIn ?? 0;
      runs += e.runsScored ?? 0;
      stolenBases += e.stolenBases ?? 0;
      final sac = e.sacrificeBunts;
      if (sac == null) {
        missingSacBunts++;
      } else {
        sacBunts += sac;
      }
    }

    if (games == 0) return null;
    return BattingStatSummary(
      gamesWithStats: games,
      plateAppearances: pa,
      hits: hits,
      walks: walks,
      strikeouts: strikeouts,
      runsBattedIn: rbi,
      runsScored: runs,
      stolenBases: stolenBases,
      sacrificeBunts: sacBunts,
      gamesMissingSacrificeBunts: missingSacBunts,
    );
  }

  /// 타석 − 희생번트 — the OBP denominator the app's own guide
  /// (`guide-stat-obp` in `assets/seed/content/discover.json`) teaches, once
  /// its 타수+볼넷+사구+희생플라이 form is rewritten in terms of 타석 (see the
  /// feature brief). **Not** raw [plateAppearances] — see [meetsThreshold].
  int get obpDenominator => plateAppearances - sacrificeBunts;

  /// The minimum [obpDenominator] before [onBasePercentage] is shown at all.
  ///
  /// This counts the *denominator*, not raw 타석: at 20 타석 with 2 희생번트
  /// the real denominator is 18, and one more game's single event there
  /// would move the rate by 1/19 ≈ .053 — already past the .05 "one event
  /// shouldn't swing it" line this threshold exists to hold. 20 is the
  /// smallest denominator where that no longer happens: from a shown rate of
  /// .000 (0 for the denominator), the next single-PA game going 1-for-1
  /// moves it to 1/(denominator+1) — 1/21 ≈ .048 at 20 (under .05, so 20
  /// qualifies), but 1/20 = .050 at 19 (not under .05, so 19 does not).
  static const int threshold = 20;

  bool get meetsThreshold => obpDenominator >= threshold;

  /// Null below [threshold] — see [meetsThreshold]. (안타 + 볼넷) ÷
  /// [obpDenominator], matching the app's own OBP guide once 몸에 맞는 공 is
  /// folded into [walks] — see `GameLogEntry.walks`'s doc.
  double? get onBasePercentage =>
      meetsThreshold ? (hits + walks) / obpDenominator : null;

  /// 안타 + 볼넷 — the OBP numerator, and also the plain-language "나갔어요"
  /// count shown before the threshold is met.
  int get reachedBaseCount => hits + walks;
}

/// The player's own aggregated pitching line, built only from games that
/// actually have one (`outsPitched != null`) — the pitching mirror of
/// [BattingStatSummary.from]'s exclusion rule.
@immutable
class PitchingStatSummary {
  const PitchingStatSummary({
    required this.gamesWithStats,
    required this.outsPitched,
    required this.strikeouts,
    required this.walks,
    required this.runsAllowed,
  });

  final int gamesWithStats;

  /// Total outs recorded (innings × 3) — see `formatInningsPitched`.
  final int outsPitched;
  final int strikeouts;
  final int walks;
  final int runsAllowed;

  static PitchingStatSummary? from(Iterable<GameLogEntry> entries) {
    var games = 0;
    var outs = 0;
    var strikeouts = 0;
    var walks = 0;
    var runsAllowed = 0;
    for (final e in entries) {
      final entryOuts = e.outsPitched;
      if (entryOuts == null) continue;
      games++;
      outs += entryOuts;
      strikeouts += e.pitchingStrikeouts ?? 0;
      walks += e.pitchingWalks ?? 0;
      runsAllowed += e.runsAllowed ?? 0;
    }
    if (games == 0) return null;
    return PitchingStatSummary(
      gamesWithStats: games,
      outsPitched: outs,
      strikeouts: strikeouts,
      walks: walks,
      runsAllowed: runsAllowed,
    );
  }

  String get inningsLabelKo => formatInningsPitched(outsPitched);
}

/// The whole "내 기록" aggregate card in one object: how many games, her
/// W-L-D record, and the batting/pitching lines built from whichever of them
/// actually carry a stat line. See [BattingStatSummary.from] and
/// [PitchingStatSummary.from] for the per-game inclusion rule.
@immutable
class GameLogStatSummary {
  const GameLogStatSummary({
    required this.totalGames,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.batting,
    required this.pitching,
  });

  final int totalGames;
  final int wins;
  final int losses;
  final int draws;

  /// Null only when not one logged game has a batting stat line — the
  /// original Stage 1 case, where nothing here should render at all.
  final BattingStatSummary? batting;

  /// Null when no logged game has a pitching stat line, including for a
  /// player who has never selected 투수 — see the entry sheet, which never
  /// shows the pitching section (and so never writes `outsPitched`) unless
  /// 투수 is among the game's recorded positions.
  final PitchingStatSummary? pitching;

  /// Games logged with no batting stat line at all — "타격 기록이 없는 경기
  /// 가 N경기 있어요".
  int get gamesWithoutBattingStats =>
      totalGames - (batting?.gamesWithStats ?? 0);

  bool get hasAnyResult => wins > 0 || losses > 0 || draws > 0;

  factory GameLogStatSummary.from(List<GameLogEntry> entries) {
    var wins = 0;
    var losses = 0;
    var draws = 0;
    for (final e in entries) {
      switch (e.result) {
        case GameLogResult.win:
          wins++;
        case GameLogResult.loss:
          losses++;
        case GameLogResult.draw:
          draws++;
        case GameLogResult.unspecified:
          break;
      }
    }
    return GameLogStatSummary(
      totalGames: entries.length,
      wins: wins,
      losses: losses,
      draws: draws,
      batting: BattingStatSummary.from(entries),
      pitching: PitchingStatSummary.from(entries),
    );
  }
}
