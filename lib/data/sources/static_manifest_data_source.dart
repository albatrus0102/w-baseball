import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../../core/network/http_client.dart';
import '../sync/sync_contracts.dart';
import 'bundled_seed_data_source.dart';
import 'json_document_data_source.dart';
import 'payload_envelope.dart';

/// Remembers per-file cache validators between launches.
///
/// Backed by the settings store in production and by a map in tests. Kept as
/// an interface so this source has no dependency on the database.
abstract interface class ValidatorStore {
  Future<SyncValidators> load(String key);

  Future<void> save(String key, SyncValidators validators, {String? sha256});

  Future<String?> loadHash(String key);

  Future<void> clear();
}

/// In-memory implementation used by tests and as a fallback.
class InMemoryValidatorStore implements ValidatorStore {
  final Map<String, SyncValidators> _validators = {};
  final Map<String, String> _hashes = {};

  @override
  Future<SyncValidators> load(String key) async =>
      _validators[key] ?? const SyncValidators();

  @override
  Future<String?> loadHash(String key) async => _hashes[key];

  @override
  Future<void> save(
    String key,
    SyncValidators validators, {
    String? sha256,
  }) async {
    _validators[key] = validators;
    if (sha256 != null) _hashes[key] = sha256;
  }

  @override
  Future<void> clear() async {
    _validators.clear();
    _hashes.clear();
  }
}

/// Reads the published static JSON data set over HTTP.
///
/// Cost control is the point of this source: there is no always-on server.
/// Files sit on any static host, and we avoid downloading them at all when we
/// can. Two layers of avoidance:
///  1. `version.json` carries a sha256 per file. If it matches what we already
///     applied, the file is never requested.
///  2. If the hash is absent or differs, the request is conditional
///     (`If-None-Match` / `If-Modified-Since`) so an unchanged file costs a
///     304 rather than a body.
final class StaticManifestDataSource extends JsonDocumentDataSource {
  StaticManifestDataSource({
    required this.config,
    required this.contract,
    required WbHttpClient httpClient,
    required ValidatorStore validatorStore,
    this.cancelToken,
  }) : _http = httpClient,
       _store = validatorStore;

  final ManifestConfig config;
  final DataContractConfig contract;
  final CancelToken? cancelToken;

  final WbHttpClient _http;
  final ValidatorStore _store;

  DataManifest? _manifest;
  DataManifestReader? _index;
  bool _manifestLoadAttempted = false;

  @override
  String get sourceName => 'static-manifest';

  @override
  String get displayName => '정적 데이터 배포본';

  @override
  bool get isEnabled => config.isConfigured;

  @override
  bool supportsSchemaVersion(int schemaVersion) =>
      contract.supports(schemaVersion);

  /// The publisher's build id for the data currently loaded.
  String? get dataVersion => _manifest?.dataVersion;

  DateTime? get generatedAt => _manifest?.generatedAt;

  /// Loads `version.json` once per sync run.
  ///
  /// A manifest whose `schemaVersion` we cannot read stops the refresh with
  /// [SyncFailureKind.schemaUnsupported] — deliberately *before* any file is
  /// downloaded, so the existing cache is left completely intact.
  Future<DataManifest?> loadManifest({bool force = false}) async {
    if (!isEnabled) return null;
    if (_manifestLoadAttempted && !force) return _manifest;
    _manifestLoadAttempted = true;

    final key = _validatorKey(DataPaths.version);
    final validators = await _store.load(key);

    final doc = await _http.getDocument(
      config.versionUri,
      sourceName: sourceName,
      // Always revalidate the manifest itself; it is small and it is the
      // thing that tells us whether anything else changed.
      validators: validators,
      cancelToken: cancelToken,
    );

    if (doc == null) {
      throw SyncException(
        SyncFailureKind.notFound,
        sourceName: sourceName,
        message: 'version.json을 찾을 수 없습니다: ${config.versionUri}',
      );
    }

    if (doc.notModified && _manifest != null) return _manifest;

    if (doc.notModified) {
      // 304 but we have no parsed manifest in this process (fresh launch).
      // Drop the stored validator and re-request unconditionally next time.
      await _store.save(key, const SyncValidators());
      return null;
    }

    final DataManifest manifest;
    try {
      manifest = DataManifest.decode(doc.body);
    } on PayloadFormatException catch (e) {
      throw SyncException(
        SyncFailureKind.malformedPayload,
        sourceName: sourceName,
        message: e.message,
      );
    }

    if (!contract.supports(manifest.schemaVersion)) {
      throw SyncException(
        SyncFailureKind.schemaUnsupported,
        sourceName: sourceName,
        receivedSchemaVersion: manifest.schemaVersion,
        message:
            '배포된 데이터 버전(${manifest.schemaVersion})을 이 앱 버전은 읽을 수 없습니다. '
            '기존 데이터는 그대로 유지합니다.',
      );
    }

    _manifest = manifest;
    _index = DataManifestReader.fromPaths(manifest.files.map((f) => f.path));
    await _store.save(key, doc.validators);
    return manifest;
  }

