import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/app/providers.dart';
import 'package:w_baseball/core/config/app_config.dart';
import 'package:w_baseball/core/database/database.dart';
import 'package:w_baseball/data/sources/bundled_seed_data_source.dart';
import 'package:w_baseball/data/sources/sports_data_source.dart';

import '../widget/harness.dart';

/// Reproduces the "방금 갱신" bug end to end, through the real
/// `dataSourcesProvider` — not the empty list every widget test substitutes
/// (see `harness.dart`'s `buildTestApp`, which is exactly why this bug never
/// surfaced in a widget test).
///
/// With `WB_MANIFEST_BASE_URL` unset (the shipped default) and no other
/// adapter flag on, `dataSourcesProvider` still contains one enabled entry:
/// the bundled seed. `SyncController.refresh()` re-reads it on every call —
/// `bootstrap.dart` does exactly this on every cold start — and before the
/// fix, `SyncReport.anySucceeded` counted that re-read as a real sync,
/// advancing `lastSuccessfulSyncAt` to "now" and flipping the app bar to
/// "방금 갱신" seconds after a fresh install with nothing configured to sync
/// from at all.
void main() {
  late WbDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = WbDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('원격이 설정되지 않은 상태에서 갱신해도 시드만 다시 읽었을 뿐 실제 동기화가 아니다', () async {
    final config = AppConfig.fromEnvironment(); // WB_MANIFEST_BASE_URL empty.

    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        databaseProvider.overrideWithValue(db),
        preferencesProvider.overrideWithValue(FakePreferences()),
        // Only the seed's asset source is swapped in (disk instead of a real
        // asset bundle, so this plain unit test does not need Flutter's
        // asset channel). `dataSourcesProvider` itself is left real and
        // untouched — it is assembled from this override plus `config`
        // above, exactly as `bootstrap.dart` assembles it.
        seedSourceProvider.overrideWithValue(
          BundledSeedDataSource(
            contract: config.dataContract,
            bundle: MapAssetBundle(loadSeedFromDisk()),
          ),
        ),
      ],
    );

    expect(
      container.read(hasRemoteSourceConfiguredProvider),
      isFalse,
      reason: 'WB_MANIFEST_BASE_URL이 비어 있으면 원격 출처는 없어야 합니다',
    );
    expect(container.read(syncControllerProvider).lastSuccessAt, isNull);

    final report = await container
        .read(syncControllerProvider.notifier)
        .refresh(force: true);

    // The seed did succeed — that part of the report stays honest.
    expect(
      report.results.any(
        (r) =>
            r.sourceName == BundledSeedDataSource.seedSourceName && r.isSuccess,
      ),
      isTrue,
      reason: '시드 자체는 정상적으로 다시 읽혔어야 합니다',
    );

    // But nothing left the device, so this must not count as "a sync
    // succeeded" for the purpose the app bar cares about.
    expect(
      container.read(syncControllerProvider).lastSuccessAt,
      isNull,
      reason: '시드만 다시 읽은 것은 "갱신"이 아닙니다 — lastSuccessAt이 그대로 null이어야 합니다',
    );
  });

  test('원격 출처가 실제로 성공하면 lastSuccessAt이 채워진다', () async {
    // The other direction: the fix must not make `lastSuccessAt` impossible
    // to set. A real (non-seed) success has to advance it exactly as before.
    final config = AppConfig.fromEnvironment().copyWith(
      manifest: const ManifestConfig(baseUrl: 'https://example.test/wb'),
    );

    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        databaseProvider.overrideWithValue(db),
        preferencesProvider.overrideWithValue(FakePreferences()),
        // A trivially-successful stand-in for a real remote source. Empty
        // `supportedEntities` means the engine has nothing to fetch and
        // nothing to fail on — the point here is only that its name is not
        // `seed`.
        dataSourcesProvider.overrideWithValue(<SportsDataSource>[
          _AlwaysSucceedsSource(),
        ]),
      ],
    );

    expect(container.read(hasRemoteSourceConfiguredProvider), isTrue);
    await container.read(syncControllerProvider.notifier).refresh(force: true);

    expect(
      container.read(syncControllerProvider).lastSuccessAt,
      isNotNull,
      reason: '시드가 아닌 실제 출처가 성공했다면 lastSuccessAt이 채워져야 합니다',
    );
  });
}

/// A remote stand-in that always succeeds and touches nothing.
final class _AlwaysSucceedsSource extends BaseSportsDataSource {
  @override
  String get sourceName => 'fake-remote';

  @override
  Set<SyncEntityType> get supportedEntities => const <SyncEntityType>{};
}
