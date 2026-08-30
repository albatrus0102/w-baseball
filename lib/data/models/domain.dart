import 'package:meta/meta.dart';

import 'provenance.dart';

export 'provenance.dart';

/// Lifecycle of a game.
///
/// Cancelled / postponed / forfeit are first-class states, never collapsed
/// into a win-loss. `unknown` exists so an unrecognised upstream code is
/// preserved rather than silently mapped to `scheduled`.
enum GameStatus {
  scheduled,
  delayed,
  postponed,
  cancelled,
  live,
  finalized,
  forfeit,
  unknown;

  /// Wire value is `final`, which is a Dart reserved word, hence [finalized].
  static GameStatus parse(String? raw) => switch (raw) {
    'scheduled' => GameStatus.scheduled,
    'delayed' => GameStatus.delayed,
    'postponed' => GameStatus.postponed,
    'cancelled' => GameStatus.cancelled,
    'live' => GameStatus.live,
    'final' => GameStatus.finalized,
    'forfeit' => GameStatus.forfeit,
    _ => GameStatus.unknown,
  };

  String get wireValue => this == GameStatus.finalized ? 'final' : name;

  /// Has the game produced a result we can display as a score?
  bool get hasResult =>
      this == GameStatus.finalized || this == GameStatus.forfeit;

  /// Is the game still ahead of us on the calendar?
  bool get isUpcoming =>
      this == GameStatus.scheduled || this == GameStatus.delayed;

  /// Did the game fail to take place as scheduled?
  bool get isDisrupted =>
      this == GameStatus.postponed ||
      this == GameStatus.cancelled ||
      this == GameStatus.delayed;

  String get labelKo => switch (this) {
    GameStatus.scheduled => '예정',
    GameStatus.delayed => '지연',
    GameStatus.postponed => '연기',
    GameStatus.cancelled => '취소',
    GameStatus.live => '진행 중',
    GameStatus.finalized => '종료',
    GameStatus.forfeit => '몰수',
    GameStatus.unknown => '미확인',
  };
}

enum CompetitionLevel {
  domestic,
  international,
  unknown;

  static CompetitionLevel parse(String? raw) => switch (raw) {
    'domestic' => CompetitionLevel.domestic,
    'international' => CompetitionLevel.international,
    _ => CompetitionLevel.unknown,
  };

  String get wireValue => name;

  String get labelKo => switch (this) {
    CompetitionLevel.domestic => '국내',
    CompetitionLevel.international => '국제',
    CompetitionLevel.unknown => '기타',
  };
}

enum CompetitionPhase {
  upcoming,
  ongoing,
  completed,
  unknown;

  static CompetitionPhase parse(String? raw) => switch (raw) {
    'upcoming' => CompetitionPhase.upcoming,
    'ongoing' => CompetitionPhase.ongoing,
    'completed' => CompetitionPhase.completed,
    _ => CompetitionPhase.unknown,
  };

  String get wireValue => name;

  String get labelKo => switch (this) {
    CompetitionPhase.upcoming => '예정',
    CompetitionPhase.ongoing => '진행 중',
    CompetitionPhase.completed => '종료',
    CompetitionPhase.unknown => '미정',
  };
}

enum StageFormat {
  league,
  groupStage,
  knockout,
  friendly,
  unknown;

  static StageFormat parse(String? raw) => switch (raw) {
    'league' => StageFormat.league,
    'groupStage' => StageFormat.groupStage,
    'knockout' => StageFormat.knockout,
    'friendly' => StageFormat.friendly,
    _ => StageFormat.unknown,
  };

  String get wireValue => name;
}

enum RecruitmentStatus {
  open,
  closed,
  unknown;

  static RecruitmentStatus parse(String? raw) => switch (raw) {
    'open' => RecruitmentStatus.open,
    'closed' => RecruitmentStatus.closed,
    _ => RecruitmentStatus.unknown,
  };

  String get wireValue => name;

