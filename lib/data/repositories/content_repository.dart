import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../core/database/database.dart';
import '../mappers/row_mappers.dart';
import '../models/audience.dart';
import '../models/content.dart';
import '../models/domain.dart';

/// A featured topic resolved together with whatever it points at.
@immutable
class FeaturedItem {
  const FeaturedItem({
    required this.topic,
    this.program,
    this.programSeason,
    this.latestEpisode,
    this.latestRecap,
    this.clips = const <OfficialClip>[],
    this.people = const <FeaturedPerson>[],
    this.storyCluster,
    this.guide,
    this.competition,
    this.links = const <ContentEntityLink>[],
    this.isFollowingProgram = false,
  });

  final FeaturedTopic topic;
  final Program? program;
  final ProgramSeason? programSeason;
  final Episode? latestEpisode;
  final EpisodeRecap? latestRecap;
  final List<OfficialClip> clips;
  final List<FeaturedPerson> people;
  final StoryCluster? storyCluster;
  final BeginnerGuide? guide;
  final Competition? competition;
  final List<ContentEntityLink> links;
  final bool isFollowingProgram;

  /// The one-line headline, respecting the user's spoiler choice.
  String headline(SpoilerPolicy policy) {
    final recap = latestRecap;
    if (recap != null) {
      final masked = recap.maskedHeadline(policy);
      if (masked != null && masked.isNotEmpty) return masked;
    }
    return topic.subtitle ?? topic.title;
  }

  /// Whether the card must render its summary behind a "결과 보기" veil.
  bool isMasked(SpoilerPolicy policy) {
    final recap = latestRecap;
    if (recap == null) return false;
    return policy.shouldMask(recap.meta.spoilerLevel);
  }

  /// Confirmed links only. An unconfirmed connection between a broadcast
  /// participant and a real player is never presented as fact.
  List<ContentEntityLink> get confirmedRealLinks =>
      links.where((l) => l.isConfirmedIdentity).toList(growable: false);
}

abstract interface class ContentRepository {
  /// Active featured topics in priority order.
  ///
  /// When a broadcast season ends its topic stops being active and the next
  /// priority (international → domestic → story → nearby → getting started)
  /// takes the lead slot automatically. No release required, no empty section.
  Stream<List<FeaturedItem>> watchFeatured({int limit = 5});

  Stream<FeaturedItem?> watchFeaturedTopic(String topicId);

  /// Non-personalised "모두가 알아둘 주요 소식".
  Stream<List<StoryCluster>> watchTopStories({int limit = 5});

  /// Personalised by follows. Falls back to recency when nothing is followed.
  Stream<List<StoryCluster>> watchStoriesForYou({int limit = 8});

  Stream<StoryCluster?> watchStoryCluster(String clusterId);

  Stream<List<BeginnerGuide>> watchGuides({GuideKind? kind, String? anchorKey});

  Future<BeginnerGuide?> guideForAnchor(String anchorKey);

  Stream<List<Video>> watchVideos({int limit = 20});

  Stream<List<Article>> watchNotices({int limit = 10});

  /// Programme seasons that have finished — the "지난 시즌 다시보기" archive.
  Stream<List<ProgramSeason>> watchArchivedProgramSeasons();

  /// Entities a piece of content links to, for the "실제 여자야구와 연결" block.
  Future<List<ContentEntityLink>> linksFrom(ContentEntityKind kind, String id);
}

