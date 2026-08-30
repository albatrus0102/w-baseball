import 'package:meta/meta.dart';

import 'json_reader.dart';

/// Wire-format DTOs.
///
/// These mirror the *published contract* (see `schemas/`), not any particular
/// upstream site. Site-specific shapes are converted into these by the
/// adapters in `lib/data/sources/adapters/`, so the domain layer never sees a
/// WBAK field name or a WBSC field name.
///
/// Every DTO keeps its source's own record id ([sourceRecordId]) separate from
/// the app's canonical id, and none of them is allowed to reach the database
/// without passing through `lib/data/mappers/`.

/// Provenance block shared by every published record.
@immutable
class ProvenanceDto {
  const ProvenanceDto({
    required this.sourceName,
    required this.sourceUrl,
    required this.fetchedAt,
    this.sourceRecordId,
    this.verifiedAt,
    this.contentHash,
    this.qualityStatus,
    this.licenseStatus,
    this.visibility,
    this.isDemo = false,
  });

  final String sourceName;
  final String sourceUrl;
  final DateTime fetchedAt;
  final String? sourceRecordId;
  final DateTime? verifiedAt;
  final String? contentHash;
  final String? qualityStatus;
  final String? licenseStatus;
  final String? visibility;
  final bool isDemo;

  static const knownKeys = <String>{
    'sourceName',
    'sourceUrl',
    'sourceRecordId',
    'fetchedAt',
    'verifiedAt',
    'contentHash',
    'qualityStatus',
    'licenseStatus',
    'visibility',
    'isDemo',
  };

  /// Reads the `source` block. Publishing without one is a hard error: a
  /// record we cannot attribute is a record we will not show.
  factory ProvenanceDto.fromReader(JsonReader parent) {
    final r = parent.optionalObject('source');
    if (r == null) {
      throw DtoValidationException(
        'source',
        'source 블록이 없습니다',
        recordId: parent.recordId,
      );
    }
    return ProvenanceDto(
      sourceName: r.requireString('sourceName'),
      // App-authored content (guides, derived leaderboards) has no external
      // page, so an `app:` URI is accepted here and rendered as a plain source
      // label with no outbound link. Everything else must be http(s).
      sourceUrl: _requireSourceUrl(r),
      fetchedAt: r.requireInstant('fetchedAt'),
      sourceRecordId: r.optionalString('sourceRecordId'),
      verifiedAt: r.optionalInstant('verifiedAt'),
      contentHash: r.optionalString('contentHash'),
      qualityStatus: r.optionalString('qualityStatus'),
      licenseStatus: r.optionalString('licenseStatus'),
      visibility: r.optionalString('visibility'),
      isDemo: r.optionalBool('isDemo'),
    );
  }
}

/// Common fields every entity DTO carries.
abstract class EntityDto {
  String get id;
  String? get sourceRecordId;
  ProvenanceDto get source;

  /// Explicit upstream deletion marker (a tombstone), distinct from simply
  /// being absent from a delta page.
  DateTime? get deletedAt;
}

@immutable
class OrganizationDto implements EntityDto {
  const OrganizationDto({
    required this.id,
    required this.name,
    required this.source,
    this.shortName,
    this.country,
    this.websiteUrl,
    this.deletedAt,
  });

  @override
  final String id;
  final String name;
  final String? shortName;
  final String? country;
  final String? websiteUrl;
  @override
  final ProvenanceDto source;
  @override
  final DateTime? deletedAt;

  @override
  String? get sourceRecordId => source.sourceRecordId;

  static const knownKeys = <String>{
    'id',
    'name',
    'shortName',
    'country',
    'websiteUrl',
    'deletedAt',
    'source',
  };

  factory OrganizationDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return OrganizationDto(
      id: r.requireString('id'),
      name: r.requireString('name'),
      shortName: r.optionalString('shortName'),
      country: r.optionalString('country'),
      websiteUrl: r.optionalUrl('websiteUrl'),
      deletedAt: r.optionalInstant('deletedAt'),
      source: ProvenanceDto.fromReader(r),
    );
  }
}

@immutable
class CompetitionDto implements EntityDto {
  const CompetitionDto({
    required this.id,
    required this.name,
    required this.source,
    this.shortName,
    this.level,
    this.organizationId,
    this.description,
    this.regulationsUrl,
    this.bracketUrl,
    this.resultsUrl,
    this.seasons = const <SeasonDto>[],
    this.deletedAt,
  });

