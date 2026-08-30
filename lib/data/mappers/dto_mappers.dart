import 'package:drift/drift.dart';

import '../../core/database/database.dart';
import '../../core/utils/korean_text.dart';
import '../../core/utils/kst.dart';
import '../dto/dtos.dart';
import '../models/domain.dart';
import 'row_mappers.dart';

/// Wire DTO → storage row.
///
/// This is where source-shaped data becomes app-shaped data. Denormalised
/// helper columns (`monthKey`, `dayKey`, `searchKey`, `dedupeKey`) are computed
/// here, once at write time, so read queries stay indexed and cheap.
class DtoMappers {
  const DtoMappers._();

  static Value<T> _v<T extends Object>(T? value) =>
      value == null ? const Value.absent() : Value<T>(value);

  static OrganizationsCompanion organization(OrganizationDto dto) {
    return OrganizationsCompanion.insert(
      id: dto.id,
      name: dto.name,
      shortName: _v(dto.shortName),
      country: _v(dto.country),
      websiteUrl: _v(dto.websiteUrl),
      deletedAt: _v(dto.deletedAt),
      sourceName: dto.source.sourceName,
      sourceUrl: dto.source.sourceUrl,
      sourceRecordId: _v(dto.source.sourceRecordId),
      fetchedAt: dto.source.fetchedAt,
      verifiedAt: _v(dto.source.verifiedAt),
      contentHash: _v(dto.source.contentHash),
      qualityStatus: _v(dto.source.qualityStatus),
      licenseStatus: _v(dto.source.licenseStatus),
      visibility: _v(dto.source.visibility),
      isDemo: Value(dto.source.isDemo),
    );
  }

  static CompetitionsCompanion competition(CompetitionDto dto) {
    return CompetitionsCompanion.insert(
      id: dto.id,
      name: dto.name,
      shortName: _v(dto.shortName),
      level: _v(dto.level),
      organizationId: _v(dto.organizationId),
      description: _v(dto.description),
      regulationsUrl: _v(dto.regulationsUrl),
      bracketUrl: _v(dto.bracketUrl),
      resultsUrl: _v(dto.resultsUrl),
      deletedAt: _v(dto.deletedAt),
      sourceName: dto.source.sourceName,
      sourceUrl: dto.source.sourceUrl,
      sourceRecordId: _v(dto.source.sourceRecordId),
      fetchedAt: dto.source.fetchedAt,
      verifiedAt: _v(dto.source.verifiedAt),
      contentHash: _v(dto.source.contentHash),
      qualityStatus: _v(dto.source.qualityStatus),
      licenseStatus: _v(dto.source.licenseStatus),
      visibility: _v(dto.source.visibility),
      isDemo: Value(dto.source.isDemo),
    );
  }

  /// Seasons and stages arrive nested inside a competition; they inherit its
  /// provenance so every row remains individually attributable.
  static SeasonsCompanion season(SeasonDto dto, ProvenanceDto source) {
    return SeasonsCompanion.insert(
      id: dto.id,
      competitionId: dto.competitionId,
      year: dto.year,
      name: dto.name,
      phase: _v(dto.phase),
      startDate: _v(dto.startDate),
      endDate: _v(dto.endDate),
      deletedAt: _v(dto.deletedAt),
      sourceName: source.sourceName,
      sourceUrl: source.sourceUrl,
      sourceRecordId: _v(source.sourceRecordId),
      fetchedAt: source.fetchedAt,
      verifiedAt: _v(source.verifiedAt),
      contentHash: _v(source.contentHash),
      qualityStatus: _v(source.qualityStatus),
      licenseStatus: _v(source.licenseStatus),
      visibility: _v(source.visibility),
      isDemo: Value(source.isDemo),
    );
  }

  static StagesCompanion stage(StageDto dto, ProvenanceDto source) {
    return StagesCompanion.insert(
      id: dto.id,
      seasonId: dto.seasonId,
      name: dto.name,
      format: _v(dto.format),
      groupLabel: _v(dto.groupLabel),
      ordering: Value(dto.ordering),
      deletedAt: _v(dto.deletedAt),
      sourceName: source.sourceName,
      sourceUrl: source.sourceUrl,
      sourceRecordId: _v(source.sourceRecordId),
      fetchedAt: source.fetchedAt,
      verifiedAt: _v(source.verifiedAt),
      contentHash: _v(source.contentHash),
      qualityStatus: _v(source.qualityStatus),
      licenseStatus: _v(source.licenseStatus),
      visibility: _v(source.visibility),
      isDemo: Value(source.isDemo),
    );
  }

