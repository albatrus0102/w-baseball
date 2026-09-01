import 'package:meta/meta.dart';

/// 출전 일지 — a player's own record of the games she played.
///
/// Everything in this file is Stage 1 of the feature: a log entry, not a
/// stat line. There is deliberately no batting average or pitch count here
/// (Stage 2), no comparison against anyone else, and nothing the app itself
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
