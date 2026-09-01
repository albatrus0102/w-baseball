import 'package:drift/drift.dart';

/// Provenance columns carried by every publishable entity.
///
/// Mixed into each table so "where did this come from and when did we last
/// confirm it?" is answerable for any row without a join, and so the publish
/// pipeline's required-metadata rule has a physical home.
mixin ProvenanceColumns on Table {
  TextColumn get sourceName => text()();
  TextColumn get sourceUrl => text()();
  TextColumn get sourceRecordId => text().nullable()();
  DateTimeColumn get fetchedAt => dateTime()();
  DateTimeColumn get verifiedAt => dateTime().nullable()();
  TextColumn get contentHash => text().nullable()();
  TextColumn get qualityStatus =>
      text().withDefault(const Constant('autoVerified'))();
  TextColumn get licenseStatus =>
      text().withDefault(const Constant('unknown'))();
  TextColumn get visibility => text().withDefault(const Constant('public'))();
  BoolColumn get isDemo => boolean().withDefault(const Constant(false))();

  /// Tombstone. Records that vanish upstream are marked here and hidden by
  /// policy; they are never hard-deleted, so a source glitch cannot silently
  /// erase a user's saved game.
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// Editorial metadata for content entities (recaps, story clusters, guides).
mixin ContentMetaColumns on Table {
  DateTimeColumn get publishedAt => dateTime()();
  TextColumn get summaryMethod =>
      text().withDefault(const Constant('manual'))();
  TextColumn get reviewStatus =>
      text().withDefault(const Constant('reviewed'))();
  TextColumn get spoilerLevel => text().withDefault(const Constant('none'))();
  DateTimeColumn get generatedAt => dateTime().nullable()();
  IntColumn get coverageObserved => integer().withDefault(const Constant(0))();
  IntColumn get coverageExpected => integer().withDefault(const Constant(0))();
  TextColumn get coverageNote => text().nullable()();
}

// ---------------------------------------------------------------------------
// Core sport entities
// ---------------------------------------------------------------------------

@DataClassName('OrganizationRow')
class Organizations extends Table with ProvenanceColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get shortName => text().nullable()();
  TextColumn get country => text().withDefault(const Constant('KR'))();
  TextColumn get websiteUrl => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CompetitionRow')
class Competitions extends Table with ProvenanceColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get shortName => text().nullable()();
  TextColumn get level => text().withDefault(const Constant('unknown'))();
  TextColumn get organizationId => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get regulationsUrl => text().nullable()();
  TextColumn get bracketUrl => text().nullable()();
  TextColumn get resultsUrl => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SeasonRow')
class Seasons extends Table with ProvenanceColumns {
  TextColumn get id => text()();
  TextColumn get competitionId => text()();
  IntColumn get year => integer()();
  TextColumn get name => text()();
  TextColumn get phase => text().withDefault(const Constant('unknown'))();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('StageRow')
class Stages extends Table with ProvenanceColumns {
  TextColumn get id => text()();
  TextColumn get seasonId => text()();
  TextColumn get name => text()();
  TextColumn get format => text().withDefault(const Constant('unknown'))();
  TextColumn get groupLabel => text().nullable()();
  IntColumn get ordering => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TeamRow')
class Teams extends Table with ProvenanceColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get shortName => text().nullable()();
  TextColumn get region => text().nullable()();
  TextColumn get city => text().nullable()();
  IntColumn get foundedYear => integer().nullable()();
  TextColumn get introduction => text().nullable()();
  TextColumn get recruitment => text().withDefault(const Constant('unknown'))();
  TextColumn get recruitmentTarget => text().nullable()();
  TextColumn get homeVenueId => text().nullable()();
  TextColumn get practiceArea => text().nullable()();
  TextColumn get officialUrl => text().nullable()();
  TextColumn get contactUrl => text().nullable()();
  TextColumn get logoUrl => text().nullable()();
  TextColumn get logoLicense => text().withDefault(const Constant('unknown'))();
  TextColumn get colorHex => text().nullable()();

  /// Pre-computed search key: whitespace-stripped name plus its 초성 (Korean
  /// initial consonants), so "ㅅㅇ" matches "서울". Filled by the mapper.
  TextColumn get searchKey => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TeamAliasRow')
class TeamAliases extends Table {
  TextColumn get teamId => text()();
  TextColumn get alias => text()();

  /// Case-folded, whitespace-stripped lookup form.
  TextColumn get normalized => text()();
  TextColumn get sourceName => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {teamId, normalized};
}

@DataClassName('TeamSeasonRow')
class TeamSeasons extends Table with ProvenanceColumns {
  TextColumn get id => text()();
  TextColumn get teamId => text()();
  TextColumn get seasonId => text()();
  TextColumn get stageId => text().nullable()();
  TextColumn get displayName => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Deliberately minimal. There is no column for a phone number, address,
/// e-mail, or full date of birth, so such data cannot be stored even by
/// accident.
@DataClassName('PersonRow')
class People extends Table with ProvenanceColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  BoolColumn get isMinor => boolean().withDefault(const Constant(false))();
  TextColumn get photoUrl => text().nullable()();
  TextColumn get photoLicense =>
      text().withDefault(const Constant('unknown'))();
  TextColumn get searchKey => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('PersonAliasRow')
class PersonAliases extends Table {
  TextColumn get personId => text()();
  TextColumn get alias => text()();
  TextColumn get normalized => text()();
  TextColumn get sourceName => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {personId, normalized};
}

@DataClassName('RosterEntryRow')
class RosterEntries extends Table with ProvenanceColumns {
  TextColumn get id => text()();
  TextColumn get teamSeasonId => text()();
  TextColumn get personId => text()();
  TextColumn get jerseyNumber => text().nullable()();
  TextColumn get position => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('VenueRow')
class Venues extends Table with ProvenanceColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get region => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  IntColumn get capacity => integer().nullable()();
  TextColumn get surface => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get searchKey => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('GameRow')
class Games extends Table with ProvenanceColumns {
  TextColumn get id => text()();
  TextColumn get status => text()();

  /// Always UTC. Display converts to Asia/Seoul (and to [localTimeZone] for
  /// away fixtures).
  DateTimeColumn get startTimeUtc => dateTime()();

  /// `yyyy-MM` in Asia/Seoul, denormalised so month queries hit an index
  /// instead of scanning and converting every row.
  TextColumn get monthKey => text()();

  /// `yyyy-MM-dd` in Asia/Seoul, for day grouping and the calendar board.
  TextColumn get dayKey => text()();

  TextColumn get homeTeamId => text()();
  TextColumn get awayTeamId => text()();
  TextColumn get seasonId => text().nullable()();
  TextColumn get stageId => text().nullable()();
  TextColumn get competitionId => text().nullable()();
  TextColumn get venueId => text().nullable()();
  IntColumn get homeScore => integer().nullable()();
  IntColumn get awayScore => integer().nullable()();
  TextColumn get localTimeZone =>
      text().withDefault(const Constant('Asia/Seoul'))();
  TextColumn get round => text().nullable()();
  TextColumn get summary => text().nullable()();
  TextColumn get officialDetailUrl => text().nullable()();
  TextColumn get statusNote => text().nullable()();

  /// Stable fixture identity used to collapse duplicates arriving from
  /// different sources with different ids.
  TextColumn get dedupeKey => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('GameLineScoreRow')
class GameLineScores extends Table {
  TextColumn get gameId => text()();

  /// JSON arrays of nullable ints. Null entries mean "did not bat", which is
  /// different from scoring zero.
  TextColumn get homeInnings => text()();
  TextColumn get awayInnings => text()();
  IntColumn get homeRuns => integer().nullable()();
  IntColumn get awayRuns => integer().nullable()();
  IntColumn get homeHits => integer().nullable()();
  IntColumn get awayHits => integer().nullable()();
  IntColumn get homeErrors => integer().nullable()();
  IntColumn get awayErrors => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {gameId};
}

@DataClassName('BattingStatRow')
class BattingStats extends Table {
  TextColumn get gameId => text()();
  TextColumn get personId => text()();
  TextColumn get teamId => text()();
  TextColumn get playerName => text()();
  IntColumn get battingOrder => integer().nullable()();
  TextColumn get position => text().nullable()();
  IntColumn get atBats => integer().withDefault(const Constant(0))();
  IntColumn get runs => integer().withDefault(const Constant(0))();
  IntColumn get hits => integer().withDefault(const Constant(0))();
  IntColumn get doubles => integer().withDefault(const Constant(0))();
  IntColumn get triples => integer().withDefault(const Constant(0))();
  IntColumn get homeRuns => integer().withDefault(const Constant(0))();
  IntColumn get rbi => integer().withDefault(const Constant(0))();
  IntColumn get walks => integer().withDefault(const Constant(0))();
  IntColumn get strikeouts => integer().withDefault(const Constant(0))();
  IntColumn get stolenBases => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {gameId, personId};
}

@DataClassName('PitchingStatRow')
class PitchingStats extends Table {
  TextColumn get gameId => text()();
  TextColumn get personId => text()();
  TextColumn get teamId => text()();
  TextColumn get playerName => text()();

  /// Outs, not decimal innings, so 5⅓ is exactly 16.
  IntColumn get outsRecorded => integer().withDefault(const Constant(0))();
  IntColumn get hitsAllowed => integer().withDefault(const Constant(0))();
  IntColumn get runsAllowed => integer().withDefault(const Constant(0))();
  IntColumn get earnedRuns => integer().withDefault(const Constant(0))();
  IntColumn get walks => integer().withDefault(const Constant(0))();
  IntColumn get strikeouts => integer().withDefault(const Constant(0))();
  IntColumn get homeRunsAllowed => integer().withDefault(const Constant(0))();
  TextColumn get decision => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {gameId, personId};
}

@DataClassName('StandingRowData')
class Standings extends Table with ProvenanceColumns {
  TextColumn get id => text()();
  TextColumn get seasonId => text()();
  TextColumn get stageId => text().nullable()();
  TextColumn get teamId => text()();
  DateTimeColumn get capturedAt => dateTime()();
  IntColumn get rank => integer().nullable()();
  IntColumn get played => integer().withDefault(const Constant(0))();
  IntColumn get wins => integer().withDefault(const Constant(0))();
  IntColumn get losses => integer().withDefault(const Constant(0))();
  IntColumn get draws => integer().withDefault(const Constant(0))();
  IntColumn get runsScored => integer().withDefault(const Constant(0))();
  IntColumn get runsAllowed => integer().withDefault(const Constant(0))();
  RealColumn get gamesBehind => real().nullable()();

  /// Rank at the previous capture, so the UI can show movement without
  /// re-deriving history.
  IntColumn get previousRank => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// News / video
// ---------------------------------------------------------------------------

@DataClassName('ArticleRow')
class Articles extends Table with ProvenanceColumns {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get url => text()();
  DateTimeColumn get publishedAt => dateTime()();
  TextColumn get outlet => text().nullable()();

  /// Only the snippet the search API returned. Never scraped body text.
  TextColumn get summary => text().nullable()();
  TextColumn get teamIds => text().withDefault(const Constant(''))();
  TextColumn get competitionIds => text().withDefault(const Constant(''))();
  BoolColumn get isOfficialNotice =>
      boolean().withDefault(const Constant(false))();

  /// Set once the article has been folded into a story cluster.
  TextColumn get storyClusterId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('VideoRow')
class Videos extends Table with ProvenanceColumns {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get url => text()();
  DateTimeColumn get publishedAt => dateTime()();
  TextColumn get channelName => text().nullable()();
  TextColumn get thumbnailUrl => text().nullable()();
  IntColumn get durationSeconds => integer().nullable()();
  TextColumn get teamIds => text().withDefault(const Constant(''))();
  TextColumn get competitionIds => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Discovery / editorial content
// ---------------------------------------------------------------------------

@DataClassName('FeaturedTopicRow')
class FeaturedTopics extends Table with ProvenanceColumns, ContentMetaColumns {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get title => text()();
  TextColumn get subtitle => text().nullable()();

  /// Lower wins. Null falls back to the kind's default priority, which is what
  /// makes an ended broadcast fall through to the next topic automatically.
  IntColumn get priority => integer().nullable()();
  TextColumn get programId => text().nullable()();
  TextColumn get competitionId => text().nullable()();
  TextColumn get storyClusterId => text().nullable()();
  TextColumn get guideId => text().nullable()();
  TextColumn get heroImageUrl => text().nullable()();
  TextColumn get heroImageLicense =>
      text().withDefault(const Constant('unknown'))();
  DateTimeColumn get activeFrom => dateTime().nullable()();
  DateTimeColumn get activeUntil => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ProgramRow')
class Programs extends Table with ProvenanceColumns, ContentMetaColumns {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get broadcaster => text().nullable()();
  TextColumn get officialUrl => text().nullable()();
  TextColumn get streamingUrl => text().nullable()();
  TextColumn get description => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ProgramSeasonRow')
class ProgramSeasons extends Table with ProvenanceColumns, ContentMetaColumns {
  TextColumn get id => text()();
  TextColumn get programId => text()();
  IntColumn get seasonNumber => integer()();
  TextColumn get title => text()();

  /// ISO weekday 1-7 plus minute-of-day. Enough to say "다음 방송" without
  /// inventing an episode that has not been announced.
  IntColumn get airDayOfWeek => integer().nullable()();
  IntColumn get airTimeMinuteOfDay => integer().nullable()();
  DateTimeColumn get premiereDate => dateTime().nullable()();
  DateTimeColumn get finaleDate => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('EpisodeRow')
class Episodes extends Table with ProvenanceColumns, ContentMetaColumns {
  TextColumn get id => text()();
  TextColumn get programSeasonId => text()();
  IntColumn get episodeNumber => integer()();
  TextColumn get title => text().nullable()();
  DateTimeColumn get airedAt => dateTime().nullable()();
  TextColumn get officialUrl => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('EpisodeRecapRow')
class EpisodeRecaps extends Table with ProvenanceColumns, ContentMetaColumns {
  TextColumn get id => text()();
  TextColumn get episodeId => text()();

  /// Written to be spoiler-free; shown when the user hides results.
  TextColumn get teaser => text().nullable()();
  TextColumn get whatHappened => text().nullable()();
  TextColumn get whyItMatters => text().nullable()();
  TextColumn get whatToWatchNext => text().nullable()();
  TextColumn get background => text().nullable()();
  TextColumn get realBaseballContext => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('OfficialClipRow')
class OfficialClips extends Table with ProvenanceColumns, ContentMetaColumns {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get url => text()();
  TextColumn get programSeasonId => text().nullable()();
  TextColumn get episodeId => text().nullable()();
  TextColumn get thumbnailUrl => text().nullable()();
  TextColumn get thumbnailLicense =>
      text().withDefault(const Constant('unknown'))();
  IntColumn get durationSeconds => integer().nullable()();
  TextColumn get channelName => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('StorylineRow')
class Storylines extends Table with ProvenanceColumns, ContentMetaColumns {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get summary => text().nullable()();
  TextColumn get programSeasonId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FeaturedPersonRow')
class FeaturedPeople extends Table with ProvenanceColumns, ContentMetaColumns {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  TextColumn get episodeId => text().nullable()();
  TextColumn get storylineId => text().nullable()();
  TextColumn get role => text().nullable()();
  TextColumn get whyWatch => text().nullable()();

  /// Populated only when the identity link is officially confirmed.
  TextColumn get linkedPersonId => text().nullable()();
  TextColumn get linkedTeamId => text().nullable()();
  TextColumn get photoUrl => text().nullable()();
  TextColumn get photoLicense =>
      text().withDefault(const Constant('unknown'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('StoryClusterRow')
class StoryClusters extends Table with ProvenanceColumns, ContentMetaColumns {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get shortSummary => text().nullable()();
  TextColumn get whyItMatters => text().nullable()();
  TextColumn get beginnerContext => text().nullable()();
  DateTimeColumn get firstPublishedAt => dateTime()();
  DateTimeColumn get lastUpdatedAt => dateTime()();

  /// Drives the non-personalised "모두가 알아둘 주요 소식" rail that keeps the
  /// personalised feed from becoming a filter bubble.
  BoolColumn get isTopStory => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('StorySourceRow')
class StorySources extends Table {
  TextColumn get id => text()();
  TextColumn get storyClusterId => text()();
  TextColumn get title => text()();
  TextColumn get url => text()();
  DateTimeColumn get publishedAt => dateTime()();
  TextColumn get outlet => text().nullable()();

  /// Strictly the description the news API itself supplied.
  TextColumn get apiDescription => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ContentEntityLinkRow')
class ContentEntityLinks extends Table {
  TextColumn get id => text()();
  TextColumn get fromKind => text()();
  TextColumn get fromId => text()();
  TextColumn get toKind => text()();
  TextColumn get toId => text()();
  TextColumn get relation => text()();
  TextColumn get label => text().nullable()();

  /// Required for an `isEntity` relation: an identity claim needs a citation.
  TextColumn get confirmedSourceUrl => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('BeginnerGuideRow')
class BeginnerGuides extends Table with ProvenanceColumns, ContentMetaColumns {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();

  /// Where this attaches in the UI, e.g. `stat:era`, `screen:game_detail`.
  TextColumn get anchorKey => text().nullable()();
  IntColumn get readSeconds => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AttendanceInfoRow')
class AttendanceInfos extends Table with ProvenanceColumns {
  TextColumn get gameId => text()();

  /// Defaults to `needsConfirmation`. We never infer "free and open".
  TextColumn get status =>
      text().withDefault(const Constant('needsConfirmation'))();
  TextColumn get admissionNote => text().nullable()();
  TextColumn get entryProcedure => text().nullable()();
  TextColumn get seatingNote => text().nullable()();
  TextColumn get parkingUrl => text().nullable()();
  TextColumn get transitUrl => text().nullable()();
  BoolColumn get restroomAvailable => boolean().nullable()();
  BoolColumn get concessionAvailable => boolean().nullable()();
  BoolColumn get familyFriendlyConfirmed =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get confirmedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {gameId};
}

// ---------------------------------------------------------------------------
// Weather
// ---------------------------------------------------------------------------

@DataClassName('WeatherForecastRow')
class WeatherForecasts extends Table with ProvenanceColumns {
  TextColumn get id => text()();
  TextColumn get venueId => text()();
  TextColumn get gameId => text().nullable()();
  DateTimeColumn get targetTimeUtc => dateTime()();

  /// `shortTerm` / `midTerm` / `beyondForecast`. The renderer keys off this,
  /// so a long-range row physically cannot display a daily icon.
  TextColumn get horizon => text()();
  DateTimeColumn get issuedAt => dateTime()();

  /// The meteorological service's own forecast district, preserved.
  TextColumn get forecastZone => text().nullable()();
  RealColumn get temperatureC => real().nullable()();
  RealColumn get temperatureMinC => real().nullable()();
  RealColumn get temperatureMaxC => real().nullable()();
  IntColumn get precipitationProbability => integer().nullable()();
  RealColumn get precipitationMm => real().nullable()();
  RealColumn get windSpeedMs => real().nullable()();
  IntColumn get humidityPercent => integer().nullable()();
  TextColumn get skyCondition => text().nullable()();
  TextColumn get confidence => text().withDefault(const Constant('unknown'))();

  /// Long-range wording only ("평년보다 높을 가능성"). The single field a
  /// beyond-forecast row may populate.
  TextColumn get seasonalTendency => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Identity, audit, sync bookkeeping
// ---------------------------------------------------------------------------

@DataClassName('ExternalIdentityRow')
class ExternalIdentities extends Table {
  TextColumn get sourceName => text()();
  TextColumn get entityType => text()();
  TextColumn get sourceRecordId => text()();
  TextColumn get canonicalId => text()();
  DateTimeColumn get firstSeenAt => dateTime()();
  DateTimeColumn get lastSeenAt => dateTime()();

  /// Follows a merge chain so retired ids keep resolving.
  TextColumn get mergedIntoCanonicalId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {
    sourceName,
    entityType,
    sourceRecordId,
  };
}

@DataClassName('FieldProvenanceRow')
class FieldProvenances extends Table {
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get fieldName => text()();
  TextColumn get sourceName => text()();
  TextColumn get sourceUrl => text()();
  DateTimeColumn get observedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {entityType, entityId, fieldName};
}

@DataClassName('SourcePolicyRow')
class SourcePolicies extends Table {
  TextColumn get sourceName => text()();

  /// Lower is more authoritative. Data, not code, so a new official feed can
  /// outrank an existing source without an app release.
  IntColumn get officialRank => integer().withDefault(const Constant(100))();
  BoolColumn get trustsHumanReview =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {sourceName};
}

@DataClassName('EntityRevisionRow')
class EntityRevisions extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get fieldName => text()();
  DateTimeColumn get changedAt => dateTime()();
  TextColumn get sourceName => text()();
  TextColumn get previousValue => text().nullable()();
  TextColumn get newValue => text().nullable()();

  /// `result-correction`, `schedule-change`, `rename`, `tombstone`.
  TextColumn get reason => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SyncRunRow')
class SyncRuns extends Table {
  TextColumn get id => text()();
  TextColumn get sourceName => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  IntColumn get inserted => integer().withDefault(const Constant(0))();
  IntColumn get updated => integer().withDefault(const Constant(0))();
  IntColumn get tombstoned => integer().withDefault(const Constant(0))();
  IntColumn get unchanged => integer().withDefault(const Constant(0))();
  IntColumn get pagesFetched => integer().withDefault(const Constant(0))();
  TextColumn get failureKind => text().nullable()();
  TextColumn get failureMessage => text().nullable()();
  TextColumn get dataVersion => text().nullable()();
  BoolColumn get skippedNotModified =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SyncErrorRow')
class SyncErrors extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get syncRunId => text()();
  TextColumn get sourceName => text()();
  TextColumn get entityType => text()();
  TextColumn get severity => text()();
  TextColumn get message => text()();
  TextColumn get sourceRecordId => text().nullable()();
  TextColumn get field => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
}

@DataClassName('CorrectionRow')
class Corrections extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get submittedAt => dateTime()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Device-local state (never uploaded, never tied to an identity)
// ---------------------------------------------------------------------------

@DataClassName('LocalFollowRow')
class LocalFollows extends Table {
  TextColumn get kind => text()();
  TextColumn get entityId => text()();
  DateTimeColumn get followedAt => dateTime()();

  /// Cached label so a follow still renders before its entity has synced.
  TextColumn get label => text().nullable()();
  BoolColumn get muted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {kind, entityId};
}

@DataClassName('SavedItemRow')
class SavedItems extends Table {
  TextColumn get kind => text()();
  TextColumn get entityId => text()();
  DateTimeColumn get savedAt => dateTime()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {kind, entityId};
}

/// Items the user has already seen, so the home screen can avoid re-leading
/// with something they read yesterday.
@DataClassName('SeenItemRow')
class SeenItems extends Table {
  TextColumn get kind => text()();
  TextColumn get entityId => text()();
  DateTimeColumn get seenAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {kind, entityId};
}

/// Notifications we have actually scheduled with the OS.
///
/// Tracked so a schedule change can cancel and re-schedule precisely instead
/// of leaving a stale alarm, and so a reboot / time-zone change can rebuild.
@DataClassName('ScheduledNotificationRow')
class ScheduledNotifications extends Table {
  /// The OS notification id.
  IntColumn get id => integer()();
  TextColumn get category => text()();
  TextColumn get entityKind => text()();
  TextColumn get entityId => text()();
  DateTimeColumn get scheduledForUtc => dateTime()();

  /// The game start time this alert was derived from. If the fixture moves,
  /// this no longer matches and the alert is rebuilt.
  DateTimeColumn get basisTimeUtc => dateTime().nullable()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get spoilerLevel => text().withDefault(const Constant('none'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Local-only product analytics. No personal data, no coordinates, no ids that
/// could identify a device. Read by the debug screen; never transmitted.
@DataClassName('JourneyEventRow')
class JourneyEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get occurredAt => dateTime()();

  /// Small JSON map of non-identifying properties (screen, mode, tab count).
  TextColumn get properties => text().nullable()();
}

/// A player's own 출전 일지 entry — a game she attended, in her own words.
///
/// Device-local and never uploaded, deliberately sitting here with
/// [LocalFollows] / [SavedItems] / [SeenItems] rather than among the synced
/// tables that carry `ProvenanceColumns`: nothing here was published by
/// anyone. It is the user's own record of her own game, so there is no
/// source to cite and no quality/licence status to track.
///
/// Stage 1 only — see the feature brief. Deliberately **not** a stat table:
/// no 타수/안타/타율 columns exist here (Stage 2), and nothing here is ever
/// aggregated into a ranking against anyone else.
@DataClassName('GameLogEntryRow')
class GameLogEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The KST calendar day of the game, stored as the UTC instant of that
  /// day's KST midnight (see `Kst.fromKst`) — the same convention `games`
  /// uses for its own timestamps.
  DateTimeColumn get playedAt => dateTime()();

  /// `yyyy-MM-dd` in KST — the grouping/sort key, mirroring `games.day_key`.
  TextColumn get dayKey => text()();

  /// Present only once a real fixture exists to bind to. Deliberately not a
  /// foreign key: every league fixture bundled with this build is demo data,
  /// so there is normally nothing real to reference yet. An entry stands on
  /// its free-text labels alone today; a later build can start writing this
  /// column without a migration, since it already exists.
  TextColumn get gameId => text().nullable()();

  /// Free text — 대회. There is no competition table to join against here on
  /// purpose; see `gameId`.
  TextColumn get competitionLabel => text().nullable()();

  /// Free text — 상대.
  TextColumn get opponentLabel => text().nullable()();

  /// Free text — 구장.
  TextColumn get venueLabel => text().nullable()();

  /// Comma-joined `GameLogPosition.wireValue`s, e.g. `catcher,leftField`. A
  /// personal log entry, never joined against anything, so a delimited
  /// column is enough — no junction table needed.
  TextColumn get positions => text().withDefault(const Constant(''))();

  /// `GameLogResult.wireValue`. Chosen from a fixed short list, not typed —
  /// see the feature brief's "steppers and chips" rule.
  TextColumn get result => text().withDefault(const Constant('unspecified'))();

  /// One line, in her own words. Shown only on her own screens and her own
  /// export — never search, never any surface anyone else can see. See the
  /// feature brief: a record about herself is not what the minor-safety
  /// rules for shared surfaces exist to guard against.
  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

/// Cached "how complete is this?" figures per scope.
@DataClassName('DataCoverageRow')
class DataCoverages extends Table {
  TextColumn get scopeKey => text()();
  IntColumn get observed => integer().withDefault(const Constant(0))();
  IntColumn get expected => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get computedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {scopeKey};
}

/// Key/value store for sync watermarks, ETags and file hashes.
@DataClassName('SyncStateRow')
class SyncStates extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();
  TextColumn get etag => text().nullable()();
  DateTimeColumn get lastModified => dateTime().nullable()();
  TextColumn get contentHash => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
