import 'package:meta/meta.dart';

import 'dtos.dart' show ProvenanceDto;
import 'json_reader.dart';

/// Wire DTOs for the discovery layer.
///
/// These travel in a single `content/discover.json` bundle rather than one
/// file per type: the editorial set is small, changes together, and is always
/// read together. It still goes through the same [PayloadEnvelope] →
/// tolerant-decode → quarantine path as sport data, so the contract rules
/// (unknown fields ignored, bad records isolated, schema version gated) hold
/// identically.

/// Editorial metadata block, the content counterpart of `ProvenanceDto`.
@immutable
class ContentMetaDto {
  const ContentMetaDto({
    required this.source,
    required this.publishedAt,
    this.summaryMethod,
    this.reviewStatus,
    this.spoilerLevel,
    this.generatedAt,
    this.coverageObserved = 0,
    this.coverageExpected = 0,
    this.coverageNote,
  });

  final ProvenanceDto source;
  final DateTime publishedAt;
  final String? summaryMethod;
  final String? reviewStatus;
  final String? spoilerLevel;
  final DateTime? generatedAt;
  final int coverageObserved;
  final int coverageExpected;
  final String? coverageNote;

  factory ContentMetaDto.fromReader(JsonReader r) {
    final method = r.optionalString('summaryMethod');
    final generatedAt = r.optionalInstant('generatedAt');

    // An AI-assisted summary without a generation time cannot be labelled
    // honestly, so it is rejected rather than shown with a missing timestamp.
    if (method == 'aiAssisted' && generatedAt == null) {
      throw DtoValidationException(
        'generatedAt',
        'AI 요약에는 생성 시각이 필요합니다',
        recordId: r.recordId,
      );
    }

    return ContentMetaDto(
      source: ProvenanceDto.fromReader(r),
      publishedAt: r.requireInstant('publishedAt'),
      summaryMethod: method,
      reviewStatus: r.optionalString('reviewStatus'),
      spoilerLevel: r.optionalString('spoilerLevel'),
      generatedAt: generatedAt,
      coverageObserved: r.optionalInt('coverageObserved') ?? 0,
      coverageExpected: r.optionalInt('coverageExpected') ?? 0,
      coverageNote: r.optionalString('coverageNote'),
    );
  }
}

@immutable
class ProgramDto {
  const ProgramDto({
    required this.id,
    required this.title,
    required this.meta,
    this.broadcaster,
    this.officialUrl,
    this.streamingUrl,
    this.description,
    this.seasons = const <ProgramSeasonDto>[],
    this.deletedAt,
  });

  final String id;
  final String title;
  final String? broadcaster;
  final String? officialUrl;
  final String? streamingUrl;
  final String? description;
  final List<ProgramSeasonDto> seasons;
  final ContentMetaDto meta;
  final DateTime? deletedAt;

  factory ProgramDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final id = r.requireString('id');
    return ProgramDto(
      id: id,
      title: r.requireString('title'),
      broadcaster: r.optionalString('broadcaster'),
      officialUrl: r.optionalUrl('officialUrl'),
      streamingUrl: r.optionalUrl('streamingUrl'),
      description: r.optionalString('description'),
      seasons: r
          .objectList('seasons')
          .map((s) => ProgramSeasonDto.fromReader(s, programId: id))
          .toList(growable: false),
      deletedAt: r.optionalInstant('deletedAt'),
      meta: ContentMetaDto.fromReader(r),
    );
  }
}

@immutable
class ProgramSeasonDto {
  const ProgramSeasonDto({
    required this.id,
    required this.programId,
    required this.seasonNumber,
    required this.title,
    required this.meta,
    this.airDayOfWeek,
    this.airTimeMinuteOfDay,
    this.premiereDate,
    this.finaleDate,
    this.isActive = true,
    this.episodes = const <EpisodeDto>[],
    this.deletedAt,
  });

  final String id;
  final String programId;
  final int seasonNumber;
  final String title;
  final int? airDayOfWeek;
  final int? airTimeMinuteOfDay;
  final DateTime? premiereDate;
  final DateTime? finaleDate;
  final bool isActive;
  final List<EpisodeDto> episodes;
  final ContentMetaDto meta;
  final DateTime? deletedAt;

