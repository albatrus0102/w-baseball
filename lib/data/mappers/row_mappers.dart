import 'dart:convert';

import '../../core/database/database.dart';
import '../models/audience.dart';
import '../models/content.dart';
import '../models/domain.dart';
import '../models/game_log.dart';
import '../models/weather.dart';

/// Database row → domain model.
///
/// Kept separate from the DTO mappers on purpose: the three layers (wire DTO,
/// storage row, domain model) are allowed to diverge, and every crossing is an
/// explicit function rather than a shared class doing double duty.
extension OrganizationRowMapper on OrganizationRow {
  Organization toDomain() => Organization(
    id: id,
    name: name,
    shortName: shortName,
    country: country,
    websiteUrl: websiteUrl,
    deletedAt: deletedAt,
    provenance: _provenance(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
    ),
  );
}

extension CompetitionRowMapper on CompetitionRow {
  Competition toDomain() => Competition(
    id: id,
    name: name,
    shortName: shortName,
    level: CompetitionLevel.parse(level),
    organizationId: organizationId,
    description: description,
    regulationsUrl: regulationsUrl,
    bracketUrl: bracketUrl,
    resultsUrl: resultsUrl,
    deletedAt: deletedAt,
    provenance: _provenance(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
    ),
  );
}

extension SeasonRowMapper on SeasonRow {
  Season toDomain() => Season(
    id: id,
    competitionId: competitionId,
    year: year,
    name: name,
    phase: CompetitionPhase.parse(phase),
    startDate: startDate,
    endDate: endDate,
    deletedAt: deletedAt,
    provenance: _provenance(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
    ),
  );
}

extension StageRowMapper on StageRow {
  Stage toDomain() => Stage(
    id: id,
    seasonId: seasonId,
    name: name,
    format: StageFormat.parse(format),
    groupLabel: groupLabel,
    ordering: ordering,
    deletedAt: deletedAt,
    provenance: _provenance(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
    ),
  );
}

extension TeamRowMapper on TeamRow {
  Team toDomain() => Team(
    id: id,
    name: name,
    shortName: shortName,
    region: region,
    city: city,
    foundedYear: foundedYear,
    introduction: introduction,
    recruitment: RecruitmentStatus.parse(recruitment),
    recruitmentTarget: recruitmentTarget,
    homeVenueId: homeVenueId,
    practiceArea: practiceArea,
    officialUrl: officialUrl,
    contactUrl: contactUrl,
    logoUrl: logoUrl,
    logoLicense: LicenseStatus.parse(logoLicense),
    colorHex: colorHex,
    deletedAt: deletedAt,
    provenance: _provenance(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
    ),
  );
}

extension PersonRowMapper on PersonRow {
  Person toDomain() => Person(
    id: id,
    name: name,
    isMinor: isMinor,
    photoUrl: photoUrl,
    photoLicense: LicenseStatus.parse(photoLicense),
    deletedAt: deletedAt,
    provenance: _provenance(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
    ),
  );
}

extension RosterEntryRowMapper on RosterEntryRow {
  RosterEntry toDomain() => RosterEntry(
    id: id,
    teamSeasonId: teamSeasonId,
    personId: personId,
    jerseyNumber: jerseyNumber,
    position: position,
    deletedAt: deletedAt,
    provenance: _provenance(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
    ),
  );
}

extension VenueRowMapper on VenueRow {
  Venue toDomain() => Venue(
    id: id,
    name: name,
    address: address,
    region: region,
    latitude: latitude,
    longitude: longitude,
    capacity: capacity,
    surface: surface,
    notes: notes,
    deletedAt: deletedAt,
    provenance: _provenance(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
    ),
  );
}

extension GameRowMapper on GameRow {
  Game toDomain() => Game(
    id: id,
    status: GameStatus.parse(status),
    startTimeUtc: startTimeUtc,
    homeTeamId: homeTeamId,
    awayTeamId: awayTeamId,
    seasonId: seasonId,
    stageId: stageId,
    competitionId: competitionId,
    venueId: venueId,
    homeScore: homeScore,
    awayScore: awayScore,
    localTimeZone: localTimeZone,
    round: round,
    summary: summary,
    officialDetailUrl: officialDetailUrl,
    statusNote: statusNote,
    deletedAt: deletedAt,
    provenance: _provenance(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
    ),
  );
}