  static TeamsCompanion team(TeamDto dto) {
    return TeamsCompanion.insert(
      id: dto.id,
      name: dto.name,
      shortName: _v(dto.shortName),
      region: _v(dto.region),
      city: _v(dto.city),
      foundedYear: _v(dto.foundedYear),
      introduction: _v(dto.introduction),
      recruitment: _v(dto.recruitment),
      recruitmentTarget: _v(dto.recruitmentTarget),
      homeVenueId: _v(dto.homeVenueId),
      practiceArea: _v(dto.practiceArea),
      officialUrl: _v(dto.officialUrl),
      contactUrl: _v(dto.contactUrl),
      logoUrl: _v(dto.logoUrl),
      logoLicense: _v(dto.logoLicense),
      colorHex: _v(dto.colorHex),
      // Computed once here so 초성 search is an indexed LIKE, not a scan.
      searchKey: Value(
        KoreanText.searchKey(
          dto.name,
          aliases: <String>[
            if (dto.shortName != null) dto.shortName!,
            ...dto.aliases,
          ],
        ),
      ),
      deletedAt: _v(dto.deletedAt),
      sourceName: dto.source.sourceName,
      sourceUrl: dto.source.sourceUrl,
      sourceRecordId: _v(dto.source.sourceRecordId),
      fetchedAt: dto.source.fetchedAt,
      verifiedAt: _v(dto.source.verifiedAt),
      contentHash: _v(dto.source.contentHash),
      qualityStatus: _v(dto.source.qualityStatus),
      licenseStatus: _v(dto.source.licenseStatus),
      visibility: _v(dto.source.visibility),
      isDemo: Value(dto.source.isDemo),
    );
  }

  /// One alias row per spelling, plus the canonical name itself, so a source
  /// referring to a team by any known form resolves to the same canonical id.
  static List<TeamAliasesCompanion> teamAliases(TeamDto dto) {
    final forms = <String>{dto.name, ...dto.aliases};
    if (dto.shortName != null) forms.add(dto.shortName!);
    return forms
        .where((f) => f.trim().isNotEmpty)
        .map(
          (f) => TeamAliasesCompanion.insert(
            teamId: dto.id,
            alias: f,
            normalized: KoreanText.normalize(f),
            sourceName: _v(dto.source.sourceName),
          ),
        )
        .toList(growable: false);
  }

  static VenuesCompanion venue(VenueDto dto) {
    return VenuesCompanion.insert(
      id: dto.id,
      name: dto.name,
      address: _v(dto.address),
      region: _v(dto.region),
      latitude: _v(dto.latitude),
      longitude: _v(dto.longitude),
      capacity: _v(dto.capacity),
      surface: _v(dto.surface),
      notes: _v(dto.notes),
      searchKey: Value(KoreanText.searchKey(dto.name)),
      deletedAt: _v(dto.deletedAt),
      sourceName: dto.source.sourceName,
      sourceUrl: dto.source.sourceUrl,
      sourceRecordId: _v(dto.source.sourceRecordId),
      fetchedAt: dto.source.fetchedAt,
      verifiedAt: _v(dto.source.verifiedAt),
      contentHash: _v(dto.source.contentHash),
      qualityStatus: _v(dto.source.qualityStatus),
      licenseStatus: _v(dto.source.licenseStatus),
      visibility: _v(dto.source.visibility),
      isDemo: Value(dto.source.isDemo),
    );
  }

  static PeopleCompanion person(PersonDto dto) {
    return PeopleCompanion.insert(
      id: dto.id,
      name: dto.name,
      isMinor: Value(dto.isMinor),
      photoUrl: _v(dto.photoUrl),
      photoLicense: _v(dto.photoLicense),
      searchKey: Value(KoreanText.searchKey(dto.name, aliases: dto.aliases)),
      deletedAt: _v(dto.deletedAt),
      sourceName: dto.source.sourceName,
      sourceUrl: dto.source.sourceUrl,
      sourceRecordId: _v(dto.source.sourceRecordId),
      fetchedAt: dto.source.fetchedAt,
      verifiedAt: _v(dto.source.verifiedAt),
      contentHash: _v(dto.source.contentHash),
      qualityStatus: _v(dto.source.qualityStatus),
      licenseStatus: _v(dto.source.licenseStatus),
      visibility: _v(dto.source.visibility),
      isDemo: Value(dto.source.isDemo),
    );
  }

  static List<PersonAliasesCompanion> personAliases(PersonDto dto) {
    final forms = <String>{dto.name, ...dto.aliases};
    return forms
        .where((f) => f.trim().isNotEmpty)
        .map(
          (f) => PersonAliasesCompanion.insert(
            personId: dto.id,
            alias: f,
            normalized: KoreanText.normalize(f),
            sourceName: _v(dto.source.sourceName),
          ),
        )
        .toList(growable: false);
  }