  factory ProgramSeasonDto.fromReader(JsonReader r, {String? programId}) {
    final id = r.requireString('id');
    final owner = r.optionalString('programId') ?? programId;
    if (owner == null) {
      throw DtoValidationException('programId', '프로그램 참조가 없습니다', recordId: id);
    }
    final day = r.optionalInt('airDayOfWeek');
    if (day != null && (day < 1 || day > 7)) {
      throw DtoValidationException(
        'airDayOfWeek',
        '요일은 1~7 이어야 합니다',
        recordId: id,
      );
    }
    return ProgramSeasonDto(
      id: id,
      programId: owner,
      seasonNumber: r.requireInt('seasonNumber'),
      title: r.requireString('title'),
      airDayOfWeek: day,
      airTimeMinuteOfDay: r.optionalInt('airTimeMinuteOfDay'),
      premiereDate: r.optionalDate('premiereDate'),
      finaleDate: r.optionalDate('finaleDate'),
      isActive: r.optionalBool('isActive', fallback: true),
      episodes: r
          .objectList('episodes')
          .map((e) => EpisodeDto.fromReader(e, programSeasonId: id))
          .toList(growable: false),
      deletedAt: r.optionalInstant('deletedAt'),
      meta: ContentMetaDto.fromReader(r),
    );
  }
}

@immutable
class EpisodeDto {
  const EpisodeDto({
    required this.id,
    required this.programSeasonId,
    required this.episodeNumber,
    required this.meta,
    this.title,
    this.airedAt,
    this.officialUrl,
    this.recap,
    this.people = const <FeaturedPersonDto>[],
    this.deletedAt,
  });

  final String id;
  final String programSeasonId;
  final int episodeNumber;
  final String? title;
  final DateTime? airedAt;
  final String? officialUrl;
  final EpisodeRecapDto? recap;
  final List<FeaturedPersonDto> people;
  final ContentMetaDto meta;
  final DateTime? deletedAt;

  factory EpisodeDto.fromReader(JsonReader r, {String? programSeasonId}) {
    final id = r.requireString('id');
    final owner = r.optionalString('programSeasonId') ?? programSeasonId;
    if (owner == null) {
      throw DtoValidationException(
        'programSeasonId',
        '시즌 참조가 없습니다',
        recordId: id,
      );
    }
    final recapReader = r.optionalObject('recap');
    return EpisodeDto(
      id: id,
      programSeasonId: owner,
      episodeNumber: r.requireInt('episodeNumber'),
      title: r.optionalString('title'),
      airedAt: r.optionalInstant('airedAt'),
      officialUrl: r.optionalUrl('officialUrl'),
      recap: recapReader == null
          ? null
          : EpisodeRecapDto.fromReader(recapReader, episodeId: id),
      people: r
          .objectList('people')
          .map((p) => FeaturedPersonDto.fromReader(p, episodeId: id))
          .toList(growable: false),
      deletedAt: r.optionalInstant('deletedAt'),
      meta: ContentMetaDto.fromReader(r),
    );
  }
}

@immutable
class EpisodeRecapDto {
  const EpisodeRecapDto({
    required this.id,
    required this.episodeId,
    required this.meta,
    this.teaser,
    this.whatHappened,
    this.whyItMatters,
    this.whatToWatchNext,
    this.background,
    this.realBaseballContext,
    this.deletedAt,
  });

  final String id;
  final String episodeId;
  final String? teaser;
  final String? whatHappened;
  final String? whyItMatters;
  final String? whatToWatchNext;
  final String? background;
  final String? realBaseballContext;
  final ContentMetaDto meta;
  final DateTime? deletedAt;

