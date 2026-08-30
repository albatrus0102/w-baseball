import 'dart:convert';

import '../../../core/config/app_config.dart';
import '../../dto/dtos.dart';
import '../../sync/sync_contracts.dart';
import '../payload_envelope.dart';
import '../sports_data_source.dart';

/// An in-memory stand-in for the future official API.
///
/// It exists so the app's API-readiness can be *proved* rather than asserted.
/// It serves the same fixture files the static-manifest source reads, but
/// paginated, incremental, and capable of returning every failure mode a real
/// API produces — 401/403/404/429/500, timeouts, malformed records, an
/// unsupported schema version, duplicate deliveries, and tombstones.
///
/// `test/contract/adapter_equivalence_test.dart` runs the same fixture through
/// this source and through the static-manifest source and asserts the domain
/// results are byte-identical.
final class FakeRestApiDataSource extends BaseSportsDataSource {
  FakeRestApiDataSource({
    required this.documents,
    required this.contract,
    this.pageSize = 2,
    this.failures = const <FakeApiFailure>[],
    this.schemaVersionOverride,
    this.tombstones = const <String>[],
    this.payloadKindOverride,
    this.name = 'fake-api',
  });

  /// Raw JSON documents keyed by logical path, e.g. `teams.json`.
  final Map<String, String> documents;

  final DataContractConfig contract;

  /// Deliberately tiny so tests exercise multi-page traversal.
  final int pageSize;

  /// Scripted failures, consumed in order.
  final List<FakeApiFailure> failures;

  /// Forces a schema version the app may not support.
  final int? schemaVersionOverride;

  final List<String> tombstones;

  /// Forces a payload kind regardless of what the document declares. Normally
  /// null, so the envelope's own `payloadKind` is honoured — a delta document
  /// must stay a delta, or the engine would wrongly tombstone what it omits.
  final SyncPayloadKind? payloadKindOverride;

  final String name;

  int _failureIndex = 0;

  /// Every request the engine made, so tests can assert on pagination and
  /// incremental behaviour rather than only on the end state.
  final List<String> requestLog = <String>[];

  @override
  String get sourceName => name;

  @override
  Set<SyncEntityType> get supportedEntities => const <SyncEntityType>{
    SyncEntityType.organization,
    SyncEntityType.team,
    SyncEntityType.competition,
    SyncEntityType.venue,
    SyncEntityType.game,
    SyncEntityType.standing,
    SyncEntityType.article,
    SyncEntityType.video,
  };

  void _maybeFail(String path) {
    if (_failureIndex >= failures.length) return;
    final failure = failures[_failureIndex];
    if (failure.path != null && failure.path != path) return;
    _failureIndex++;
    throw SyncException(
      failure.kind,
      sourceName: sourceName,
      statusCode: failure.statusCode,
      retryAfter: failure.retryAfter,
      message: failure.message,
    );
  }

