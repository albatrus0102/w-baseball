import 'dart:convert';

import '../dto/json_reader.dart';
import '../sync/sync_contracts.dart';
import 'sports_data_source.dart';

/// The one payload shape every source normalises into.
///
/// This is the "identical normalisation input contract" the architecture
/// requires: a bundled seed asset, a file behind a static manifest, and a
/// future REST or GraphQL response all get converted into an [PayloadEnvelope]
/// before anything else happens. Because the decode path after this point is
/// shared, a static file and an API serving the same records provably produce
/// the same domain objects — which is exactly what
/// `test/contract/adapter_equivalence_test.dart` asserts.
///
/// ```json
/// {
///   "schemaVersion": 1,
///   "dataVersion": "2026.08.30.1",
///   "generatedAt": "2026-08-30T00:00:00Z",
///   "payloadKind": "snapshot",
///   "hasMore": false,
///   "nextCursor": null,
///   "tombstones": ["wbak:game:123"],
///   "items": [ ... ]
/// }
/// ```
///
/// A bare JSON array is also accepted and treated as a single-page snapshot,
/// so hand-maintained files stay easy to edit.
class PayloadEnvelope {
  const PayloadEnvelope({
    required this.items,
    required this.schemaVersion,
    required this.payloadKind,
    this.dataVersion,
    this.generatedAt,
    this.hasMore = false,
    this.nextCursor,
    this.tombstones = const <String>[],
  });

  final List<Object?> items;
  final int schemaVersion;
  final SyncPayloadKind payloadKind;
  final String? dataVersion;
  final DateTime? generatedAt;
  final bool hasMore;
  final SyncCursor? nextCursor;
  final List<String> tombstones;

  static const _knownKeys = <String>{
    'schemaVersion',
    'dataVersion',
    'generatedAt',
    'payloadKind',
    'hasMore',
    'nextCursor',
    'tombstones',
    'items',
    'data',
    'results',
  };

  /// Parses a decoded JSON value. Throws [PayloadFormatException] when the
  /// document is not an envelope at all — that is a source-level failure, not
  /// a per-record one.
  factory PayloadEnvelope.fromJson(Object? json) {
    if (json is List) {
      return PayloadEnvelope(
        items: json,
        schemaVersion: 1,
        payloadKind: SyncPayloadKind.snapshot,
      );
    }
    if (json is! Map) {
      throw const PayloadFormatException('최상위 JSON이 object 또는 array가 아닙니다');
    }

    final r = JsonReader.of(json);

    // `items` is canonical; `data` / `results` are tolerated because common
    // API conventions use them and there is no reason to be brittle.
    Object? rawItems = json['items'] ?? json['data'] ?? json['results'];
    if (rawItems == null) {
      throw const PayloadFormatException('items 배열이 없습니다');
    }
    if (rawItems is! List) {
      throw const PayloadFormatException('items가 배열이 아닙니다');
    }

    final kindRaw = r.optionalString('payloadKind');
    final kind = switch (kindRaw) {
      'delta' => SyncPayloadKind.delta,
      'snapshot' => SyncPayloadKind.snapshot,
      // Default to delta: it is the conservative reading. Treating an unknown
      // payload as a snapshot would let it tombstone records it never claimed
      // to replace.
      _ => SyncPayloadKind.delta,
    };

    final cursor = r.optionalString('nextCursor');

    return PayloadEnvelope(
      items: rawItems,
      schemaVersion: r.optionalInt('schemaVersion') ?? 1,
      payloadKind: kind,
      dataVersion: r.optionalString('dataVersion'),
      generatedAt: r.optionalInstant('generatedAt'),
      hasMore: r.optionalBool('hasMore', fallback: cursor != null),
      nextCursor: cursor == null ? null : SyncCursor(cursor),
      tombstones: r.stringList('tombstones'),
    );
  }