extension GameLineScoreRowMapper on GameLineScoreRow {
  GameLineScore toDomain() => GameLineScore(
    gameId: gameId,
    homeInnings: decodeNullableInts(homeInnings),
    awayInnings: decodeNullableInts(awayInnings),
    homeRuns: homeRuns,
    awayRuns: awayRuns,
    homeHits: homeHits,
    awayHits: awayHits,
    homeErrors: homeErrors,
    awayErrors: awayErrors,
  );
}

extension BattingStatRowMapper on BattingStatRow {
  BattingGameStat toDomain() => BattingGameStat(
    gameId: gameId,
    teamId: teamId,
    personId: personId,
    playerName: playerName,
    battingOrder: battingOrder,
    position: position,
    atBats: atBats,
    runs: runs,
    hits: hits,
    doubles: doubles,
    triples: triples,
    homeRuns: homeRuns,
    rbi: rbi,
    walks: walks,
    strikeouts: strikeouts,
    stolenBases: stolenBases,
  );
}

extension PitchingStatRowMapper on PitchingStatRow {
  PitchingGameStat toDomain() => PitchingGameStat(
    gameId: gameId,
    teamId: teamId,
    personId: personId,
    playerName: playerName,
    outsRecorded: outsRecorded,
    hitsAllowed: hitsAllowed,
    runsAllowed: runsAllowed,
    earnedRuns: earnedRuns,
    walks: walks,
    strikeouts: strikeouts,
    homeRunsAllowed: homeRunsAllowed,
    decision: decision,
  );
}

extension StandingRowMapper on StandingRowData {
  StandingSnapshot toDomain() => StandingSnapshot(
    id: id,
    seasonId: seasonId,
    stageId: stageId,
    teamId: teamId,
    capturedAt: capturedAt,
    rank: rank,
    played: played,
    wins: wins,
    losses: losses,
    draws: draws,
    runsScored: runsScored,
    runsAllowed: runsAllowed,
    gamesBehind: gamesBehind,
    provenance: _provenance(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
    ),
  );
}

extension ArticleRowMapper on ArticleRow {
  Article toDomain() => Article(
    id: id,
    title: title,
    url: url,
    publishedAt: publishedAt,
    outlet: outlet,
    summary: summary,
    teamIds: decodeIdList(teamIds),
    competitionIds: decodeIdList(competitionIds),
    isOfficialNotice: isOfficialNotice,
    deletedAt: deletedAt,
    provenance: _provenance(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
    ),
  );
}

extension VideoRowMapper on VideoRow {
  Video toDomain() => Video(
    id: id,
    title: title,
    url: url,
    publishedAt: publishedAt,
    channelName: channelName,
    thumbnailUrl: thumbnailUrl,
    durationSeconds: durationSeconds,
    teamIds: decodeIdList(teamIds),
    competitionIds: decodeIdList(competitionIds),
    deletedAt: deletedAt,
    provenance: _provenance(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
    ),
  );
}

// ---------------------------------------------------------------------------
// Content
// ---------------------------------------------------------------------------

extension FeaturedTopicRowMapper on FeaturedTopicRow {
  FeaturedTopic toDomain() => FeaturedTopic(
    id: id,
    kind: FeaturedTopicKind.parse(kind),
    title: title,
    subtitle: subtitle,
    priority: priority,
    programId: programId,
    competitionId: competitionId,
    storyClusterId: storyClusterId,
    guideId: guideId,
    heroImageUrl: heroImageUrl,
    heroImageLicense: LicenseStatus.parse(heroImageLicense),
    activeFrom: activeFrom,
    activeUntil: activeUntil,
    deletedAt: deletedAt,
    meta: _contentMeta(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
      publishedAt: publishedAt,
      summaryMethod: summaryMethod,
      reviewStatus: reviewStatus,
      spoilerLevel: spoilerLevel,
      generatedAt: generatedAt,
      coverageObserved: coverageObserved,
      coverageExpected: coverageExpected,
      coverageNote: coverageNote,
    ),
  );
}

