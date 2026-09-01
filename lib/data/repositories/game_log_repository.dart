import 'package:drift/drift.dart';

import '../../core/database/database.dart';
import '../../core/utils/kst.dart';
import '../mappers/row_mappers.dart';
import '../models/game_log.dart';

/// The player's own 출전 일지 — device-local, never uploaded.
///
/// There is no account and no server (see the feature brief's "phone-change
/// problem"). Everything here lives in [WbDatabase.gameLogEntries] and only
/// leaves the device through [PlatformServices.sharing]'s explicit,
/// user-initiated export.
abstract interface class GameLogRepository {
  /// All entries, most recent game first.
  Stream<List<GameLogEntry>> watchEntries();

  Future<GameLogEntry> addEntry({
    required DateTime playedAt,
    String? gameId,
    String? competitionLabel,
    String? opponentLabel,
    String? venueLabel,
    List<GameLogPosition> positions = const <GameLogPosition>[],
    GameLogResult result = GameLogResult.unspecified,
    String? note,
  });

  Future<void> deleteEntry(int id);

  /// How many entries exist. Used for the "N번째 기록" export nudge and the
  /// "N게임" count shown on the module — counting only what she entered,
  /// never anything the app inferred.
  Future<int> countEntries();
}

class DriftGameLogRepository implements GameLogRepository {
  DriftGameLogRepository({required this.db, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final WbDatabase db;
  final DateTime Function() _clock;

  @override
  Stream<List<GameLogEntry>> watchEntries() {
    final select = db.select(db.gameLogEntries)
      ..orderBy([
        (t) => OrderingTerm.desc(t.playedAt),
        (t) => OrderingTerm.desc(t.createdAt),
      ]);
    return select.watch().map(
      (rows) => rows.map((r) => r.toDomain()).toList(growable: false),
    );
  }

  @override
  Future<GameLogEntry> addEntry({
    required DateTime playedAt,
    String? gameId,
    String? competitionLabel,
    String? opponentLabel,
    String? venueLabel,
    List<GameLogPosition> positions = const <GameLogPosition>[],
    GameLogResult result = GameLogResult.unspecified,
    String? note,
  }) async {
    final now = _clock().toUtc();
    final id = await db
        .into(db.gameLogEntries)
        .insert(
          GameLogEntriesCompanion.insert(
            playedAt: playedAt,
            dayKey: Kst.dayKey(playedAt),
            gameId: Value(gameId),
            competitionLabel: Value(_orNull(competitionLabel)),
            opponentLabel: Value(_orNull(opponentLabel)),
            venueLabel: Value(_orNull(venueLabel)),
            positions: Value(GameLogPosition.encodeList(positions)),
            result: Value(result.wireValue),
            note: Value(_orNull(note)),
            createdAt: now,
          ),
        );
    return GameLogEntry(
      id: id,
      playedAt: playedAt,
      dayKey: Kst.dayKey(playedAt),
      gameId: gameId,
      competitionLabel: _orNull(competitionLabel),
      opponentLabel: _orNull(opponentLabel),
      venueLabel: _orNull(venueLabel),
      positions: positions,
      result: result,
      note: _orNull(note),
      createdAt: now,
    );
  }

  @override
  Future<void> deleteEntry(int id) async {
    await (db.delete(db.gameLogEntries)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<int> countEntries() async {
    final count = db.gameLogEntries.id.count();
    final query = db.selectOnly(db.gameLogEntries)..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  static String? _orNull(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
