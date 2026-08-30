import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/database/database.dart';
import 'package:w_baseball/core/utils/korean_text.dart';
import 'package:w_baseball/data/models/domain.dart';
import 'package:w_baseball/data/repositories/search_repository.dart';

/// Search is one tap from every primary screen, and it had no tests.
///
/// The interesting cases are the ones a person hits by accident: a stray
/// punctuation mark, a name found through an alias, a gated entity that must
/// not be reachable by typing its name.
void main() {
  late WbDatabase db;
  final now = DateTime.utc(2026, 8, 30, 9);

  setUp(() => db = WbDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  DriftSearchRepository repo({bool playerProfiles = false}) =>
      DriftSearchRepository(db: db, playerProfilesEnabled: playerProfiles);

  Future<void> addTeam(
    String id,
    String name, {
    List<String> aliases = const [],
    String recruitment = 'closed',
  }) async {
    await db
        .into(db.teams)
        .insert(
          TeamsCompanion.insert(
            id: id,
            name: name,
            searchKey: Value(KoreanText.searchKey(name, aliases: aliases)),
            recruitment: Value(recruitment),
            sourceName: 'demo',
            sourceUrl: 'https://example.test/demo',
            fetchedAt: now,
          ),
        );
  }

  Future<void> addPerson(String id, String name, {bool isMinor = false}) async {
    await db
        .into(db.people)
        .insert(
          PeopleCompanion.insert(
            id: id,
            name: name,
            searchKey: Value(KoreanText.searchKey(name)),
            isMinor: Value(isMinor),
            sourceName: 'demo',
            sourceUrl: 'https://example.test/demo',
            fetchedAt: now,
          ),
        );
  }

  group('한글 검색', () {
    setUp(() async {
      await addTeam('t-seoul', '서울 다이아몬드');
      await addTeam('t-han', '한강 리버베어스');
      await addTeam('t-busan', '부산 씨걸스', aliases: const ['BSG']);
    });

    test('전체 이름으로 찾는다', () async {
      final hits = await repo().search('서울 다이아몬드');
      expect(hits.first.id, 't-seoul');
      expect(hits.first.score, 100);
    });

    test('앞부분만 쳐도 찾는다', () async {
      final hits = await repo().search('서울');
      expect(hits.map((h) => h.id), contains('t-seoul'));
    });

    test('초성으로 찾는다', () async {
      // The whole reason `search_key` stores two forms in one column.
      final hits = await repo().search('ㅅㅇ');
      expect(hits.map((h) => h.id), contains('t-seoul'));
    });

    test('별칭으로도 찾는다', () async {
      final hits = await repo().search('BSG');
      expect(hits.map((h) => h.id), contains('t-busan'));
    });

    test('맞는 것이 없으면 빈 결과를 준다', () async {
      expect(await repo().search('존재하지않는팀이름'), isEmpty);
    });

    test('빈 질의는 아무것도 찾지 않는다', () async {
      expect(await repo().search('   '), isEmpty);
    });
  });

  group('LIKE 메타문자', () {
    setUp(() async {
      await addTeam('t-a', '서울 다이아몬드');
      await addTeam('t-b', '한강 리버베어스');
      await addTeam('t-c', '부산 씨걸스');
    });

    test('%만 입력하면 전체 목록이 나오지 않는다', () async {
      // `search_key LIKE '%q%'`. A `%` that survives normalisation is a
      // wildcard, and typing one used to return every row in the database as
      // if the user had searched for something.
      expect(await repo().search('%'), isEmpty);
    });

    test('%를 섞어도 와일드카드로 동작하지 않는다', () async {
      // Stripped, not escaped — so this reads as a search for 서울, which is a
      // real team. What must not happen is 한강 and 부산 coming along too.
      final hits = await repo().search('서%울');
      expect(hits.map((h) => h.id), <String>['t-a']);
    });

    test('키 구분자를 입력해도 전체가 걸리지 않는다', () async {
      // `|` separates the normalised name from its 초성 inside every key, so
      // an unstripped one both matches everything and matches across a
      // boundary that exists in no name.
      expect(await repo().search('|'), isEmpty);
    });

    test('밑줄은 한 글자 와일드카드로 동작하지 않는다', () async {
      expect(await repo().search('_'), isEmpty);
    });
  });

  group('선수 노출 제한', () {
    setUp(() async {
      await addPerson('p-adult', '김선수');
      await addPerson('p-minor', '이유망', isMinor: true);
    });

    test('플래그가 꺼져 있으면 선수는 검색되지 않는다', () async {
      // Search must not be a back door into a screen the flag has closed.
      expect(await repo().search('김선수'), isEmpty);
    });

    test('플래그가 켜져 있어도 미성년 선수는 검색되지 않는다', () async {
      final hits = await repo(playerProfiles: true).search('이유망');
      expect(hits, isEmpty, reason: '미성년 선수는 플래그와 무관하게 제외됩니다');
    });

    test('플래그가 켜지면 성인 선수는 검색된다', () async {
      final hits = await repo(playerProfiles: true).search('김선수');
      expect(hits.map((h) => h.id), <String>['p-adult']);
      expect(hits.first.type, SearchEntityType.person);
    });
  });

  group('정렬과 개수 제한', () {
    test('정확히 일치하는 결과가 부분 일치보다 위에 온다', () async {
      await addTeam('t-exact', '서울');
      await addTeam('t-partial', '서울 다이아몬드');

      final hits = await repo().search('서울');
      expect(hits.first.id, 't-exact');
    });

    test('limit을 넘겨 돌려주지 않는다', () async {
      for (var i = 0; i < 10; i++) {
        await addTeam('t-$i', '서울 $i팀');
      }
      expect(await repo().search('서울', limit: 3), hasLength(3));
    });
  });

  group('입력 전 추천', () {
    test('팔로우한 팀을 먼저 제안한다', () async {
      await addTeam('t-follow', '서울 다이아몬드');
      await addTeam('t-open', '한강 리버베어스', recruitment: 'open');
      await db
          .into(db.localFollows)
          .insert(
            LocalFollowsCompanion.insert(
              kind: 'team',
              entityId: 't-follow',
              followedAt: now,
            ),
          );

      final hits = await repo().suggestions();
      expect(hits.first.id, 't-follow');
      expect(hits.first.subtitle, '팔로우 중');
    });

    test('팔로우가 없으면 모집 중인 팀을 제안한다', () async {
      await addTeam('t-open', '한강 리버베어스', recruitment: 'open');
      await addTeam('t-closed', '서울 다이아몬드');

      final hits = await repo().suggestions();
      expect(hits.map((h) => h.id), <String>['t-open']);
      expect(hits.first.subtitle, '모집 중');
    });

    test('같은 팀을 두 번 제안하지 않는다', () async {
      await addTeam('t-both', '한강 리버베어스', recruitment: 'open');
      await db
          .into(db.localFollows)
          .insert(
            LocalFollowsCompanion.insert(
              kind: 'team',
              entityId: 't-both',
              followedAt: now,
            ),
          );

      final hits = await repo().suggestions();
      expect(hits.where((h) => h.id == 't-both'), hasLength(1));
    });
  });
}