extension ProgramRowMapper on ProgramRow {
  Program toDomain() => Program(
    id: id,
    title: title,
    broadcaster: broadcaster,
    officialUrl: officialUrl,
    streamingUrl: streamingUrl,
    description: description,
    deletedAt: deletedAt,
    meta: _contentMeta(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
      publishedAt: publishedAt,
      summaryMethod: summaryMethod,
      reviewStatus: reviewStatus,
      spoilerLevel: spoilerLevel,
      generatedAt: generatedAt,
      coverageObserved: coverageObserved,
      coverageExpected: coverageExpected,
      coverageNote: coverageNote,
    ),
  );
}

extension ProgramSeasonRowMapper on ProgramSeasonRow {
  ProgramSeason toDomain() => ProgramSeason(
    id: id,
    programId: programId,
    seasonNumber: seasonNumber,
    title: title,
    airDayOfWeek: airDayOfWeek,
    airTimeMinuteOfDay: airTimeMinuteOfDay,
    premiereDate: premiereDate,
    finaleDate: finaleDate,
    isActive: isActive,
    deletedAt: deletedAt,
    meta: _contentMeta(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
      publishedAt: publishedAt,
      summaryMethod: summaryMethod,
      reviewStatus: reviewStatus,
      spoilerLevel: spoilerLevel,
      generatedAt: generatedAt,
      coverageObserved: coverageObserved,
      coverageExpected: coverageExpected,
      coverageNote: coverageNote,
    ),
  );
}

extension EpisodeRowMapper on EpisodeRow {
  Episode toDomain() => Episode(
    id: id,
    programSeasonId: programSeasonId,
    episodeNumber: episodeNumber,
    title: title,
    airedAt: airedAt,
    officialUrl: officialUrl,
    deletedAt: deletedAt,
    meta: _contentMeta(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
      publishedAt: publishedAt,
      summaryMethod: summaryMethod,
      reviewStatus: reviewStatus,
      spoilerLevel: spoilerLevel,
      generatedAt: generatedAt,
      coverageObserved: coverageObserved,
      coverageExpected: coverageExpected,
      coverageNote: coverageNote,
    ),
  );
}

extension EpisodeRecapRowMapper on EpisodeRecapRow {
  EpisodeRecap toDomain() => EpisodeRecap(
    id: id,
    episodeId: episodeId,
    teaser: teaser,
    whatHappened: whatHappened,
    whyItMatters: whyItMatters,
    whatToWatchNext: whatToWatchNext,
    background: background,
    realBaseballContext: realBaseballContext,
    deletedAt: deletedAt,
    meta: _contentMeta(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
      publishedAt: publishedAt,
      summaryMethod: summaryMethod,
      reviewStatus: reviewStatus,
      spoilerLevel: spoilerLevel,
      generatedAt: generatedAt,
      coverageObserved: coverageObserved,
      coverageExpected: coverageExpected,
      coverageNote: coverageNote,
    ),
  );
}

extension OfficialClipRowMapper on OfficialClipRow {
  OfficialClip toDomain() => OfficialClip(
    id: id,
    title: title,
    url: url,
    programSeasonId: programSeasonId,
    episodeId: episodeId,
    thumbnailUrl: thumbnailUrl,
    thumbnailLicense: LicenseStatus.parse(thumbnailLicense),
    durationSeconds: durationSeconds,
    channelName: channelName,
    deletedAt: deletedAt,
    meta: _contentMeta(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
      publishedAt: publishedAt,
      summaryMethod: summaryMethod,
      reviewStatus: reviewStatus,
      spoilerLevel: spoilerLevel,
      generatedAt: generatedAt,
      coverageObserved: coverageObserved,
      coverageExpected: coverageExpected,
      coverageNote: coverageNote,
    ),
  );
}

extension FeaturedPersonRowMapper on FeaturedPersonRow {
  FeaturedPerson toDomain() => FeaturedPerson(
    id: id,
    displayName: displayName,
    episodeId: episodeId,
    storylineId: storylineId,
    role: role,
    whyWatch: whyWatch,
    linkedPersonId: linkedPersonId,
    linkedTeamId: linkedTeamId,
    photoUrl: photoUrl,
    photoLicense: LicenseStatus.parse(photoLicense),
    deletedAt: deletedAt,
    meta: _contentMeta(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
      publishedAt: publishedAt,
      summaryMethod: summaryMethod,
      reviewStatus: reviewStatus,
      spoilerLevel: spoilerLevel,
      generatedAt: generatedAt,
      coverageObserved: coverageObserved,
      coverageExpected: coverageExpected,
      coverageNote: coverageNote,
    ),
  );
}