class DriftContentRepository implements ContentRepository {
  DriftContentRepository({required this.db, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final WbDatabase db;
  final DateTime Function() _clock;

  @override
  Stream<List<FeaturedItem>> watchFeatured({int limit = 5}) {
    final select = db.select(db.featuredTopics)
      ..where((t) => t.deletedAt.isNull());
    return select.watch().asyncMap((rows) async {
      final now = _clock().toUtc();
      final active =
          rows.map((r) => r.toDomain()).where((t) => t.isActiveAt(now)).toList()
            ..sort(
              (a, b) => a.effectivePriority.compareTo(b.effectivePriority),
            );

      final out = <FeaturedItem>[];
      for (final topic in active.take(limit)) {
        out.add(await _resolve(topic));
      }
      return out;
    });
  }

  @override
  Stream<FeaturedItem?> watchFeaturedTopic(String topicId) {
    final select = db.select(db.featuredTopics)
      ..where((t) => t.id.equals(topicId));
    return select.watchSingleOrNull().asyncMap((row) async {
      if (row == null) return null;
      return _resolve(row.toDomain());
    });
  }

  Future<FeaturedItem> _resolve(FeaturedTopic topic) async {
    Program? program;
    ProgramSeason? season;
    Episode? episode;
    EpisodeRecap? recap;
    var clips = const <OfficialClip>[];
    var people = const <FeaturedPerson>[];
    StoryCluster? cluster;
    BeginnerGuide? guide;
    Competition? competition;
    var links = const <ContentEntityLink>[];
    var following = false;

    if (topic.programId != null) {
      final programRow = await (db.select(
        db.programs,
      )..where((t) => t.id.equals(topic.programId!))).getSingleOrNull();
      program = programRow?.toDomain();

      // Prefer the active season; otherwise the most recent one, so an
      // archived programme still resolves rather than rendering blank.
      final seasonRows =
          await (db.select(db.programSeasons)
                ..where(
                  (t) =>
                      t.programId.equals(topic.programId!) &
                      t.deletedAt.isNull(),
                )
                ..orderBy([(t) => OrderingTerm.desc(t.seasonNumber)]))
              .get();
      final activeRow =
          seasonRows.where((r) => r.isActive).firstOrNull ??
          seasonRows.firstOrNull;
      season = activeRow?.toDomain();

      if (activeRow != null) {
        final now = _clock().toUtc();
        final episodeRows =
            await (db.select(db.episodes)
                  ..where(
                    (t) =>
                        t.programSeasonId.equals(activeRow.id) &
                        t.deletedAt.isNull(),
                  )
                  ..orderBy([(t) => OrderingTerm.desc(t.episodeNumber)]))
                .get();
        // Only episodes that have actually aired. We never present an
        // unaired episode as if it had content.
        final airedRow = episodeRows
            .where((r) => r.airedAt != null && r.airedAt!.isBefore(now))
            .firstOrNull;
        episode = airedRow?.toDomain();

        if (airedRow != null) {
          final recapRow =
              await (db.select(db.episodeRecaps)..where(
                    (t) =>
                        t.episodeId.equals(airedRow.id) & t.deletedAt.isNull(),
                  ))
                  .getSingleOrNull();
          // A recap that has not passed review is simply not shown.
          final candidate = recapRow?.toDomain();
          if (candidate != null && candidate.meta.isPublishable) {
            recap = candidate;
          }

          people =
              (await (db.select(db.featuredPeople)
                        ..where(
                          (t) =>
                              t.episodeId.equals(airedRow.id) &
                              t.deletedAt.isNull(),
                        )
                        ..limit(3))
                      .get())
                  .map((r) => r.toDomain())
                  .toList(growable: false);
        }

        clips =
            (await (db.select(db.officialClips)
                      ..where(
                        (t) =>
                            t.programSeasonId.equals(activeRow.id) &
                            t.deletedAt.isNull(),
                      )
                      ..orderBy([(t) => OrderingTerm.desc(t.publishedAt)])
                      ..limit(6))
                    .get())
                .map((r) => r.toDomain())
                .toList(growable: false);

        links = await linksFrom(
          ContentEntityKind.episode,
          episode?.id ?? activeRow.id,
        );
      }

      following =
          await (db.select(db.localFollows)..where(
                (t) =>
                    t.kind.equals(FollowKind.program.wireValue) &
                    t.entityId.equals(topic.programId!),
              ))
              .getSingleOrNull() !=
          null;
    }

    if (topic.storyClusterId != null) {
      cluster = await _cluster(topic.storyClusterId!);
    }
    if (topic.guideId != null) {
      final row = await (db.select(
        db.beginnerGuides,
      )..where((t) => t.id.equals(topic.guideId!))).getSingleOrNull();
      guide = row?.toDomain();
    }
    if (topic.competitionId != null) {
      final row = await (db.select(
        db.competitions,
      )..where((t) => t.id.equals(topic.competitionId!))).getSingleOrNull();
      competition = row?.toDomain();
    }

    return FeaturedItem(
      topic: topic,
      program: program,
      programSeason: season,
      latestEpisode: episode,
      latestRecap: recap,
      clips: clips,
      people: people,
      storyCluster: cluster,
      guide: guide,
      competition: competition,
      links: links,
      isFollowingProgram: following,
    );
  }

  @override
  Stream<List<StoryCluster>> watchTopStories({int limit = 5}) {
    final select = db.select(db.storyClusters)
      ..where((t) => t.isTopStory.equals(true) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.lastUpdatedAt)])
      ..limit(limit);
    return select.watch().asyncMap(_withSources);
  }

