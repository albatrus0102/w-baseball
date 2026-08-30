import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/config/app_config.dart';
import 'package:w_baseball/data/dto/dtos.dart';
import 'package:w_baseball/data/dto/json_reader.dart';
import 'package:w_baseball/data/models/domain.dart';
import 'package:w_baseball/data/sources/payload_envelope.dart';
import 'package:w_baseball/data/sources/sports_data_source.dart';
import 'package:w_baseball/data/sync/sync_contracts.dart';

Map<String, dynamic> source({bool demo = false}) => <String, dynamic>{
  'sourceName': 'test',
  'sourceUrl': 'https://example.org/game/1',
  'fetchedAt': '2026-08-30T00:00:00Z',
  'isDemo': demo,
};

Map<String, dynamic> game({
  String id = 'g1',
  String status = 'final',
  String home = 'team-a',
  String away = 'team-b',
  int? homeScore = 5,
  int? awayScore = 4,
  Map<String, dynamic>? lineScore,
  String startTime = '2026-08-30T05:00:00Z',
}) => <String, dynamic>{
  'id': id,
  'status': status,
  'startTime': startTime,
  'homeTeamId': home,
  'awayTeamId': away,
  'homeScore': ?homeScore,
  'awayScore': ?awayScore,
  'lineScore': ?lineScore,
  'source': source(),
};