  /// The roster row needs a `teamSeasonId`, which the sync engine resolves (or
  /// creates) from the DTO's team + season pair.
  static RosterEntriesCompanion rosterEntry(
    RosterEntryDto dto,
    String teamSeasonId,
  ) {
    return RosterEntriesCompanion.insert(
      id: dto.id,
      teamSeasonId: teamSeasonId,
      personId: dto.personId,
      jerseyNumber: _v(dto.jerseyNumber),
      position: _v(dto.position),
      deletedAt: _v(dto.deletedAt),
      sourceName: dto.source.sourceName,
      sourceUrl: dto.source.sourceUrl,
      sourceRecordId: _v(dto.source.sourceRecordId),
      fetchedAt: dto.source.fetchedAt,
      verifiedAt: _v(dto.source.verifiedAt),
      contentHash: _v(dto.source.contentHash),
      qualityStatus: _v(dto.source.qualityStatus),
      licenseStatus: _v(dto.source.licenseStatus),
      visibility: _v(dto.source.visibility),
      isDemo: Value(dto.source.isDemo),
    );
  }

  static TeamSeasonsCompanion teamSeason({
    required String id,
    required String teamId,
    required String seasonId,
    required ProvenanceDto source,
    String? stageId,
  }) {
    return TeamSeasonsCompanion.insert(
      id: id,
      teamId: teamId,
      seasonId: seasonId,
      stageId: _v(stageId),
      sourceName: source.sourceName,
      sourceUrl: source.sourceUrl,
      sourceRecordId: _v(source.sourceRecordId),
      fetchedAt: source.fetchedAt,
      verifiedAt: _v(source.verifiedAt),
      contentHash: _v(source.contentHash),
      qualityStatus: _v(source.qualityStatus),
      licenseStatus: _v(source.licenseStatus),
      visibility: _v(source.visibility),
      isDemo: Value(source.isDemo),
    );
  }

  static GamesCompanion game(GameDto dto) {
    final startUtc = dto.startTime.toUtc();
    // A domain Game is built purely to compute the canonical dedupe key, so
    // the same rule applies whether a fixture arrives from JSON or an API.
    final probe = Game(
      id: dto.id,
      status: GameStatus.parse(dto.status),
      startTimeUtc: startUtc,
      homeTeamId: dto.homeTeamId,
      awayTeamId: dto.awayTeamId,
      competitionId: dto.competitionId,
      venueId: dto.venueId,
      provenance: Provenance(
        sourceName: dto.source.sourceName,
        sourceUrl: dto.source.sourceUrl,
        fetchedAt: dto.source.fetchedAt,
      ),
    );

    return GamesCompanion.insert(
      id: dto.id,
      status: dto.status,
      startTimeUtc: startUtc,
      monthKey: Kst.monthKey(startUtc),
      dayKey: Kst.dayKey(startUtc),
      homeTeamId: dto.homeTeamId,
      awayTeamId: dto.awayTeamId,
      seasonId: _v(dto.seasonId),
      stageId: _v(dto.stageId),
      competitionId: _v(dto.competitionId),
      venueId: _v(dto.venueId),
      homeScore: _v(dto.homeScore),
      awayScore: _v(dto.awayScore),
      localTimeZone: _v(dto.localTimeZone),
      round: _v(dto.round),
      summary: _v(dto.summary),
      officialDetailUrl: _v(dto.officialDetailUrl),
      statusNote: _v(dto.statusNote),
      dedupeKey: Value(probe.dedupeKey()),
      deletedAt: _v(dto.deletedAt),
      sourceName: dto.source.sourceName,
      sourceUrl: dto.source.sourceUrl,
      sourceRecordId: _v(dto.source.sourceRecordId),
      fetchedAt: dto.source.fetchedAt,
      verifiedAt: _v(dto.source.verifiedAt),
      contentHash: _v(dto.source.contentHash),
      qualityStatus: _v(dto.source.qualityStatus),
      licenseStatus: _v(dto.source.licenseStatus),
      visibility: _v(dto.source.visibility),
      isDemo: Value(dto.source.isDemo),
    );
  }

  static GameLineScoresCompanion? lineScore(GameDto dto) {
    final line = dto.lineScore;
    if (line == null) return null;
    return GameLineScoresCompanion.insert(
      gameId: dto.id,
      homeInnings: encodeNullableInts(line.homeInnings),
      awayInnings: encodeNullableInts(line.awayInnings),
      homeRuns: _v(line.homeRuns ?? dto.homeScore),
      awayRuns: _v(line.awayRuns ?? dto.awayScore),
      homeHits: _v(line.homeHits),
      awayHits: _v(line.awayHits),
      homeErrors: _v(line.homeErrors),
      awayErrors: _v(line.awayErrors),
    );
  }

