import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/app/providers.dart';
import 'package:w_baseball/core/analytics/analytics.dart';
import 'package:w_baseball/core/config/app_config.dart';
import 'package:w_baseball/core/database/database.dart';
import 'package:w_baseball/core/platform/platform_services.dart';
import 'package:w_baseball/data/sources/bundled_seed_data_source.dart';
import 'package:w_baseball/data/sources/sports_data_source.dart';
import 'package:w_baseball/data/dto/dtos.dart';
import 'package:w_baseball/data/sync/sync_contracts.dart';
import 'package:w_baseball/features/settings/more_screen.dart';

import 'harness.dart';

/// `SyncStatus.isPartial` had the same sibling bug as `lastSuccessAt`: it
/// gated on `lastReport.anySucceeded`, which the bundled seed always
/// satisfies, so a configured-but-completely-unreachable remote source still
/// showed "일부 데이터만 갱신됨" — telling the user some data was refreshed when
/// only the bundle (already on the device) had been re-read.
///
/// Both directions matter: the badge must disappear when only the seed
/// succeeded, and must still appear for a genuine partial sync (one real
/// source succeeds, another fails).
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

  Future<TestApp> buildApp(List<SportsDataSource> sources) async {
    final config = AppConfig.fromEnvironment().copyWith(
      manifest: const ManifestConfig(baseUrl: 'https://example.test/wb'),
    );
    final prefs = FakePreferences();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        databaseProvider.overrideWithValue(db),
        preferencesProvider.overrideWithValue(prefs),
        platformServicesProvider.overrideWithValue(PlatformServices.noop()),
        analyticsProvider.overrideWithValue(const NoopAnalyticsService()),
        dataSourcesProvider.overrideWithValue(sources),
      ],
    );
    return TestApp(db: db, container: container, preferences: prefs);
  }

  testWidgets('시드만 성공하고 실제 원격은 모두 실패하면 부분 갱신 배지가 뜨지 않는다', (tester) async {
    final app = await buildApp(<SportsDataSource>[
      _AlwaysFailsSource(),
      _SeedStandIn(),
    ]);
    addTearDown(app.dispose);

    await pumpScreen(tester, app, const MoreScreen());
    await container.read(syncControllerProvider.notifier).refresh(force: true);
    await tester.pump();

    expect(container.read(syncControllerProvider).isPartial, isFalse);
    expect(find.text('일부 데이터만 갱신됨'), findsNothing);
  });

  testWidgets('실제 원격 하나가 성공하고 다른 하나가 실패하면 부분 갱신 배지가 뜬다', (tester) async {
    final app = await buildApp(<SportsDataSource>[
      _AlwaysFailsSource(),
      _AlwaysSucceedsRealSource(),
    ]);
    addTearDown(app.dispose);

    await pumpScreen(tester, app, const MoreScreen());
    await container.read(syncControllerProvider.notifier).refresh(force: true);
    await tester.pump();

    expect(container.read(syncControllerProvider).isPartial, isTrue);
    expect(find.text('일부 데이터만 갱신됨'), findsOneWidget);
  });
}

/// A stand-in for the bundled seed: same `sourceName`, always succeeds,
/// touches nothing. Cheaper than reading real seed assets for a test that
/// only cares whether this source's success alone can trigger the badge.
final class _SeedStandIn extends BaseSportsDataSource {
  @override
  String get sourceName => BundledSeedDataSource.seedSourceName;
}

/// A remote stand-in that always succeeds and touches nothing.
final class _AlwaysSucceedsRealSource extends BaseSportsDataSource {
  @override
  String get sourceName => 'fake-remote-ok';
}

/// A remote stand-in that always fails on the one entity type it claims to
/// support.
final class _AlwaysFailsSource extends BaseSportsDataSource {
  @override
  String get sourceName => 'fake-remote-fail';

  @override
  Set<SyncEntityType> get supportedEntities => const <SyncEntityType>{
    SyncEntityType.team,
  };

  @override
  Future<SyncPage<TeamDto>> fetchTeams(SyncRequest request) {
    throw SyncException(
      SyncFailureKind.serverError,
      sourceName: sourceName,
      message: '테스트용 강제 실패',
    );
  }
}