void main() {
  group('JsonReader 관용성', () {
    test('모르는 필드는 무시한다', () {
      final dto = TeamDto.fromJson(<String, dynamic>{
        'id': 't1',
        'name': '한강 리버베어스',
        'somethingTheServerAddedLater': {'nested': true},
        'source': source(),
      });
      expect(dto.id, 't1');
      expect(dto.name, '한강 리버베어스');
    });

    test('필수 필드가 없으면 해당 레코드만 거부한다', () {
      expect(
        () => TeamDto.fromJson(<String, dynamic>{
          'name': '이름만',
          'source': source(),
        }),
        throwsA(isA<DtoValidationException>()),
      );
    });

    test('출처 블록이 없으면 거부한다', () {
      expect(
        () => TeamDto.fromJson(<String, dynamic>{'id': 't1', 'name': '팀'}),
        throwsA(isA<DtoValidationException>()),
      );
    });
  });

  group('시각 처리', () {
    test('시간대가 없는 시각은 거부한다', () {
      // A kick-off time without a zone is not a usable kick-off time.
      expect(
        () => GameDto.fromJson(game(startTime: '2026-08-30T14:00:00')),
        throwsA(isA<DtoValidationException>()),
      );
    });

    test('Z와 오프셋 표기를 모두 받아 UTC로 정규화한다', () {
      final z = GameDto.fromJson(game(startTime: '2026-08-30T05:00:00Z'));
      final offset = GameDto.fromJson(
        game(id: 'g2', startTime: '2026-08-30T14:00:00+09:00'),
      );
      expect(z.startTime.isUtc, isTrue);
      expect(z.startTime, offset.startTime);
    });
  });

  group('경기 검증 규칙', () {
    test('홈팀과 원정팀이 같으면 거부한다', () {
      expect(
        () => GameDto.fromJson(game(home: 'team-a', away: 'team-a')),
        throwsA(isA<DtoValidationException>()),
      );
    });

    test('종료 경기에 점수가 없으면 거부한다', () {
      expect(
        () => GameDto.fromJson(game(homeScore: null, awayScore: null)),
        throwsA(isA<DtoValidationException>()),
      );
    });

    test('예정 경기는 점수가 없어도 통과한다', () {
      final dto = GameDto.fromJson(
        game(status: 'scheduled', homeScore: null, awayScore: null),
      );
      expect(dto.status, 'scheduled');
      expect(dto.homeScore, isNull);
    });

    test('음수 점수를 거부한다', () {
      expect(
        () => GameDto.fromJson(game(homeScore: -1)),
        throwsA(isA<DtoValidationException>()),
      );
    });

    test('이닝 합계가 최종 점수와 다르면 거부한다', () {
      expect(
        () => GameDto.fromJson(
          game(
            homeScore: 5,
            awayScore: 4,
            lineScore: <String, dynamic>{
              'homeInnings': <int>[
                1,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
              ], // sums to 1, not 5
              'awayInnings': <int>[1, 1, 1, 1, 0, 0, 0, 0, 0],
            },
          ),
        ),
        throwsA(isA<DtoValidationException>()),
      );
    });

    test('이닝 합계가 맞으면 통과한다', () {
      final dto = GameDto.fromJson(
        game(
          homeScore: 5,
          awayScore: 4,
          lineScore: <String, dynamic>{
            'homeInnings': <int>[2, 0, 1, 0, 2, 0, 0, 0, 0],
            'awayInnings': <int>[1, 1, 0, 1, 0, 1, 0, 0, 0],
          },
        ),
      );
      expect(dto.lineScore, isNotNull);
      expect(dto.lineScore!.homeInnings.length, 9);
    });

    test('타지 않은 이닝(null)은 0점과 구분된다', () {
      final dto = GameDto.fromJson(
        game(
          homeScore: 3,
          awayScore: 4,
          lineScore: <String, dynamic>{
            // Home did not bat in the 9th — a walk-off. `null`, not 0.
            'homeInnings': <dynamic>[1, 0, 1, 0, 1, 0, 0, 0, null],
            'awayInnings': <int>[2, 0, 1, 0, 1, 0, 0, 0, 0],
          },
        ),
      );
      expect(dto.lineScore!.homeInnings.last, isNull);
      expect(dto.lineScore!.homeInnings[1], 0);
    });
  });

  group('순위 검증', () {
    test('경기 수가 승패무 합계보다 적으면 거부한다', () {
      expect(
        () => StandingDto.fromJson(<String, dynamic>{
          'id': 's1',
          'seasonId': 'season',
          'teamId': 'team-a',
          'capturedAt': '2026-08-30T00:00:00Z',
          'played': 2,
          'wins': 3,
          'losses': 1,
          'source': source(),
        }),
        throwsA(isA<DtoValidationException>()),
      );
    });
  });

  group('개인정보 최소화', () {
    test('PersonDto에는 연락처를 담을 자리가 없다', () {
      final dto = PersonDto.fromJson(<String, dynamic>{
        'id': 'p1',
        'name': '홍길동',
        // Even if an upstream feed sends these, they are simply not read.
        'phone': '010-0000-0000',
        'email': 'x@example.com',
        'birthDate': '1990-01-01',
        'address': '서울시',
        'source': source(),
      });
      expect(dto.name, '홍길동');
      expect(PersonDto.knownKeys.contains('phone'), isFalse);
      expect(PersonDto.knownKeys.contains('email'), isFalse);
      expect(PersonDto.knownKeys.contains('birthDate'), isFalse);
      expect(PersonDto.knownKeys.contains('address'), isFalse);
    });

    test('미성년 표시는 사진 표시를 막는다', () {
      final person = Person(
        id: 'p1',
        name: '선수',
        isMinor: true,
        photoUrl: 'https://example.org/p.jpg',
        photoLicense: LicenseStatus.permitted,
        provenance: Provenance(
          sourceName: 'test',
          sourceUrl: 'https://example.org',
          fetchedAt: DateTime.utc(2026, 8, 30),
        ),
      );
      expect(person.canShowPhoto, isFalse);
    });

    test('라이선스가 확인되지 않은 사진은 표시하지 않는다', () {
      final person = Person(
        id: 'p2',
        name: '선수',
        photoUrl: 'https://example.org/p.jpg',
        photoLicense: LicenseStatus.unknown,
        provenance: Provenance(
          sourceName: 'test',
          sourceUrl: 'https://example.org',
          fetchedAt: DateTime.utc(2026, 8, 30),
        ),
      );
      expect(person.canShowPhoto, isFalse);
    });
  });

  group('PayloadEnvelope', () {
    const contract = DataContractConfig();

    test('배열만 있는 문서도 스냅샷으로 받아들인다', () {
      final envelope = PayloadEnvelope.decode(
        jsonEncode(<dynamic>[
          <String, dynamic>{'id': 't1', 'name': '팀', 'source': source()},
        ]),
      );
      expect(envelope.payloadKind, SyncPayloadKind.snapshot);
      expect(envelope.items.length, 1);
    });

    test('payloadKind가 없으면 delta로 본다', () {
      // Conservative: an unknown payload must not license tombstoning.
      final envelope = PayloadEnvelope.decode(
        jsonEncode(<String, dynamic>{'items': <dynamic>[]}),
      );
      expect(envelope.payloadKind, SyncPayloadKind.delta);
    });

    test('한 레코드가 깨져도 나머지는 살린다', () {
      final envelope = PayloadEnvelope.decode(
        jsonEncode(<String, dynamic>{
          'schemaVersion': 1,
          'payloadKind': 'snapshot',
          'items': <dynamic>[
            <String, dynamic>{'id': 't1', 'name': '정상', 'source': source()},
            <String, dynamic>{'name': 'id 없음', 'source': source()},
            <String, dynamic>{'id': 't3', 'name': '정상2', 'source': source()},
          ],
        }),
      );
      final page = envelope.toPage<TeamDto>(
        sourceName: 'test',
        entityType: SyncEntityType.team,
        parse: TeamDto.fromJson,
        supports: contract.supports,
      );
      expect(page.items.length, 2);
      expect(page.issues.length, 1);
      expect(page.issues.first.severity, SyncIssueSeverity.recordRejected);
      expect(page.hasRejections, isTrue);
    });

    test('지원하지 않는 스키마 버전은 캐시를 건드리지 않고 중단시킨다', () {
      final envelope = PayloadEnvelope.decode(
        jsonEncode(<String, dynamic>{
          'schemaVersion': 99,
          'items': <dynamic>[],
        }),
      );
      expect(
        () => envelope.toPage<TeamDto>(
          sourceName: 'test',
          entityType: SyncEntityType.team,
          parse: TeamDto.fromJson,
          supports: contract.supports,
        ),
        throwsA(
          isA<SyncException>().having(
            (e) => e.kind,
            'kind',
            SyncFailureKind.schemaUnsupported,
          ),
        ),
      );
    });

    test('JSON이 아니면 문서 수준 오류', () {
      expect(
        () => PayloadEnvelope.decode('this is not json'),
        throwsA(isA<PayloadFormatException>()),
      );
    });
  });

  group('GameStatus', () {
    test('final은 예약어라 finalized로 매핑되지만 wire 값은 유지된다', () {
      expect(GameStatus.parse('final'), GameStatus.finalized);
      expect(GameStatus.finalized.wireValue, 'final');
    });

    test('모르는 값은 unknown으로 두고 scheduled로 오해하지 않는다', () {
      expect(GameStatus.parse('something-new'), GameStatus.unknown);
      expect(GameStatus.parse(null), GameStatus.unknown);
    });

    test('연기·취소는 승패로 취급하지 않는다', () {
      for (final status in <GameStatus>[
        GameStatus.postponed,
        GameStatus.cancelled,
        GameStatus.delayed,
      ]) {
        expect(status.hasResult, isFalse, reason: status.name);
        expect(status.isDisrupted, isTrue, reason: status.name);
      }
    });
  });

  group('중복 판정', () {
    Game make({
      required String id,
      required DateTime start,
      String home = 'a',
      String away = 'b',
      String? venue = 'v1',
    }) => Game(
      id: id,
      status: GameStatus.scheduled,
      startTimeUtc: start,
      homeTeamId: home,
      awayTeamId: away,
      competitionId: 'comp',
      venueId: venue,
      provenance: Provenance(
        sourceName: 's',
        sourceUrl: 'https://example.org',
        fetchedAt: DateTime.utc(2026),
      ),
    );

    test('같은 대회·시간·구장·두 팀이면 id가 달라도 같은 경기로 본다', () {
      final a = make(id: 'x', start: DateTime.utc(2026, 8, 30, 5));
      final b = make(id: 'y', start: DateTime.utc(2026, 8, 30, 5, 30));
      expect(a.dedupeKey(), b.dedupeKey());
    });

    test('홈·원정이 뒤바뀌어도 같은 경기로 본다', () {
      final a = make(id: 'x', start: DateTime.utc(2026, 8, 30, 5));
      final b = make(
        id: 'y',
        start: DateTime.utc(2026, 8, 30, 5),
        home: 'b',
        away: 'a',
      );
      expect(a.dedupeKey(), b.dedupeKey());
    });

    test('다른 날이면 다른 경기다', () {
      final a = make(id: 'x', start: DateTime.utc(2026, 8, 30, 5));
      final b = make(id: 'y', start: DateTime.utc(2026, 8, 31, 5));
      expect(a.dedupeKey(), isNot(b.dedupeKey()));
    });
  });
}