  static List<BattingStatsCompanion> batting(GameDto dto) => dto.batting
      .map(
        (b) => BattingStatsCompanion.insert(
          gameId: dto.id,
          personId: b.personId,
          teamId: b.teamId,
          playerName: b.playerName,
          battingOrder: _v(b.battingOrder),
          position: _v(b.position),
          atBats: Value(b.atBats),
          runs: Value(b.runs),
          hits: Value(b.hits),
          doubles: Value(b.doubles),
          triples: Value(b.triples),
          homeRuns: Value(b.homeRuns),
          rbi: Value(b.rbi),
          walks: Value(b.walks),
          strikeouts: Value(b.strikeouts),
          stolenBases: Value(b.stolenBases),
        ),
      )
      .toList(growable: false);

  static List<PitchingStatsCompanion> pitching(GameDto dto) => dto.pitching
      .map(
        (p) => PitchingStatsCompanion.insert(
          gameId: dto.id,
          personId: p.personId,
          teamId: p.teamId,
          playerName: p.playerName,
          outsRecorded: Value(p.outsRecorded),
          hitsAllowed: Value(p.hitsAllowed),
          runsAllowed: Value(p.runsAllowed),
          earnedRuns: Value(p.earnedRuns),
          walks: Value(p.walks),
          strikeouts: Value(p.strikeouts),
          homeRunsAllowed: Value(p.homeRunsAllowed),
          decision: _v(p.decision),
        ),
      )
      .toList(growable: false);

  static StandingsCompanion standing(StandingDto dto, {int? previousRank}) {
    return StandingsCompanion.insert(
      id: dto.id,
      seasonId: dto.seasonId,
      stageId: _v(dto.stageId),
      teamId: dto.teamId,
      capturedAt: dto.capturedAt,
      rank: _v(dto.rank),
      played: Value(dto.played),
      wins: Value(dto.wins),
      losses: Value(dto.losses),
      draws: Value(dto.draws),
      runsScored: Value(dto.runsScored),
      runsAllowed: Value(dto.runsAllowed),
      gamesBehind: _v(dto.gamesBehind),
      previousRank: _v(previousRank),
      deletedAt: _v(dto.deletedAt),
      sourceName: dto.source.sourceName,
      sourceUrl: dto.source.sourceUrl,
      sourceRecordId: _v(dto.source.sourceRecordId),
      fetchedAt: dto.source.fetchedAt,
      verifiedAt: _v(dto.source.verifiedAt),
      contentHash: _v(dto.source.contentHash),
      qualityStatus: _v(dto.source.qualityStatus),
      licenseStatus: _v(dto.source.licenseStatus),
      visibility: _v(dto.source.visibility),
      isDemo: Value(dto.source.isDemo),
    );
  }

  static ArticlesCompanion article(ArticleDto dto) {
    return ArticlesCompanion.insert(
      id: dto.id,
      title: dto.title,
      url: dto.url,
      publishedAt: dto.publishedAt,
      outlet: _v(dto.outlet),
      summary: _v(dto.summary),
      teamIds: Value(encodeIdList(dto.teamIds)),
      competitionIds: Value(encodeIdList(dto.competitionIds)),
      isOfficialNotice: Value(dto.isOfficialNotice),
      deletedAt: _v(dto.deletedAt),
      sourceName: dto.source.sourceName,
      sourceUrl: dto.source.sourceUrl,
      sourceRecordId: _v(dto.source.sourceRecordId),
      fetchedAt: dto.source.fetchedAt,
      verifiedAt: _v(dto.source.verifiedAt),
      contentHash: _v(dto.source.contentHash),
      qualityStatus: _v(dto.source.qualityStatus),
      licenseStatus: _v(dto.source.licenseStatus),
      visibility: _v(dto.source.visibility),
      isDemo: Value(dto.source.isDemo),
    );
  }

  static VideosCompanion video(VideoDto dto) {
    return VideosCompanion.insert(
      id: dto.id,
      title: dto.title,
      url: dto.url,
      publishedAt: dto.publishedAt,
      channelName: _v(dto.channelName),
      thumbnailUrl: _v(dto.thumbnailUrl),
      durationSeconds: _v(dto.durationSeconds),
      teamIds: Value(encodeIdList(dto.teamIds)),
      competitionIds: Value(encodeIdList(dto.competitionIds)),
      deletedAt: _v(dto.deletedAt),
      sourceName: dto.source.sourceName,
      sourceUrl: dto.source.sourceUrl,
      sourceRecordId: _v(dto.source.sourceRecordId),
      fetchedAt: dto.source.fetchedAt,
      verifiedAt: _v(dto.source.verifiedAt),
      contentHash: _v(dto.source.contentHash),
      qualityStatus: _v(dto.source.qualityStatus),
      licenseStatus: _v(dto.source.licenseStatus),
      visibility: _v(dto.source.visibility),
      isDemo: Value(dto.source.isDemo),
    );
  }
}
