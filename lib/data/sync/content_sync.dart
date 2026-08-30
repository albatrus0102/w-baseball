import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/database/database.dart';
import '../dto/content_dtos.dart';
import '../dto/json_reader.dart';
import '../sources/json_document_data_source.dart';
import '../sources/payload_envelope.dart';
import 'sync_contracts.dart';

/// Reads and applies the discovery bundle.
///
/// Separate from [SyncEngine] because editorial content has different
/// cardinality and a different review lifecycle, but it deliberately reuses the
/// same primitives: [PayloadEnvelope] for the outer document, the tolerant
/// [JsonReader] DTOs, per-record quarantine, and a single transaction for the
/// whole apply. So the contract guarantees are identical.
class ContentSyncEngine {
  ContentSyncEngine({
    required this.db,
    required this.supportsSchemaVersion,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final WbDatabase db;
  final bool Function(int schemaVersion) supportsSchemaVersion;
  final DateTime Function() _clock;

  static const String discoverPath = 'content/discover.json';
  static const String sourceName = 'content-bundle';

  /// Decodes a bundle document. Per-record failures become issues, not throws.
  DiscoverBundleDto decode(String body) {
    final envelope = PayloadEnvelope.decode(body);
    if (!supportsSchemaVersion(envelope.schemaVersion)) {
      throw SyncException(
        SyncFailureKind.schemaUnsupported,
        sourceName: sourceName,
        receivedSchemaVersion: envelope.schemaVersion,
        message: '지원하지 않는 콘텐츠 데이터 버전입니다.',
      );
    }

    // The bundle's `items` holds exactly one object with a section per type.
    final first = envelope.items.isEmpty ? null : envelope.items.first;
    if (first == null) return const DiscoverBundleDto();
    final root = JsonReader.of(first);

    final issues = <String>[];

    List<T> decodeSection<T>(String key, T Function(Object?) parse) {
      final raw = (first as Map)[key];
      if (raw is! List) return <T>[];
      final out = <T>[];
      for (final entry in raw) {
        try {
          out.add(parse(entry));
        } on Object catch (e) {
          // Quarantine this record only.
          issues.add('$key: $e');
        }
      }
      return out;
    }

    // `root` is used for its side effect of validating the shape.
    root.optionalString('generatedAt');

    return DiscoverBundleDto(
      featuredTopics: decodeSection(
        'featuredTopics',
        FeaturedTopicDto.fromJson,
      ),
      programs: decodeSection('programs', ProgramDto.fromJson),
      clips: decodeSection('clips', OfficialClipDto.fromJson),
      storyClusters: decodeSection('storyClusters', StoryClusterDto.fromJson),
      guides: decodeSection('guides', BeginnerGuideDto.fromJson),
      attendance: decodeSection('attendance', AttendanceInfoDto.fromJson),
      forecasts: decodeSection('forecasts', WeatherForecastDto.fromJson),
      issues: issues,
    );
  }

  /// Applies a decoded bundle in one transaction.
  Future<SyncResult> apply(DiscoverBundleDto bundle) async {
    final startedAt = _clock().toUtc();
    var inserted = 0;

    await db.transaction(() async {
      for (final topic in bundle.featuredTopics) {
        await db
            .into(db.featuredTopics)
            .insertOnConflictUpdate(
              FeaturedTopicsCompanion.insert(
                id: topic.id,
                kind: topic.kind,
                title: topic.title,
                subtitle: Value(topic.subtitle),
                priority: Value(topic.priority),
                programId: Value(topic.programId),
                competitionId: Value(topic.competitionId),
                storyClusterId: Value(topic.storyClusterId),
                guideId: Value(topic.guideId),
                heroImageUrl: Value(topic.heroImageUrl),
                heroImageLicense: _defaulted(topic.heroImageLicense),
                activeFrom: Value(topic.activeFrom),
                activeUntil: Value(topic.activeUntil),
                deletedAt: Value(topic.deletedAt),
                sourceName: topic.meta.source.sourceName,
                sourceUrl: topic.meta.source.sourceUrl,
                sourceRecordId: Value(topic.meta.source.sourceRecordId),
                fetchedAt: topic.meta.source.fetchedAt,
                verifiedAt: Value(topic.meta.source.verifiedAt),
                licenseStatus: _defaulted(topic.meta.source.licenseStatus),
                isDemo: Value(topic.meta.source.isDemo),
                publishedAt: topic.meta.publishedAt,
                summaryMethod: _defaulted(topic.meta.summaryMethod),
                reviewStatus: _reviewOrPending(topic.meta.reviewStatus),
                spoilerLevel: _spoilerOrNone(topic.meta.spoilerLevel),
                generatedAt: Value(topic.meta.generatedAt),
                coverageObserved: Value(topic.meta.coverageObserved),
                coverageExpected: Value(topic.meta.coverageExpected),
                coverageNote: Value(topic.meta.coverageNote),
              ),
            );
        inserted++;
      }

      for (final program in bundle.programs) {
        await db
            .into(db.programs)
            .insertOnConflictUpdate(
              ProgramsCompanion.insert(
                id: program.id,
                title: program.title,
                broadcaster: Value(program.broadcaster),
                officialUrl: Value(program.officialUrl),
                streamingUrl: Value(program.streamingUrl),
                description: Value(program.description),
                deletedAt: Value(program.deletedAt),
                sourceName: program.meta.source.sourceName,
                sourceUrl: program.meta.source.sourceUrl,
                fetchedAt: program.meta.source.fetchedAt,
                licenseStatus: _defaulted(program.meta.source.licenseStatus),
                isDemo: Value(program.meta.source.isDemo),
                publishedAt: program.meta.publishedAt,
                summaryMethod: _defaulted(program.meta.summaryMethod),
                reviewStatus: _reviewOrPending(program.meta.reviewStatus),
                spoilerLevel: _spoilerOrNone(program.meta.spoilerLevel),
              ),
            );
        inserted++;

        for (final season in program.seasons) {
          await db
              .into(db.programSeasons)
              .insertOnConflictUpdate(
                ProgramSeasonsCompanion.insert(
                  id: season.id,
                  programId: season.programId,
                  seasonNumber: season.seasonNumber,
                  title: season.title,
                  airDayOfWeek: Value(season.airDayOfWeek),
                  airTimeMinuteOfDay: Value(season.airTimeMinuteOfDay),
                  premiereDate: Value(season.premiereDate),
                  finaleDate: Value(season.finaleDate),
                  isActive: Value(season.isActive),
                  deletedAt: Value(season.deletedAt),
                  sourceName: season.meta.source.sourceName,
                  sourceUrl: season.meta.source.sourceUrl,
                  fetchedAt: season.meta.source.fetchedAt,
                  licenseStatus: _defaulted(season.meta.source.licenseStatus),
                  isDemo: Value(season.meta.source.isDemo),
                  publishedAt: season.meta.publishedAt,
                  summaryMethod: _defaulted(season.meta.summaryMethod),
                  reviewStatus: _reviewOrPending(season.meta.reviewStatus),
                  spoilerLevel: _spoilerOrNone(season.meta.spoilerLevel),
                ),
              );
          inserted++;

          for (final episode in season.episodes) {
            await db
                .into(db.episodes)
                .insertOnConflictUpdate(
                  EpisodesCompanion.insert(
                    id: episode.id,
                    programSeasonId: episode.programSeasonId,
                    episodeNumber: episode.episodeNumber,
                    title: Value(episode.title),
                    airedAt: Value(episode.airedAt),
                    officialUrl: Value(episode.officialUrl),
                    deletedAt: Value(episode.deletedAt),
                    sourceName: episode.meta.source.sourceName,
                    sourceUrl: episode.meta.source.sourceUrl,
                    fetchedAt: episode.meta.source.fetchedAt,
                    licenseStatus: _defaulted(
                      episode.meta.source.licenseStatus,
                    ),
                    isDemo: Value(episode.meta.source.isDemo),
                    publishedAt: episode.meta.publishedAt,
                    summaryMethod: _defaulted(episode.meta.summaryMethod),
                    reviewStatus: _reviewOrPending(episode.meta.reviewStatus),
                    spoilerLevel: _spoilerOrResult(episode.meta.spoilerLevel),
                  ),
                );
            inserted++;

            final recap = episode.recap;
            if (recap != null) {
              await db
                  .into(db.episodeRecaps)
                  .insertOnConflictUpdate(
                    EpisodeRecapsCompanion.insert(
                      id: recap.id,
                      episodeId: recap.episodeId,
                      teaser: Value(recap.teaser),
                      whatHappened: Value(recap.whatHappened),
                      whyItMatters: Value(recap.whyItMatters),
                      whatToWatchNext: Value(recap.whatToWatchNext),
                      background: Value(recap.background),
                      realBaseballContext: Value(recap.realBaseballContext),
                      deletedAt: Value(recap.deletedAt),
                      sourceName: recap.meta.source.sourceName,
                      sourceUrl: recap.meta.source.sourceUrl,
                      fetchedAt: recap.meta.source.fetchedAt,
                      verifiedAt: Value(recap.meta.source.verifiedAt),
                      licenseStatus: _defaulted(
                        recap.meta.source.licenseStatus,
                      ),
                      isDemo: Value(recap.meta.source.isDemo),
                      publishedAt: recap.meta.publishedAt,
                      summaryMethod: _defaulted(recap.meta.summaryMethod),
                      reviewStatus: _reviewOrPending(recap.meta.reviewStatus),
                      spoilerLevel: _spoilerOrResult(recap.meta.spoilerLevel),
                      generatedAt: Value(recap.meta.generatedAt),
                    ),
                  );
              inserted++;
            }

            for (final person in episode.people) {
              await db
                  .into(db.featuredPeople)
                  .insertOnConflictUpdate(
                    FeaturedPeopleCompanion.insert(
                      id: person.id,
                      displayName: person.displayName,
                      episodeId: Value(person.episodeId),
                      storylineId: Value(person.storylineId),
                      role: Value(person.role),
                      whyWatch: Value(person.whyWatch),
                      linkedPersonId: Value(person.linkedPersonId),
                      linkedTeamId: Value(person.linkedTeamId),
                      photoUrl: Value(person.photoUrl),
                      photoLicense: _defaulted(person.photoLicense),
                      deletedAt: Value(person.deletedAt),
                      sourceName: person.meta.source.sourceName,
                      sourceUrl: person.meta.source.sourceUrl,
                      fetchedAt: person.meta.source.fetchedAt,
                      licenseStatus: _defaulted(
                        person.meta.source.licenseStatus,
                      ),
                      isDemo: Value(person.meta.source.isDemo),
                      publishedAt: person.meta.publishedAt,
                      summaryMethod: _defaulted(person.meta.summaryMethod),
                      reviewStatus: _reviewOrPending(person.meta.reviewStatus),
                      spoilerLevel: _spoilerOrNone(person.meta.spoilerLevel),
                    ),
                  );
              inserted++;
            }
          }
        }
      }

      for (final clip in bundle.clips) {
        await db
            .into(db.officialClips)
            .insertOnConflictUpdate(
              OfficialClipsCompanion.insert(
                id: clip.id,
                title: clip.title,
                url: clip.url,
                programSeasonId: Value(clip.programSeasonId),
                episodeId: Value(clip.episodeId),
                thumbnailUrl: Value(clip.thumbnailUrl),
                thumbnailLicense: _defaulted(clip.thumbnailLicense),
                durationSeconds: Value(clip.durationSeconds),
                channelName: Value(clip.channelName),
                deletedAt: Value(clip.deletedAt),
                sourceName: clip.meta.source.sourceName,
                sourceUrl: clip.meta.source.sourceUrl,
                fetchedAt: clip.meta.source.fetchedAt,
                licenseStatus: _defaulted(clip.meta.source.licenseStatus),
                isDemo: Value(clip.meta.source.isDemo),
                publishedAt: clip.meta.publishedAt,
                summaryMethod: _defaulted(clip.meta.summaryMethod),
                reviewStatus: _reviewOrPending(clip.meta.reviewStatus),
                spoilerLevel: _spoilerOrResult(clip.meta.spoilerLevel),
              ),
            );
        inserted++;
      }

      for (final cluster in bundle.storyClusters) {
        await db
            .into(db.storyClusters)
            .insertOnConflictUpdate(
              StoryClustersCompanion.insert(
                id: cluster.id,
                title: cluster.title,
                shortSummary: Value(cluster.shortSummary),
                whyItMatters: Value(cluster.whyItMatters),
                beginnerContext: Value(cluster.beginnerContext),
                firstPublishedAt: cluster.firstPublishedAt,
                lastUpdatedAt: cluster.lastUpdatedAt,
                isTopStory: Value(cluster.isTopStory),
                deletedAt: Value(cluster.deletedAt),
                sourceName: cluster.meta.source.sourceName,
                sourceUrl: cluster.meta.source.sourceUrl,
                fetchedAt: cluster.meta.source.fetchedAt,
                verifiedAt: Value(cluster.meta.source.verifiedAt),
                licenseStatus: _defaulted(cluster.meta.source.licenseStatus),
                isDemo: Value(cluster.meta.source.isDemo),
                publishedAt: cluster.meta.publishedAt,
                summaryMethod: _defaulted(cluster.meta.summaryMethod),
                reviewStatus: _reviewOrPending(cluster.meta.reviewStatus),
                spoilerLevel: _spoilerOrResult(cluster.meta.spoilerLevel),
                generatedAt: Value(cluster.meta.generatedAt),
              ),
            );
        inserted++;

        for (final source in cluster.sources) {
          await db
              .into(db.storySources)
              .insertOnConflictUpdate(
                StorySourcesCompanion.insert(
                  id: source.id,
                  storyClusterId: source.storyClusterId,
                  title: source.title,
                  url: source.url,
                  publishedAt: source.publishedAt,
                  outlet: Value(source.outlet),
                  apiDescription: Value(source.apiDescription),
                ),
              );
        }
        for (final link in cluster.links) {
          await _insertLink(link);
        }
      }

      for (final guide in bundle.guides) {
        await db
            .into(db.beginnerGuides)
            .insertOnConflictUpdate(
              BeginnerGuidesCompanion.insert(
                id: guide.id,
                kind: guide.kind,
                title: guide.title,
                body: guide.body,
                anchorKey: Value(guide.anchorKey),
                readSeconds: Value(guide.readSeconds),
                deletedAt: Value(guide.deletedAt),
                sourceName: guide.meta.source.sourceName,
                sourceUrl: guide.meta.source.sourceUrl,
                fetchedAt: guide.meta.source.fetchedAt,
                licenseStatus: _defaulted(guide.meta.source.licenseStatus),
                isDemo: Value(guide.meta.source.isDemo),
                publishedAt: guide.meta.publishedAt,
                summaryMethod: _defaulted(guide.meta.summaryMethod),
                reviewStatus: _reviewOrPending(guide.meta.reviewStatus),
                spoilerLevel: _spoilerOrNone(guide.meta.spoilerLevel),
              ),
            );
        inserted++;
      }

      for (final info in bundle.attendance) {
        await db
            .into(db.attendanceInfos)
            .insertOnConflictUpdate(
              AttendanceInfosCompanion.insert(
                gameId: info.gameId,
                status: _defaulted(info.status),
                admissionNote: Value(info.admissionNote),
                entryProcedure: Value(info.entryProcedure),
                seatingNote: Value(info.seatingNote),
                parkingUrl: Value(info.parkingUrl),
                transitUrl: Value(info.transitUrl),
                restroomAvailable: Value(info.restroomAvailable),
                concessionAvailable: Value(info.concessionAvailable),
                familyFriendlyConfirmed: Value(info.familyFriendlyConfirmed),
                confirmedAt: Value(info.confirmedAt),
                sourceName: info.source.sourceName,
                sourceUrl: info.source.sourceUrl,
                fetchedAt: info.source.fetchedAt,
                licenseStatus: _defaulted(info.source.licenseStatus),
                isDemo: Value(info.source.isDemo),
              ),
            );
        inserted++;
      }

      for (final forecast in bundle.forecasts) {
        await db
            .into(db.weatherForecasts)
            .insertOnConflictUpdate(
              WeatherForecastsCompanion.insert(
                id: forecast.id,
                venueId: forecast.venueId,
                gameId: Value(forecast.gameId),
                targetTimeUtc: forecast.targetTime,
                horizon: forecast.horizon ?? 'midTerm',
                issuedAt: forecast.issuedAt,
                forecastZone: Value(forecast.forecastZone),
                temperatureC: Value(forecast.temperatureC),
                temperatureMinC: Value(forecast.temperatureMinC),
                temperatureMaxC: Value(forecast.temperatureMaxC),
                precipitationProbability: Value(
                  forecast.precipitationProbability,
                ),
                precipitationMm: Value(forecast.precipitationMm),
                windSpeedMs: Value(forecast.windSpeedMs),
                humidityPercent: Value(forecast.humidityPercent),
                skyCondition: Value(forecast.skyCondition),
                confidence: _defaulted(forecast.confidence),
                seasonalTendency: Value(forecast.seasonalTendency),
                sourceName: forecast.source.sourceName,
                sourceUrl: forecast.source.sourceUrl,
                fetchedAt: forecast.source.fetchedAt,
                licenseStatus: _defaulted(forecast.source.licenseStatus),
                isDemo: Value(forecast.source.isDemo),
              ),
            );
        inserted++;
      }
    });

    return SyncResult(
      sourceName: sourceName,
      startedAt: startedAt,
      finishedAt: _clock().toUtc(),
      inserted: inserted,
      issues: bundle.issues
          .map(
            (message) => SyncIssue(
              severity: SyncIssueSeverity.recordRejected,
              sourceName: sourceName,
              entityType: 'content',
              message: message,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> _insertLink(ContentLinkDto link) async {
    await db
        .into(db.contentEntityLinks)
        .insertOnConflictUpdate(
          ContentEntityLinksCompanion.insert(
            id: link.id,
            fromKind: link.fromKind,
            fromId: link.fromId,
            toKind: link.toKind,
            toId: link.toId,
            relation: link.relation,
            label: Value(link.label),
            confirmedSourceUrl: Value(link.confirmedSourceUrl),
          ),
        );
  }

  /// Convenience: read a bundle from a [JsonDocumentDataSource] and apply it.
  Future<SyncResult?> syncFrom(JsonDocumentDataSource source) async {
    final doc = await source.loadDocument(discoverPath, const SyncValidators());
    if (doc == null || doc.notModified || doc.body.isEmpty) return null;
    return apply(decode(doc.body));
  }

  /// Round-trips a bundle back to JSON. Used by the publish script's
  /// verification step and by contract tests.
  static String encodeBundle(Map<String, Object?> sections) => jsonEncode({
    'schemaVersion': 1,
    'items': <Object?>[sections],
  });
}

/// `Value.absent()` for a null, so a column that has a database default keeps
/// it instead of being handed a null the schema does not allow.
Value<String> _defaulted(String? value) =>
    value == null ? const Value<String>.absent() : Value<String>(value);

/// Spoiler level for content that can carry an outcome.
///
/// A missing `spoilerLevel` used to fall through to the column default of
/// `none`, i.e. "safe to show". That is the wrong direction to fail: showing a
/// result to someone who asked not to see it cannot be undone, while veiling
/// something harmless costs one tap. Anything that could contain a result —
/// an episode, a recap, a clip, a news cluster — is therefore treated as a
/// spoiler until the source says otherwise.
Value<String> _spoilerOrResult(String? value) =>
    value == null ? const Value<String>(_spoilerResult) : Value<String>(value);

/// Spoiler level for evergreen content (guides, programme metadata, people).
/// Nothing here carries a result, so an absent value really is `none`.
Value<String> _spoilerOrNone(String? value) =>
    value == null ? const Value<String>(_spoilerNone) : Value<String>(value);

/// Review status for synced content.
///
/// Never defaults to `reviewed`. Automation produces candidates; only a person
/// promotes them, and an omitted field is not a promotion.
Value<String> _reviewOrPending(String? value) =>
    value == null ? const Value<String>(_reviewPending) : Value<String>(value);

const _spoilerResult = 'result';
const _spoilerNone = 'none';
const _reviewPending = 'pending';