  Future<SyncPage<T>> _page<T>({
    required String path,
    required SyncEntityType entityType,
    required T Function(Object?) parse,
    required SyncRequest request,
  }) async {
    requestLog.add(
      '$path?page=${request.pageNumber ?? '-'}'
      '&cursor=${request.cursor?.value ?? '-'}'
      '&since=${request.updatedSince?.toIso8601String() ?? '-'}',
    );

    _maybeFail(path);

    final body = documents[path];
    if (body == null) return SyncPage.empty<T>(sourceName);

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (e) {
      throw SyncException(
        SyncFailureKind.malformedPayload,
        sourceName: sourceName,
        message: e.message,
      );
    }

    final envelope = PayloadEnvelope.fromJson(decoded);
    var items = envelope.items;

    // Incremental: drop anything not newer than the watermark, the way a real
    // API would filter server-side.
    final since = request.updatedSince;
    if (since != null) {
      items = items.where((item) {
        if (item is! Map) return true;
        final source = item['source'];
        final raw = source is Map ? source['fetchedAt'] : null;
        final fetchedAt = raw is String ? DateTime.tryParse(raw) : null;
        if (fetchedAt == null) return true;
        return fetchedAt.toUtc().isAfter(since);
      }).toList();
    }

    // Cursor is simply the offset, encoded, so the traversal is inspectable.
    final offset =
        int.tryParse(request.cursor?.value ?? '') ??
        ((request.pageNumber ?? 1) - 1) * pageSize;
    final end = (offset + pageSize).clamp(0, items.length);
    final slice = offset >= items.length
        ? const <Object?>[]
        : items.sublist(offset, end);
    final hasMore = end < items.length;

    final schemaVersion = schemaVersionOverride ?? envelope.schemaVersion;
    if (!contract.supports(schemaVersion)) {
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
    final outcome = decoder.decodeList<T>(slice, parse);

    return SyncPage<T>(
      items: outcome.items,
      sourceName: sourceName,
      // Only the final page of a snapshot may carry snapshot semantics, or a
      // partial page would tombstone everything it did not contain.
      payloadKind: hasMore
          ? SyncPayloadKind.delta
          : (payloadKindOverride ?? envelope.payloadKind),
      hasMore: hasMore,
      nextCursor: hasMore ? SyncCursor('$end') : null,
      schemaVersion: schemaVersion,
      dataVersion: envelope.dataVersion,
      issues: outcome.issues,
      generatedAt: envelope.generatedAt,
      tombstonedSourceRecordIds: hasMore ? const <String>[] : tombstones,
    );
  }

  @override
  Future<SyncPage<OrganizationDto>> fetchOrganizations(SyncRequest request) =>
      _page<OrganizationDto>(
        path: 'organizations.json',
        entityType: SyncEntityType.organization,
        parse: OrganizationDto.fromJson,
        request: request,
      );

  @override
  Future<SyncPage<TeamDto>> fetchTeams(SyncRequest request) => _page<TeamDto>(
    path: 'teams.json',
    entityType: SyncEntityType.team,
    parse: TeamDto.fromJson,
    request: request,
  );

  @override
  Future<SyncPage<VenueDto>> fetchVenues(SyncRequest request) =>
      _page<VenueDto>(
        path: 'venues.json',
        entityType: SyncEntityType.venue,
        parse: VenueDto.fromJson,
        request: request,
      );

  @override
  Future<SyncPage<CompetitionDto>> fetchCompetitions(SyncRequest request) {
    final path = documents.keys.firstWhere(
      (k) => k.startsWith('competitions/'),
      orElse: () => 'competitions/none.json',
    );
    return _page<CompetitionDto>(
      path: path,
      entityType: SyncEntityType.competition,
      parse: CompetitionDto.fromJson,
      request: request,
    );
  }

  @override
  Future<SyncPage<GameDto>> fetchGames(GameSyncRequest request) {
    final month = request.month ?? request.scopeKey;
    final path = month == null
        ? documents.keys.firstWhere(
            (k) => k.startsWith('games/'),
            orElse: () => 'games/none.json',
          )
        : 'games/$month.json';
    return _page<GameDto>(
      path: path,
      entityType: SyncEntityType.game,
      parse: GameDto.fromJson,
      request: request,
    );
  }

  @override
  Future<SyncPage<StandingDto>> fetchStandings(SyncRequest request) {
    final path = documents.keys.firstWhere(
      (k) => k.startsWith('standings/'),
      orElse: () => 'standings/none.json',
    );
    return _page<StandingDto>(
      path: path,
      entityType: SyncEntityType.standing,
      parse: StandingDto.fromJson,
      request: request,
    );
  }

  @override
  Future<SyncPage<ArticleDto>> fetchArticles(SyncRequest request) =>
      _page<ArticleDto>(
        path: 'content/news.json',
        entityType: SyncEntityType.article,
        parse: ArticleDto.fromJson,
        request: request,
      );

  @override
  Future<SyncPage<VideoDto>> fetchVideos(SyncRequest request) =>
      _page<VideoDto>(
        path: 'content/videos.json',
        entityType: SyncEntityType.video,
        parse: VideoDto.fromJson,
        request: request,
      );
}

/// One scripted failure.
class FakeApiFailure {
  const FakeApiFailure(
    this.kind, {
    this.path,
    this.statusCode,
    this.retryAfter,
    this.message,
  });

  final SyncFailureKind kind;

  /// Restrict the failure to one document; null matches the next request.
  final String? path;

  final int? statusCode;
  final Duration? retryAfter;
  final String? message;

  static const FakeApiFailure unauthorized = FakeApiFailure(
    SyncFailureKind.unauthorized,
    statusCode: 401,
  );
  static const FakeApiFailure forbidden = FakeApiFailure(
    SyncFailureKind.forbidden,
    statusCode: 403,
  );
  static const FakeApiFailure notFound = FakeApiFailure(
    SyncFailureKind.notFound,
    statusCode: 404,
  );
  static const FakeApiFailure rateLimited = FakeApiFailure(
    SyncFailureKind.rateLimited,
    statusCode: 429,
    retryAfter: Duration(seconds: 30),
  );
  static const FakeApiFailure serverError = FakeApiFailure(
    SyncFailureKind.serverError,
    statusCode: 500,
  );
  static const FakeApiFailure timeout = FakeApiFailure(SyncFailureKind.timeout);
}

/// Serves documents from an in-memory map, standing in for a static host.
///
/// Used alongside [FakeRestApiDataSource] in the equivalence test: same bytes,
/// two transports.
class InMemoryDocumentSource {
  const InMemoryDocumentSource(this.documents);

  final Map<String, String> documents;

  String? read(String path) => documents[path];
}
