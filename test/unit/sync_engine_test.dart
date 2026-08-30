import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/config/app_config.dart';
import 'package:w_baseball/core/database/database.dart';
import 'package:w_baseball/data/dto/dtos.dart';
import 'package:w_baseball/data/models/domain.dart';
import 'package:w_baseball/data/sources/fake/fake_rest_api_data_source.dart';
import 'package:w_baseball/data/sources/sports_data_source.dart';
import 'package:w_baseball/data/sync/sync_contracts.dart';
import 'package:w_baseball/data/sync/sync_engine.dart';

/// Behaviour a real API will exercise: pagination, incremental sync,
/// idempotent upsert, tombstones, corrections, per-record quarantine, failure
/// isolation, schema-version refusal, and resume after a restart.
void main() {
  late WbDatabase db;
  late SyncEngine engine;
  var clock = DateTime.utc(2026, 8, 30, 0, 0, 0);

  const contract = DataContractConfig();
  final config = AppConfig.fromEnvironment();

  setUp(() {
    clock = DateTime.utc(2026, 8, 30);
    db = WbDatabase(NativeDatabase.memory());
    engine = SyncEngine(db: db, config: config, clock: () => clock);
  });

  tearDown(() async => db.close());

  String sourceBlock(String id, {String fetchedAt = '2026-08-30T00:00:00Z'}) =>
      '"source":{"sourceName":"fake-api","sourceUrl":"https://example.org/$id",'
      '"sourceRecordId":"$id","fetchedAt":"$fetchedAt"}';

  String teamsDoc(
    List<String> ids, {
    String fetchedAt = '2026-08-30T00:00:00Z',
  }) {
    final items = ids
        .map(
          (id) =>
              '{"id":"$id","name":"팀 $id",${sourceBlock(id, fetchedAt: fetchedAt)}}',
        )
        .join(',');
    return '{"schemaVersion":1,"payloadKind":"snapshot","items":[$items]}';
  }

  String gamesDoc(List<Map<String, Object?>> games) {
    final items = games
        .map((g) {
          final id = g['id'] as String;
          final buffer = StringBuffer('{"id":"$id"');
          g.forEach((key, value) {
            if (key == 'id') return;
            buffer.write(',"$key":${value is String ? '"$value"' : value}');
          });
          buffer.write(',${sourceBlock(id)}}');
          return buffer.toString();
        })
        .join(',');
    return '{"schemaVersion":1,"payloadKind":"snapshot","items":[$items]}';
  }

  Map<String, String> baseDocs({
    List<String> teams = const <String>['a', 'b'],
    String? games,
  }) => <String, String>{
    'teams.json': teamsDoc(teams),
    'games/2026-08.json': ?games,
  };

  const scope = GameSyncScope(months: <String>['2026-08']);

  group('페이지네이션', () {
    test('cursor로 3페이지를 모두 순회한다', () async {
      final source = FakeRestApiDataSource(
        documents: baseDocs(teams: <String>['a', 'b', 'c', 'd', 'e', 'f']),
        contract: contract,
        pageSize: 2,
      );

      final result = await engine.refreshSource(source, scope: scope);

      expect(result.isSuccess, isTrue);
      expect(result.inserted, 6);
      // 3 pages of teams (+1 request for the empty games month).
      final teamRequests = source.requestLog
          .where((r) => r.startsWith('teams.json'))
          .length;
      expect(teamRequests, 3);

      final stored = await db.select(db.teams).get();
      expect(stored.length, 6);
    });

    test('같은 cursor를 반복해도 무한 루프에 빠지지 않는다', () async {
      final source = _StuckCursorSource(contract: contract);
      final result = await engine.refreshSource(source, scope: scope);
      expect(result.isSuccess, isTrue);
      // Stops as soon as the cursor repeats rather than spinning.
      expect(source.calls, lessThan(5));
    });
  });

  group('멱등성', () {
    test('같은 페이지를 두 번 받아도 중복이 생기지 않는다', () async {
      final docs = baseDocs(teams: <String>['a', 'b', 'c']);

      await engine.refreshSource(
        FakeRestApiDataSource(
          documents: docs,
          contract: contract,
          pageSize: 10,
        ),
        scope: scope,
      );
      final second = await engine.refreshSource(
        FakeRestApiDataSource(
          documents: docs,
          contract: contract,
          pageSize: 10,
        ),
        scope: scope,
        incremental: false,
      );

      final stored = await db.select(db.teams).get();
      expect(stored.length, 3);
      // Second delivery updates rather than inserting.
      expect(second.inserted, 0);
      expect(second.updated, 3);
    });
  });

  group('증분 동기화', () {
    test('두 번째 호출은 updatedSince를 보낸다', () async {
      final docs = baseDocs(teams: <String>['a', 'b']);
      await engine.refreshSource(
        FakeRestApiDataSource(
          documents: docs,
          contract: contract,
          pageSize: 10,
        ),
        scope: scope,
      );

      final second = FakeRestApiDataSource(
        documents: docs,
        contract: contract,
        pageSize: 10,
      );
      await engine.refreshSource(second, scope: scope);

      final teamRequest = second.requestLog.firstWhere(
        (r) => r.startsWith('teams.json'),
      );
      expect(teamRequest, contains('since=2026-08-30'));
    });

    test('한 경기만 수정된 델타를 적용한다', () async {
      final initial = gamesDoc(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'g1',
          'status': 'final',
          'startTime': '2026-08-20T05:00:00Z',
          'homeTeamId': 'a',
          'awayTeamId': 'b',
          'homeScore': 3,
          'awayScore': 2,
        },
        <String, Object?>{
          'id': 'g2',
          'status': 'scheduled',
          'startTime': '2026-08-25T05:00:00Z',
          'homeTeamId': 'b',
          'awayTeamId': 'a',
        },
      ]);

      await engine.refreshSource(
        FakeRestApiDataSource(
          documents: baseDocs(games: initial),
          contract: contract,
          pageSize: 10,
        ),
        scope: scope,
      );

      // A correction to g1 only, delivered as a delta.
      final corrected =
          '{"schemaVersion":1,"payloadKind":"delta","items":['
          '{"id":"g1","status":"final","startTime":"2026-08-20T05:00:00Z",'
          '"homeTeamId":"a","awayTeamId":"b","homeScore":4,"awayScore":2,'
          '${sourceBlock('g1', fetchedAt: '2026-08-31T00:00:00Z')}}]}';

      clock = DateTime.utc(2026, 8, 31);
      await engine.refreshSource(
        FakeRestApiDataSource(
          documents: <String, String>{
            'teams.json': teamsDoc(<String>['a', 'b']),
            'games/2026-08.json': corrected,
          },
          contract: contract,
          pageSize: 10,
        ),
        scope: scope,
      );

      final g1 = await (db.select(
        db.games,
      )..where((t) => t.id.equals('g1'))).getSingle();
      final g2 = await (db.select(
        db.games,
      )..where((t) => t.id.equals('g2'))).getSingle();

      expect(g1.homeScore, 4);
      // A delta must never tombstone the record it did not mention.
      expect(g2.deletedAt, isNull);
    });
  });

  group('결과 정정 이력', () {
    test('종료된 경기의 점수가 바뀌면 정정 이력을 남긴다', () async {
      final first = gamesDoc(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'g1',
          'status': 'final',
          'startTime': '2026-08-20T05:00:00Z',
          'homeTeamId': 'a',
          'awayTeamId': 'b',
          'homeScore': 3,
          'awayScore': 2,
        },
      ]);
      await engine.refreshSource(
        FakeRestApiDataSource(
          documents: baseDocs(games: first),
          contract: contract,
          pageSize: 10,
        ),
        scope: scope,
      );

      final second = gamesDoc(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'g1',
          'status': 'final',
          'startTime': '2026-08-20T05:00:00Z',
          'homeTeamId': 'a',
          'awayTeamId': 'b',
          'homeScore': 5,
          'awayScore': 2,
        },
      ]);
      clock = DateTime.utc(2026, 9);
      await engine.refreshSource(
        FakeRestApiDataSource(
          documents: baseDocs(games: second),
          contract: contract,
          pageSize: 10,
        ),
        scope: scope,
        incremental: false,
      );

      final revisions = await (db.select(
        db.entityRevisions,
      )..where((t) => t.reason.equals('result-correction'))).get();
      expect(revisions, hasLength(1));
      expect(revisions.first.previousValue, '3-2');
      expect(revisions.first.newValue, '5-2');
    });

    test('일정 변경도 이력으로 남는다', () async {
      final first = gamesDoc(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'g1',
          'status': 'scheduled',
          'startTime': '2026-08-20T05:00:00Z',
          'homeTeamId': 'a',
          'awayTeamId': 'b',
        },
      ]);
      await engine.refreshSource(
        FakeRestApiDataSource(
          documents: baseDocs(games: first),
          contract: contract,
          pageSize: 10,
        ),
        scope: scope,
      );

      final moved = gamesDoc(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'g1',
          'status': 'postponed',
          'statusNote': '우천 순연',
          'startTime': '2026-08-27T05:00:00Z',
          'homeTeamId': 'a',
          'awayTeamId': 'b',
        },
      ]);
      clock = DateTime.utc(2026, 8, 21);
      await engine.refreshSource(
        FakeRestApiDataSource(
          documents: baseDocs(games: moved),
          contract: contract,
          pageSize: 10,
        ),
        scope: scope,
        incremental: false,
      );

      final reasons = (await db.select(db.entityRevisions).get())
          .map((r) => r.reason)
          .toSet();
      expect(
        reasons,
        containsAll(<String>['schedule-change', 'status-change']),
      );
    });
  });

  group('tombstone', () {
    test('스냅샷에서 사라진 레코드는 삭제 표시만 하고 지우지 않는다', () async {
      await engine.refreshSource(
        FakeRestApiDataSource(
          documents: baseDocs(teams: <String>['a', 'b', 'c']),
          contract: contract,
          pageSize: 10,
        ),
        scope: scope,
      );

      clock = DateTime.utc(2026, 8, 31);
      final result = await engine.refreshSource(
        FakeRestApiDataSource(
          documents: baseDocs(teams: <String>['a', 'b']),
          contract: contract,
          pageSize: 10,
        ),
        scope: scope,
        incremental: false,
      );

      expect(result.tombstoned, 1);
      final rows = await db.select(db.teams).get();
      // Row still present, just marked.
      expect(rows.length, 3);
      final gone = rows.firstWhere((r) => r.id == 'c');
      expect(gone.deletedAt, isNotNull);
    });

    test('명시적 tombstone 목록도 처리한다', () async {
      await engine.refreshSource(
        FakeRestApiDataSource(
          documents: baseDocs(teams: <String>['a', 'b']),
          contract: contract,
          pageSize: 10,
        ),
        scope: scope,
      );

      clock = DateTime.utc(2026, 8, 31);
      await engine.refreshSource(
        FakeRestApiDataSource(
          documents: baseDocs(teams: <String>['a', 'b']),
          contract: contract,
          pageSize: 10,
          tombstones: <String>['b'],
        ),
        scope: scope,
        incremental: false,
      );

      final b = await (db.select(
        db.teams,
      )..where((t) => t.id.equals('b'))).getSingle();
      expect(b.deletedAt, isNotNull);
    });
  });

  group('레코드 격리', () {
    test('깨진 레코드가 있어도 나머지는 저장된다', () async {
      const doc =
          '{"schemaVersion":1,"payloadKind":"snapshot","items":['
          '{"id":"a","name":"정상","source":{"sourceName":"fake-api",'
          '"sourceUrl":"https://example.org/a","fetchedAt":"2026-08-30T00:00:00Z"}},'
          '{"name":"id 없음","source":{"sourceName":"fake-api",'
          '"sourceUrl":"https://example.org/x","fetchedAt":"2026-08-30T00:00:00Z"}},'
          '{"id":"c","name":"정상2","source":{"sourceName":"fake-api",'
          '"sourceUrl":"https://example.org/c","fetchedAt":"2026-08-30T00:00:00Z"}}]}';

      final result = await engine.refreshSource(
        FakeRestApiDataSource(
          documents: <String, String>{'teams.json': doc},
          contract: contract,
          pageSize: 10,
        ),
        scope: scope,
      );

      expect(result.isSuccess, isTrue);
      expect(result.isPartial, isTrue);
      expect((await db.select(db.teams).get()).length, 2);

      final errors = await db.select(db.syncErrors).get();
      expect(errors, hasLength(1));
      expect(errors.first.severity, 'recordRejected');
    });
  });

  group('실패 격리', () {
    test('한 출처가 실패해도 다른 출처는 적용된다', () async {
      final failing = FakeRestApiDataSource(
        documents: baseDocs(),
        contract: contract,
        failures: const <FakeApiFailure>[FakeApiFailure.serverError],
        name: 'broken',
      );
      final working = FakeRestApiDataSource(
        documents: baseDocs(teams: <String>['x', 'y']),
        contract: contract,
        pageSize: 10,
        name: 'working',
      );

      final report = await engine.refreshAll(
        <dynamic>[failing, working].cast(),
        scope: scope,
      );

      expect(report.anyFailed, isTrue);
      expect(report.anySucceeded, isTrue);
      // The healthy source still landed its data.
      expect((await db.select(db.teams).get()).length, 2);
    });

    for (final failure in <(String, FakeApiFailure, SyncFailureKind)>[
      ('401', FakeApiFailure.unauthorized, SyncFailureKind.unauthorized),
      ('403', FakeApiFailure.forbidden, SyncFailureKind.forbidden),
      ('429', FakeApiFailure.rateLimited, SyncFailureKind.rateLimited),
      ('500', FakeApiFailure.serverError, SyncFailureKind.serverError),
      ('timeout', FakeApiFailure.timeout, SyncFailureKind.timeout),
    ]) {
      test('${failure.$1} 실패는 결과로 보고되고 예외를 던지지 않는다', () async {
        final result = await engine.refreshSource(
          FakeRestApiDataSource(
            documents: baseDocs(),
            contract: contract,
            failures: <FakeApiFailure>[failure.$2],
          ),
          scope: scope,
        );
        expect(result.isSuccess, isFalse);
        expect(result.failure, failure.$3);
        expect(result.failureMessage, isNotNull);
      });
    }

    test('404는 실패가 아니라 "그 파일 없음"으로 처리한다', () async {
      // A missing partition is normal; only the engine's own doc map decides.
      final result = await engine.refreshSource(
        FakeRestApiDataSource(
          documents: <String, String>{
            'teams.json': teamsDoc(<String>['a']),
          },
          contract: contract,
          pageSize: 10,
        ),
        scope: const GameSyncScope(months: <String>['2099-01']),
      );
      expect(result.isSuccess, isTrue);
      expect((await db.select(db.teams).get()).length, 1);
    });
  });

  group('스키마 버전', () {
    test('상위 버전을 받으면 기존 캐시를 유지한 채 갱신만 중단한다', () async {
      await engine.refreshSource(
        FakeRestApiDataSource(
          documents: baseDocs(teams: <String>['a', 'b']),
          contract: contract,
          pageSize: 10,
        ),
        scope: scope,
      );
      expect((await db.select(db.teams).get()).length, 2);

      final result = await engine.refreshSource(
        FakeRestApiDataSource(
          documents: baseDocs(teams: <String>['a', 'b', 'c']),
          contract: contract,
          pageSize: 10,
          schemaVersionOverride: 99,
        ),
        scope: scope,
        incremental: false,
      );

      expect(result.failure, SyncFailureKind.schemaUnsupported);
      // Cache untouched — the user can still read what they had.
      expect((await db.select(db.teams).get()).length, 2);
    });
  });

  group('재개', () {
    test('앱을 종료했다 다시 열어도 이어서 동기화한다', () async {
      final docs = baseDocs(teams: <String>['a', 'b', 'c', 'd']);

      // First run fails partway through.
      await engine.refreshSource(
        FakeRestApiDataSource(
          documents: docs,
          contract: contract,
          pageSize: 2,
          failures: const <FakeApiFailure>[
            FakeApiFailure(SyncFailureKind.timeout, path: 'teams.json'),
          ],
        ),
        scope: scope,
      );

      // A fresh engine, as after a restart, using the same database.
      final resumed = SyncEngine(db: db, config: config, clock: () => clock);
      final result = await resumed.refreshSource(
        FakeRestApiDataSource(documents: docs, contract: contract, pageSize: 2),
        scope: scope,
        incremental: false,
      );

      expect(result.isSuccess, isTrue);
      expect((await db.select(db.teams).get()).length, 4);
    });
  });

  group('동기화 기록', () {
    test('sync_runs에 결과가 남는다', () async {
      await engine.refreshSource(
        FakeRestApiDataSource(
          documents: baseDocs(teams: <String>['a']),
          contract: contract,
          pageSize: 10,
        ),
        scope: scope,
      );
      final runs = await db.select(db.syncRuns).get();
      expect(runs, hasLength(1));
      expect(runs.first.finishedAt, isNotNull);
      expect(runs.first.inserted, 1);
      expect(runs.first.failureKind, isNull);
    });

    test('external_identities로 원천 id를 canonical id에 연결한다', () async {
      await engine.refreshSource(
        FakeRestApiDataSource(
          documents: baseDocs(teams: <String>['a']),
          contract: contract,
          pageSize: 10,
        ),
        scope: scope,
      );
      final identities = await db.select(db.externalIdentities).get();
      expect(identities, hasLength(1));
      expect(identities.first.sourceRecordId, 'a');
      expect(identities.first.canonicalId, 'a');
    });
  });

  group('기본 출처 정책', () {
    test('공식 단체가 seed보다 우선한다', () async {
      final policies = await db.select(db.sourcePolicies).get();
      final byName = {for (final p in policies) p.sourceName: p};
      expect(
        byName['wbak']!.officialRank,
        lessThan(byName['seed']!.officialRank),
      );
      expect(
        byName['manual-submission']!.officialRank,
        lessThan(byName['seed']!.officialRank),
      );
    });

    test('SourcePolicy는 사람 검수 → 공식성 → 최신성 순으로 판정한다', () {
      const official = SourcePolicy(
        sourceName: 'wbak',
        officialRank: 0,
        trustsHumanReview: true,
      );
      const seed = SourcePolicy(
        sourceName: 'seed',
        officialRank: 90,
        trustsHumanReview: true,
      );
      final older = Provenance(
        sourceName: 'wbak',
        sourceUrl: 'https://example.org',
        fetchedAt: DateTime.utc(2026, 8, 1),
      );
      final newer = Provenance(
        sourceName: 'seed',
        sourceUrl: 'https://example.org',
        fetchedAt: DateTime.utc(2026, 8, 30),
      );

      // A fresher but less official record must not overwrite an official one.
      expect(
        SourcePolicy.challengerWins(
          incumbentPolicy: official,
          incumbent: older,
          challengerPolicy: seed,
          challenger: newer,
        ),
        isFalse,
      );

      // Human review wins over mere officialness.
      expect(
        SourcePolicy.challengerWins(
          incumbentPolicy: official,
          incumbent: older,
          challengerPolicy: seed,
          challenger: newer.copyWith(
            qualityStatus: QualityStatus.humanVerified,
          ),
        ),
        isTrue,
      );
    });
  });
}

/// A source that keeps returning the same cursor, to prove the engine stops.
final class _StuckCursorSource extends BaseSportsDataSource {
  _StuckCursorSource({required this.contract});

  final DataContractConfig contract;

  int calls = 0;

  @override
  String get sourceName => 'stuck';

  @override
  Set<SyncEntityType> get supportedEntities => const <SyncEntityType>{
    SyncEntityType.team,
  };

  @override
  Future<SyncPage<TeamDto>> fetchTeams(SyncRequest request) async {
    calls++;
    return const SyncPage<TeamDto>(
      items: <TeamDto>[],
      sourceName: 'stuck',
      payloadKind: SyncPayloadKind.delta,
      hasMore: true,
      nextCursor: SyncCursor('always-the-same'),
    );
  }
}