  factory EpisodeRecapDto.fromReader(JsonReader r, {String? episodeId}) {
    final id = r.requireString('id');
    final owner = r.optionalString('episodeId') ?? episodeId;
    if (owner == null) {
      throw DtoValidationException('episodeId', '회차 참조가 없습니다', recordId: id);
    }
    final teaser = r.optionalString('teaser');
    final spoiler = r.optionalString('spoilerLevel');

    // A recap that reveals a result must carry a spoiler-free teaser, or the
    // hide-results setting would have nothing safe to display.
    if ((spoiler == 'result' || spoiler == 'full') &&
        (teaser == null || teaser.isEmpty)) {
      throw DtoValidationException(
        'teaser',
        '결과가 포함된 요약에는 스포일러 없는 teaser가 필요합니다',
        recordId: id,
      );
    }

    return EpisodeRecapDto(
      id: id,
      episodeId: owner,
      teaser: teaser,
      whatHappened: r.optionalString('whatHappened'),
      whyItMatters: r.optionalString('whyItMatters'),
      whatToWatchNext: r.optionalString('whatToWatchNext'),
      background: r.optionalString('background'),
      realBaseballContext: r.optionalString('realBaseballContext'),
      deletedAt: r.optionalInstant('deletedAt'),
      meta: ContentMetaDto.fromReader(r),
    );
  }
}

@immutable
class FeaturedPersonDto {
  const FeaturedPersonDto({
    required this.id,
    required this.displayName,
    required this.meta,
    this.episodeId,
    this.storylineId,
    this.role,
    this.whyWatch,
    this.linkedPersonId,
    this.linkedTeamId,
    this.photoUrl,
    this.photoLicense,
    this.deletedAt,
  });

  final String id;
  final String displayName;
  final String? episodeId;
  final String? storylineId;
  final String? role;
  final String? whyWatch;
  final String? linkedPersonId;
  final String? linkedTeamId;
  final String? photoUrl;
  final String? photoLicense;
  final ContentMetaDto meta;
  final DateTime? deletedAt;

  factory FeaturedPersonDto.fromReader(JsonReader r, {String? episodeId}) {
    return FeaturedPersonDto(
      id: r.requireString('id'),
      displayName: r.requireString('displayName'),
      episodeId: r.optionalString('episodeId') ?? episodeId,
      storylineId: r.optionalString('storylineId'),
      role: r.optionalString('role'),
      whyWatch: r.optionalString('whyWatch'),
      linkedPersonId: r.optionalString('linkedPersonId'),
      linkedTeamId: r.optionalString('linkedTeamId'),
      photoUrl: r.optionalUrl('photoUrl'),
      photoLicense: r.optionalString('photoLicense'),
      deletedAt: r.optionalInstant('deletedAt'),
      meta: ContentMetaDto.fromReader(r),
    );
  }
}

@immutable
class OfficialClipDto {
  const OfficialClipDto({
    required this.id,
    required this.title,
    required this.url,
    required this.meta,
    this.programSeasonId,
    this.episodeId,
    this.thumbnailUrl,
    this.thumbnailLicense,
    this.durationSeconds,
    this.channelName,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String url;
  final String? programSeasonId;
  final String? episodeId;
  final String? thumbnailUrl;
  final String? thumbnailLicense;
  final int? durationSeconds;
  final String? channelName;
  final ContentMetaDto meta;
  final DateTime? deletedAt;

  factory OfficialClipDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return OfficialClipDto(
      id: r.requireString('id'),
      title: r.requireString('title'),
      url: r.requireUrl('url'),
      programSeasonId: r.optionalString('programSeasonId'),
      episodeId: r.optionalString('episodeId'),
      thumbnailUrl: r.optionalUrl('thumbnailUrl'),
      thumbnailLicense: r.optionalString('thumbnailLicense'),
      durationSeconds: r.optionalInt('durationSeconds'),
      channelName: r.optionalString('channelName'),
      deletedAt: r.optionalInstant('deletedAt'),
      meta: ContentMetaDto.fromReader(r),
    );
  }
}

@immutable
class FeaturedTopicDto {
  const FeaturedTopicDto({
    required this.id,
    required this.kind,
    required this.title,
    required this.meta,
    this.subtitle,
    this.priority,
    this.programId,
    this.competitionId,
    this.storyClusterId,
    this.guideId,
    this.heroImageUrl,
    this.heroImageLicense,
    this.activeFrom,
    this.activeUntil,
    this.deletedAt,
  });

  final String id;
  final String kind;
  final String title;
  final String? subtitle;
  final int? priority;
  final String? programId;
  final String? competitionId;
  final String? storyClusterId;
  final String? guideId;
  final String? heroImageUrl;
  final String? heroImageLicense;
  final DateTime? activeFrom;
  final DateTime? activeUntil;
  final ContentMetaDto meta;
  final DateTime? deletedAt;

