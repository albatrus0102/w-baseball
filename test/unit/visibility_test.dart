import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/config/app_config.dart';
import 'package:w_baseball/core/database/database.dart';
import 'package:w_baseball/data/models/content.dart';
import 'package:w_baseball/data/models/provenance.dart';
import 'package:w_baseball/data/repositories/content_repository.dart';
import 'package:w_baseball/data/sources/bundled_seed_data_source.dart';
import 'package:w_baseball/data/sync/content_sync.dart';
import 'package:w_baseball/data/sync/sync_contracts.dart';
import 'package:w_baseball/data/sync/sync_engine.dart';

import '../widget/harness.dart';

/// `visibility` is a privacy control, and it did nothing.
///
/// Every entity and every content record carries `RecordVisibility`. It was
/// parsed from the payload, written to SQLite, and read back into the domain
/// model — and then no repository filtered on it and no screen consulted it. A
/// record the publisher marked `private` or `hidden` rendered exactly like a
/// public one.
///
/// Nothing in the shipped seed is non-public, so nothing leaked. The control
/// was simply not connected to anything, which is worse than a bug that fires:
/// it looks handled.
void main() {
  final now = DateTime.utc(2026, 8, 30, 9);

  /// Rewrites one record's `visibility` in the seed and re-syncs from it, so
  /// the value travels the same path a published payload would.
  Future<WbDatabase> syncSeedWith({
    required String documentPath,
    required bool Function(Map<String, dynamic> record) matches,
    required String visibility,
  }) async {
    final docs = Map<String, String>.from(loadSeedFromDisk());
    final decoded = jsonDecode(docs[documentPath]!) as Map<String, dynamic>;

    var touched = 0;
    void walk(Object? node) {
      if (node is Map<String, dynamic>) {
        if (node.containsKey('source') && matches(node)) {
          (node['source'] as Map<String, dynamic>)['visibility'] = visibility;
          touched++;
        }
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(decoded);
    expect(touched, greaterThan(0), reason: '대상 레코드를 찾지 못하면 이 테스트는 무의미합니다');
    docs[documentPath] = jsonEncode(decoded);

    final db = WbDatabase(NativeDatabase.memory());
    final config = AppConfig.fromEnvironment();
    final source = BundledSeedDataSource(
      contract: config.dataContract,
      bundle: MapAssetBundle(docs),
    );
    await SyncEngine(db: db, config: config).refreshSource(
      source,
      scope: const GameSyncScope(months: <String>['2026-08']),
      incremental: false,
    );
    await ContentSyncEngine(
      db: db,
      supportsSchemaVersion: config.dataContract.supports,
    ).syncFrom(source);
    return db;
  }

  group('비공개 표시된 엔티티', () {
    test('private 팀은 저장되지 않는다', () async {
      // Filtered on the write path: there are ten read paths and one write
      // path, and every read already excludes tombstoned rows.
      final db = await syncSeedWith(
        documentPath: 'teams.json',
        matches: (r) => r['id'] == 'team-demo-hangang',
        visibility: 'private',
      );
      addTearDown(db.close);

      final teams = await db.select(db.teams).get();

      expect(
        teams.map((t) => t.id),
        isNot(contains('team-demo-hangang')),
        reason: '발행자가 비공개로 표시한 레코드가 목록에 나옵니다',
      );
      expect(teams, isNotEmpty, reason: '나머지 팀은 그대로 있어야 합니다');
    });

    test('hidden도 마찬가지로 제외된다', () async {
      final db = await syncSeedWith(
        documentPath: 'teams.json',
        matches: (r) => r['id'] == 'team-demo-hangang',
        visibility: 'hidden',
      );
      addTearDown(db.close);

      final teams = await db.select(db.teams).get();
      expect(teams.map((t) => t.id), isNot(contains('team-demo-hangang')));
    });

    test('알 수 없는 값은 공개로 읽는다', () async {
      // Only what the publisher explicitly asked to withhold is withheld. A
      // typo must not silently empty the app.
      final db = await syncSeedWith(
        documentPath: 'teams.json',
        matches: (r) => r['id'] == 'team-demo-hangang',
        visibility: 'privte',
      );
      addTearDown(db.close);

      final teams = await db.select(db.teams).get();
      expect(teams.map((t) => t.id), contains('team-demo-hangang'));
    });
  });

  group('비공개 표시된 콘텐츠', () {
    test('private 가이드는 목록에 나오지 않는다', () async {
      // Content arrives through ContentSyncEngine's nested write loops rather
      // than the entity sync path, so it is enforced at the publish gate the
      // repository already consults on every read.
      final db = await syncSeedWith(
        documentPath: 'content/discover.json',
        matches: (r) => r['id'] == 'guide-one-minute',
        visibility: 'private',
      );
      addTearDown(db.close);

      final repo = DriftContentRepository(db: db, clock: () => now);
      final guides = await repo.watchGuides().first;

      expect(guides.map((g) => g.id), isNot(contains('guide-one-minute')));
      expect(guides, isNotEmpty, reason: '나머지 가이드는 그대로 있어야 합니다');
    });

    test('id를 알아도 비공개 가이드를 꺼낼 수 없다', () async {
      // Knowing an address must not be a way around the gate.
      final db = await syncSeedWith(
        documentPath: 'content/discover.json',
        matches: (r) => r['id'] == 'guide-one-minute',
        visibility: 'private',
      );
      addTearDown(db.close);

      final repo = DriftContentRepository(db: db, clock: () => now);
      final guides = await repo.watchGuides().first;
      for (final g in guides) {
        expect(g.id, isNot('guide-one-minute'));
      }
    });
  });

  group('게시 가능 판정', () {
    ContentMeta meta(RecordVisibility visibility) => ContentMeta(
      provenance: Provenance(
        sourceName: 's',
        sourceUrl: 'https://example.org',
        fetchedAt: now,
        visibility: visibility,
      ),
      publishedAt: now,
    );

    test('공개가 아니면 검수 상태와 무관하게 게시할 수 없다', () {
      expect(meta(RecordVisibility.public).isPublishable, isTrue);
      expect(meta(RecordVisibility.private).isPublishable, isFalse);
      expect(meta(RecordVisibility.hidden).isPublishable, isFalse);
    });
  });
}
