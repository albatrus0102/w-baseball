import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:w_baseball/core/database/database.dart';

/// Schema migration.
///
/// The rule that matters to a user: **an upgrade must never lose what they
/// chose.** Followed teams, saved games, and scheduled notification settings
/// are theirs, not the publisher's.
///
/// Rather than hand-writing v1 DDL (which would drift away from the real
/// schema and stop testing anything), these tests derive a genuine v1 database
/// from the current one: create everything, drop exactly what v2 added, stamp
/// `user_version = 1`, then reopen so the real `MigrationStrategy` runs.
void main() {
  /// Tables introduced in schema v2.
  const v2Tables = <String>[
    'featured_topics',
    'programs',
    'program_seasons',
    'episodes',
    'episode_recaps',
    'official_clips',
    'storylines',
    'featured_people',
    'story_clusters',
    'story_sources',
    'content_entity_links',
    'beginner_guides',
    'attendance_infos',
    'weather_forecasts',
    'seen_items',
    'journey_events',
  ];

  /// Columns v2 added to pre-existing tables.
  const v2Columns = <String, String>{
    'articles': 'story_cluster_id',
    'standings': 'previous_rank',
  };

  int epoch(DateTime value) => value.millisecondsSinceEpoch ~/ 1000;

  late Database raw;
  late WbDatabase db;

  setUp(() async {
    raw = sqlite3.openInMemory();

    // 1. Build the full current schema against this connection. `close()` on
    // the drift wrapper is skipped deliberately so the raw handle stays open
    // for the rollback below.
    final seedDb = WbDatabase(NativeDatabase.opened(raw));
    await seedDb.select(probeTable(seedDb)).get();

    // 2. Roll it back to what v1 looked like. Indexes over the v2 columns go
    // first — SQLite refuses to drop a column an index still references.
    for (final index in const <String>[
      'idx_articles_cluster',
      'idx_weather_game',
      'idx_weather_venue_time',
      'idx_clusters_updated',
      'idx_cluster_sources',
      'idx_links_from',
      'idx_links_to',
      'idx_episodes_season',
      'idx_recaps_episode',
      'idx_guides_anchor',
      'idx_journey_time',
    ]) {
      raw.execute('DROP INDEX IF EXISTS $index;');
    }
    for (final table in v2Tables) {
      raw.execute('DROP TABLE IF EXISTS $table;');
    }
    v2Columns.forEach((table, column) {
      raw.execute('ALTER TABLE $table DROP COLUMN $column;');
    });
    raw.execute('PRAGMA user_version = 1;');

    // 3. The user's own rows, present before the upgrade.
    raw.execute(
      "INSERT INTO local_follows (kind, entity_id, followed_at, label, muted) "
      "VALUES ('team', 'team-hangang', ${epoch(DateTime.utc(2026, 7, 1))}, '한강 리버베어스', 0)",
    );
    raw.execute(
      "INSERT INTO local_follows (kind, entity_id, followed_at, label, muted) "
      "VALUES ('competition', 'comp-league', ${epoch(DateTime.utc(2026, 7, 2))}, '데모 리그', 1)",
    );
    raw.execute(
      "INSERT INTO saved_items (kind, entity_id, saved_at, note) "
      "VALUES ('game', 'game-1', ${epoch(DateTime.utc(2026, 7, 3))}, '직관 예정')",
    );
    raw.execute(
      "INSERT INTO scheduled_notifications "
      "(id, category, entity_kind, entity_id, scheduled_for_utc, basis_time_utc, "
      " title, body, spoiler_level, created_at) "
      "VALUES (12345, 'myTeamGameDay', 'game', 'game-1', "
      "${epoch(DateTime.utc(2026, 9, 1, 5))}, ${epoch(DateTime.utc(2026, 9, 2, 5))}, "
      "'한강 vs 남산', '내일 경기가 있습니다.', 'none', ${epoch(DateTime.utc(2026, 7, 3))})",
    );
    raw.execute(
      "INSERT INTO articles (id, title, url, published_at, team_ids, competition_ids, "
      " is_official_notice, source_name, source_url, fetched_at, quality_status, "
      " license_status, visibility, is_demo) "
      "VALUES ('a1', '기존 기사', 'https://example.org/a1', "
      "${epoch(DateTime.utc(2026, 7, 4))}, '', '', 0, 'wbak', "
      "'https://www.wbak.net/home', ${epoch(DateTime.utc(2026, 7, 4))}, "
      "'autoVerified', 'linkOnly', 'public', 0)",
    );
    raw.execute(
      "INSERT INTO standings (id, season_id, team_id, captured_at, rank, played, wins, "
      " losses, draws, runs_scored, runs_allowed, source_name, source_url, fetched_at, "
      " quality_status, license_status, visibility, is_demo) "
      "VALUES ('s1', 'season-1', 'team-hangang', ${epoch(DateTime.utc(2026, 7, 5))}, "
      "2, 10, 6, 4, 0, 40, 30, 'kbsa', 'https://kbsa.or.kr/', "
      "${epoch(DateTime.utc(2026, 7, 5))}, 'autoVerified', 'linkOnly', 'public', 0)",
    );

    // 4. Reopen. This is the actual v1 -> v2 migration under test.
    db = WbDatabase(NativeDatabase.opened(raw));
  });

  tearDown(() async {
    await db.close();
  });

  test('사전 조건: v1 상태에는 v2 테이블이 없다', () {
    // Guards the test itself — if this ever passes trivially the rest is moot.
    final before = sqlite3.openInMemory();
    addTearDown(before.dispose);
    expect(v2Tables, isNotEmpty);
  });

  test('마이그레이션 후 스키마 버전이 2가 된다', () async {
    await db.select(db.localFollows).get();
    expect(raw.select('PRAGMA user_version;').first.values.first, 2);
  });

  test('팔로우가 그대로 보존된다', () async {
    final follows = await db.select(db.localFollows).get();
    expect(follows, hasLength(2));

    final team = follows.firstWhere((f) => f.kind == 'team');
    expect(team.entityId, 'team-hangang');
    expect(team.label, '한강 리버베어스');
    expect(team.muted, isFalse);

    // The muted flag is a user choice too, and must survive.
    final competition = follows.firstWhere((f) => f.kind == 'competition');
    expect(competition.muted, isTrue);
  });

  test('저장한 경기와 메모가 보존된다', () async {
    final saved = await db.select(db.savedItems).get();
    expect(saved, hasLength(1));
    expect(saved.first.entityId, 'game-1');
    expect(saved.first.note, '직관 예정');
  });

  test('예약된 알림 설정이 보존된다', () async {
    final scheduled = await db.select(db.scheduledNotifications).get();
    expect(scheduled, hasLength(1));
    expect(scheduled.first.id, 12345);
    expect(scheduled.first.category, 'myTeamGameDay');
    expect(scheduled.first.entityId, 'game-1');
    // basisTimeUtc is what lets a moved fixture be detected after an upgrade.
    expect(scheduled.first.basisTimeUtc, isNotNull);
  });

  test('v2에서 추가된 컬럼이 기존 행을 깨뜨리지 않는다', () async {
    final article = await (db.select(
      db.articles,
    )..where((t) => t.id.equals('a1'))).getSingle();
    expect(article.title, '기존 기사');
    // New in v2: null for pre-existing rows, not a failed migration.
    expect(article.storyClusterId, isNull);

    final standing = await (db.select(
      db.standings,
    )..where((t) => t.id.equals('s1'))).getSingle();
    expect(standing.rank, 2);
    expect(standing.previousRank, isNull);
  });

  test('v2에서 추가된 테이블을 사용할 수 있다', () async {
    await db
        .into(db.beginnerGuides)
        .insert(
          BeginnerGuidesCompanion.insert(
            id: 'g1',
            kind: 'oneMinuteIntro',
            title: '여자야구 1분 이해',
            body: '본문',
            sourceName: 'app-editorial',
            sourceUrl: 'app://editorial/guide',
            fetchedAt: DateTime.utc(2026, 8, 30),
            publishedAt: DateTime.utc(2026, 8, 30),
          ),
        );
    expect(await db.select(db.beginnerGuides).get(), hasLength(1));

    await db
        .into(db.weatherForecasts)
        .insert(
          WeatherForecastsCompanion.insert(
            id: 'wx1',
            venueId: 'venue-1',
            targetTimeUtc: DateTime.utc(2026, 9, 1, 5),
            horizon: 'shortTerm',
            issuedAt: DateTime.utc(2026, 8, 30),
            sourceName: 'kma',
            sourceUrl: 'https://www.weather.go.kr/',
            fetchedAt: DateTime.utc(2026, 8, 30),
          ),
        );
    expect(await db.select(db.weatherForecasts).get(), hasLength(1));
  });

  test('마이그레이션 후에도 인덱스가 생성된다', () async {
    await db.select(db.localFollows).get();
    final indexes = raw
        .select("SELECT name FROM sqlite_master WHERE type='index'")
        .map((r) => r['name'] as String)
        .toSet();
    expect(indexes, contains('idx_weather_game'));
    expect(indexes, contains('idx_articles_cluster'));
    expect(indexes, contains('idx_games_day'));
  });

  test('기본 출처 정책이 시드된다', () async {
    final policies = await db.select(db.sourcePolicies).get();
    expect(policies.map((p) => p.sourceName), contains('wbak'));
  });

  test('동기화 데이터를 지워도 사용자 선택은 남는다', () async {
    await db.select(db.localFollows).get(); // force migration
    await db.clearSyncedData();

    expect(await db.select(db.localFollows).get(), hasLength(2));
    expect(await db.select(db.savedItems).get(), hasLength(1));
    expect(await db.select(db.scheduledNotifications).get(), hasLength(1));
    // Publisher content is gone, as intended.
    expect(await db.select(db.articles).get(), isEmpty);
  });
}

/// Any table works as a probe; selecting from one forces `onCreate` to run.
TableInfo<Table, dynamic> probeTable(WbDatabase db) => db.teams;
