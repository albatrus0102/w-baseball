import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/config/app_config.dart';
import 'package:w_baseball/data/sources/adapters/permission_gated_adapters.dart';
import 'package:w_baseball/data/sources/future_rest_api_data_source.dart';
import 'package:w_baseball/data/sync/sync_contracts.dart';

/// The "off unless permitted" promise, asserted rather than commented.
///
/// WBAK and KBSA expose no documented external API; WBSC and WPBL expose
/// endpoints that are reachable but were never offered to us as a contract.
/// The app's answer is that all four are compiled in and none of them run
/// without an explicit grant. That promise lived only in a doc comment and in
/// default parameter values — nothing failed if a later edit flipped one.
void main() {
  group('이용허락 게이트', () {
    test('기본 설정에서 네 어댑터가 모두 꺼져 있다', () {
      // The default constructor and the dart-define reader are two separate
      // paths to the same flags; a default can be correct in one and wrong in
      // the other, so both are checked.
      for (final flags in [
        const FeatureFlags(),
        FeatureFlags.fromEnvironment(),
      ]) {
        final adapters = buildGatedAdapters(flags);
        expect(adapters, hasLength(4));
        expect(
          adapters.where((a) => a.isEnabled),
          isEmpty,
          reason: '이용허락이 확인되지 않은 출처가 기본으로 켜져 있습니다',
        );
      }
    });

    test('꺼져 있으면 수집 대상 엔티티가 없다', () {
      // isEnabled alone is not enough: SyncEngine asks what a source provides.
      // A disabled adapter that still claims to supply games would be selected
      // and then asked for them.
      for (final adapter in buildGatedAdapters(const FeatureFlags())) {
        expect(
          adapter.supportedEntities,
          isEmpty,
          reason: '${adapter.sourceName}이(가) 꺼진 상태로 엔티티를 신고합니다',
        );
      }
    });

    test('꺼져 있으면 요청해도 빈 페이지를 돌려주고 던지지 않는다', () async {
      // Belt and braces. If some future caller reaches a disabled adapter
      // directly, it must be inert — not an exception that turns into a
      // user-visible sync error about a source we deliberately do not use.
      for (final adapter in buildGatedAdapters(const FeatureFlags())) {
        final page = await adapter.fetchGames(
          const GameSyncRequest(month: '2026-08'),
        );
        expect(page.items, isEmpty);
        expect(page.sourceName, adapter.sourceName);
      }
    });

    test('켜면 조용히 비어 있는 대신 notImplemented로 실패한다', () async {
      // The dangerous failure is the silent one: a grant arrives, someone sets
      // the flag, sync reports success, and the app shows nothing new for
      // weeks. Enabling an unbuilt adapter has to be loud.
      final wbak = buildGatedAdapters(
        const FeatureFlags(wbakAdapterEnabled: true),
      ).firstWhere((a) => a.sourceName == 'wbak');

      expect(wbak.isEnabled, isTrue);
      expect(wbak.supportedEntities, isNotEmpty);

      await expectLater(
        wbak.fetchGames(const GameSyncRequest(month: '2026-08')),
        throwsA(
          isA<SyncException>().having(
            (e) => e.kind,
            'kind',
            SyncFailureKind.notImplemented,
          ),
        ),
      );
    });

    test('하나를 켜도 나머지는 켜지지 않는다', () {
      final adapters = buildGatedAdapters(
        const FeatureFlags(wbscAdapterEnabled: true),
      );
      expect(
        adapters.where((a) => a.isEnabled).map((a) => a.sourceName),
        <String>['wbsc'],
      );
    });

    test('꺼진 어댑터는 사용자에게 보여줄 이유 문구를 갖는다', () {
      // The data-sources screen explains why a source is idle. An empty string
      // there reads as a bug rather than as a decision.
      for (final adapter in buildGatedAdapters(const FeatureFlags())) {
        expect(
          (adapter as PermissionGatedAdapter).disabledReasonKo.trim(),
          isNotEmpty,
        );
      }
    });
  });

  group('미구현 출처의 실패 문구', () {
    test('notImplemented는 권한 문제로 말하지 않는다', () {
      // These two sentences point at different people. Reporting an unbuilt
      // adapter as an access problem sends the user to the publisher over
      // something that is ours to fix.
      expect(SyncFailureKind.notImplemented.messageKo, contains('연결되지 않'));
      expect(
        SyncFailureKind.notImplemented.messageKo,
        isNot(SyncFailureKind.unauthorized.messageKo),
      );
      expect(
        SyncFailureKind.notImplemented.messageKo,
        isNot(SyncFailureKind.forbidden.messageKo),
      );
    });

    test('notImplemented는 재시도 대상이 아니다', () {
      // Nothing about waiting changes whether code exists.
      expect(SyncFailureKind.notImplemented.isRetryable, isFalse);
    });

    test('GraphQL 전송으로 설정하면 켜지지만 notImplemented로 실패한다', () async {
      // `WB_API_TRANSPORT=graphql` is a supported value with no implementation
      // behind it. It used to report `unauthorized`, i.e. "데이터 접근 권한이
      // 없습니다" — which blames the publisher for a switch we shipped.
      const source = FutureGraphqlDataSource(
        config: FutureApiConfig(
          baseUrl: 'https://example.test',
          transport: ApiTransport.graphql,
        ),
        contract: DataContractConfig(),
      );

      expect(source.isEnabled, isTrue);

      await expectLater(
        source.fetchGames(const GameSyncRequest(month: '2026-08')),
        throwsA(
          isA<SyncException>().having(
            (e) => e.kind,
            'kind',
            SyncFailureKind.notImplemented,
          ),
        ),
      );
    });

    test('REST 전송으로 설정하면 GraphQL 출처는 꺼진다', () {
      const source = FutureGraphqlDataSource(
        config: FutureApiConfig(
          baseUrl: 'https://example.test',
          transport: ApiTransport.rest,
        ),
        contract: DataContractConfig(),
      );
      expect(source.isEnabled, isFalse);
      expect(source.supportedEntities, isEmpty);
    });
  });
}