  String get labelKo => switch (this) {
    RecruitmentStatus.open => '모집 중',
    RecruitmentStatus.closed => '모집 안 함',
    RecruitmentStatus.unknown => '모집 정보 없음',
  };
}

/// A governing body or league (WBAK, KBSA, WBSC, WPBL).
@immutable
class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.provenance,
    this.shortName,
    this.country = 'KR',
    this.websiteUrl,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String? shortName;
  final String country;
  final String? websiteUrl;
  final Provenance provenance;

  /// Tombstone. Records vanishing upstream are marked, never hard-deleted.
  final DateTime? deletedAt;

  bool get isActive => deletedAt == null;
  String get displayName => shortName?.isNotEmpty == true ? shortName! : name;
}

/// A competition that recurs across seasons (e.g. 전국여자야구대회).
@immutable
class Competition {
  const Competition({
    required this.id,
    required this.name,
    required this.level,
    required this.provenance,
    this.organizationId,
    this.shortName,
    this.description,
    this.regulationsUrl,
    this.bracketUrl,
    this.resultsUrl,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String? shortName;
  final CompetitionLevel level;
  final String? organizationId;
  final String? description;

  /// Official documents. Opened in the shared in-app browser / PDF viewer.
  final String? regulationsUrl;
  final String? bracketUrl;
  final String? resultsUrl;

  final Provenance provenance;
  final DateTime? deletedAt;

  bool get isActive => deletedAt == null;
  String get displayName => shortName?.isNotEmpty == true ? shortName! : name;
}

/// One edition of a competition.
@immutable
class Season {
  const Season({
    required this.id,
    required this.competitionId,
    required this.year,
    required this.name,
    required this.phase,
    required this.provenance,
    this.startDate,
    this.endDate,
    this.deletedAt,
  });

  final String id;
  final String competitionId;
  final int year;
  final String name;
  final CompetitionPhase phase;
  final DateTime? startDate;
  final DateTime? endDate;
  final Provenance provenance;
  final DateTime? deletedAt;

  bool get isActive => deletedAt == null;
}

/// A round, group, or bracket step inside a season.
@immutable
class Stage {
  const Stage({
    required this.id,
    required this.seasonId,
    required this.name,
    required this.format,
    required this.provenance,
    this.groupLabel,
    this.ordering = 0,
    this.deletedAt,
  });

  final String id;
  final String seasonId;
  final String name;
  final StageFormat format;

  /// "A조", "B조" — null for a straight league.
  final String? groupLabel;
  final int ordering;
  final Provenance provenance;
  final DateTime? deletedAt;

  bool get isActive => deletedAt == null;
}

/// A club. Identified by an internal UUID, never by its name — names change.
@immutable
class Team {
  const Team({
    required this.id,
    required this.name,
    required this.provenance,
    this.shortName,
    this.region,
    this.city,
    this.foundedYear,
    this.introduction,
    this.recruitment = RecruitmentStatus.unknown,
    this.recruitmentTarget,
    this.homeVenueId,
    this.practiceArea,
    this.officialUrl,
    this.contactUrl,
    this.logoUrl,
    this.logoLicense = LicenseStatus.unknown,
    this.colorHex,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String? shortName;

  /// Broad region used by the team-finder chips ("서울", "경기", "부산" …).
  final String? region;
  final String? city;
  final int? foundedYear;
  final String? introduction;

  final RecruitmentStatus recruitment;

  /// Who the team is recruiting ("초보 환영", "20대~40대") — free text from the
  /// team itself, never inferred.
  final String? recruitmentTarget;

  final String? homeVenueId;
  final String? practiceArea;

  /// Official SNS / blog. Contact goes through this, never a personal number.
  final String? officialUrl;
  final String? contactUrl;

  /// Only rendered when [logoLicense] is [LicenseStatus.permitted]; otherwise
  /// the UI falls back to a typographic monogram.
  final String? logoUrl;
  final LicenseStatus logoLicense;

  /// Accent colour for the team, used sparingly as a 4dp rail — never as a
  /// card fill, so contrast stays predictable.
  final String? colorHex;

  final Provenance provenance;
  final DateTime? deletedAt;

  bool get isActive => deletedAt == null;
  String get displayName => shortName?.isNotEmpty == true ? shortName! : name;
  bool get isRecruiting => recruitment == RecruitmentStatus.open;
  bool get canShowLogo =>
      logoUrl != null &&
      logoUrl!.isNotEmpty &&
      logoLicense == LicenseStatus.permitted;
}

/// Alternate spellings so "서울 다이아몬드" and "서울다이아몬드" resolve to one team.
@immutable
class TeamAlias {
  const TeamAlias({
    required this.teamId,
    required this.alias,
    required this.normalized,
    this.sourceName,
  });

  final String teamId;
  final String alias;

  /// Whitespace-stripped, case-folded form used for lookup.
  final String normalized;
  final String? sourceName;
}

/// A team's participation in one season.
@immutable
class TeamSeason {
  const TeamSeason({
    required this.id,
    required this.teamId,
    required this.seasonId,
    required this.provenance,
    this.stageId,
    this.displayName,
    this.deletedAt,
  });

  final String id;
  final String teamId;
  final String seasonId;
  final String? stageId;

  /// The name the team competed under that season, if it differs from today's.
  final String? displayName;
  final Provenance provenance;
  final DateTime? deletedAt;
}

/// A person. Deliberately minimal: no phone, address, e-mail, or full date of
/// birth is modelled, so it cannot be stored or accidentally published.
@immutable
class Person {
  const Person({
    required this.id,
    required this.name,
    required this.provenance,
    this.isMinor = false,
    this.photoUrl,
    this.photoLicense = LicenseStatus.unknown,
    this.deletedAt,
  });

  final String id;
  final String name;

  /// When true the UI shows no photo and no personal profile without an
  /// explicit, recorded basis. Enforced by [canShowPhoto].
  final bool isMinor;

  final String? photoUrl;
  final LicenseStatus photoLicense;
  final Provenance provenance;
  final DateTime? deletedAt;

  bool get isActive => deletedAt == null;

  /// Minors never get a photo rendered; adults need a cleared licence.
  bool get canShowPhoto =>
      !isMinor &&
      photoUrl != null &&
      photoUrl!.isNotEmpty &&
      photoLicense == LicenseStatus.permitted;
}

@immutable
class PersonAlias {
  const PersonAlias({
    required this.personId,
    required this.alias,
    required this.normalized,
    this.sourceName,
  });

  final String personId;
  final String alias;
  final String normalized;
  final String? sourceName;
}

/// A player on a team's published roster for a season.
@immutable
class RosterEntry {
  const RosterEntry({
    required this.id,
    required this.teamSeasonId,
    required this.personId,
    required this.provenance,
    this.jerseyNumber,
    this.position,
    this.deletedAt,
  });

  final String id;
  final String teamSeasonId;
  final String personId;

  /// Kept as a string: "00" and "0" are different shirts.
  final String? jerseyNumber;
  final String? position;
  final Provenance provenance;
  final DateTime? deletedAt;
}

@immutable
class Venue {
  const Venue({
    required this.id,
    required this.name,
    required this.provenance,
    this.address,
    this.region,
    this.latitude,
    this.longitude,
    this.capacity,
    this.surface,
    this.notes,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String? address;
  final String? region;
  final double? latitude;
  final double? longitude;
  final int? capacity;
  final String? surface;
  final String? notes;
  final Provenance provenance;
  final DateTime? deletedAt;

  bool get hasCoordinates => latitude != null && longitude != null;

  /// A venue is routable if we can hand *something* to a maps app.
  bool get isRoutable => hasCoordinates || (address?.isNotEmpty ?? false);
}

/// A single game. `startTimeUtc` is always stored in UTC; the display layer
/// converts to Asia/Seoul (and optionally to a local zone for away fixtures).
@immutable
class Game {
  const Game({
    required this.id,
    required this.status,
    required this.startTimeUtc,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.provenance,
    this.seasonId,
    this.stageId,
    this.competitionId,
    this.venueId,
    this.homeScore,
    this.awayScore,
    this.localTimeZone = 'Asia/Seoul',
    this.round,
    this.summary,
    this.officialDetailUrl,
    this.statusNote,
    this.deletedAt,
  });

  final String id;
  final GameStatus status;
  final DateTime startTimeUtc;
  final String homeTeamId;
  final String awayTeamId;
  final String? seasonId;
  final String? stageId;
  final String? competitionId;
  final String? venueId;
  final int? homeScore;
  final int? awayScore;

  /// IANA zone the fixture is played in. Domestic games are Asia/Seoul; a
  /// World Cup game in Rockford carries America/Chicago so the detail screen
  /// can show local time alongside KST.
  final String localTimeZone;

  final String? round;

  /// A short factual recap, only when the source licence permits reproduction.
  final String? summary;

  /// Deep link to the official box score for this exact game.
  final String? officialDetailUrl;

  /// Free-text reason for a disrupted game ("우천 순연").
  final String? statusNote;

  final Provenance provenance;
  final DateTime? deletedAt;

  bool get isActive => deletedAt == null;
  bool get hasScore => homeScore != null && awayScore != null;

  /// Null when the game is drawn, has no score, or was not actually played.
  String? get winnerTeamId {
    if (!status.hasResult || !hasScore) return null;
    if (homeScore! > awayScore!) return homeTeamId;
    if (awayScore! > homeScore!) return awayTeamId;
    return null;
  }

  bool get isDraw => status.hasResult && hasScore && homeScore == awayScore;

  /// Deduplication key. Two records describing the same fixture must collapse
  /// even when they arrive from different sources with different ids.
  String dedupeKey() {
    final ids = <String>[homeTeamId, awayTeamId]..sort();
    final slot = startTimeUtc.toUtc().toIso8601String().substring(0, 13);
    return '${competitionId ?? '-'}|$slot|${ids.join('~')}|${venueId ?? '-'}';
  }

  Game copyWith({
    GameStatus? status,
    DateTime? startTimeUtc,
    int? homeScore,
    int? awayScore,
    String? statusNote,
    Provenance? provenance,
    DateTime? deletedAt,
  }) {
    return Game(
      id: id,
      status: status ?? this.status,
      startTimeUtc: startTimeUtc ?? this.startTimeUtc,
      homeTeamId: homeTeamId,
      awayTeamId: awayTeamId,
      seasonId: seasonId,
      stageId: stageId,
      competitionId: competitionId,
      venueId: venueId,
      homeScore: homeScore ?? this.homeScore,
      awayScore: awayScore ?? this.awayScore,
      localTimeZone: localTimeZone,
      round: round,
      summary: summary,
      officialDetailUrl: officialDetailUrl,
      statusNote: statusNote ?? this.statusNote,
      provenance: provenance ?? this.provenance,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

/// Per-inning runs plus the R/H/E totals.
@immutable
class GameLineScore {
  const GameLineScore({
    required this.gameId,
    required this.homeInnings,
    required this.awayInnings,
    this.homeRuns,
    this.awayRuns,
    this.homeHits,
    this.awayHits,
    this.homeErrors,
    this.awayErrors,
  });

  final String gameId;

  /// Null entries mean "did not bat" (the home half of a walk-off ninth), not
  /// zero — the table renders those as `-`.
  final List<int?> homeInnings;
  final List<int?> awayInnings;

  final int? homeRuns;
  final int? awayRuns;
  final int? homeHits;
  final int? awayHits;
  final int? homeErrors;
  final int? awayErrors;

  int get inningCount => homeInnings.length > awayInnings.length
      ? homeInnings.length
      : awayInnings.length;

  static int _sum(List<int?> innings) =>
      innings.fold(0, (acc, v) => acc + (v ?? 0));

  int get homeInningTotal => _sum(homeInnings);
  int get awayInningTotal => _sum(awayInnings);

  /// Validation hook: innings must add up to the stated run totals.
  bool get isInternallyConsistent {
    final h = homeRuns;
    final a = awayRuns;
    if (h != null && h != homeInningTotal) return false;
    if (a != null && a != awayInningTotal) return false;
    return true;
  }
}

@immutable
class BattingGameStat {
  const BattingGameStat({
    required this.gameId,
    required this.teamId,
    required this.personId,
    required this.playerName,
    this.battingOrder,
    this.position,
    this.atBats = 0,
    this.runs = 0,
    this.hits = 0,
    this.doubles = 0,
    this.triples = 0,
    this.homeRuns = 0,
    this.rbi = 0,
    this.walks = 0,
    this.strikeouts = 0,
    this.stolenBases = 0,
  });

  final String gameId;
  final String teamId;
  final String personId;
  final String playerName;
  final int? battingOrder;
  final String? position;
  final int atBats;
  final int runs;
  final int hits;
  final int doubles;
  final int triples;
  final int homeRuns;
  final int rbi;
  final int walks;
  final int strikeouts;
  final int stolenBases;

  double? get average => atBats == 0 ? null : hits / atBats;
}

@immutable
class PitchingGameStat {
  const PitchingGameStat({
    required this.gameId,
    required this.teamId,
    required this.personId,
    required this.playerName,
    this.outsRecorded = 0,
    this.hitsAllowed = 0,
    this.runsAllowed = 0,
    this.earnedRuns = 0,
    this.walks = 0,
    this.strikeouts = 0,
    this.homeRunsAllowed = 0,
    this.decision,
  });

  final String gameId;
  final String teamId;
  final String personId;
  final String playerName;

  /// Stored as outs so 5⅓ innings is exact (16 outs), not 5.33.
  final int outsRecorded;
  final int hitsAllowed;
  final int runsAllowed;
  final int earnedRuns;
  final int walks;
  final int strikeouts;
  final int homeRunsAllowed;

  /// 'W', 'L', 'S', 'H' or null.
  final String? decision;

  String get inningsPitchedLabel {
    final full = outsRecorded ~/ 3;
    final part = outsRecorded % 3;
    return part == 0 ? '$full' : '$full.$part';
  }

  double? get era => outsRecorded == 0 ? null : earnedRuns * 27 / outsRecorded;
}

/// A standings row captured at a point in time.
@immutable
class StandingSnapshot {
  const StandingSnapshot({
    required this.id,
    required this.seasonId,
    required this.teamId,
    required this.capturedAt,
    required this.provenance,
    this.stageId,
    this.rank,
    this.played = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.runsScored = 0,
    this.runsAllowed = 0,
    this.gamesBehind,
  });

  final String id;
  final String seasonId;
  final String? stageId;
  final String teamId;
  final DateTime capturedAt;
  final int? rank;
  final int played;
  final int wins;
  final int losses;
  final int draws;
  final int runsScored;
  final int runsAllowed;
  final double? gamesBehind;
  final Provenance provenance;

  /// Korean baseball convention: draws are excluded from the denominator.
  double? get winRate {
    final decided = wins + losses;
    return decided == 0 ? null : wins / decided;
  }

  int get runDifferential => runsScored - runsAllowed;
}

/// News metadata. We store the headline, outlet, timestamp, the short
/// description the search API itself returns, and the link. Never the article
/// body and never the outlet's images.
@immutable
class Article {
  const Article({
    required this.id,
    required this.title,
    required this.url,
    required this.publishedAt,
    required this.provenance,
    this.outlet,
    this.summary,
    this.teamIds = const <String>[],
    this.competitionIds = const <String>[],
    this.isOfficialNotice = false,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String url;
  final DateTime publishedAt;
  final String? outlet;

  /// Only the snippet supplied by the search API, never scraped body text.
  final String? summary;

  final List<String> teamIds;
  final List<String> competitionIds;

  /// True for governing-body notices, which rank above press coverage.
  final bool isOfficialNotice;

  final Provenance provenance;
  final DateTime? deletedAt;
}

@immutable
class Video {
  const Video({
    required this.id,
    required this.title,
    required this.url,
    required this.publishedAt,
    required this.provenance,
    this.channelName,
    this.thumbnailUrl,
    this.durationSeconds,
    this.teamIds = const <String>[],
    this.competitionIds = const <String>[],
    this.deletedAt,
  });

  final String id;
  final String title;
  final String url;
  final DateTime publishedAt;
  final String? channelName;

  /// YouTube thumbnails are served for embedding under the API terms; other
  /// sources fall back to a generated card.
  final String? thumbnailUrl;
  final int? durationSeconds;
  final List<String> teamIds;
  final List<String> competitionIds;
  final Provenance provenance;
  final DateTime? deletedAt;
}

/// Links an app-internal canonical id to one source's own record id.
@immutable
class ExternalIdentity {
  const ExternalIdentity({
    required this.sourceName,
    required this.entityType,
    required this.sourceRecordId,
    required this.canonicalId,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.mergedIntoCanonicalId,
  });

  final String sourceName;
  final String entityType;
  final String sourceRecordId;
  final String canonicalId;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;

  /// Set when this canonical entity was merged into another one; lookups
  /// follow the chain so old ids keep resolving.
  final String? mergedIntoCanonicalId;

  String get key => '$sourceName|$entityType|$sourceRecordId';
}

/// Audit trail for a changed field.
@immutable
class EntityRevision {
  const EntityRevision({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.fieldName,
    required this.changedAt,
    required this.sourceName,
    this.previousValue,
    this.newValue,
    this.reason,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String fieldName;
  final DateTime changedAt;
  final String sourceName;
  final String? previousValue;
  final String? newValue;

  /// e.g. `result-correction`, `schedule-change`, `rename`.
  final String? reason;
}

/// A user-submitted correction. Submitting is not publishing.
enum CorrectionStatus {
  pending,
  needsReview,
  approved,
  rejected;

  static CorrectionStatus parse(String? raw) => switch (raw) {
    'needsReview' => CorrectionStatus.needsReview,
    'approved' => CorrectionStatus.approved,
    'rejected' => CorrectionStatus.rejected,
    _ => CorrectionStatus.pending,
  };

  String get wireValue => name;

  String get labelKo => switch (this) {
    CorrectionStatus.pending => '접수됨',
    CorrectionStatus.needsReview => '검토 중',
    CorrectionStatus.approved => '반영됨',
    CorrectionStatus.rejected => '반영 안 됨',
  };
}

@immutable
class Correction {
  const Correction({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.status,
    required this.submittedAt,
    this.note,
    this.resolvedAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final CorrectionStatus status;
  final DateTime submittedAt;
  final String? note;
  final DateTime? resolvedAt;
}

// ---------------------------------------------------------------------------
// Read models
// ---------------------------------------------------------------------------

/// A game joined with everything a card needs to render. Repositories build
/// these so the UI never issues follow-up lookups per row.
@immutable
class GameCard {
  const GameCard({
    required this.game,
    required this.homeTeam,
    required this.awayTeam,
    this.venue,
    this.competition,
    this.season,
    this.isHomeFavorite = false,
    this.isAwayFavorite = false,
  });

  final Game game;
  final Team homeTeam;
  final Team awayTeam;
  final Venue? venue;
  final Competition? competition;
  final Season? season;
  final bool isHomeFavorite;
  final bool isAwayFavorite;

  bool get involvesFavorite => isHomeFavorite || isAwayFavorite;

  Team? get winner {
    final id = game.winnerTeamId;
    if (id == null) return null;
    return id == homeTeam.id ? homeTeam : awayTeam;
  }
}

/// Full game detail.
@immutable
class GameDetail {
  const GameDetail({
    required this.card,
    this.lineScore,
    this.batting = const <BattingGameStat>[],
    this.pitching = const <PitchingGameStat>[],
    this.articles = const <Article>[],
    this.videos = const <Video>[],
  });

  final GameCard card;
  final GameLineScore? lineScore;
  final List<BattingGameStat> batting;
  final List<PitchingGameStat> pitching;
  final List<Article> articles;
  final List<Video> videos;

  Game get game => card.game;

  /// Whether we hold any native box-score data. When false the detail screen
  /// shows the "official site" call to action instead of an empty table.
  bool get hasBoxScore =>
      lineScore != null || batting.isNotEmpty || pitching.isNotEmpty;
}

/// UI-independent read model for "what is my next game". Shared by the home
/// hero card and, later, an Android home-screen widget / iOS WidgetKit entry.
@immutable
class NextGameSummary {
  const NextGameSummary({required this.card, required this.isFavoriteDriven});

  final GameCard card;

  /// True when this was chosen because the user follows one of the teams.
  final bool isFavoriteDriven;
}

@immutable
class TeamDetail {
  const TeamDetail({
    required this.team,
    this.homeVenue,
    this.nextGames = const <GameCard>[],
    this.recentGames = const <GameCard>[],
    this.seasons = const <Season>[],
    this.roster = const <RosterMember>[],
    this.standings = const <StandingSnapshot>[],
    this.isFavorite = false,
  });

  final Team team;
  final Venue? homeVenue;
  final List<GameCard> nextGames;
  final List<GameCard> recentGames;
  final List<Season> seasons;
  final List<RosterMember> roster;
  final List<StandingSnapshot> standings;
  final bool isFavorite;
}

@immutable
class RosterMember {
  const RosterMember({required this.entry, required this.person});

  final RosterEntry entry;
  final Person person;
}

@immutable
class CompetitionDetail {
  const CompetitionDetail({
    required this.competition,
    required this.season,
    this.stages = const <Stage>[],
    this.standings = const <StandingRow>[],
    this.games = const <GameCard>[],
    this.isFavorite = false,
  });

  final Competition competition;
  final Season season;
  final List<Stage> stages;
  final List<StandingRow> standings;
  final List<GameCard> games;
  final bool isFavorite;
}

@immutable
class StandingRow {
  const StandingRow({
    required this.snapshot,
    required this.team,
    this.isFavorite = false,
    this.computedRank,
    this.isTied = false,
    this.sourceRankDiffers = false,
  });

  final StandingSnapshot snapshot;
  final Team team;
  final bool isFavorite;

  /// The rank this app worked out from the recorded results, using the
  /// competition's stated rule. Null when there is nothing to rank on — a team
  /// with no decided games.
  final int? computedRank;

  /// Shares its rank with another team under every stated criterion.
  final bool isTied;

  /// The source published a different rank. Shown rather than resolved: it
  /// usually means the league applies a rule we do not know about.
  final bool sourceRankDiffers;

  /// What to print in the rank column. Prefers the computed value, because
  /// that is the one whose derivation the app can explain.
  int? get displayRank => computedRank ?? snapshot.rank;

  StandingRow withRanking({
    int? computedRank,
    required bool isTied,
    required bool sourceRankDiffers,
  }) => StandingRow(
    snapshot: snapshot,
    team: team,
    isFavorite: isFavorite,
    computedRank: computedRank,
    isTied: isTied,
    sourceRankDiffers: sourceRankDiffers,
  );
}

/// One hit in unified search.
enum SearchEntityType { team, competition, person, venue }

@immutable
class SearchHit {
  const SearchHit({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
    this.score = 0,
  });

  final SearchEntityType type;
  final String id;
  final String title;
  final String? subtitle;

  /// Higher is a better match; used only for ordering.
  final int score;
}
