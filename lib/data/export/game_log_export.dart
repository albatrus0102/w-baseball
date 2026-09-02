import 'dart:convert';

import '../models/game_log.dart';

/// Export/import format for 출전 일지.
///
/// This is the layer that protects a season of someone's own work: there is
/// no server and no account (see the feature brief's "phone-change
/// problem"), so a versioned, round-trippable file is the only thing standing
/// between a reinstall and losing every entry. [GameLogJsonCodec] is
/// therefore built and tested as an encode/decode pair *now*, in Stage 1,
/// even though the app does not yet offer an import screen — Stage 2's
/// import path, and the "총무의 엑셀" bulk path, both read this same shape.
///
/// [GameLogCsvCodec] is encode-only for Stage 1: it exists so the export is
/// something a person can actually open and read (or hand to someone doing
/// bulk entry in a spreadsheet), not so this build can parse it back in.
class GameLogJsonCodec {
  const GameLogJsonCodec._();

  /// The format tag written into every export and checked on import. Bumping
  /// this is a breaking change to the file shape; a new field on an existing
  /// entry is not (see [decode]'s handling of unknown/missing keys).
  static const String formatTag = 'wb-myrecords-v1';

  static String encode(
    List<GameLogEntry> entries, {
    required DateTime exportedAt,
    // 다음 경기에서 해볼 것 (Stage 3). A new top-level key on an
    // already-shipped envelope — `formatTag` stays `wb-myrecords-v1`, same
    // as the stat-line fields added above; see this class's doc comment.
    // Not in [GameLogCsvCodec] — see that class's doc for why.
    List<GameLogGoal> goals = const <GameLogGoal>[],
  }) {
    final json = <String, Object?>{
      'format': formatTag,
      'exportedAt': exportedAt.toUtc().toIso8601String(),
      'entries': entries.map(_encodeEntry).toList(growable: false),
      'goals': goals.map(_encodeGoal).toList(growable: false),
    };
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  static Map<String, Object?> _encodeEntry(GameLogEntry e) => <String, Object?>{
    'id': e.id,
    'playedAt': e.playedAt.toUtc().toIso8601String(),
    'dayKey': e.dayKey,
    'gameId': e.gameId,
    'competitionLabel': e.competitionLabel,
    'opponentLabel': e.opponentLabel,
    'venueLabel': e.venueLabel,
    'positions': e.positions.map((p) => p.wireValue).toList(growable: false),
    'result': e.result.wireValue,
    'note': e.note,
    'createdAt': e.createdAt.toUtc().toIso8601String(),
    'updatedAt': e.updatedAt?.toUtc().toIso8601String(),
    // Stat line (Stage 2). Optional keys on an already-shipped envelope —
    // `formatTag` stays `wb-myrecords-v1`; see this class's doc comment for
    // why a new field is additive, not a breaking change.
    'plateAppearances': e.plateAppearances,
    'hits': e.hits,
    'walks': e.walks,
    'sacrificeBunts': e.sacrificeBunts,
    'strikeouts': e.strikeouts,
    'runsBattedIn': e.runsBattedIn,
    'runsScored': e.runsScored,
    'stolenBases': e.stolenBases,
    'outsPitched': e.outsPitched,
    'pitchingStrikeouts': e.pitchingStrikeouts,
    'pitchingWalks': e.pitchingWalks,
    'runsAllowed': e.runsAllowed,
  };

  static Map<String, Object?> _encodeGoal(GameLogGoal g) => <String, Object?>{
    'id': g.id,
    'body': g.body,
    'entryId': g.entryId,
    'createdAt': g.createdAt.toUtc().toIso8601String(),
    'closedAt': g.closedAt?.toUtc().toIso8601String(),
    'outcome': g.outcome?.wireValue,
  };

  /// Parses an export file back into entries.
  ///
  /// Never throws on a malformed *entry* — one bad row must not sink an
  /// otherwise-good file, which is exactly the situation a hand-edited or
  /// partially-corrupted backup produces. A malformed *envelope* (not valid
  /// JSON, no `entries` array, or an unrecognised `format`) is reported as
  /// [GameLogImportResult.formatError] instead, since there is nothing safe
  /// to salvage from that.
  static GameLogImportResult decode(String raw) {
    final Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } on FormatException {
      return const GameLogImportResult(
        entries: <GameLogEntry>[],
        skippedCount: 0,
        formatError: '파일을 읽을 수 없습니다.',
      );
    }
    if (parsed is! Map<String, Object?>) {
      return const GameLogImportResult(
        entries: <GameLogEntry>[],
        skippedCount: 0,
        formatError: '알 수 없는 파일 형식입니다.',
      );
    }
    final format = parsed['format'];
    if (format != formatTag) {
      return GameLogImportResult(
        entries: const <GameLogEntry>[],
        skippedCount: 0,
        formatError: '지원하지 않는 형식입니다 ($format).',
      );
    }
    final rawEntries = parsed['entries'];
    if (rawEntries is! List) {
      return const GameLogImportResult(
        entries: <GameLogEntry>[],
        skippedCount: 0,
        formatError: '기록 목록을 찾을 수 없습니다.',
      );
    }

    final entries = <GameLogEntry>[];
    var skipped = 0;
    for (final item in rawEntries) {
      final entry = _decodeEntry(item);
      if (entry == null) {
        skipped++;
      } else {
        entries.add(entry);
      }
    }

    // 다음 경기에서 해볼 것 (Stage 3). Missing entirely on a file exported
    // before this key existed — reads as "no goals in this file", the same
    // additive-field handling every stat-line key above already gets, not a
    // format error.
    final rawGoals = parsed['goals'];
    final goals = <GameLogGoal>[];
    if (rawGoals is List) {
      for (final item in rawGoals) {
        final goal = _decodeGoal(item);
        if (goal != null) goals.add(goal);
      }
    }

    return GameLogImportResult(
      entries: entries,
      goals: goals,
      skippedCount: skipped,
    );
  }