extension StoryClusterRowMapper on StoryClusterRow {
  StoryCluster toDomain({
    List<StorySource> sources = const <StorySource>[],
    List<ContentEntityLink> links = const <ContentEntityLink>[],
  }) => StoryCluster(
    id: id,
    title: title,
    shortSummary: shortSummary,
    whyItMatters: whyItMatters,
    beginnerContext: beginnerContext,
    firstPublishedAt: firstPublishedAt,
    lastUpdatedAt: lastUpdatedAt,
    isTopStory: isTopStory,
    sources: sources,
    links: links,
    deletedAt: deletedAt,
    meta: _contentMeta(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
      publishedAt: publishedAt,
      summaryMethod: summaryMethod,
      reviewStatus: reviewStatus,
      spoilerLevel: spoilerLevel,
      generatedAt: generatedAt,
      coverageObserved: coverageObserved,
      coverageExpected: coverageExpected,
      coverageNote: coverageNote,
    ),
  );
}

extension StorySourceRowMapper on StorySourceRow {
  StorySource toDomain() => StorySource(
    id: id,
    storyClusterId: storyClusterId,
    title: title,
    url: url,
    publishedAt: publishedAt,
    outlet: outlet,
    apiDescription: apiDescription,
  );
}

extension ContentEntityLinkRowMapper on ContentEntityLinkRow {
  ContentEntityLink toDomain() => ContentEntityLink(
    id: id,
    fromKind: ContentEntityKind.parse(fromKind),
    fromId: fromId,
    toKind: ContentEntityKind.parse(toKind),
    toId: toId,
    relation: ContentLinkRelation.parse(relation),
    label: label,
    confirmedSourceUrl: confirmedSourceUrl,
  );
}

extension BeginnerGuideRowMapper on BeginnerGuideRow {
  BeginnerGuide toDomain() => BeginnerGuide(
    id: id,
    kind: GuideKind.parse(kind),
    title: title,
    body: body,
    anchorKey: anchorKey,
    readSeconds: readSeconds,
    deletedAt: deletedAt,
    meta: _contentMeta(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
      publishedAt: publishedAt,
      summaryMethod: summaryMethod,
      reviewStatus: reviewStatus,
      spoilerLevel: spoilerLevel,
      generatedAt: generatedAt,
      coverageObserved: coverageObserved,
      coverageExpected: coverageExpected,
      coverageNote: coverageNote,
    ),
  );
}

extension AttendanceInfoRowMapper on AttendanceInfoRow {
  AttendanceInfo toDomain() => AttendanceInfo(
    gameId: gameId,
    status: AttendanceStatus.parse(status),
    admissionNote: admissionNote,
    entryProcedure: entryProcedure,
    seatingNote: seatingNote,
    parkingUrl: parkingUrl,
    transitUrl: transitUrl,
    restroomAvailable: restroomAvailable,
    concessionAvailable: concessionAvailable,
    familyFriendlyConfirmed: familyFriendlyConfirmed,
    confirmedAt: confirmedAt,
    provenance: _provenance(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
    ),
  );
}

extension WeatherForecastRowMapper on WeatherForecastRow {
  WeatherForecast toDomain() => WeatherForecast(
    id: id,
    venueId: venueId,
    gameId: gameId,
    targetTimeUtc: targetTimeUtc,
    horizon: ForecastHorizon.parse(horizon),
    issuedAt: issuedAt,
    forecastZone: forecastZone,
    temperatureC: temperatureC,
    temperatureMinC: temperatureMinC,
    temperatureMaxC: temperatureMaxC,
    precipitationProbability: precipitationProbability,
    precipitationMm: precipitationMm,
    windSpeedMs: windSpeedMs,
    humidityPercent: humidityPercent,
    skyCondition: skyCondition,
    confidence: ForecastConfidence.parse(confidence),
    seasonalTendency: seasonalTendency,
    provenance: _provenance(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceRecordId: sourceRecordId,
      fetchedAt: fetchedAt,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
    ),
  );
}

