import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../../core/network/http_client.dart';
import '../dto/dtos.dart';
import '../sync/sync_contracts.dart';
import 'payload_envelope.dart';
import 'sports_data_source.dart';

/// Adapter for a future official REST API.
///
/// It is complete and compiled, but inert until `WB_API_TRANSPORT=rest` and
/// `WB_API_BASE_URL` are supplied — [isEnabled] returns false otherwise, and
/// the sync engine skips it without treating that as a failure.
///
/// The only thing this class does that the static-manifest source does not is
/// build a URL with query parameters. Everything after the response body —
/// envelope parsing, schema gating, per-record quarantine, tombstones,
/// pagination — is the shared code path, which is exactly why
/// `test/contract/adapter_equivalence_test.dart` can prove a REST response and
/// a static file produce identical domain objects.
///
/// See `docs/connecting-an-official-api.md` for the switch-over checklist.
final class FutureRestApiDataSource extends BaseSportsDataSource {
  FutureRestApiDataSource({
    required this.config,
    required this.contract,
    required WbHttpClient httpClient,
    this.cancelToken,
    this.authHeaderProvider,
  }) : _http = httpClient;

  final FutureApiConfig config;
  final DataContractConfig contract;
  final CancelToken? cancelToken;

  /// Supplies an Authorization header when the API needs one.
  ///
  /// Deliberately a callback, not a stored string: **no key is ever compiled
  /// into the app**. In production this would read from a short-lived token
  /// obtained by a proxy. See the secrets section of the connection guide.
  final Future<Map<String, String>> Function()? authHeaderProvider;

  final WbHttpClient _http;

  @override
  String get sourceName => 'official-api';

  @override
  String get displayName => '공식 API';

  @override
  bool get isEnabled =>
      config.transport == ApiTransport.rest && config.isConfigured;

  @override
  Set<SyncEntityType> get supportedEntities => const <SyncEntityType>{
    SyncEntityType.organization,
    SyncEntityType.team,
    SyncEntityType.competition,
    SyncEntityType.venue,
    SyncEntityType.game,
    SyncEntityType.standing,
  };

  Future<SyncPage<T>> _fetch<T>({
    required String path,
    required SyncEntityType entityType,
    required T Function(Object?) parse,
    required SyncRequest request,
    Map<String, String> extraQuery = const <String, String>{},
  }) async {
    if (!isEnabled) return SyncPage.empty<T>(sourceName);

    final query = <String, String>{
      'pageSize': '${request.pageSize}',
      if (request.cursor != null) 'cursor': request.cursor!.value,
      if (request.pageNumber != null) 'page': '${request.pageNumber}',
      // Incremental sync: the server returns only what changed since this.
      if (request.updatedSince != null)
        'updatedSince': request.updatedSince!.toUtc().toIso8601String(),
      ...extraQuery,
    };

    final uri = config.uri(path).replace(queryParameters: query);

    final headers = authHeaderProvider == null
        ? const <String, String>{}
        : await authHeaderProvider!();

    final doc = await _http.getDocument(
      uri,
      sourceName: sourceName,
      validators: request.validators,
      cancelToken: cancelToken,
      extraHeaders: headers,
    );

    if (doc == null) return SyncPage.empty<T>(sourceName);
    if (doc.notModified) {
      return SyncPage.unchanged<T>(sourceName, doc.validators);
    }

    final PayloadEnvelope envelope;
    try {
      envelope = PayloadEnvelope.decode(doc.body);
    } on PayloadFormatException catch (e) {
      throw SyncException(
        SyncFailureKind.malformedPayload,
        sourceName: sourceName,
        message: '$path: ${e.message}',
      );
    }

    return envelope.toPage<T>(
      sourceName: sourceName,
      entityType: entityType,
      parse: parse,
      supports: contract.supports,
      validators: doc.validators,
      rateLimit: doc.rateLimit,
    );
  }

  @override
  Future<SyncPage<OrganizationDto>> fetchOrganizations(SyncRequest request) =>
      _fetch<OrganizationDto>(
        path: config.organizationsPath,
        entityType: SyncEntityType.organization,
        parse: OrganizationDto.fromJson,
        request: request,
      );