  factory FeaturedTopicDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return FeaturedTopicDto(
      id: r.requireString('id'),
      kind: r.requireString('kind'),
      title: r.requireString('title'),
      subtitle: r.optionalString('subtitle'),
      priority: r.optionalInt('priority'),
      programId: r.optionalString('programId'),
      competitionId: r.optionalString('competitionId'),
      storyClusterId: r.optionalString('storyClusterId'),
      guideId: r.optionalString('guideId'),
      heroImageUrl: r.optionalUrl('heroImageUrl'),
      heroImageLicense: r.optionalString('heroImageLicense'),
      activeFrom: r.optionalInstant('activeFrom'),
      activeUntil: r.optionalInstant('activeUntil'),
      deletedAt: r.optionalInstant('deletedAt'),
      meta: ContentMetaDto.fromReader(r),
    );
  }
}

@immutable
class StorySourceDto {
  const StorySourceDto({
    required this.id,
    required this.storyClusterId,
    required this.title,
    required this.url,
    required this.publishedAt,
    this.outlet,
    this.apiDescription,
  });

  final String id;
  final String storyClusterId;
  final String title;
  final String url;
  final DateTime publishedAt;
  final String? outlet;
  final String? apiDescription;

  factory StorySourceDto.fromReader(JsonReader r, {String? clusterId}) {
    final id = r.requireString('id');
    final owner = r.optionalString('storyClusterId') ?? clusterId;
    if (owner == null) {
      throw DtoValidationException(
        'storyClusterId',
        '묶음 참조가 없습니다',
        recordId: id,
      );
    }
    return StorySourceDto(
      id: id,
      storyClusterId: owner,
      title: r.requireString('title'),
      url: r.requireUrl('url'),
      publishedAt: r.requireInstant('publishedAt'),
      outlet: r.optionalString('outlet'),
      // Only the description the news API itself returned belongs here.
      apiDescription: r.optionalString('apiDescription'),
    );
  }
}

@immutable
class StoryClusterDto {
  const StoryClusterDto({
    required this.id,
    required this.title,
    required this.meta,
    required this.firstPublishedAt,
    required this.lastUpdatedAt,
    this.shortSummary,
    this.whyItMatters,
    this.beginnerContext,
    this.isTopStory = false,
    this.sources = const <StorySourceDto>[],
    this.links = const <ContentLinkDto>[],
    this.deletedAt,
  });

  final String id;
  final String title;
  final String? shortSummary;
  final String? whyItMatters;
  final String? beginnerContext;
  final bool isTopStory;
  final DateTime firstPublishedAt;
  final DateTime lastUpdatedAt;
  final List<StorySourceDto> sources;
  final List<ContentLinkDto> links;
  final ContentMetaDto meta;
  final DateTime? deletedAt;

  factory StoryClusterDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final id = r.requireString('id');
    final sources = r
        .objectList('sources')
        .map((s) => StorySourceDto.fromReader(s, clusterId: id))
        .toList(growable: false);

    // A cluster with no source is an unattributed claim.
    if (sources.isEmpty) {
      throw DtoValidationException('sources', '출처가 최소 1개 필요합니다', recordId: id);
    }

    return StoryClusterDto(
      id: id,
      title: r.requireString('title'),
      shortSummary: r.optionalString('shortSummary'),
      whyItMatters: r.optionalString('whyItMatters'),
      beginnerContext: r.optionalString('beginnerContext'),
      isTopStory: r.optionalBool('isTopStory'),
      firstPublishedAt: r.requireInstant('firstPublishedAt'),
      lastUpdatedAt: r.requireInstant('lastUpdatedAt'),
      sources: sources,
      links: r
          .objectList('links')
          .map(
            (l) => ContentLinkDto.fromReader(
              l,
              fromKind: 'storyCluster',
              fromId: id,
            ),
          )
          .toList(growable: false),
      deletedAt: r.optionalInstant('deletedAt'),
      meta: ContentMetaDto.fromReader(r),
    );
  }
}

@immutable
class ContentLinkDto {
  const ContentLinkDto({
    required this.id,
    required this.fromKind,
    required this.fromId,
    required this.toKind,
    required this.toId,
    required this.relation,
    this.label,
    this.confirmedSourceUrl,
  });

