import '../dto/dtos.dart';
import '../sync/sync_contracts.dart';
import 'payload_envelope.dart';
import 'sports_data_source.dart';

/// Canonical layout of the published data set.
///
/// The *only* place file paths are written down. Screens, repositories, and
/// the sync engine refer to entity types; this class turns an entity type plus
/// a scope into a path. Swapping the static layout for API endpoints means
/// replacing this resolution step inside one adapter, nothing else.
class DataPaths {
  const DataPaths._();

  static const String version = 'version.json';
  static const String organizations = 'organizations.json';
  static const String teams = 'teams.json';
  static const String venues = 'venues.json';
  static const String people = 'people.json';
  static const String roster = 'roster.json';
  static const String news = 'content/news.json';
  static const String videos = 'content/videos.json';

  static const String competitionsPrefix = 'competitions/';
  static const String gamesPrefix = 'games/';
  static const String standingsPrefix = 'standings/';

  /// `competitions/2026.json`
  static String competitionsForYear(int year) =>
      '$competitionsPrefix$year.json';

  /// `games/2026-08.json`
  static String gamesForMonth(String month) => '$gamesPrefix$month.json';

  /// `standings/<seasonId>.json`
  static String standingsForSeason(String seasonId) =>
      '$standingsPrefix$seasonId.json';

  /// Fixed documents that always exist in a complete data set.
  static const List<String> singletons = <String>[
    organizations,
    teams,
    venues,
    people,
    roster,
    news,
    videos,
  ];
}

/// One fetched document plus its cache validators.
class SourceDocument {
  const SourceDocument({
    required this.body,
    this.validators = const SyncValidators(),
    this.notModified = false,
    this.rateLimit,
  });

  final String body;
  final SyncValidators validators;

  /// 304 — the caller must preserve, not clear, what it already has.
  final bool notModified;

  final RateLimitInfo? rateLimit;

  static const SourceDocument unchangedMarker = SourceDocument(
    body: '',
    notModified: true,
  );
}

