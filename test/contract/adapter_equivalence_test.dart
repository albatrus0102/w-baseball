import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/config/app_config.dart';
import 'package:w_baseball/core/database/database.dart';
import 'package:w_baseball/data/mappers/row_mappers.dart';
import 'package:w_baseball/data/models/domain.dart';
import 'package:w_baseball/data/sources/bundled_seed_data_source.dart';
import 'package:w_baseball/data/sources/fake/fake_rest_api_data_source.dart';
import 'package:w_baseball/data/sync/sync_contracts.dart';
import 'package:w_baseball/data/sync/sync_engine.dart';

/// The core API-readiness claim, tested rather than asserted:
///
/// **the same fixture, delivered as static JSON files or as a paginated REST
/// API, must produce identical domain objects.**
///
/// If that holds, connecting a real official API later is a matter of adding
/// one adapter — repositories, screens and the database are untouched.
void main() {
  const contract = DataContractConfig();
  final config = AppConfig.fromEnvironment();
  final clock = DateTime.utc(2026, 8, 30);

  /// One fixture, shared by both transports.
  final fixture = <String, String>{
    'version.json': jsonEncode(<String, dynamic>{
      'schemaVersion': 1,
      'dataVersion': '2026.08.30.1',
      'generatedAt': '2026-08-30T00:00:00Z',
      'files': <dynamic>[
        <String, dynamic>{'path': 'teams.json'},
        <String, dynamic>{'path': 'venues.json'},
        <String, dynamic>{'path': 'games/2026-08.json'},
        <String, dynamic>{'path': 'competitions/2026.json'},
      ],
    }),
    'teams.json': _doc(<Map<String, dynamic>>[
      _team('team-a', '한강 리버베어스', region: '11', color: '#1F4E79'),
      _team('team-b', '남산 스카이라크스', region: '11'),
      _team('team-c', '수원 필드메이커스', region: '41'),
      _team('team-d', '부산 씨걸스', region: '26'),
      _team('team-e', '인천 하버라이츠', region: '28'),
    ]),
    'venues.json': _doc(<Map<String, dynamic>>[
      _venue('venue-1', '한강 야구장', 37.53, 127.07),
      _venue('venue-2', '수원 스포츠파크', 37.28, 127.01),
    ]),
    'competitions/2026.json': _doc(<Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'comp-1',
        'name': '2026 데모 리그',
        'level': 'domestic',
        'seasons': <dynamic>[
          <String, dynamic>{
            'id': 'season-1',
            'year': 2026,
            'name': '2026 정규 시즌',
            'phase': 'ongoing',
            'stages': <dynamic>[
              <String, dynamic>{
                'id': 'stage-1',
                'name': '정규 리그',
                'format': 'league',
                'ordering': 1,
              },
            ],
          },
        ],
        'source': _source('comp-1'),
      },
    ]),
    'games/2026-08.json': _doc(<Map<String, dynamic>>[
      _game(
        'g1',
        home: 'team-a',
        away: 'team-b',
        start: '2026-08-05T05:00:00Z',
        status: 'final',
        homeScore: 5,
        awayScore: 3,
      ),
      _game(
        'g2',
        home: 'team-c',
        away: 'team-d',
        start: '2026-08-12T05:00:00Z',
        status: 'final',
        homeScore: 2,
        awayScore: 2,
      ),
      _game(
        'g3',
        home: 'team-e',
        away: 'team-a',
        start: '2026-08-19T05:00:00Z',
        status: 'scheduled',
      ),
      _game(
        'g4',
        home: 'team-b',
        away: 'team-c',
        start: '2026-08-26T05:00:00Z',
        status: 'postponed',
        note: '우천 순연',
      ),
      _game(
        'g5',
        home: 'team-d',
        away: 'team-e',
        start: '2026-08-28T05:00:00Z',
        status: 'cancelled',
      ),
    ]),
  };

  const scope = GameSyncScope(months: <String>['2026-08']);

  /// Runs a source into a fresh database and returns the resulting domain
  /// objects, ordered deterministically.
  Future<_DomainSnapshot> runSource(
    Future<void> Function(SyncEngine engine) apply,
  ) async {
    final db = WbDatabase(NativeDatabase.memory());
    final engine = SyncEngine(db: db, config: config, clock: () => clock);
    await apply(engine);

    final teams =
        (await db.select(db.teams).get()).map((r) => r.toDomain()).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    final games =
        (await db.select(db.games).get()).map((r) => r.toDomain()).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    final venues =
        (await db.select(db.venues).get()).map((r) => r.toDomain()).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    final competitions =
        (await db.select(db.competitions).get())
            .map((r) => r.toDomain())
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    final seasons =
        (await db.select(db.seasons).get()).map((r) => r.toDomain()).toList()
          ..sort((a, b) => a.id.compareTo(b.id));

    await db.close();
    return _DomainSnapshot(
      teams: teams,
      games: games,
      venues: venues,
      competitions: competitions,
      seasons: seasons,
    );
  }

  late _DomainSnapshot viaStaticFiles;
  late _DomainSnapshot viaFakeApi;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Transport A: files, exactly as the bundled/static source reads them.
    viaStaticFiles = await runSource((engine) async {
      final source = BundledSeedDataSource(
        contract: contract,
        bundle: _MapAssetBundle(fixture, prefix: 'assets/seed/'),
      );
      await engine.refreshSource(source, scope: scope, incremental: false);
    });

    // Transport B: a paginated REST API over the same bytes.
    viaFakeApi = await runSource((engine) async {
      final source = FakeRestApiDataSource(
        documents: fixture,
        contract: contract,
        // Deliberately small, so the API path traverses several pages while
        // the file path reads one document.
        pageSize: 2,
      );
      await engine.refreshSource(source, scope: scope, incremental: false);
    });
  });

  test('두 경로 모두 데이터를 실제로 적재한다', () {
    // Guards against the test passing because both produced nothing.
    expect(viaStaticFiles.teams, hasLength(5));
    expect(viaStaticFiles.games, hasLength(5));
    expect(viaFakeApi.teams, hasLength(5));
    expect(viaFakeApi.games, hasLength(5));
  });

  test('팀 도메인 결과가 동일하다', () {
    expect(viaFakeApi.teams.length, viaStaticFiles.teams.length);
    for (var i = 0; i < viaStaticFiles.teams.length; i++) {
      final a = viaStaticFiles.teams[i];
      final b = viaFakeApi.teams[i];
      expect(b.id, a.id);
      expect(b.name, a.name);
      expect(b.region, a.region);
      expect(b.colorHex, a.colorHex);
      expect(b.recruitment, a.recruitment);
      expect(b.displayName, a.displayName);
    }
  });

  test('경기 도메인 결과가 동일하다', () {
    expect(viaFakeApi.games.length, viaStaticFiles.games.length);
    for (var i = 0; i < viaStaticFiles.games.length; i++) {
      final a = viaStaticFiles.games[i];
      final b = viaFakeApi.games[i];
      expect(b.id, a.id);
      expect(b.status, a.status);
      expect(b.startTimeUtc, a.startTimeUtc);
      expect(b.homeTeamId, a.homeTeamId);
      expect(b.awayTeamId, a.awayTeamId);
      expect(b.homeScore, a.homeScore);
      expect(b.awayScore, a.awayScore);
      expect(b.statusNote, a.statusNote);
      // Derived facts must agree too, not just stored columns.
      expect(b.winnerTeamId, a.winnerTeamId);
      expect(b.isDraw, a.isDraw);
      expect(b.dedupeKey(), a.dedupeKey());
    }
  });

  test('경기장·대회·시즌 결과가 동일하다', () {
    expect(
      viaFakeApi.venues.map((v) => '${v.id}|${v.name}|${v.latitude}'),
      viaStaticFiles.venues.map((v) => '${v.id}|${v.name}|${v.latitude}'),
    );
    expect(
      viaFakeApi.competitions.map((c) => '${c.id}|${c.name}|${c.level.name}'),
      viaStaticFiles.competitions.map(
        (c) => '${c.id}|${c.name}|${c.level.name}',
      ),
    );
    // Nested seasons and stages must flatten identically on both paths.
    expect(
      viaFakeApi.seasons.map((s) => '${s.id}|${s.year}|${s.phase.name}'),
      viaStaticFiles.seasons.map((s) => '${s.id}|${s.year}|${s.phase.name}'),
    );
  });

  test('출처 메타데이터가 동일하게 보존된다', () {
    for (var i = 0; i < viaStaticFiles.games.length; i++) {
      final a = viaStaticFiles.games[i].provenance;
      final b = viaFakeApi.games[i].provenance;
      expect(b.sourceUrl, a.sourceUrl);
      expect(b.fetchedAt, a.fetchedAt);
      expect(b.isDemo, a.isDemo);
      expect(b.licenseStatus, a.licenseStatus);
    }
  });

  test('연기·취소 경기가 승패로 뭉개지지 않는다', () {
    for (final snapshot in <_DomainSnapshot>[viaStaticFiles, viaFakeApi]) {
      final postponed = snapshot.games.firstWhere((g) => g.id == 'g4');
      final cancelled = snapshot.games.firstWhere((g) => g.id == 'g5');
      expect(postponed.status, GameStatus.postponed);
      expect(postponed.statusNote, '우천 순연');
      expect(postponed.winnerTeamId, isNull);
      expect(cancelled.status, GameStatus.cancelled);
      expect(cancelled.winnerTeamId, isNull);
    }
  });

  test('무승부는 승자 없음으로 동일하게 처리된다', () {
    for (final snapshot in <_DomainSnapshot>[viaStaticFiles, viaFakeApi]) {
      final draw = snapshot.games.firstWhere((g) => g.id == 'g2');
      expect(draw.isDraw, isTrue);
      expect(draw.winnerTeamId, isNull);
    }
  });

  test('전체 스냅샷의 도메인 지문이 일치한다', () {
    // A single end-to-end assertion: if any field diverged, this fails.
    expect(viaFakeApi.fingerprint(), viaStaticFiles.fingerprint());
  });
}