  final String id;
  final String fromKind;
  final String fromId;
  final String toKind;
  final String toId;
  final String relation;
  final String? label;
  final String? confirmedSourceUrl;

  factory ContentLinkDto.fromReader(
    JsonReader r, {
    String? fromKind,
    String? fromId,
  }) {
    final id = r.requireString('id');
    final relation = r.optionalString('relation') ?? 'mentions';
    final citation = r.optionalUrl('confirmedSourceUrl');

    // An identity claim ("this broadcast participant *is* this player") must
    // carry a citation, or it is a guess. Rejected rather than shown.
    if (relation == 'isEntity' && (citation == null || citation.isEmpty)) {
      throw DtoValidationException(
        'confirmedSourceUrl',
        '공식 확인 연결에는 근거 URL이 필요합니다',
        recordId: id,
      );
    }

    return ContentLinkDto(
      id: id,
      fromKind: r.optionalString('fromKind') ?? fromKind ?? 'storyCluster',
      fromId: r.optionalString('fromId') ?? fromId ?? '',
      toKind: r.requireString('toKind'),
      toId: r.requireString('toId'),
      relation: relation,
      label: r.optionalString('label'),
      confirmedSourceUrl: citation,
    );
  }
}

@immutable
class BeginnerGuideDto {
  const BeginnerGuideDto({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.meta,
    this.anchorKey,
    this.readSeconds,
    this.deletedAt,
  });

  final String id;
  final String kind;
  final String title;
  final String body;
  final String? anchorKey;
  final int? readSeconds;
  final ContentMetaDto meta;
  final DateTime? deletedAt;

  factory BeginnerGuideDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return BeginnerGuideDto(
      id: r.requireString('id'),
      kind: r.optionalString('kind') ?? 'oneMinuteIntro',
      title: r.requireString('title'),
      body: r.requireString('body'),
      anchorKey: r.optionalString('anchorKey'),
      readSeconds: r.optionalInt('readSeconds'),
      deletedAt: r.optionalInstant('deletedAt'),
      meta: ContentMetaDto.fromReader(r),
    );
  }
}

@immutable
class AttendanceInfoDto {
  const AttendanceInfoDto({
    required this.gameId,
    required this.source,
    this.status,
    this.admissionNote,
    this.entryProcedure,
    this.seatingNote,
    this.parkingUrl,
    this.transitUrl,
    this.restroomAvailable,
    this.concessionAvailable,
    this.familyFriendlyConfirmed = false,
    this.confirmedAt,
  });

  final String gameId;
  final String? status;
  final String? admissionNote;
  final String? entryProcedure;
  final String? seatingNote;
  final String? parkingUrl;
  final String? transitUrl;
  final bool? restroomAvailable;
  final bool? concessionAvailable;
  final bool familyFriendlyConfirmed;
  final DateTime? confirmedAt;
  final ProvenanceDto source;

  factory AttendanceInfoDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final gameId = r.requireString('gameId');
    final status = r.optionalString('status');

    // "open" is a claim about the world; it needs a confirmation timestamp.
    if (status == 'open' && !r.has('confirmedAt')) {
      throw DtoValidationException(
        'confirmedAt',
        '관람 가능 확정에는 확인 시각이 필요합니다',
        recordId: gameId,
      );
    }

    return AttendanceInfoDto(
      gameId: gameId,
      status: status,
      admissionNote: r.optionalString('admissionNote'),
      entryProcedure: r.optionalString('entryProcedure'),
      seatingNote: r.optionalString('seatingNote'),
      parkingUrl: r.optionalUrl('parkingUrl'),
      transitUrl: r.optionalUrl('transitUrl'),
      restroomAvailable: r.has('restroomAvailable')
          ? r.optionalBool('restroomAvailable')
          : null,
      concessionAvailable: r.has('concessionAvailable')
          ? r.optionalBool('concessionAvailable')
          : null,
      familyFriendlyConfirmed: r.optionalBool('familyFriendlyConfirmed'),
      confirmedAt: r.optionalInstant('confirmedAt'),
      source: ProvenanceDto.fromReader(r),
    );
  }
}