  @override
  final String id;
  final String name;
  final String? shortName;
  final String? level;
  final String? organizationId;
  final String? description;
  final String? regulationsUrl;
  final String? bracketUrl;
  final String? resultsUrl;

  /// Seasons arrive nested; the mapper flattens them.
  final List<SeasonDto> seasons;

  @override
  final ProvenanceDto source;
  @override
  final DateTime? deletedAt;

  @override
  String? get sourceRecordId => source.sourceRecordId;

  static const knownKeys = <String>{
    'id',
    'name',
    'shortName',
    'level',
    'organizationId',
    'description',
    'regulationsUrl',
    'bracketUrl',
    'resultsUrl',
    'seasons',
    'deletedAt',
    'source',
  };

  factory CompetitionDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final id = r.requireString('id');
    return CompetitionDto(
      id: id,
      name: r.requireString('name'),
      shortName: r.optionalString('shortName'),
      level: r.optionalString('level'),
      organizationId: r.optionalString('organizationId'),
      description: r.optionalString('description'),
      regulationsUrl: r.optionalUrl('regulationsUrl'),
      bracketUrl: r.optionalUrl('bracketUrl'),
      resultsUrl: r.optionalUrl('resultsUrl'),
      seasons: r
          .objectList('seasons')
          .map((s) => SeasonDto.fromReader(s, competitionId: id))
          .toList(growable: false),
      deletedAt: r.optionalInstant('deletedAt'),
      source: ProvenanceDto.fromReader(r),
    );
  }
}

@immutable
class SeasonDto {
  const SeasonDto({
    required this.id,
    required this.competitionId,
    required this.year,
    required this.name,
    this.phase,
    this.startDate,
    this.endDate,
    this.stages = const <StageDto>[],
    this.deletedAt,
  });

  final String id;
  final String competitionId;
  final int year;
  final String name;
  final String? phase;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<StageDto> stages;
  final DateTime? deletedAt;

  static const knownKeys = <String>{
    'id',
    'competitionId',
    'year',
    'name',
    'phase',
    'startDate',
    'endDate',
    'stages',
    'deletedAt',
  };

  factory SeasonDto.fromReader(JsonReader r, {String? competitionId}) {
    final id = r.requireString('id');
    final owner = r.optionalString('competitionId') ?? competitionId;
    if (owner == null) {
      throw DtoValidationException(
        'competitionId',
        '시즌의 대회 참조가 없습니다',
        recordId: id,
      );
    }
    return SeasonDto(
      id: id,
      competitionId: owner,
      year: r.requireInt('year'),
      name: r.requireString('name'),
      phase: r.optionalString('phase'),
      startDate: r.optionalDate('startDate'),
      endDate: r.optionalDate('endDate'),
      stages: r
          .objectList('stages')
          .map((s) => StageDto.fromReader(s, seasonId: id))
          .toList(growable: false),
      deletedAt: r.optionalInstant('deletedAt'),
    );
  }
}

@immutable
class StageDto {
  const StageDto({
    required this.id,
    required this.seasonId,
    required this.name,
    this.format,
    this.groupLabel,
    this.ordering = 0,
    this.deletedAt,
  });

  final String id;
  final String seasonId;
  final String name;
  final String? format;
  final String? groupLabel;
  final int ordering;
  final DateTime? deletedAt;

  static const knownKeys = <String>{
    'id',
    'seasonId',
    'name',
    'format',
    'groupLabel',
    'ordering',
    'deletedAt',
  };

  factory StageDto.fromReader(JsonReader r, {String? seasonId}) {
    final id = r.requireString('id');
    final owner = r.optionalString('seasonId') ?? seasonId;
    if (owner == null) {
      throw DtoValidationException('seasonId', '단계의 시즌 참조가 없습니다', recordId: id);
    }
    return StageDto(
      id: id,
      seasonId: owner,
      name: r.requireString('name'),
      format: r.optionalString('format'),
      groupLabel: r.optionalString('groupLabel'),
      ordering: r.optionalInt('ordering') ?? 0,
      deletedAt: r.optionalInstant('deletedAt'),
    );
  }
}

