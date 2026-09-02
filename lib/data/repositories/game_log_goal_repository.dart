import 'package:drift/drift.dart';

import '../../core/database/database.dart';
import '../mappers/row_mappers.dart';
import '../models/game_log.dart';

/// "다음 경기에서 해볼 것" — the player's own goal, written in her own words.
///
/// Device-local, like [GameLogRepository]. There is no account and no
/// server, so this never leaves the device except through the export file
/// (see `lib/data/export/game_log_export.dart`'s `goals` field).
///
/// At most one goal is ever open (`closedAt == null`) at a time. See
/// [setGoal]'s doc for exactly what happens to the previous one when a new
/// one is written.
abstract interface class GameLogGoalRepository {
  /// The one open goal, if any — null once every goal has been closed one
  /// way or another (or none was ever written).
  Stream<GameLogGoal?> watchOpenGoal();

  /// Every goal ever written, open or closed, most recent first. Used only
  /// by the full export (see `lib/data/export/game_log_export.dart`) — the
  /// screen itself never lists closed goals; see the class doc.
  Future<List<GameLogGoal>> allGoals();

  /// Writes a new goal, freshly typed after logging a game.
  ///
  /// If a goal is already open, it is closed first with `outcome: null` —
  /// silently, not as `carried`. Nobody was asked whether she did the old
  /// one and nobody answered; that is a different thing from any of the
  /// reflection card's three buttons being pressed, which is exactly why
  /// `null` and `carried` are different values. See `GameLogGoalOutcome`.
  ///
  /// Does nothing if [body], once trimmed, is empty — an empty goal is the
  /// same as not writing one at all.
  Future<void> setGoal({required String body, int? entryId});

  /// "했어요" — closes [id] with `outcome: done`. No new goal opens.
  Future<void> markDone(int id);

  /// "지우기" — closes [id] with `outcome: dropped`. No new goal opens.
  Future<void> dropGoal(int id);

  /// "다음에도" — closes [id] with `outcome: carried`, then immediately opens
  /// a new goal with the same [body] and no `entryId` (it was not written
  /// alongside any one game this time).
  Future<void> carryForward({required int id, required String body});
}

class DriftGameLogGoalRepository implements GameLogGoalRepository {
  DriftGameLogGoalRepository({required this.db, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final WbDatabase db;
  final DateTime Function() _clock;

  @override
  Stream<GameLogGoal?> watchOpenGoal() {
    final select = db.select(db.gameLogGoals)
      ..where((t) => t.closedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(1);
    return select.watchSingleOrNull().map((row) => row?.toDomain());
  }

  @override
  Future<List<GameLogGoal>> allGoals() async {
    final select = db.select(db.gameLogGoals)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    final rows = await select.get();
    return rows.map((r) => r.toDomain()).toList(growable: false);
  }

  @override
  Future<void> setGoal({required String body, int? entryId}) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    final now = _clock().toUtc();
    await db.transaction(() async {
      await _closeOpenGoal(outcome: null, now: now);
      await db
          .into(db.gameLogGoals)
          .insert(
            GameLogGoalsCompanion.insert(
              body: trimmed,
              entryId: Value(entryId),
              createdAt: now,
            ),
          );
    });
  }

  @override
  Future<void> markDone(int id) =>
      _closeGoal(id: id, outcome: GameLogGoalOutcome.done);

  @override
  Future<void> dropGoal(int id) =>
      _closeGoal(id: id, outcome: GameLogGoalOutcome.dropped);

  @override
  Future<void> carryForward({required int id, required String body}) async {
    final trimmed = body.trim();
    final now = _clock().toUtc();
    await db.transaction(() async {
      await (db.update(db.gameLogGoals)..where((t) => t.id.equals(id))).write(
        GameLogGoalsCompanion(
          closedAt: Value(now),
          outcome: Value(GameLogGoalOutcome.carried.wireValue),
        ),
      );
      if (trimmed.isEmpty) return;
      await db
          .into(db.gameLogGoals)
          .insert(GameLogGoalsCompanion.insert(body: trimmed, createdAt: now));
    });
  }

  Future<void> _closeGoal({
    required int id,
    required GameLogGoalOutcome outcome,
  }) async {
    final now = _clock().toUtc();
    await (db.update(db.gameLogGoals)..where((t) => t.id.equals(id))).write(
      GameLogGoalsCompanion(
        closedAt: Value(now),
        outcome: Value(outcome.wireValue),
      ),
    );
  }

  /// Closes whichever goal is currently open (if any) with [outcome] —
  /// `null` for a silent supersede, a real value for an explicit button.
  Future<void> _closeOpenGoal({
    required GameLogGoalOutcome? outcome,
    required DateTime now,
  }) async {
    await (db.update(db.gameLogGoals)..where((t) => t.closedAt.isNull())).write(
      GameLogGoalsCompanion(
        closedAt: Value(now),
        outcome: Value(outcome?.wireValue),
      ),
    );
  }
}