  static GameLogEntry? _decodeEntry(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final playedAtRaw = raw['playedAt'];
    final createdAtRaw = raw['createdAt'];
    if (id is! int || playedAtRaw is! String || createdAtRaw is! String) {
      return null;
    }
    final playedAt = DateTime.tryParse(playedAtRaw)?.toUtc();
    final createdAt = DateTime.tryParse(createdAtRaw)?.toUtc();
    if (playedAt == null || createdAt == null) return null;

    final dayKey = raw['dayKey'];
    final updatedAtRaw = raw['updatedAt'];
    final positionsRaw = raw['positions'];

    return GameLogEntry(
      id: id,
      playedAt: playedAt,
      dayKey: dayKey is String && dayKey.isNotEmpty
          ? dayKey
          : _fallbackDayKey(playedAt),
      gameId: raw['gameId'] as String?,
      competitionLabel: raw['competitionLabel'] as String?,
      opponentLabel: raw['opponentLabel'] as String?,
      venueLabel: raw['venueLabel'] as String?,
      positions: positionsRaw is List
          ? positionsRaw
                .whereType<String>()
                .map(GameLogPosition.parse)
                .whereType<GameLogPosition>()
                .toList(growable: false)
          : const <GameLogPosition>[],
      result: GameLogResult.parse(raw['result'] as String?),
      note: raw['note'] as String?,
      createdAt: createdAt,
      updatedAt: updatedAtRaw is String
          ? DateTime.tryParse(updatedAtRaw)?.toUtc()
          : null,
      // Stat line (Stage 2). A missing key (an export from before this
      // field existed) reads as null the same way a wrong-typed value
      // does — both mean "no stat line", never a silently-wrong 0.
      plateAppearances: _intOrNull(raw['plateAppearances']),
      hits: _intOrNull(raw['hits']),
      walks: _intOrNull(raw['walks']),
      sacrificeBunts: _intOrNull(raw['sacrificeBunts']),
      strikeouts: _intOrNull(raw['strikeouts']),
      runsBattedIn: _intOrNull(raw['runsBattedIn']),
      runsScored: _intOrNull(raw['runsScored']),
      stolenBases: _intOrNull(raw['stolenBases']),
      outsPitched: _intOrNull(raw['outsPitched']),
      pitchingStrikeouts: _intOrNull(raw['pitchingStrikeouts']),
      pitchingWalks: _intOrNull(raw['pitchingWalks']),
      runsAllowed: _intOrNull(raw['runsAllowed']),
    );
  }