extension LocalFollowRowMapper on LocalFollowRow {
  LocalFollow toDomain() => LocalFollow(
    kind: FollowKind.parse(kind),
    entityId: entityId,
    followedAt: followedAt,
    label: label,
    muted: muted,
  );
}

extension SavedItemRowMapper on SavedItemRow {
  SavedItem toDomain() => SavedItem(
    kind: SavedItemKind.parse(kind),
    entityId: entityId,
    savedAt: savedAt,
    note: note,
  );
}

extension GameLogEntryRowMapper on GameLogEntryRow {
  GameLogEntry toDomain() => GameLogEntry(
    id: id,
    playedAt: playedAt,
    dayKey: dayKey,
    gameId: gameId,
    competitionLabel: competitionLabel,
    opponentLabel: opponentLabel,
    venueLabel: venueLabel,
    positions: GameLogPosition.decodeList(positions),
    result: GameLogResult.parse(result),
    note: note,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

Provenance _provenance({
  required String sourceName,
  required String sourceUrl,
  required DateTime fetchedAt,
  required String qualityStatus,
  required String licenseStatus,
  required String visibility,
  required bool isDemo,
  String? sourceRecordId,
  DateTime? verifiedAt,
  String? contentHash,
}) {
  return Provenance(
    sourceName: sourceName,
    sourceUrl: sourceUrl,
    fetchedAt: fetchedAt,
    sourceRecordId: sourceRecordId,
    verifiedAt: verifiedAt,
    contentHash: contentHash,
    qualityStatus: QualityStatus.parse(qualityStatus),
    licenseStatus: LicenseStatus.parse(licenseStatus),
    visibility: RecordVisibility.parse(visibility),
    isDemo: isDemo,
  );
}

ContentMeta _contentMeta({
  required String sourceName,
  required String sourceUrl,
  required DateTime fetchedAt,
  required String qualityStatus,
  required String licenseStatus,
  required String visibility,
  required bool isDemo,
  required DateTime publishedAt,
  required String summaryMethod,
  required String reviewStatus,
  required String spoilerLevel,
  required int coverageObserved,
  required int coverageExpected,
  String? sourceRecordId,
  DateTime? verifiedAt,
  String? contentHash,
  DateTime? generatedAt,
  String? coverageNote,
}) {
  return ContentMeta(
    provenance: _provenance(
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      fetchedAt: fetchedAt,
      sourceRecordId: sourceRecordId,
      verifiedAt: verifiedAt,
      contentHash: contentHash,
      qualityStatus: qualityStatus,
      licenseStatus: licenseStatus,
      visibility: visibility,
      isDemo: isDemo,
    ),
    publishedAt: publishedAt,
    summaryMethod: SummaryMethod.parse(summaryMethod),
    reviewStatus: ReviewStatus.parse(reviewStatus),
    spoilerLevel: SpoilerLevel.parse(spoilerLevel),
    generatedAt: generatedAt,
    coverage: DataCoverage(
      observed: coverageObserved,
      expected: coverageExpected,
      note: coverageNote,
    ),
  );
}

/// Id lists are stored as a JSON array in one column. Small, rarely queried
/// individually, and far cheaper than a join table for a handful of tags.
List<String> decodeIdList(String raw) {
  if (raw.isEmpty) return const <String>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];
    return decoded
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  } on FormatException {
    return const <String>[];
  }
}

String encodeIdList(List<String> ids) => ids.isEmpty ? '' : jsonEncode(ids);

/// Innings are stored as a JSON array that preserves nulls, because "did not
/// bat" and "scored zero" are different facts.
List<int?> decodeNullableInts(String raw) {
  if (raw.isEmpty) return const <int?>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <int?>[];
    return decoded
        .map<int?>((e) {
          if (e == null) return null;
          if (e is int) return e;
          if (e is num) return e.round();
          return int.tryParse(e.toString());
        })
        .toList(growable: false);
  } on FormatException {
    return const <int?>[];
  }
}

String encodeNullableInts(List<int?> values) =>
    values.isEmpty ? '' : jsonEncode(values);
