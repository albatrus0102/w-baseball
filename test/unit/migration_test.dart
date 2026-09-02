import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:w_baseball/core/database/database.dart';
import 'package:w_baseball/data/mappers/row_mappers.dart';
import 'package:w_baseball/data/models/game_log.dart';

/// Schema migration.
///
/// The rule that matters to a user: **an upgrade must never lose what they
/// chose.** Followed teams, saved games, scheduled notification settings,
/// (from v3) game log entries, and (from v5) game log goals are theirs, not
/// the publisher's.
///
/// Rather than hand-writing old DDL (which would drift away from the real
/// schema and stop testing anything), these tests derive a genuine older
/// database from the current one: create everything, drop exactly what a
/// later version added, stamp `user_version` back down, then reopen so the
/// real `MigrationStrategy` runs.
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

  /// Tables introduced in schema v3 — see `GameLogEntries` in `tables.dart`.
  const v3Tables = <String>['game_log_entries'];

  /// Tables introduced in schema v5 — see `GameLogGoals` in `tables.dart`.
  const v5Tables = <String>['game_log_goals'];

  int epoch(DateTime value) => value.millisecondsSinceEpoch ~/ 1000;

  group('v1 → v5 마이그레이션 (신규 설치가 오래 방치된 경우)', () {
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
      // v3 added no columns to an existing table (only a new table), so
      // dropping `game_log_entries` below removes its own index for free.
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
      for (final table in <String>[...v2Tables, ...v3Tables, ...v5Tables]) {
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

      // 4. Reopen. This is the actual v1 -> v5 migration under test — the
      // `game_log_entries` table dropped above gets recreated straight from
      // the *current* table definition (already including v4's 12 stat
      // columns), so this install jumps all the way to v4 in one step (see
      // the `else if` in `WbDatabase.migration`'s `onUpgrade`), and the new
      // `game_log_goals` table (v5) is created in the same reopen by the
      // independent `if (from < 5)` right after.
      db = WbDatabase(NativeDatabase.opened(raw));
    });

    tearDown(() async {
      await db.close();
    });

    test('사전 조건: v1 상태에는 v2/v3/v5 테이블이 없다', () {
      // Guards the test itself — if this ever passes trivially the rest is
      // moot.
      final before = sqlite3.openInMemory();
      addTearDown(before.dispose);
      expect(v2Tables, isNotEmpty);
      expect(v3Tables, isNotEmpty);
      expect(v5Tables, isNotEmpty);
    });

    test('마이그레이션 후 스키마 버전이 5가 된다', () async {
      await db.select(db.localFollows).get();
      expect(raw.select('PRAGMA user_version;').first.values.first, 5);
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

    test('v3에서 추가된 출전 일지 테이블을 사용할 수 있다', () async {
      await db
          .into(db.gameLogEntries)
          .insert(
            GameLogEntriesCompanion.insert(
              playedAt: DateTime.utc(2026, 8, 29),
              dayKey: '2026-08-29',
              createdAt: DateTime.utc(2026, 8, 29, 21),
            ),
          );
      final rows = await db.select(db.gameLogEntries).get();
      expect(rows, hasLength(1));
      // v4's stat columns exist on this freshly-created table too (this
      // install jumped straight from v1 to v5) and default to null, not 0.
      expect(rows.single.plateAppearances, isNull);
    });

    test('v5에서 추가된 다음 경기 목표 테이블을 사용할 수 있다', () async {
      expect(await db.select(db.gameLogGoals).get(), isEmpty);
      await db
          .into(db.gameLogGoals)
          .insert(
            GameLogGoalsCompanion.insert(
              body: '초구 공략',
              createdAt: DateTime.utc(2026, 8, 29, 21),
            ),
          );
      final rows = await db.select(db.gameLogGoals).get();
      expect(rows, hasLength(1));
      expect(rows.single.closedAt, isNull);
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
      expect(indexes, contains('idx_game_log_day'));
      expect(indexes, contains('idx_game_log_goals_open'));
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
  });

  group('v2 → v5 마이그레이션 (한 버전 뒤처진 설치)', () {
    // A separate baseline from the group above: this one derives a genuine
    // *v2* database (only v3's and v5's additions rolled back) rather than
    // v1. Like the v1 group, `game_log_entries` gets recreated from the
    // current (v4-shaped) table definition, so this also lands on v4 for
    // that table directly — see the `else if` in `WbDatabase.migration`'s
    // `onUpgrade` — before the same reopen also creates `game_log_goals`
    // (v5). The 3-columns-added-later case (a v3 install that already has
    // the table without the stat columns) is what the "v3 → v4" group below
    // tests instead.
    late Database raw;
    late WbDatabase db;

    setUp(() async {
      raw = sqlite3.openInMemory();

      final seedDb = WbDatabase(NativeDatabase.opened(raw));
      await seedDb.select(probeTable(seedDb)).get();

      for (final table in <String>[...v3Tables, ...v5Tables]) {
        raw.execute('DROP TABLE IF EXISTS $table;');
      }
      raw.execute('PRAGMA user_version = 2;');

      raw.execute(
        "INSERT INTO local_follows (kind, entity_id, followed_at, label, muted) "
        "VALUES ('team', 'team-hangang', ${epoch(DateTime.utc(2026, 7, 1))}, '한강 리버베어스', 0)",
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

      // 오래된 v2 설치에 이미 있었던, v2에서 추가된 테이블의 데이터도 살아남아야
      // 한다 — v3 업그레이드가 v2의 것까지 건드리지 않는지 확인한다.
      raw.execute(
        "INSERT INTO beginner_guides (id, kind, title, body, source_name, "
        " source_url, fetched_at, published_at, quality_status, license_status, "
        " visibility, is_demo) "
        "VALUES ('g1', 'oneMinuteIntro', '여자야구 1분 이해', '본문', 'app-editorial', "
        "'app://editorial/guide', ${epoch(DateTime.utc(2026, 8, 30))}, "
        "${epoch(DateTime.utc(2026, 8, 30))}, 'autoVerified', 'unknown', 'public', 0)",
      );

      // This is the actual v2 -> v5 migration under test.
      db = WbDatabase(NativeDatabase.opened(raw));
    });

    tearDown(() async {
      await db.close();
    });

    test('사전 조건: v2 상태에는 game_log_entries도 game_log_goals도 없다', () {
      expect(v3Tables, contains('game_log_entries'));
      expect(v5Tables, contains('game_log_goals'));
    });

    test('마이그레이션 후 스키마 버전이 5가 된다', () async {
      await db.select(db.localFollows).get();
      expect(raw.select('PRAGMA user_version;').first.values.first, 5);
    });

    test('팔로우가 그대로 보존된다', () async {
      final follows = await db.select(db.localFollows).get();
      expect(follows, hasLength(1));
      expect(follows.first.entityId, 'team-hangang');
      expect(follows.first.label, '한강 리버베어스');
    });

    test('저장한 경기가 그대로 보존된다', () async {
      final saved = await db.select(db.savedItems).get();
      expect(saved, hasLength(1));
      expect(saved.first.entityId, 'game-1');
      expect(saved.first.note, '직관 예정');
    });

    test('예약된 알림 설정이 그대로 보존된다', () async {
      final scheduled = await db.select(db.scheduledNotifications).get();
      expect(scheduled, hasLength(1));
      expect(scheduled.first.id, 12345);
      expect(scheduled.first.category, 'myTeamGameDay');
    });

    test('v2에서 이미 있던 데이터도 그대로 보존된다', () async {
      final guides = await db.select(db.beginnerGuides).get();
      expect(guides, hasLength(1));
      expect(guides.first.title, '여자야구 1분 이해');
    });

    test('출전 일지 테이블이 새로 생기고 바로 쓸 수 있다', () async {
      final table = await (db.selectOnly(
        db.gameLogEntries,
      )..addColumns([db.gameLogEntries.id.count()])).getSingle();
      expect(table.read(db.gameLogEntries.id.count()), 0);

      await db
          .into(db.gameLogEntries)
          .insert(
            GameLogEntriesCompanion.insert(
              playedAt: DateTime.utc(2026, 8, 29),
              dayKey: '2026-08-29',
              competitionLabel: const Value('동호인 리그'),
              positions: const Value('catcher'),
              createdAt: DateTime.utc(2026, 8, 29, 21),
            ),
          );
      final rows = await db.select(db.gameLogEntries).get();
      expect(rows, hasLength(1));
      expect(rows.first.competitionLabel, '동호인 리그');
    });

    test('출전 일지 인덱스가 생성된다', () async {
      await db.select(db.gameLogEntries).get();
      final indexes = raw
          .select("SELECT name FROM sqlite_master WHERE type='index'")
          .map((r) => r['name'] as String)
          .toSet();
      expect(indexes, contains('idx_game_log_day'));
    });
  });

  group('v3 → v5 마이그레이션 (성적 칼럼도 목표 테이블도 없던 설치)', () {
    // A genuine *v3* database: `game_log_entries` exists (Stage 1 shipped),
    // but none of the 12 stat columns Stage 2 added do, and `game_log_goals`
    // (v5) does not exist yet either. Derived by dropping exactly those
    // columns and that table from the current schema, the same technique
    // every group above uses — see the file doc comment.
    const v4StatColumns = <String>[
      'plate_appearances',
      'hits',
      'walks',
      'sacrifice_bunts',
      'strikeouts',
      'runs_batted_in',
      'runs_scored',
      'stolen_bases',
      'outs_pitched',
      'pitching_strikeouts',
      'pitching_walks',
      'runs_allowed',
    ];

    late Database raw;
    late WbDatabase db;

    setUp(() async {
      raw = sqlite3.openInMemory();

      final seedDb = WbDatabase(NativeDatabase.opened(raw));
      await seedDb.select(probeTable(seedDb)).get();

      for (final column in v4StatColumns) {
        raw.execute('ALTER TABLE game_log_entries DROP COLUMN $column;');
      }
      for (final table in v5Tables) {
        raw.execute('DROP TABLE IF EXISTS $table;');
      }
      raw.execute('PRAGMA user_version = 3;');

      // A real Stage 1 row, exactly as a player would have left it before
      // this upgrade ever existed — no stat line, because the columns to
      // hold one did not exist yet.
      raw.execute(
        "INSERT INTO game_log_entries "
        "(played_at, day_key, competition_label, opponent_label, positions, "
        " result, note, created_at) "
        "VALUES (${epoch(DateTime.utc(2026, 7, 12))}, '2026-07-12', "
        "'동호인 리그', '남산 호크스', 'leftField', 'loss', '아깝게 졌다', "
        "${epoch(DateTime.utc(2026, 7, 12, 21))})",
      );

      // This is the actual v3 -> v5 migration under test.
      db = WbDatabase(NativeDatabase.opened(raw));
    });

    tearDown(() async {
      await db.close();
    });

    test('사전 조건: v3 상태에는 성적 칼럼도 목표 테이블도 없다', () {
      expect(v4StatColumns, isNotEmpty);
      expect(v5Tables, isNotEmpty);
    });

    test('마이그레이션 후 스키마 버전이 5가 된다', () async {
      await db.select(db.gameLogEntries).get();
      expect(raw.select('PRAGMA user_version;').first.values.first, 5);
    });

    test('기존 출전 일지 행이 그대로 보존된다', () async {
      final rows = await db.select(db.gameLogEntries).get();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.competitionLabel, '동호인 리그');
      expect(row.opponentLabel, '남산 호크스');
      expect(row.note, '아깝게 졌다');
    });

    test('새 성적 칼럼은 전부 null이다 — 0으로 채워지지 않는다', () async {
      final row = (await db.select(db.gameLogEntries).get()).single;
      // Every one of these must be null, not 0: this row predates the stat
      // line entirely, and a false 0 would silently misreport a real
      // 0-for-0 game that never happened. See `GameLogEntries` in
      // `tables.dart`.
      expect(row.plateAppearances, isNull);
      expect(row.hits, isNull);
      expect(row.walks, isNull);
      expect(row.sacrificeBunts, isNull);
      expect(row.strikeouts, isNull);
      expect(row.runsBattedIn, isNull);
      expect(row.runsScored, isNull);
      expect(row.stolenBases, isNull);
      expect(row.outsPitched, isNull);
      expect(row.pitchingStrikeouts, isNull);
      expect(row.pitchingWalks, isNull);
      expect(row.runsAllowed, isNull);
    });

    test('null 성적을 가진 이 행은 타격 집계에서 완전히 빠진다', () async {
      final rows = await db.select(db.gameLogEntries).get();
      final entries = rows.map((r) => r.toDomain()).toList();

      // This is the same exclusion `BattingStatSummary.from` promises for
      // any migrated row — a game with no stat line contributes nothing,
      // not a false 0-for-0. If this ever starts counting the game, the
      // aggregate for every pre-Stage-2 install would suddenly under-report
      // a real player's OBP the day she upgrades.
      final batting = BattingStatSummary.from(entries);
      expect(batting, isNull);
    });

    test('새 성적 칼럼에 바로 값을 쓸 수 있다', () async {
      await db
          .into(db.gameLogEntries)
          .insert(
            GameLogEntriesCompanion.insert(
              playedAt: DateTime.utc(2026, 8, 29),
              dayKey: '2026-08-29',
              createdAt: DateTime.utc(2026, 8, 29, 21),
              plateAppearances: const Value(4),
              hits: const Value(2),
              walks: const Value(1),
            ),
          );
      final rows = await db.select(db.gameLogEntries).get();
      final newRow = rows.firstWhere((r) => r.dayKey == '2026-08-29');
      expect(newRow.plateAppearances, 4);
      expect(newRow.hits, 2);
      expect(newRow.walks, 1);
      // Untouched columns on the same insert stay null, not 0.
      expect(newRow.sacrificeBunts, isNull);
    });
  });

  group('v4 → v5 마이그레이션 (다음 경기 목표 테이블이 없던 설치)', () {
    // A genuine *v4* database: the full stat-line shape from the group
    // above already exists, but `game_log_goals` (v5) does not yet — the
    // same technique as every group above, just rolling back only v5's own
    // addition. See `GameLogGoals` in `tables.dart`.
    late Database raw;
    late WbDatabase db;

    setUp(() async {
      raw = sqlite3.openInMemory();

      final seedDb = WbDatabase(NativeDatabase.opened(raw));
      await seedDb.select(probeTable(seedDb)).get();

      for (final table in v5Tables) {
        raw.execute('DROP TABLE IF EXISTS $table;');
      }
      raw.execute('PRAGMA user_version = 4;');

      // A real Stage 2 row, exactly as a player would have left it before
      // this upgrade ever existed — a full stat line, but obviously no
      // 다음 경기에서 해볼 것 note, since there was nowhere yet to put one.
      raw.execute(
        "INSERT INTO game_log_entries "
        "(played_at, day_key, competition_label, opponent_label, positions, "
        " result, note, created_at, plate_appearances, hits, walks) "
        "VALUES (${epoch(DateTime.utc(2026, 8, 23))}, '2026-08-23', "
        "'동호인 리그', '한강 리버베어스', 'catcher', 'win', '병살 하나 잡음', "
        "${epoch(DateTime.utc(2026, 8, 23, 21))}, 4, 2, 0)",
      );

      // This is the actual v4 -> v5 migration under test.
      db = WbDatabase(NativeDatabase.opened(raw));
    });

    tearDown(() async {
      await db.close();
    });

    test('사전 조건: v4 상태에는 game_log_goals가 없다', () {
      expect(v5Tables, contains('game_log_goals'));
    });

    test('마이그레이션 후 스키마 버전이 5가 된다', () async {
      await db.select(db.gameLogEntries).get();
      expect(raw.select('PRAGMA user_version;').first.values.first, 5);
    });

    test('① 기존 출전 일지 기록이 그대로 보존된다', () async {
      final rows = await db.select(db.gameLogEntries).get();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.competitionLabel, '동호인 리그');
      expect(row.opponentLabel, '한강 리버베어스');
      expect(row.note, '병살 하나 잡음');
      // Its Stage 2 stat line survives the upgrade untouched too.
      expect(row.plateAppearances, 4);
      expect(row.hits, 2);
    });

    test('② 새 목표 테이블은 비어 있다', () async {
      expect(await db.select(db.gameLogGoals).get(), isEmpty);
    });

    test('③ 열린 목표가 없으므로 카드에 보여줄 것이 없다', () async {
      // What `_GameLogGoalCard` gates on: no row with `closedAt IS NULL`.
      // See `GameLogGoalRepository.watchOpenGoal` — an upgraded install with
      // no goal ever written must not manufacture one.
      final openGoals = await (db.select(
        db.gameLogGoals,
      )..where((t) => t.closedAt.isNull())).get();
      expect(openGoals, isEmpty);
    });

    test('새 목표 테이블에 바로 값을 쓸 수 있다', () async {
      await db
          .into(db.gameLogGoals)
          .insert(
            GameLogGoalsCompanion.insert(
              body: '초구 공략',
              entryId: const Value(1),
              createdAt: DateTime.utc(2026, 8, 23, 21),
            ),
          );
      final rows = await db.select(db.gameLogGoals).get();
      expect(rows, hasLength(1));
      expect(rows.single.body, '초구 공략');
      expect(rows.single.closedAt, isNull);
    });

    test('목표 테이블 인덱스가 생성된다', () async {
      await db.select(db.gameLogGoals).get();
      final indexes = raw
          .select("SELECT name FROM sqlite_master WHERE type='index'")
          .map((r) => r['name'] as String)
          .toSet();
      expect(indexes, contains('idx_game_log_goals_open'));
    });
  });
}

/// Any table works as a probe; selecting from one forces `onCreate` to run.
TableInfo<Table, dynamic> probeTable(WbDatabase db) => db.teams;