@immutable
class TeamDto implements EntityDto {
  const TeamDto({
    required this.id,
    required this.name,
    required this.source,
    this.shortName,
    this.region,
    this.city,
    this.foundedYear,
    this.introduction,
    this.recruitment,
    this.recruitmentTarget,
    this.homeVenueId,
    this.practiceArea,
    this.officialUrl,
    this.contactUrl,
    this.logoUrl,
    this.logoLicense,
    this.colorHex,
    this.aliases = const <String>[],
    this.deletedAt,
  });

  @override
  final String id;
  final String name;
  final String? shortName;
  final String? region;
  final String? city;
  final int? foundedYear;
  final String? introduction;
  final String? recruitment;
  final String? recruitmentTarget;
  final String? homeVenueId;
  final String? practiceArea;
  final String? officialUrl;
  final String? contactUrl;
  final String? logoUrl;
  final String? logoLicense;
  final String? colorHex;
  final List<String> aliases;

  @override
  final ProvenanceDto source;
  @override
  final DateTime? deletedAt;

  @override
  String? get sourceRecordId => source.sourceRecordId;

  static const knownKeys = <String>{
    'id',
    'name',
    'shortName',
    'region',
    'city',
    'foundedYear',
    'introduction',
    'recruitment',
    'recruitmentTarget',
    'homeVenueId',
    'practiceArea',
    'officialUrl',
    'contactUrl',
    'logoUrl',
    'logoLicense',
    'colorHex',
    'aliases',
    'deletedAt',
    'source',
  };

  factory TeamDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return TeamDto(
      id: r.requireString('id'),
      name: r.requireString('name'),
      shortName: r.optionalString('shortName'),
      region: r.optionalString('region'),
      city: r.optionalString('city'),
      foundedYear: r.optionalInt('foundedYear'),
      introduction: r.optionalString('introduction'),
      recruitment: r.optionalString('recruitment'),
      recruitmentTarget: r.optionalString('recruitmentTarget'),
      homeVenueId: r.optionalString('homeVenueId'),
      practiceArea: r.optionalString('practiceArea'),
      officialUrl: r.optionalUrl('officialUrl'),
      contactUrl: r.optionalUrl('contactUrl'),
      logoUrl: r.optionalUrl('logoUrl'),
      logoLicense: r.optionalString('logoLicense'),
      colorHex: r.optionalString('colorHex'),
      aliases: r.stringList('aliases'),
      deletedAt: r.optionalInstant('deletedAt'),
      source: ProvenanceDto.fromReader(r),
    );
  }
}

@immutable
class VenueDto implements EntityDto {
  const VenueDto({
    required this.id,
    required this.name,
    required this.source,
    this.address,
    this.region,
    this.latitude,
    this.longitude,
    this.capacity,
    this.surface,
    this.notes,
    this.deletedAt,
  });

  @override
  final String id;
  final String name;
  final String? address;
  final String? region;
  final double? latitude;
  final double? longitude;
  final int? capacity;
  final String? surface;
  final String? notes;

  @override
  final ProvenanceDto source;
  @override
  final DateTime? deletedAt;

  @override
  String? get sourceRecordId => source.sourceRecordId;

  static const knownKeys = <String>{
    'id',
    'name',
    'address',
    'region',
    'latitude',
    'longitude',
    'capacity',
    'surface',
    'notes',
    'deletedAt',
    'source',
  };

  factory VenueDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final lat = r.optionalDouble('latitude');
    final lon = r.optionalDouble('longitude');
    // Out-of-range coordinates would send a maps app somewhere absurd, so we
    // drop them rather than reject the whole venue.
    final validLat = (lat != null && lat.abs() <= 90) ? lat : null;
    final validLon = (lon != null && lon.abs() <= 180) ? lon : null;
    return VenueDto(
      id: r.requireString('id'),
      name: r.requireString('name'),
      address: r.optionalString('address'),
      region: r.optionalString('region'),
      latitude: (validLat != null && validLon != null) ? validLat : null,
      longitude: (validLat != null && validLon != null) ? validLon : null,
      capacity: r.optionalInt('capacity'),
      surface: r.optionalString('surface'),
      notes: r.optionalString('notes'),
      deletedAt: r.optionalInstant('deletedAt'),
      source: ProvenanceDto.fromReader(r),
    );
  }
}

@immutable
class LineScoreDto {
  const LineScoreDto({
    this.homeInnings = const <int?>[],
    this.awayInnings = const <int?>[],
    this.homeRuns,
    this.awayRuns,
    this.homeHits,
    this.awayHits,
    this.homeErrors,
    this.awayErrors,
  });