  factory PayloadEnvelope.decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw PayloadFormatException('JSON 파싱 실패: ${e.message}');
    }
    return PayloadEnvelope.fromJson(decoded);
  }

  List<String> unknownKeys(Map<String, dynamic> raw) =>
      raw.keys.where((k) => !_knownKeys.contains(k)).toList(growable: false);

  /// Decode into a typed [SyncPage], quarantining bad records.
  ///
  /// [supports] is the app's contract-version check. An unsupported version
  /// raises [SyncFailureKind.schemaUnsupported] so the engine can stop the
  /// refresh *without* touching the existing cache.
  SyncPage<T> toPage<T>({
    required String sourceName,
    required SyncEntityType entityType,
    required T Function(Object?) parse,
    required bool Function(int schemaVersion) supports,
    SyncValidators validators = const SyncValidators(),
    RateLimitInfo? rateLimit,
  }) {
    if (!supports(schemaVersion)) {
      throw SyncException(
        SyncFailureKind.schemaUnsupported,
        sourceName: sourceName,
        receivedSchemaVersion: schemaVersion,
        message: '지원하지 않는 데이터 버전입니다 (schemaVersion=$schemaVersion)',
      );
    }

    final decoder = RecordDecoder(
      sourceName: sourceName,
      entityType: entityType,
    );
    final outcome = decoder.decodeList<T>(items, parse);

    return SyncPage<T>(
      items: outcome.items,
      sourceName: sourceName,
      payloadKind: payloadKind,
      hasMore: hasMore,
      nextCursor: nextCursor,
      schemaVersion: schemaVersion,
      dataVersion: dataVersion,
      validators: validators,
      rateLimit: rateLimit,
      issues: outcome.issues,
      generatedAt: generatedAt,
      tombstonedSourceRecordIds: tombstones,
    );
  }
}

/// The document itself is unusable (not JSON, wrong shape). Distinct from a
/// record-level problem, which never throws.
class PayloadFormatException implements Exception {
  const PayloadFormatException(this.message);

  final String message;

  @override
  String toString() => 'PayloadFormatException: $message';
}

/// `version.json` — the manifest that tells the app which files changed.
class DataManifest {
  const DataManifest({
    required this.schemaVersion,
    required this.dataVersion,
    required this.generatedAt,
    required this.files,
  });

  final int schemaVersion;
  final String dataVersion;
  final DateTime generatedAt;
  final List<ManifestFile> files;

  ManifestFile? fileFor(String path) {
    for (final f in files) {
      if (f.path == path) return f;
    }
    return null;
  }

  /// Every file whose path starts with [prefix] (e.g. `games/`), so the engine
  /// can pull a whole partitioned entity type without hard-coding filenames.
  List<ManifestFile> filesWithPrefix(String prefix) =>
      files.where((f) => f.path.startsWith(prefix)).toList(growable: false);

  factory DataManifest.fromJson(Object? json) {
    if (json is! Map) {
      throw const PayloadFormatException('version.json이 object가 아닙니다');
    }
    final r = JsonReader.of(json);
    final rawFiles = json['files'];
    if (rawFiles is! List) {
      throw const PayloadFormatException('version.json에 files 배열이 없습니다');
    }
    final files = <ManifestFile>[];
    for (final entry in rawFiles) {
      if (entry is! Map) continue;
      final fr = JsonReader.of(entry);
      final path = fr.optionalString('path');
      if (path == null) continue;
      files.add(
        ManifestFile(
          path: path,
          sha256: fr.optionalString('sha256'),
          size: fr.optionalInt('size'),
          etag: fr.optionalString('etag'),
          updatedAt: fr.optionalInstant('updatedAt'),
        ),
      );
    }

    final dataVersion = r.optionalString('dataVersion');
    final generatedAt = r.optionalInstant('generatedAt');
    if (dataVersion == null || generatedAt == null) {
      throw const PayloadFormatException(
        'version.json에 dataVersion 또는 generatedAt이 없습니다',
      );
    }

    return DataManifest(
      schemaVersion: r.optionalInt('schemaVersion') ?? 1,
      dataVersion: dataVersion,
      generatedAt: generatedAt,
      files: files,
    );
  }

  factory DataManifest.decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw PayloadFormatException('version.json 파싱 실패: ${e.message}');
    }
    return DataManifest.fromJson(decoded);
  }
}

class ManifestFile {
  const ManifestFile({
    required this.path,
    this.sha256,
    this.size,
    this.etag,
    this.updatedAt,
  });

  final String path;

  /// Content hash. When it matches what we already downloaded we skip the
  /// request entirely — cheaper than a conditional GET.
  final String? sha256;

  final int? size;
  final String? etag;
  final DateTime? updatedAt;

  /// True when the publisher's hash differs from the one we stored.
  bool changedFrom(String? knownSha256) {
    if (sha256 == null || knownSha256 == null) return true;
    return sha256 != knownSha256;
  }
}