  static GameLogGoal? _decodeGoal(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final body = raw['body'];
    final createdAtRaw = raw['createdAt'];
    if (id is! int || body is! String || createdAtRaw is! String) {
      return null;
    }
    final createdAt = DateTime.tryParse(createdAtRaw)?.toUtc();
    if (createdAt == null) return null;

    final closedAtRaw = raw['closedAt'];
    return GameLogGoal(
      id: id,
      body: body,
      entryId: _intOrNull(raw['entryId']),
      createdAt: createdAt,
      closedAt: closedAtRaw is String
          ? DateTime.tryParse(closedAtRaw)?.toUtc()
          : null,
      outcome: GameLogGoalOutcome.parse(raw['outcome'] as String?),
    );
  }

  static int? _intOrNull(Object? raw) => raw is int ? raw : null;

  static String _fallbackDayKey(DateTime utc) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}-${p2(utc.month)}-${p2(utc.day)}';
  }
}

/// Result of parsing an export file.
class GameLogImportResult {
  const GameLogImportResult({
    required this.entries,
    required this.skippedCount,
    this.goals = const <GameLogGoal>[],
    this.formatError,
  });

  final List<GameLogEntry> entries;

  /// 다음 경기에서 해볼 것 (Stage 3). Empty on a file exported before this
  /// field existed, or one with no goals ever written — see
  /// [GameLogJsonCodec.decode].
  final List<GameLogGoal> goals;

  /// Individual rows that could not be parsed and were dropped, not the
  /// whole file — see [GameLogJsonCodec.decode].
  final int skippedCount;

  /// Set only when the envelope itself is unreadable; [entries] is then
  /// always empty.
  final String? formatError;

  bool get isValid => formatError == null;
}

/// Human-readable CSV, for opening in a spreadsheet or for the "총무의 엑셀"
/// bulk-entry path later. See the class doc above for why this is
/// encode-only in Stage 1.
///
/// 다음 경기에서 해볼 것 (Stage 3) is deliberately **not** a column here: this
/// format is one row per game, and a goal is not a per-game fact — it can
/// outlive the game it was written after (carried forward across several),
/// or exist with no game tied to it at all once carried. Forcing it into a
/// per-row shape would either duplicate it across every row until the next
/// goal, or silently drop whichever goal has no entry to sit next to.
/// [GameLogJsonCodec] carries it instead, where it belongs as its own array.
class GameLogCsvCodec {
  const GameLogCsvCodec._();

  static const List<String> _header = <String>[
    '날짜',
    '대회',
    '상대',
    '구장',
    '포지션',
    '결과',
    '메모',
    '타석',
    '안타',
    '볼넷',
    '희생번트',
    '삼진',
    '타점',
    '득점',
    '도루',
    '투구아웃수',
    '탈삼진',
    '볼넷(투구)',
    '실점',
  ];

  static String encode(List<GameLogEntry> entries) {
    final buffer = StringBuffer()..writeln(_header.map(_quote).join(','));
    for (final e in entries) {
      final row = <String>[
        e.dayKey,
        e.competitionLabel ?? '',
        e.opponentLabel ?? '',
        e.venueLabel ?? '',
        e.positions.map((p) => p.labelKo).join('/'),
        e.result.labelKo,
        e.note ?? '',
        e.plateAppearances?.toString() ?? '',
        e.hits?.toString() ?? '',
        e.walks?.toString() ?? '',
        e.sacrificeBunts?.toString() ?? '',
        e.strikeouts?.toString() ?? '',
        e.runsBattedIn?.toString() ?? '',
        e.runsScored?.toString() ?? '',
        e.stolenBases?.toString() ?? '',
        // Raw outs (innings × 3), not the `12⅔이닝` display form — a plain
        // number is what stays summable if this file is opened in a
        // spreadsheet, and what a later CSV-import path (⑤, not this build)
        // would need to read back exactly.
        e.outsPitched?.toString() ?? '',
        e.pitchingStrikeouts?.toString() ?? '',
        e.pitchingWalks?.toString() ?? '',
        e.runsAllowed?.toString() ?? '',
      ];
      buffer.writeln(row.map(_quote).join(','));
    }
    return buffer.toString();
  }

  /// RFC 4180-style quoting: wrap in quotes and double any embedded quote
  /// whenever the field could otherwise be misread — a comma, a quote, or a
  /// newline in a free-text 메모 must not silently break the column count.
  static String _quote(String field) {
    final needsQuoting =
        field.contains(',') || field.contains('"') || field.contains('\n');
    if (!needsQuoting) return field;
    return '"${field.replaceAll('"', '""')}"';
  }
}