  final List<int?> homeInnings;
  final List<int?> awayInnings;
  final int? homeRuns;
  final int? awayRuns;
  final int? homeHits;
  final int? awayHits;
  final int? homeErrors;
  final int? awayErrors;

  bool get isEmpty => homeInnings.isEmpty && awayInnings.isEmpty;

  static const knownKeys = <String>{
    'homeInnings',
    'awayInnings',
    'homeRuns',
    'awayRuns',
    'homeHits',
    'awayHits',
    'homeErrors',
    'awayErrors',
  };

  factory LineScoreDto.fromReader(JsonReader r) {
    return LineScoreDto(
      homeInnings: r.nullableIntList('homeInnings'),
      awayInnings: r.nullableIntList('awayInnings'),
      homeRuns: r.optionalInt('homeRuns'),
      awayRuns: r.optionalInt('awayRuns'),
      homeHits: r.optionalInt('homeHits'),
      awayHits: r.optionalInt('awayHits'),
      homeErrors: r.optionalInt('homeErrors'),
      awayErrors: r.optionalInt('awayErrors'),
    );
  }
}

@immutable
class BattingStatDto {
  const BattingStatDto({
    required this.personId,
    required this.playerName,
    required this.teamId,
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

  final String personId;
  final String playerName;
  final String teamId;
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

  factory BattingStatDto.fromReader(JsonReader r) {
    return BattingStatDto(
      personId: r.requireString('personId'),
      playerName: r.requireString('playerName'),
      teamId: r.requireString('teamId'),
      battingOrder: r.optionalInt('battingOrder'),
      position: r.optionalString('position'),
      atBats: r.optionalInt('atBats') ?? 0,
      runs: r.optionalInt('runs') ?? 0,
      hits: r.optionalInt('hits') ?? 0,
      doubles: r.optionalInt('doubles') ?? 0,
      triples: r.optionalInt('triples') ?? 0,
      homeRuns: r.optionalInt('homeRuns') ?? 0,
      rbi: r.optionalInt('rbi') ?? 0,
      walks: r.optionalInt('walks') ?? 0,
      strikeouts: r.optionalInt('strikeouts') ?? 0,
      stolenBases: r.optionalInt('stolenBases') ?? 0,
    );
  }
}

@immutable
class PitchingStatDto {
  const PitchingStatDto({
    required this.personId,
    required this.playerName,
    required this.teamId,
    this.outsRecorded = 0,
    this.hitsAllowed = 0,
    this.runsAllowed = 0,
    this.earnedRuns = 0,
    this.walks = 0,
    this.strikeouts = 0,
    this.homeRunsAllowed = 0,
    this.decision,
  });

  final String personId;
  final String playerName;
  final String teamId;
  final int outsRecorded;
  final int hitsAllowed;
  final int runsAllowed;
  final int earnedRuns;
  final int walks;
  final int strikeouts;
  final int homeRunsAllowed;
  final String? decision;

  factory PitchingStatDto.fromReader(JsonReader r) {
    // Sources express workload as either outs or "5.1" innings. Outs win when
    // present because they are unambiguous.
    var outs = r.optionalInt('outsRecorded');
    if (outs == null) {
      final ip = r.optionalString('inningsPitched');
      if (ip != null) {
        final parts = ip.split('.');
        final whole = int.tryParse(parts.first) ?? 0;
        final part = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
        outs = whole * 3 + (part <= 2 ? part : 0);
      }
    }
    return PitchingStatDto(
      personId: r.requireString('personId'),
      playerName: r.requireString('playerName'),
      teamId: r.requireString('teamId'),
      outsRecorded: outs ?? 0,
      hitsAllowed: r.optionalInt('hitsAllowed') ?? 0,
      runsAllowed: r.optionalInt('runsAllowed') ?? 0,
      earnedRuns: r.optionalInt('earnedRuns') ?? 0,
      walks: r.optionalInt('walks') ?? 0,
      strikeouts: r.optionalInt('strikeouts') ?? 0,
      homeRunsAllowed: r.optionalInt('homeRunsAllowed') ?? 0,
      decision: r.optionalString('decision'),
    );
  }
}

@immutable
class GameDto implements EntityDto {
  const GameDto({
    required this.id,
    required this.status,
    required this.startTime,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.source,
    this.seasonId,
    this.stageId,
    this.competitionId,
    this.venueId,
    this.homeScore,
    this.awayScore,
    this.localTimeZone,
    this.round,
    this.summary,
    this.officialDetailUrl,
    this.statusNote,
    this.lineScore,
    this.batting = const <BattingStatDto>[],
    this.pitching = const <PitchingStatDto>[],
    this.deletedAt,
  });

  @override
  final String id;
  final String status;
  final DateTime startTime;
  final String homeTeamId;
  final String awayTeamId;
  final String? seasonId;
  final String? stageId;
  final String? competitionId;
  final String? venueId;
  final int? homeScore;
  final int? awayScore;
  final String? localTimeZone;
  final String? round;
  final String? summary;
  final String? officialDetailUrl;
  final String? statusNote;
  final LineScoreDto? lineScore;
  final List<BattingStatDto> batting;
  final List<PitchingStatDto> pitching;

  @override
  final ProvenanceDto source;
  @override
  final DateTime? deletedAt;

  @override
  String? get sourceRecordId => source.sourceRecordId;

  static const knownKeys = <String>{
    'id',
    'status',
    'startTime',
    'homeTeamId',
    'awayTeamId',
    'seasonId',
    'stageId',
    'competitionId',
    'venueId',
    'homeScore',
    'awayScore',
    'localTimeZone',
    'round',
    'summary',
    'officialDetailUrl',
    'statusNote',
    'lineScore',
    'batting',
    'pitching',
    'deletedAt',
    'source',
  };

  factory GameDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final id = r.requireString('id');
    final home = r.requireString('homeTeamId');
    final away = r.requireString('awayTeamId');

    // A team cannot play itself. This is a data error, not a display quirk.
    if (home == away) {
      throw DtoValidationException(
        'awayTeamId',
        '홈팀과 원정팀이 동일합니다',
        recordId: id,
      );
    }

    final status = r.optionalString('status') ?? 'unknown';
    final homeScore = r.optionalInt('homeScore');
    final awayScore = r.optionalInt('awayScore');

    // A finished game with no score is not a finished game we can display.
    if (status == 'final' && (homeScore == null || awayScore == null)) {
      throw DtoValidationException(
        'homeScore',
        '종료된 경기에 점수가 없습니다',
        recordId: id,
      );
    }
    if ((homeScore != null && homeScore < 0) ||
        (awayScore != null && awayScore < 0)) {
      throw DtoValidationException('homeScore', '점수가 음수입니다', recordId: id);
    }

    final lineReader = r.optionalObject('lineScore');
    final line = lineReader == null
        ? null
        : LineScoreDto.fromReader(lineReader);
    if (line != null && !line.isEmpty) {
      final homeSum = line.homeInnings.fold<int>(0, (a, v) => a + (v ?? 0));
      final awaySum = line.awayInnings.fold<int>(0, (a, v) => a + (v ?? 0));
      final declaredHome = line.homeRuns ?? homeScore;
      final declaredAway = line.awayRuns ?? awayScore;
      if (declaredHome != null && declaredHome != homeSum) {
        throw DtoValidationException(
          'lineScore.homeInnings',
          '이닝 합계($homeSum)가 최종 득점($declaredHome)과 다릅니다',
          recordId: id,
        );
      }
      if (declaredAway != null && declaredAway != awaySum) {
        throw DtoValidationException(
          'lineScore.awayInnings',
          '이닝 합계($awaySum)가 최종 득점($declaredAway)과 다릅니다',
          recordId: id,
        );
      }
    }

    return GameDto(
      id: id,
      status: status,
      startTime: r.requireInstant('startTime'),
      homeTeamId: home,
      awayTeamId: away,
      seasonId: r.optionalString('seasonId'),
      stageId: r.optionalString('stageId'),
      competitionId: r.optionalString('competitionId'),
      venueId: r.optionalString('venueId'),
      homeScore: homeScore,
      awayScore: awayScore,
      localTimeZone: r.optionalString('localTimeZone'),
      round: r.optionalString('round'),
      summary: r.optionalString('summary'),
      officialDetailUrl: r.optionalUrl('officialDetailUrl'),
      statusNote: r.optionalString('statusNote'),
      lineScore: (line == null || line.isEmpty) ? null : line,
      batting: r
          .objectList('batting')
          .map(BattingStatDto.fromReader)
          .toList(growable: false),
      pitching: r
          .objectList('pitching')
          .map(PitchingStatDto.fromReader)
          .toList(growable: false),
      deletedAt: r.optionalInstant('deletedAt'),
      source: ProvenanceDto.fromReader(r),
    );
  }
}

@immutable
class StandingDto implements EntityDto {
  const StandingDto({
    required this.id,
    required this.seasonId,
    required this.teamId,
    required this.capturedAt,
    required this.source,
    this.stageId,
    this.rank,
    this.played = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.runsScored = 0,
    this.runsAllowed = 0,
    this.gamesBehind,
    this.deletedAt,
  });