@immutable
class WeatherForecastDto {
  const WeatherForecastDto({
    required this.id,
    required this.venueId,
    required this.targetTime,
    required this.issuedAt,
    required this.source,
    this.gameId,
    this.horizon,
    this.forecastZone,
    this.temperatureC,
    this.temperatureMinC,
    this.temperatureMaxC,
    this.precipitationProbability,
    this.precipitationMm,
    this.windSpeedMs,
    this.humidityPercent,
    this.skyCondition,
    this.confidence,
    this.seasonalTendency,
  });

  final String id;
  final String venueId;
  final String? gameId;
  final DateTime targetTime;
  final DateTime issuedAt;
  final String? horizon;
  final String? forecastZone;
  final double? temperatureC;
  final double? temperatureMinC;
  final double? temperatureMaxC;
  final int? precipitationProbability;
  final double? precipitationMm;
  final double? windSpeedMs;
  final int? humidityPercent;
  final String? skyCondition;
  final String? confidence;
  final String? seasonalTendency;
  final ProvenanceDto source;

  factory WeatherForecastDto.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final id = r.requireString('id');
    final targetTime = r.requireInstant('targetTime');
    final issuedAt = r.requireInstant('issuedAt');
    final horizon = r.optionalString('horizon');
    final pop = r.optionalInt('precipitationProbability');

    if (pop != null && (pop < 0 || pop > 100)) {
      throw DtoValidationException(
        'precipitationProbability',
        '강수확률은 0~100 이어야 합니다',
        recordId: id,
      );
    }

    // The publisher must not ship a daily value beyond the forecast horizon.
    // Rejecting here means the honesty rule cannot be bypassed by bad data.
    if (horizon == 'beyondForecast' &&
        (r.has('temperatureC') ||
            r.has('temperatureMinC') ||
            r.has('temperatureMaxC') ||
            pop != null)) {
      throw DtoValidationException(
        'horizon',
        '상세 예보 구간을 벗어난 예보에는 기온·강수확률을 넣을 수 없습니다',
        recordId: id,
      );
    }

    return WeatherForecastDto(
      id: id,
      venueId: r.requireString('venueId'),
      gameId: r.optionalString('gameId'),
      targetTime: targetTime,
      issuedAt: issuedAt,
      horizon: horizon,
      forecastZone: r.optionalString('forecastZone'),
      temperatureC: r.optionalDouble('temperatureC'),
      temperatureMinC: r.optionalDouble('temperatureMinC'),
      temperatureMaxC: r.optionalDouble('temperatureMaxC'),
      precipitationProbability: pop,
      precipitationMm: r.optionalDouble('precipitationMm'),
      windSpeedMs: r.optionalDouble('windSpeedMs'),
      humidityPercent: r.optionalInt('humidityPercent'),
      skyCondition: r.optionalString('skyCondition'),
      confidence: r.optionalString('confidence'),
      seasonalTendency: r.optionalString('seasonalTendency'),
      source: ProvenanceDto.fromReader(r),
    );
  }
}

/// The whole discovery bundle, decoded from one document.
@immutable
class DiscoverBundleDto {
  const DiscoverBundleDto({
    this.featuredTopics = const <FeaturedTopicDto>[],
    this.programs = const <ProgramDto>[],
    this.clips = const <OfficialClipDto>[],
    this.storyClusters = const <StoryClusterDto>[],
    this.guides = const <BeginnerGuideDto>[],
    this.attendance = const <AttendanceInfoDto>[],
    this.forecasts = const <WeatherForecastDto>[],
    this.issues = const <String>[],
  });

  final List<FeaturedTopicDto> featuredTopics;
  final List<ProgramDto> programs;
  final List<OfficialClipDto> clips;
  final List<StoryClusterDto> storyClusters;
  final List<BeginnerGuideDto> guides;
  final List<AttendanceInfoDto> attendance;
  final List<WeatherForecastDto> forecasts;

  /// Per-record rejections, so a single bad entry never loses the bundle.
  final List<String> issues;

  bool get isEmpty =>
      featuredTopics.isEmpty &&
      programs.isEmpty &&
      clips.isEmpty &&
      storyClusters.isEmpty &&
      guides.isEmpty &&
      attendance.isEmpty &&
      forecasts.isEmpty;
}
