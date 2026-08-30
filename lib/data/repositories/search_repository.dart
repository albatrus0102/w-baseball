import 'package:drift/drift.dart';

import '../../core/database/database.dart';
import '../../core/utils/korean_text.dart';
import '../models/domain.dart';

/// Unified search across teams, competitions, people and venues.
///
/// Reachable in one tap from every primary screen. Matching is Korean-aware:
/// the stored `search_key` holds both the normalised name and its 초성, so
/// `ㅅㅇ`, `서울`, and `서울다이아몬드` all find the same team through a single
/// indexed LIKE.
abstract interface class SearchRepository {
  Future<List<SearchHit>> search(String query, {int limit = 30});

  /// Suggestions shown before the user types, and on an empty result.
  Future<List<SearchHit>> suggestions({int limit = 6});
}

class DriftSearchRepository implements SearchRepository {
  DriftSearchRepository({
    required this.db,
    required this.playerProfilesEnabled,
  });

  final WbDatabase db;

  /// Person results are suppressed entirely while player profiles are gated,
  /// so search cannot become a back door to a screen the flag has disabled.
  final bool playerProfilesEnabled;

  @override
  Future<List<SearchHit>> search(String query, {int limit = 30}) async {
    final q = KoreanText.queryKey(query);
    if (q.isEmpty) return const <SearchHit>[];
    final like = '%$q%';

    final hits = <SearchHit>[];

    final teams =
        await (db.select(db.teams)
              ..where((t) => t.deletedAt.isNull() & t.searchKey.like(like))
              ..limit(limit))
            .get();
    for (final t in teams) {
      hits.add(
        SearchHit(
          type: SearchEntityType.team,
          id: t.id,
          title: t.name,
          subtitle: <String?>[
            t.region,
            t.city,
          ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
          score: KoreanText.score(t.name, query),
        ),
      );
    }

    // Competitions have no precomputed key (there are few of them), so we
    // match in memory against the same normalisation rules.
    final competitions = await (db.select(
      db.competitions,
    )..where((t) => t.deletedAt.isNull())).get();
    for (final c in competitions) {
      final score = KoreanText.score(c.name, query);
      if (score == 0) continue;

      // The competition screen is addressed by *season*, not by competition —
      // a competition spans years and has no standings of its own. Emitting the
      // competition id here sent every competition search straight to
      // "대회를 찾을 수 없습니다".
      final season =
          await (db.select(db.seasons)
                ..where(
                  (t) => t.competitionId.equals(c.id) & t.deletedAt.isNull(),
                )
                ..orderBy([(t) => OrderingTerm.desc(t.year)])
                ..limit(1))
              .getSingleOrNull();
      if (season == null) {
        // No season means nothing to show. Better to omit the hit than to
        // offer a result that dead-ends.
        continue;
      }

      hits.add(
        SearchHit(
          type: SearchEntityType.competition,
          id: season.id,
          title: c.name,
          subtitle:
              '${season.year} · ${CompetitionLevel.parse(c.level).labelKo}',
          score: score,
        ),
      );
    }

    final venues =
        await (db.select(db.venues)
              ..where((t) => t.deletedAt.isNull() & t.searchKey.like(like))
              ..limit(limit))
            .get();
    for (final v in venues) {
      hits.add(
        SearchHit(
          type: SearchEntityType.venue,
          id: v.id,
          title: v.name,
          subtitle: v.address ?? v.region,
          score: KoreanText.score(v.name, query),
        ),
      );
    }

    if (playerProfilesEnabled) {
      final people =
          await (db.select(db.people)
                ..where((t) => t.deletedAt.isNull() & t.searchKey.like(like))
                ..limit(limit))
              .get();
      for (final p in people) {
        // Minors are excluded from search results regardless of the flag.
        if (p.isMinor) continue;
        hits.add(
          SearchHit(
            type: SearchEntityType.person,
            id: p.id,
            title: p.name,
            score: KoreanText.score(p.name, query),
          ),
        );
      }
    }

    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.title.compareTo(b.title);
    });

    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }

  @override
  Future<List<SearchHit>> suggestions({int limit = 6}) async {
    // Suggest what the user already follows first, then recruiting teams —
    // both are more useful than an arbitrary alphabetical slice.
    final follows =
        await (db.select(db.localFollows)
              ..where((t) => t.kind.equals('team'))
              ..limit(limit))
            .get();

    final hits = <SearchHit>[];
    if (follows.isNotEmpty) {
      final ids = follows.map((f) => f.entityId).toSet();
      final teams = await (db.select(
        db.teams,
      )..where((t) => t.id.isIn(ids))).get();
      for (final t in teams) {
        hits.add(
          SearchHit(
            type: SearchEntityType.team,
            id: t.id,
            title: t.name,
            subtitle: '팔로우 중',
          ),
        );
      }
    }

    if (hits.length < limit) {
      final recruiting =
          await (db.select(db.teams)
                ..where(
                  (t) =>
                      t.deletedAt.isNull() &
                      t.recruitment.equals(RecruitmentStatus.open.wireValue),
                )
                ..limit(limit - hits.length))
              .get();
      for (final t in recruiting) {
        if (hits.any((h) => h.id == t.id)) continue;
        hits.add(
          SearchHit(
            type: SearchEntityType.team,
            id: t.id,
            title: t.name,
            subtitle: '모집 중',
          ),
        );
      }
    }

    return hits;
  }
}