  @override
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

  @override
  final ProvenanceDto source;
  @override
  final DateTime? deletedAt;

  @override
  String? get sourceRecordId => source.sourceRecordId;

  static const knownKeys = <String>{
    'id',
    'seasonId',
    'stageId',
    'teamId',
    'capturedAt',
    'rank',
    'played',
    'wins',
    'losses',
    'draws',
    'runsScored',
    'runsAllowed',
    'gamesBehind',
    'deletedAt',
    'source',
  };

  factory StandingDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final id = r.requireString('id');
    final wins = r.optionalInt('wins') ?? 0;
    final losses = r.optionalInt('losses') ?? 0;
    final draws = r.optionalInt('draws') ?? 0;
    final played = r.optionalInt('played') ?? (wins + losses + draws);
    if (played < wins + losses + draws) {
      throw DtoValidationException(
        'played',
        '경기 수가 승/패/무 합계보다 적습니다',
        recordId: id,
      );
    }
    return StandingDto(
      id: id,
      seasonId: r.requireString('seasonId'),
      stageId: r.optionalString('stageId'),
      teamId: r.requireString('teamId'),
      capturedAt: r.requireInstant('capturedAt'),
      rank: r.optionalInt('rank'),
      played: played,
      wins: wins,
      losses: losses,
      draws: draws,
      runsScored: r.optionalInt('runsScored') ?? 0,
      runsAllowed: r.optionalInt('runsAllowed') ?? 0,
      gamesBehind: r.optionalDouble('gamesBehind'),
      deletedAt: r.optionalInstant('deletedAt'),
      source: ProvenanceDto.fromReader(r),
    );
  }
}

