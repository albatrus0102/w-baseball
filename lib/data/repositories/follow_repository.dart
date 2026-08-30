import 'package:drift/drift.dart';

import '../../core/database/database.dart';
import '../mappers/row_mappers.dart';
import '../models/audience.dart';

/// Device-local follows, saves, and seen-state.
///
/// There is no account and no server. Everything here lives on the device and
/// is never transmitted, which is what lets the app personalise without asking
/// anyone to sign up.
abstract interface class FollowRepository {
  Stream<List<LocalFollow>> watchFollows({FollowKind? kind});

  Stream<Set<String>> watchFollowedIds(FollowKind kind);

  Future<bool> isFollowing(FollowKind kind, String entityId);

  Future<void> follow(FollowKind kind, String entityId, {String? label});

  Future<void> unfollow(FollowKind kind, String entityId);

  /// Returns the new state, so callers can drive a toggle animation.
  Future<bool> toggleFollow(FollowKind kind, String entityId, {String? label});

  Future<void> setMuted(FollowKind kind, String entityId, bool muted);

  Stream<List<SavedItem>> watchSavedItems({SavedItemKind? kind});

  Stream<Set<String>> watchSavedIds(SavedItemKind kind);

  Future<bool> toggleSaved(SavedItemKind kind, String entityId, {String? note});

  Future<bool> isSaved(SavedItemKind kind, String entityId);

  /// Records that the user has seen a piece of content, so the home screen can
  /// avoid leading with the same story two days running.
  Future<void> markSeen(String kind, String entityId);

  Future<Set<String>> seenIds(String kind);

  /// Clears follows and saves. Used by "설정 초기화".
  Future<void> clearAll();
}

class DriftFollowRepository implements FollowRepository {
  DriftFollowRepository({required this.db, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final WbDatabase db;
  final DateTime Function() _clock;

  @override
  Stream<List<LocalFollow>> watchFollows({FollowKind? kind}) {
    final select = db.select(db.localFollows)
      ..orderBy([(t) => OrderingTerm.desc(t.followedAt)]);
    if (kind != null) {
      select.where((t) => t.kind.equals(kind.wireValue));
    }
    return select.watch().map(
      (rows) => rows.map((r) => r.toDomain()).toList(growable: false),
    );
  }

  @override
  Stream<Set<String>> watchFollowedIds(FollowKind kind) {
    final select = db.select(db.localFollows)
      ..where((t) => t.kind.equals(kind.wireValue));
    return select.watch().map((rows) => rows.map((r) => r.entityId).toSet());
  }

  @override
  Future<bool> isFollowing(FollowKind kind, String entityId) async {
    final row =
        await (db.select(db.localFollows)..where(
              (t) =>
                  t.kind.equals(kind.wireValue) & t.entityId.equals(entityId),
            ))
            .getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> follow(FollowKind kind, String entityId, {String? label}) async {
    await db
        .into(db.localFollows)
        .insertOnConflictUpdate(
          LocalFollowsCompanion.insert(
            kind: kind.wireValue,
            entityId: entityId,
            followedAt: _clock().toUtc(),
            label: Value(label),
          ),
        );
  }

  @override
  Future<void> unfollow(FollowKind kind, String entityId) async {
    await (db.delete(db.localFollows)..where(
          (t) => t.kind.equals(kind.wireValue) & t.entityId.equals(entityId),
        ))
        .go();
  }

  @override
  Future<bool> toggleFollow(
    FollowKind kind,
    String entityId, {
    String? label,
  }) async {
    if (await isFollowing(kind, entityId)) {
      await unfollow(kind, entityId);
      return false;
    }
    await follow(kind, entityId, label: label);
    return true;
  }

  @override
  Future<void> setMuted(FollowKind kind, String entityId, bool muted) async {
    await (db.update(db.localFollows)..where(
          (t) => t.kind.equals(kind.wireValue) & t.entityId.equals(entityId),
        ))
        .write(LocalFollowsCompanion(muted: Value(muted)));
  }

  @override
  Stream<List<SavedItem>> watchSavedItems({SavedItemKind? kind}) {
    final select = db.select(db.savedItems)
      ..orderBy([(t) => OrderingTerm.desc(t.savedAt)]);
    if (kind != null) {
      select.where((t) => t.kind.equals(kind.wireValue));
    }
    return select.watch().map(
      (rows) => rows.map((r) => r.toDomain()).toList(growable: false),
    );
  }

  @override
  Stream<Set<String>> watchSavedIds(SavedItemKind kind) {
    final select = db.select(db.savedItems)
      ..where((t) => t.kind.equals(kind.wireValue));
    return select.watch().map((rows) => rows.map((r) => r.entityId).toSet());
  }

  @override
  Future<bool> isSaved(SavedItemKind kind, String entityId) async {
    final row =
        await (db.select(db.savedItems)..where(
              (t) =>
                  t.kind.equals(kind.wireValue) & t.entityId.equals(entityId),
            ))
            .getSingleOrNull();
    return row != null;
  }

  @override
  Future<bool> toggleSaved(
    SavedItemKind kind,
    String entityId, {
    String? note,
  }) async {
    if (await isSaved(kind, entityId)) {
      await (db.delete(db.savedItems)..where(
            (t) => t.kind.equals(kind.wireValue) & t.entityId.equals(entityId),
          ))
          .go();
      return false;
    }
    await db
        .into(db.savedItems)
        .insertOnConflictUpdate(
          SavedItemsCompanion.insert(
            kind: kind.wireValue,
            entityId: entityId,
            savedAt: _clock().toUtc(),
            note: Value(note),
          ),
        );
    return true;
  }

  @override
  Future<void> markSeen(String kind, String entityId) async {
    await db
        .into(db.seenItems)
        .insertOnConflictUpdate(
          SeenItemsCompanion.insert(
            kind: kind,
            entityId: entityId,
            seenAt: _clock().toUtc(),
          ),
        );
  }

  @override
  Future<Set<String>> seenIds(String kind) async {
    final rows = await (db.select(
      db.seenItems,
    )..where((t) => t.kind.equals(kind))).get();
    return rows.map((r) => r.entityId).toSet();
  }

  @override
  Future<void> clearAll() async {
    await db.transaction(() async {
      await db.delete(db.localFollows).go();
      await db.delete(db.savedItems).go();
      await db.delete(db.seenItems).go();
    });
  }
}