class _DomainSnapshot {
  const _DomainSnapshot({
    required this.teams,
    required this.games,
    required this.venues,
    required this.competitions,
    required this.seasons,
  });

  final List<Team> teams;
  final List<Game> games;
  final List<Venue> venues;
  final List<Competition> competitions;
  final List<Season> seasons;

  /// A stable textual projection of everything a screen could read.
  String fingerprint() {
    final buffer = StringBuffer();
    for (final t in teams) {
      buffer.writeln(
        'T|${t.id}|${t.name}|${t.region}|${t.colorHex}'
        '|${t.recruitment.wireValue}|${t.provenance.sourceUrl}',
      );
    }
    for (final v in venues) {
      buffer.writeln('V|${v.id}|${v.name}|${v.latitude}|${v.longitude}');
    }
    for (final c in competitions) {
      buffer.writeln('C|${c.id}|${c.name}|${c.level.wireValue}');
    }
    for (final s in seasons) {
      buffer.writeln(
        'S|${s.id}|${s.competitionId}|${s.year}|${s.phase.wireValue}',
      );
    }
    for (final g in games) {
      buffer.writeln(
        'G|${g.id}|${g.status.wireValue}'
        '|${g.startTimeUtc.toIso8601String()}|${g.homeTeamId}|${g.awayTeamId}'
        '|${g.homeScore}|${g.awayScore}|${g.statusNote}|${g.winnerTeamId}'
        '|${g.dedupeKey()}',
      );
    }
    return buffer.toString();
  }
}