  @override
  Future<SyncPage<TeamDto>> fetchTeams(SyncRequest request) => _fetch<TeamDto>(
    path: config.teamsPath,
    entityType: SyncEntityType.team,
    parse: TeamDto.fromJson,
    request: request,
  );

  @override
  Future<SyncPage<CompetitionDto>> fetchCompetitions(SyncRequest request) =>
      _fetch<CompetitionDto>(
        path: config.competitionsPath,
        entityType: SyncEntityType.competition,
        parse: CompetitionDto.fromJson,
        request: request,
      );

  @override
  Future<SyncPage<VenueDto>> fetchVenues(SyncRequest request) =>
      _fetch<VenueDto>(
        path: config.venuesPath,
        entityType: SyncEntityType.venue,
        parse: VenueDto.fromJson,
        request: request,
      );

  @override
  Future<SyncPage<GameDto>> fetchGames(GameSyncRequest request) =>
      _fetch<GameDto>(
        path: config.gamesPath,
        entityType: SyncEntityType.game,
        parse: GameDto.fromJson,
        request: request,
        extraQuery: <String, String>{
          // Scoped requests only: we never ask an API for every game it holds.
          if (request.month != null) 'month': request.month!,
          if (request.seasonId != null) 'seasonId': request.seasonId!,
          if (request.competitionId != null)
            'competitionId': request.competitionId!,
          if (request.teamId != null) 'teamId': request.teamId!,
        },
      );

  @override
  Future<SyncPage<StandingDto>> fetchStandings(SyncRequest request) =>
      _fetch<StandingDto>(
        path: config.standingsPath,
        entityType: SyncEntityType.standing,
        parse: StandingDto.fromJson,
        request: request,
      );
}

/// Adapter for a future official GraphQL API.
///
/// Present so that neither transport is baked into the app's architecture. The
/// query is built here and the response's `data.<field>` is reshaped into the
/// same [PayloadEnvelope] the REST and static paths use, so everything
/// downstream is unchanged.
final class FutureGraphqlDataSource extends BaseSportsDataSource {
  const FutureGraphqlDataSource({required this.config, required this.contract});

  final FutureApiConfig config;
  final DataContractConfig contract;

  @override
  String get sourceName => 'official-graphql';

  @override
  String get displayName => '공식 GraphQL API';

  @override
  bool get isEnabled =>
      config.transport == ApiTransport.graphql && config.isConfigured;

  @override
  Set<SyncEntityType> get supportedEntities =>
      isEnabled ? const <SyncEntityType>{SyncEntityType.game} : const {};

  /// The query shape a future schema is expected to expose. Kept here so the
  /// contract is reviewable before an API exists.
  static const String gamesQuery = r'''
query Games($month: String, $after: String, $first: Int!, $updatedSince: DateTime) {
  games(month: $month, after: $after, first: $first, updatedSince: $updatedSince) {
    pageInfo { hasNextPage endCursor }
    schemaVersion
    tombstones
    nodes {
      id status startTime homeTeamId awayTeamId competitionId seasonId venueId
      homeScore awayScore localTimeZone officialDetailUrl statusNote deletedAt
      source { sourceName sourceUrl sourceRecordId fetchedAt verifiedAt licenseStatus isDemo }
    }
  }
}
''';

  @override
  Future<SyncPage<GameDto>> fetchGames(GameSyncRequest request) async {
    // Intentionally not implemented: wiring it before a schema exists would be
    // guesswork. The switch-over guide documents exactly which two methods to
    // fill in, and the contract tests already cover the behaviour required.
    throw SyncException(
      // Not `unauthorized`: nobody denied us anything. Setting
      // `WB_API_TRANSPORT=graphql` turns this source on, and reporting the
      // resulting failure as an access problem would tell the user the
      // publisher refused them when the truth is this adapter was never built.
      SyncFailureKind.notImplemented,
      sourceName: sourceName,
      message: 'GraphQL 어댑터는 공식 스키마가 확정된 뒤 연결합니다.',
    );
  }
}