@immutable
class ArticleDto implements EntityDto {
  const ArticleDto({
    required this.id,
    required this.title,
    required this.url,
    required this.publishedAt,
    required this.source,
    this.outlet,
    this.summary,
    this.teamIds = const <String>[],
    this.competitionIds = const <String>[],
    this.isOfficialNotice = false,
    this.deletedAt,
  });

  @override
  final String id;
  final String title;
  final String url;
  final DateTime publishedAt;
  final String? outlet;
  final String? summary;
  final List<String> teamIds;
  final List<String> competitionIds;
  final bool isOfficialNotice;

  @override
  final ProvenanceDto source;
  @override
  final DateTime? deletedAt;

  @override
  String? get sourceRecordId => source.sourceRecordId;

  static const knownKeys = <String>{
    'id',
    'title',
    'url',
    'publishedAt',
    'outlet',
    'summary',
    'teamIds',
    'competitionIds',
    'isOfficialNotice',
    'deletedAt',
    'source',
  };

  factory ArticleDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return ArticleDto(
      id: r.requireString('id'),
      title: r.requireString('title'),
      url: r.requireUrl('url'),
      publishedAt: r.requireInstant('publishedAt'),
      outlet: r.optionalString('outlet'),
      summary: r.optionalString('summary'),
      teamIds: r.stringList('teamIds'),
      competitionIds: r.stringList('competitionIds'),
      isOfficialNotice: r.optionalBool('isOfficialNotice'),
      deletedAt: r.optionalInstant('deletedAt'),
      source: ProvenanceDto.fromReader(r),
    );
  }
}

@immutable
class VideoDto implements EntityDto {
  const VideoDto({
    required this.id,
    required this.title,
    required this.url,
    required this.publishedAt,
    required this.source,
    this.channelName,
    this.thumbnailUrl,
    this.durationSeconds,
    this.teamIds = const <String>[],
    this.competitionIds = const <String>[],
    this.deletedAt,
  });

  @override
  final String id;
  final String title;
  final String url;
  final DateTime publishedAt;
  final String? channelName;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final List<String> teamIds;
  final List<String> competitionIds;

