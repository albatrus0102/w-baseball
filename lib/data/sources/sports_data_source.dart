import '../dto/dtos.dart';
import '../sync/sync_contracts.dart';

/// The single seam between the app and *any* origin of data.
///
/// Implementations exist for: bundled seed assets, a static JSON manifest,
/// manual (form) submissions, a future REST API, and a future GraphQL API.
/// Adding an official API later means writing one more implementation of this
/// interface — repositories, the sync engine, the database, and every screen
/// stay untouched. See `docs/connecting-an-official-api.md`.
///
/// Contract for implementers:
///  * Never throw for a single bad record. Drop it from `items`, add a
///    [SyncIssue] with `recordRejected`, and return the rest of the page.
///  * Throw [SyncException] only when the whole page/source failed.
///  * Return `SyncPage.unchanged(...)` on a 304 instead of an empty page, so
///    the engine can tell "nothing changed" from "everything was deleted".
///  * Set [SyncPage.payloadKind] honestly: `snapshot` licenses the engine to
///    tombstone absent records, `delta` does not.
abstract interface class SportsDataSource {
  /// Stable key used in provenance, policy lookup, circuit breaking, and logs.
  String get sourceName;

  /// Human-readable name for the settings/source screen.
  String get displayName;

  /// A source may be compiled in but switched off (licence pending, flag off).
  /// Disabled sources are skipped by the engine without being an error.
  bool get isEnabled;

  /// Entity types this source can actually serve. The engine skips the rest
  /// rather than calling a method that will only return an empty page.
  Set<SyncEntityType> get supportedEntities;

  Future<SyncPage<OrganizationDto>> fetchOrganizations(SyncRequest request);

  Future<SyncPage<TeamDto>> fetchTeams(SyncRequest request);

  Future<SyncPage<CompetitionDto>> fetchCompetitions(SyncRequest request);

  Future<SyncPage<VenueDto>> fetchVenues(SyncRequest request);

  Future<SyncPage<GameDto>> fetchGames(GameSyncRequest request);

  Future<SyncPage<StandingDto>> fetchStandings(SyncRequest request);

  Future<SyncPage<ArticleDto>> fetchArticles(SyncRequest request);

  Future<SyncPage<VideoDto>> fetchVideos(SyncRequest request);

  Future<SyncPage<PersonDto>> fetchPeople(SyncRequest request);

  Future<SyncPage<RosterEntryDto>> fetchRoster(SyncRequest request);

  /// Release sockets, file handles, etc.
  Future<void> dispose() async {}
}

/// Entity types the sync engine knows how to move.
enum SyncEntityType {
  organization,
  team,
  competition,
  venue,
  game,
  standing,
  article,
  video,
  person,
  rosterEntry;

  String get storageKey => name;

  String get labelKo => switch (this) {
    SyncEntityType.organization => '단체',
    SyncEntityType.team => '팀',
    SyncEntityType.competition => '대회',
    SyncEntityType.venue => '경기장',
    SyncEntityType.game => '경기',
    SyncEntityType.standing => '순위',
    SyncEntityType.article => '뉴스',
    SyncEntityType.video => '영상',
    SyncEntityType.person => '선수',
    SyncEntityType.rosterEntry => '로스터',
  };
}

/// Convenience base that answers "not supported" for every entity type.
///
/// Adapters override only what they can actually serve, which keeps a new
/// adapter small — a WPBL adapter that only has games and articles implements
/// two methods, not ten.
abstract base class BaseSportsDataSource implements SportsDataSource {
  const BaseSportsDataSource();

  @override
  Set<SyncEntityType> get supportedEntities => const <SyncEntityType>{};

  @override
  bool get isEnabled => true;

  @override
  String get displayName => sourceName;

  SyncPage<T> _unsupported<T>() => SyncPage.empty<T>(sourceName);

  @override
  Future<SyncPage<OrganizationDto>> fetchOrganizations(
    SyncRequest request,
  ) async => _unsupported<OrganizationDto>();

  @override
  Future<SyncPage<TeamDto>> fetchTeams(SyncRequest request) async =>
      _unsupported<TeamDto>();

  @override
  Future<SyncPage<CompetitionDto>> fetchCompetitions(
    SyncRequest request,
  ) async => _unsupported<CompetitionDto>();

  @override
  Future<SyncPage<VenueDto>> fetchVenues(SyncRequest request) async =>
      _unsupported<VenueDto>();

  @override
  Future<SyncPage<GameDto>> fetchGames(GameSyncRequest request) async =>
      _unsupported<GameDto>();

  @override
  Future<SyncPage<StandingDto>> fetchStandings(SyncRequest request) async =>
      _unsupported<StandingDto>();

  @override
  Future<SyncPage<ArticleDto>> fetchArticles(SyncRequest request) async =>
      _unsupported<ArticleDto>();

  @override
  Future<SyncPage<VideoDto>> fetchVideos(SyncRequest request) async =>
      _unsupported<VideoDto>();

  @override
  Future<SyncPage<PersonDto>> fetchPeople(SyncRequest request) async =>
      _unsupported<PersonDto>();

  @override
  Future<SyncPage<RosterEntryDto>> fetchRoster(SyncRequest request) async =>
      _unsupported<RosterEntryDto>();

  @override
  Future<void> dispose() async {}
}

/// Decodes a list of records with per-record quarantine.
///
/// Shared by every adapter so the "one bad row must not kill the page" rule is
/// implemented exactly once.
class RecordDecoder {
  const RecordDecoder({required this.sourceName, required this.entityType});

  final String sourceName;
  final SyncEntityType entityType;

  DecodeOutcome<T> decodeList<T>(
    Iterable<Object?> raw,
    T Function(Object?) parse,
  ) {
    final items = <T>[];
    final issues = <SyncIssue>[];
    for (final entry in raw) {
      try {
        items.add(parse(entry));
      } on Object catch (error) {
        issues.add(
          SyncIssue(
            severity: SyncIssueSeverity.recordRejected,
            sourceName: sourceName,
            entityType: entityType.storageKey,
            message: error.toString(),
            sourceRecordId: _peekId(entry),
          ),
        );
      }
    }
    return DecodeOutcome<T>(items: items, issues: issues);
  }

  static String? _peekId(Object? entry) {
    if (entry is Map && entry['id'] is String) return entry['id'] as String;
    return null;
  }
}

class DecodeOutcome<T> {
  const DecodeOutcome({required this.items, required this.issues});

  final List<T> items;
  final List<SyncIssue> issues;
}