  @override
  Future<List<String>> availableGameMonths() async {
    await loadManifest();
    return _index?.months ?? const <String>[];
  }

  @override
  Future<List<int>> availableCompetitionYears() async {
    await loadManifest();
    return _index?.years ?? const <int>[];
  }

  @override
  Future<List<String>> availableStandingSeasons() async {
    await loadManifest();
    return _index?.seasons ?? const <String>[];
  }

  @override
  Future<SourceDocument?> loadDocument(
    String path,
    SyncValidators requestValidators,
  ) async {
    if (!isEnabled) return null;

    final manifest = await loadManifest();
    final entry = manifest?.fileFor(path);

    // Path not in the manifest: the publisher does not offer it. Not an error.
    if (manifest != null && entry == null) return null;

    final key = _validatorKey(path);

    // Cheapest path: the manifest's content hash matches what we already
    // applied, so we skip the network entirely.
    final knownHash = await _store.loadHash(key);
    if (entry != null && knownHash != null && !entry.changedFrom(knownHash)) {
      return SourceDocument.unchangedMarker;
    }

    final stored = await _store.load(key);
    final validators = requestValidators.isEmpty ? stored : requestValidators;

    final doc = await _http.getDocument(
      config.fileUri(path),
      sourceName: sourceName,
      validators: validators,
      cancelToken: cancelToken,
    );

    if (doc == null) return null;
    if (doc.notModified) {
      return SourceDocument(
        body: '',
        validators: doc.validators,
        notModified: true,
        rateLimit: doc.rateLimit,
      );
    }

    // The manifest declares what this file should hash to, so check it. The
    // hash used to serve only as a change-detection key: a file that did not
    // match was downloaded and applied anyway, and then its *declared* hash was
    // recorded as applied — so the corruption stuck and the file was never
    // fetched again.
    //
    // JSON parsing catches a truncated body, but not a body that is valid JSON
    // and simply not the one the publisher signed: a stale CDN edge, a
    // half-finished upload, a wrong file at the right path.
    final declared = entry?.sha256;
    if (declared != null && declared.isNotEmpty) {
      final actual = sha256.convert(utf8.encode(doc.body)).toString();
      // Case-insensitive: hex digests are written both ways in the wild.
      if (actual.toLowerCase() != declared.toLowerCase()) {
        throw SyncException(
          SyncFailureKind.checksumMismatch,
          sourceName: sourceName,
          message:
              '$path: manifest는 $declared 를 선언했는데 '
              '받은 파일은 $actual 입니다.',
        );
      }
    }

    // Only record the hash once the body is in hand *and verified*; the caller
    // commits it after a successful transaction via [commitApplied].
    _pendingHashes[key] = declared;
    _pendingValidators[key] = doc.validators;

    return SourceDocument(
      body: doc.body,
      validators: doc.validators,
      rateLimit: doc.rateLimit,
    );
  }

  final Map<String, String?> _pendingHashes = {};
  final Map<String, SyncValidators> _pendingValidators = {};

  /// Persist cache validators only after the data was committed to SQLite.
  ///
  /// Saving them earlier would let a crash mid-transaction convince the next
  /// launch that a file had already been applied when it had not.
  Future<void> commitApplied() async {
    for (final entry in _pendingValidators.entries) {
      await _store.save(
        entry.key,
        entry.value,
        sha256: _pendingHashes[entry.key],
      );
    }
    _pendingHashes.clear();
    _pendingValidators.clear();
  }

  /// Throw away uncommitted validators after a failed transaction.
  void discardPending() {
    _pendingHashes.clear();
    _pendingValidators.clear();
  }

  String _validatorKey(String path) => '$sourceName|${config.baseUrl}|$path';
}