  @override
  final ProvenanceDto source;
  @override
  final DateTime? deletedAt;

  @override
  String? get sourceRecordId => source.sourceRecordId;

  static const knownKeys = <String>{
    'id',
    'title',
    'url',
    'publishedAt',
    'channelName',
    'thumbnailUrl',
    'durationSeconds',
    'teamIds',
    'competitionIds',
    'deletedAt',
    'source',
  };

  factory VideoDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return VideoDto(
      id: r.requireString('id'),
      title: r.requireString('title'),
      url: r.requireUrl('url'),
      publishedAt: r.requireInstant('publishedAt'),
      channelName: r.optionalString('channelName'),
      thumbnailUrl: r.optionalUrl('thumbnailUrl'),
      durationSeconds: r.optionalInt('durationSeconds'),
      teamIds: r.stringList('teamIds'),
      competitionIds: r.stringList('competitionIds'),
      deletedAt: r.optionalInstant('deletedAt'),
      source: ProvenanceDto.fromReader(r),
    );
  }
}

@immutable
class PersonDto implements EntityDto {
  const PersonDto({
    required this.id,
    required this.name,
    required this.source,
    this.isMinor = false,
    this.photoUrl,
    this.photoLicense,
    this.aliases = const <String>[],
    this.deletedAt,
  });

  @override
  final String id;
  final String name;
  final bool isMinor;
  final String? photoUrl;
  final String? photoLicense;
  final List<String> aliases;

  @override
  final ProvenanceDto source;
  @override
  final DateTime? deletedAt;

  @override
  String? get sourceRecordId => source.sourceRecordId;

  static const knownKeys = <String>{
    'id',
    'name',
    'isMinor',
    'photoUrl',
    'photoLicense',
    'aliases',
    'deletedAt',
    'source',
  };

  factory PersonDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    // Defence in depth: even if an upstream feed carries contact details, the
    // DTO has nowhere to put them, so they cannot reach the database.
    return PersonDto(
      id: r.requireString('id'),
      name: r.requireString('name'),
      isMinor: r.optionalBool('isMinor'),
      photoUrl: r.optionalUrl('photoUrl'),
      photoLicense: r.optionalString('photoLicense'),
      aliases: r.stringList('aliases'),
      deletedAt: r.optionalInstant('deletedAt'),
      source: ProvenanceDto.fromReader(r),
    );
  }
}

@immutable
class RosterEntryDto implements EntityDto {
  const RosterEntryDto({
    required this.id,
    required this.teamId,
    required this.seasonId,
    required this.personId,
    required this.source,
    this.jerseyNumber,
    this.position,
    this.deletedAt,
  });

  @override
  final String id;
  final String teamId;
  final String seasonId;
  final String personId;
  final String? jerseyNumber;
  final String? position;

  @override
  final ProvenanceDto source;
  @override
  final DateTime? deletedAt;

  @override
  String? get sourceRecordId => source.sourceRecordId;

  static const knownKeys = <String>{
    'id',
    'teamId',
    'seasonId',
    'personId',
    'jerseyNumber',
    'position',
    'deletedAt',
    'source',
  };

  factory RosterEntryDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return RosterEntryDto(
      id: r.requireString('id'),
      teamId: r.requireString('teamId'),
      seasonId: r.requireString('seasonId'),
      personId: r.requireString('personId'),
      jerseyNumber: r.optionalString('jerseyNumber'),
      position: r.optionalString('position'),
      deletedAt: r.optionalInstant('deletedAt'),
      source: ProvenanceDto.fromReader(r),
    );
  }
}

/// Accepts an http(s) URL, or an `app:` URI for content the app itself wrote.
/// Anything else is rejected, so a record can never carry an unopenable link.
String _requireSourceUrl(JsonReader r) {
  final raw = r.optionalString('sourceUrl');
  if (raw == null || raw.isEmpty) {
    throw DtoValidationException(
      'sourceUrl',
      '출처 URL이 없습니다',
      recordId: r.recordId,
    );
  }
  final uri = Uri.tryParse(raw);
  final ok =
      uri != null &&
      ((uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty ||
          uri.scheme == 'app');
  if (!ok) {
    throw DtoValidationException(
      'sourceUrl',
      '지원하지 않는 출처 URL 형식입니다: $raw',
      recordId: r.recordId,
    );
  }
  return raw;
}