/// Serves the fixture as if it were bundled assets.
class _MapAssetBundle extends CachingAssetBundle {
  _MapAssetBundle(this.documents, {required this.prefix});

  final Map<String, String> documents;
  final String prefix;

  @override
  Future<ByteData> load(String key) async {
    final path = key.startsWith(prefix) ? key.substring(prefix.length) : key;
    final body = documents[path];
    if (body == null) {
      throw FlutterError('Asset not found: $key');
    }
    final bytes = utf8.encode(body);
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final path = key.startsWith(prefix) ? key.substring(prefix.length) : key;
    final body = documents[path];
    if (body == null) {
      throw FlutterError('Asset not found: $key');
    }
    return body;
  }
}

// --- fixture helpers ---------------------------------------------------------

String _doc(List<Map<String, dynamic>> items) => jsonEncode(<String, dynamic>{
  'schemaVersion': 1,
  'dataVersion': '2026.08.30.1',
  'generatedAt': '2026-08-30T00:00:00Z',
  'payloadKind': 'snapshot',
  'items': items,
});

Map<String, dynamic> _source(String id) => <String, dynamic>{
  'sourceName': 'fixture',
  'sourceUrl': 'https://example.org/$id',
  'sourceRecordId': id,
  'fetchedAt': '2026-08-30T00:00:00Z',
  'licenseStatus': 'permitted',
  'isDemo': false,
};

Map<String, dynamic> _team(
  String id,
  String name, {
  String? region,
  String? color,
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'region': ?region,
  'colorHex': ?color,
  'recruitment': 'open',
  'aliases': <String>[name.replaceAll(' ', '')],
  'source': _source(id),
};

Map<String, dynamic> _venue(String id, String name, double lat, double lon) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'latitude': lat,
      'longitude': lon,
      'source': _source(id),
    };

Map<String, dynamic> _game(
  String id, {
  required String home,
  required String away,
  required String start,
  required String status,
  int? homeScore,
  int? awayScore,
  String? note,
}) => <String, dynamic>{
  'id': id,
  'status': status,
  'startTime': start,
  'homeTeamId': home,
  'awayTeamId': away,
  'competitionId': 'comp-1',
  'seasonId': 'season-1',
  'venueId': 'venue-1',
  'homeScore': ?homeScore,
  'awayScore': ?awayScore,
  'statusNote': ?note,
  'source': _source(id),
};