  @override
  Stream<List<StoryCluster>> watchStoriesForYou({int limit = 8}) {
    final select = db.select(db.storyClusters)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.lastUpdatedAt)])
      ..limit(limit * 3);

    return select.watch().asyncMap((rows) async {
      final follows = await db.select(db.localFollows).get();
      final followedIds = follows.map((f) => f.entityId).toSet();
      final clusters = await _withSources(rows);

      if (followedIds.isEmpty) return clusters.take(limit).toList();

      // Personalise by moving followed-entity stories up, without hiding the
      // rest — the top-stories rail is the anti-bubble, this is the ordering.
      final linked = <String, bool>{};
      for (final c in clusters) {
        final links = await linksFrom(ContentEntityKind.storyCluster, c.id);
        linked[c.id] = links.any((l) => followedIds.contains(l.toId));
      }
      final sorted = clusters.toList()
        ..sort((a, b) {
          final af = linked[a.id] ?? false;
          final bf = linked[b.id] ?? false;
          if (af != bf) return af ? -1 : 1;
          return b.lastUpdatedAt.compareTo(a.lastUpdatedAt);
        });
      return sorted.take(limit).toList(growable: false);
    });
  }

  @override
  Stream<StoryCluster?> watchStoryCluster(String clusterId) {
    final select = db.select(db.storyClusters)
      ..where((t) => t.id.equals(clusterId));
    return select.watchSingleOrNull().asyncMap((row) async {
      if (row == null) return null;
      return _cluster(row.id);
    });
  }

  Future<StoryCluster?> _cluster(String id) async {
    final row = await (db.select(
      db.storyClusters,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final result = await _withSources(<StoryClusterRow>[row]);
    return result.firstOrNull;
  }

  Future<List<StoryCluster>> _withSources(List<StoryClusterRow> rows) async {
    if (rows.isEmpty) return const <StoryCluster>[];
    final ids = rows.map((r) => r.id).toSet();

    final sourceRows =
        await (db.select(db.storySources)
              ..where((t) => t.storyClusterId.isIn(ids))
              ..orderBy([(t) => OrderingTerm.desc(t.publishedAt)]))
            .get();
    final byCluster = <String, List<StorySource>>{};
    for (final s in sourceRows) {
      byCluster
          .putIfAbsent(s.storyClusterId, () => <StorySource>[])
          .add(s.toDomain());
    }

    final linkRows =
        await (db.select(db.contentEntityLinks)..where(
              (t) =>
                  t.fromKind.equals(ContentEntityKind.storyCluster.wireValue) &
                  t.fromId.isIn(ids),
            ))
            .get();
    final linksByCluster = <String, List<ContentEntityLink>>{};
    for (final l in linkRows) {
      linksByCluster
          .putIfAbsent(l.fromId, () => <ContentEntityLink>[])
          .add(l.toDomain());
    }

    return rows
        .map(
          (r) => r.toDomain(
            sources: byCluster[r.id] ?? const <StorySource>[],
            links: linksByCluster[r.id] ?? const <ContentEntityLink>[],
          ),
        )
        .toList(growable: false);
  }

  @override
  Stream<List<BeginnerGuide>> watchGuides({
    GuideKind? kind,
    String? anchorKey,
  }) {
    final select = db.select(db.beginnerGuides)
      ..where((t) => t.deletedAt.isNull());
    if (kind != null) {
      select.where((t) => t.kind.equals(kind.wireValue));
    }
    if (anchorKey != null) {
      select.where((t) => t.anchorKey.equals(anchorKey));
    }
    select.orderBy([(t) => OrderingTerm(expression: t.title)]);
    return select.watch().map(
      (rows) => rows.map((r) => r.toDomain()).toList(growable: false),
    );
  }

  @override
  Future<BeginnerGuide?> guideForAnchor(String anchorKey) async {
    final row =
        await (db.select(db.beginnerGuides)
              ..where(
                (t) => t.anchorKey.equals(anchorKey) & t.deletedAt.isNull(),
              )
              ..limit(1))
            .getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Stream<List<Video>> watchVideos({int limit = 20}) {
    final select = db.select(db.videos)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.publishedAt)])
      ..limit(limit);
    return select.watch().map(
      (rows) => rows.map((r) => r.toDomain()).toList(growable: false),
    );
  }

  @override
  Stream<List<Article>> watchNotices({int limit = 10}) {
    final select = db.select(db.articles)
      ..where((t) => t.isOfficialNotice.equals(true) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.publishedAt)])
      ..limit(limit);
    return select.watch().map(
      (rows) => rows.map((r) => r.toDomain()).toList(growable: false),
    );
  }

  @override
  Stream<List<ProgramSeason>> watchArchivedProgramSeasons() {
    final select = db.select(db.programSeasons)
      ..where((t) => t.isActive.equals(false) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.seasonNumber)]);
    return select.watch().map(
      (rows) => rows.map((r) => r.toDomain()).toList(growable: false),
    );
  }

  @override
  Future<List<ContentEntityLink>> linksFrom(
    ContentEntityKind kind,
    String id,
  ) async {
    final rows =
        await (db.select(db.contentEntityLinks)..where(
              (t) => t.fromKind.equals(kind.wireValue) & t.fromId.equals(id),
            ))
            .get();
    return rows.map((r) => r.toDomain()).toList(growable: false);
  }
}
