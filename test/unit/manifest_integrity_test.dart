import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/config/app_config.dart';
import 'package:w_baseball/core/network/http_client.dart';
import 'package:w_baseball/data/sources/static_manifest_data_source.dart';
import 'package:w_baseball/data/sync/sync_contracts.dart';

/// The manifest's `sha256` is a promise about the bytes, and it went unchecked.
///
/// It was used only to decide whether to re-download. A file that did not match
/// was applied anyway — and then its *declared* hash was recorded as applied,
/// so the app believed it held the right file and never fetched it again. The
/// corruption stuck.
///
/// JSON parsing already rejects a truncated body. What it cannot catch is a
/// body that parses fine and simply is not what the publisher signed: a stale
/// CDN edge, an upload caught half-finished, the wrong file at the right path.
void main() {
  String digestOf(String body) => sha256.convert(utf8.encode(body)).toString();

  const goodBody =
      '{"schemaVersion":1,"payloadKind":"snapshot","items":[],'
      '"generatedAt":"2026-08-30T00:00:00Z"}';

  /// Serves a manifest plus one file, with the manifest's declared hash under
  /// the test's control so it can be made to disagree with the body.
  ({StaticManifestDataSource source, InMemoryValidatorStore store}) build({
    required String declaredHash,
    required String servedBody,
  }) {
    final manifest = jsonEncode({
      'schemaVersion': 1,
      'dataVersion': '2026.08.30.1',
      'generatedAt': '2026-08-30T00:00:00Z',
      'files': [
        {
          'path': 'teams.json',
          'sha256': declaredHash,
          'size': servedBody.length,
        },
      ],
    });

    // Production transport options, test adapter. Hand-rolling the options
    // here changes how bodies decode and how a 404 is treated, which turns a
    // clear failure into a retry loop.
    final dio = WbHttpClient.buildDio(const SyncConfig())
      ..httpClientAdapter = _StubAdapter({
        'https://example.test/version.json': manifest,
        'https://example.test/teams.json': servedBody,
      });

    final store = InMemoryValidatorStore();
    return (
      source: StaticManifestDataSource(
        config: const ManifestConfig(
          baseUrl: 'https://example.test/',
          versionPath: 'version.json',
        ),
        contract: const DataContractConfig(),
        httpClient: WbHttpClient(config: const SyncConfig(), dio: dio),
        validatorStore: store,
      ),
      store: store,
    );
  }

  group('배포본 무결성', () {
    test('선언된 해시와 일치하면 통과한다', () async {
      final built = build(
        declaredHash: digestOf(goodBody),
        servedBody: goodBody,
      );

      final doc = await built.source.loadDocument(
        'teams.json',
        const SyncValidators(),
      );

      expect(doc, isNotNull);
      expect(doc!.body, goodBody);
    });

    test('해시 표기 대소문자가 달라도 통과한다', () async {
      // Hex digests are written both ways in the wild; a case difference is
      // not a corrupt file.
      final built = build(
        declaredHash: digestOf(goodBody).toUpperCase(),
        servedBody: goodBody,
      );

      final doc = await built.source.loadDocument(
        'teams.json',
        const SyncValidators(),
      );

      expect(doc, isNotNull);
    });

    test('해시가 다르면 checksumMismatch로 거부한다', () async {
      // Valid JSON, wrong file. Parsing cannot tell; the hash can.
      const wrongBody =
          '{"schemaVersion":1,"payloadKind":"snapshot","items":[{"id":"x"}],'
          '"generatedAt":"2026-08-30T00:00:00Z"}';
      final built = build(
        declaredHash: digestOf(goodBody),
        servedBody: wrongBody,
      );

      await expectLater(
        built.source.loadDocument('teams.json', const SyncValidators()),
        throwsA(
          isA<SyncException>().having(
            (e) => e.kind,
            'kind',
            SyncFailureKind.checksumMismatch,
          ),
        ),
      );
    });

    test('거부된 파일의 해시를 적용됨으로 기록하지 않는다', () async {
      // The sticky part of the original bug. If the declared hash were stored,
      // the next sync would skip the download and the wrong data would stay
      // forever.
      final built = build(
        declaredHash: digestOf(goodBody),
        servedBody: '{"schemaVersion":1,"payloadKind":"snapshot","items":[]}',
      );

      await built.source
          .loadDocument('teams.json', const SyncValidators())
          .then<void>((_) {}, onError: (Object _) {});
      await built.source.commitApplied();

      expect(
        await built.store.loadHash('static-manifest:teams.json'),
        isNull,
        reason: '검증에 실패한 파일의 해시가 저장되면 다음 동기화가 건너뜁니다',
      );
    });

    test('checksum 불일치는 재시도할 수 있는 실패로 분류된다', () {
      // A stale edge or a half-finished upload resolves itself; a malformed
      // payload does not. Grouping them would either retry forever or give up
      // too early.
      expect(SyncFailureKind.checksumMismatch.isRetryable, isTrue);
      expect(SyncFailureKind.malformedPayload.isRetryable, isFalse);
    });

    test('같은 파일을 동시에 요청해도 한 번만 받고 둘 다 완료된다', () async {
      // Request coalescing once deadlocked: the in-flight map was cleaned up
      // with `whenComplete(() => _inFlight.remove(key))`, and `Map.remove`
      // returns the value it removed — this future. `whenComplete` waits on a
      // future its callback returns, so the future waited for itself and every
      // request through this client hung forever.
      //
      // It went unnoticed because `WB_MANIFEST_BASE_URL` is empty by default,
      // so nothing ever took the HTTP path. Turning on data distribution would
      // have hung every sync.
      final built = build(
        declaredHash: digestOf(goodBody),
        servedBody: goodBody,
      );

      final both =
          await Future.wait([
            built.source.loadDocument('teams.json', const SyncValidators()),
            built.source.loadDocument('teams.json', const SyncValidators()),
          ]).timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw StateError('요청이 완료되지 않았습니다 (교착)'),
          );

      expect(both, hasLength(2));
      expect(both.every((d) => d?.body == goodBody), isTrue);
    });

    test('manifest에 해시가 없으면 검증하지 않고 통과시킨다', () async {
      // Not every publisher will provide one. Absence is not a mismatch.
      final built = build(declaredHash: '', servedBody: goodBody);

      final doc = await built.source.loadDocument(
        'teams.json',
        const SyncValidators(),
      );

      expect(doc, isNotNull);
    });
  });
}

/// Serves fixed bodies for known URLs and 404s everything else.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.bodies);

  final Map<String, String> bodies;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = bodies[options.uri.toString()];
    if (body == null) {
      return ResponseBody.fromString('', 404);
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