/// Base for any source whose records arrive as [PayloadEnvelope] documents.
///
/// Subclasses only implement transport — read an asset, do an HTTP GET, call a
/// fake in-memory server. Everything downstream of the raw bytes (envelope
/// parsing, schema-version gating, per-record quarantine, tombstones,
/// pagination metadata) is shared here, which is what makes different
/// transports provably equivalent for the same input.
abstract base class JsonDocumentDataSource extends BaseSportsDataSource {
  const JsonDocumentDataSource();

  /// Fetch one document. Return `null` when the document simply does not exist
  /// for this source (e.g. no standings file for a season), which is not an
  /// error. Throw [SyncException] for real transport failures.
  Future<SourceDocument?> loadDocument(String path, SyncValidators validators);

  /// Contract-version gate, supplied by config.
  bool supportsSchemaVersion(int schemaVersion);

  /// Which months / seasons / years this source should be asked for.
  /// Overridden by the manifest source, which learns them from `version.json`.
  Future<List<String>> availableGameMonths() async => const <String>[];

  Future<List<int>> availableCompetitionYears() async => const <int>[];

  Future<List<String>> availableStandingSeasons() async => const <String>[];

  @override
  Set<SyncEntityType> get supportedEntities => SyncEntityType.values.toSet();

  Future<SyncPage<T>> _page<T>({
    required String path,
    required SyncEntityType entityType,
    required T Function(Object?) parse,
    required SyncRequest request,
  }) async {
    final SourceDocument? doc;
    try {
      doc = await loadDocument(path, request.validators);
    } on SyncException {
      rethrow;
    } on PayloadFormatException catch (e) {
      throw SyncException(
        SyncFailureKind.malformedPayload,
        sourceName: sourceName,
        message: e.message,
      );
    }

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
      supports: supportsSchemaVersion,
      validators: doc.validators,
      rateLimit: doc.rateLimit,
    );
  }

  /// Reads several documents and concatenates them into one logical page.
  /// Used where the published layout partitions an entity across files but the
  /// engine wants a single stream (competitions by year, standings by season).
  Future<SyncPage<T>> _mergedPages<T>({
    required List<String> paths,
    required SyncEntityType entityType,
    required T Function(Object?) parse,
    required SyncRequest request,
  }) async {
    if (paths.isEmpty) return SyncPage.empty<T>(sourceName);

    final items = <T>[];
    final issues = <SyncIssue>[];
    final tombstones = <String>[];
    var kind = SyncPayloadKind.delta;
    String? dataVersion;
    DateTime? generatedAt;
    var sawAnything = false;
    var allUnchanged = true;

    for (final path in paths) {
      final page = await _page<T>(
        path: path,
        entityType: entityType,
        parse: parse,
        request: request,
      );
      if (page.notModified) continue;
      allUnchanged = false;
      sawAnything = true;
      items.addAll(page.items);
      issues.addAll(page.issues);
      tombstones.addAll(page.tombstonedSourceRecordIds);
      // A merged result is only a snapshot if every part was one; otherwise
      // treating it as a snapshot would tombstone records the delta parts
      // never spoke about.
      if (page.payloadKind == SyncPayloadKind.snapshot &&
          kind == SyncPayloadKind.delta) {
        kind = paths.length == 1 ? SyncPayloadKind.snapshot : kind;
      }
      dataVersion ??= page.dataVersion;
      generatedAt ??= page.generatedAt;
    }

    if (!sawAnything && allUnchanged) {
      return SyncPage.unchanged<T>(sourceName, request.validators);
    }

    return SyncPage<T>(
      items: items,
      sourceName: sourceName,
      payloadKind: paths.length == 1 ? kind : SyncPayloadKind.snapshot,
      schemaVersion: 1,
      dataVersion: dataVersion,
      issues: issues,
      generatedAt: generatedAt,
      tombstonedSourceRecordIds: tombstones,
    );
  }

  @override
  Future<SyncPage<OrganizationDto>> fetchOrganizations(SyncRequest request) =>
      _page<OrganizationDto>(
        path: DataPaths.organizations,
        entityType: SyncEntityType.organization,
        parse: OrganizationDto.fromJson,
        request: request,
      );

  @override
  Future<SyncPage<TeamDto>> fetchTeams(SyncRequest request) => _page<TeamDto>(
    path: DataPaths.teams,
    entityType: SyncEntityType.team,
    parse: TeamDto.fromJson,
    request: request,
  );

  @override
  Future<SyncPage<VenueDto>> fetchVenues(SyncRequest request) =>
      _page<VenueDto>(
        path: DataPaths.venues,
        entityType: SyncEntityType.venue,
        parse: VenueDto.fromJson,
        request: request,
      );

  @override
  Future<SyncPage<PersonDto>> fetchPeople(SyncRequest request) =>
      _page<PersonDto>(
        path: DataPaths.people,
        entityType: SyncEntityType.person,
        parse: PersonDto.fromJson,
        request: request,
      );

  @override
  Future<SyncPage<RosterEntryDto>> fetchRoster(SyncRequest request) =>
      _page<RosterEntryDto>(
        path: DataPaths.roster,
        entityType: SyncEntityType.rosterEntry,
        parse: RosterEntryDto.fromJson,
        request: request,
      );

  @override
  Future<SyncPage<ArticleDto>> fetchArticles(SyncRequest request) =>
      _page<ArticleDto>(
        path: DataPaths.news,
        entityType: SyncEntityType.article,
        parse: ArticleDto.fromJson,
        request: request,
      );

  @override
  Future<SyncPage<VideoDto>> fetchVideos(SyncRequest request) =>
      _page<VideoDto>(
        path: DataPaths.videos,
        entityType: SyncEntityType.video,
        parse: VideoDto.fromJson,
        request: request,
      );

  @override
  Future<SyncPage<CompetitionDto>> fetchCompetitions(
    SyncRequest request,
  ) async {
    final years = await availableCompetitionYears();
    final paths = years.isEmpty
        ? <String>[]
        : years.map(DataPaths.competitionsForYear).toList(growable: false);
    return _mergedPages<CompetitionDto>(
      paths: paths,
      entityType: SyncEntityType.competition,
      parse: CompetitionDto.fromJson,
      request: request,
    );
  }

  @override
  Future<SyncPage<StandingDto>> fetchStandings(SyncRequest request) async {
    final seasons = await availableStandingSeasons();
    final paths = seasons.isEmpty
        ? <String>[]
        : seasons.map(DataPaths.standingsForSeason).toList(growable: false);
    return _mergedPages<StandingDto>(
      paths: paths,
      entityType: SyncEntityType.standing,
      parse: StandingDto.fromJson,
      request: request,
    );
  }

  @override
  Future<SyncPage<GameDto>> fetchGames(GameSyncRequest request) async {
    // A month is the request's primary partition. Without one we fall back to
    // whatever the source advertises, so we never ask for "all games ever".
    final month = request.month ?? request.scopeKey;
    if (month != null) {
      return _page<GameDto>(
        path: DataPaths.gamesForMonth(month),
        entityType: SyncEntityType.game,
        parse: GameDto.fromJson,
        request: request,
      );
    }
    final months = await availableGameMonths();
    return _mergedPages<GameDto>(
      paths: months.map(DataPaths.gamesForMonth).toList(growable: false),
      entityType: SyncEntityType.game,
      parse: GameDto.fromJson,
      request: request,
    );
  }
}
