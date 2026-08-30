import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/utils/korean_text.dart';

void main() {
  group('초성 추출', () {
    test('한글 음절에서 첫 자음을 뽑는다', () {
      expect(KoreanText.initials('서울'), 'ㅅㅇ');
      expect(KoreanText.initials('부산 씨걸스'), 'ㅂㅅㅆㄱㅅ');
      expect(KoreanText.leadOf('한'), 'ㅎ');
    });

    test('공백은 무시하고 영문·숫자는 소문자로 남긴다', () {
      expect(KoreanText.initials('WBAK 서울'), 'wbakㅅㅇ');
    });

    test('쌍자음을 단자음으로 뭉개지 않는다', () {
      expect(KoreanText.initials('까치'), 'ㄲㅊ');
    });
  });

  group('정규화', () {
    test('공백과 문장부호를 제거한다', () {
      expect(KoreanText.normalize('서울 다이아몬드'), '서울다이아몬드');
      expect(KoreanText.normalize('한강·리버베어스'), '한강리버베어스');
      expect(KoreanText.normalize('WBAK (서울)'), 'wbak서울');
    });
  });

  group('검색 매칭', () {
    const team = '한강 리버베어스';

    test('띄어쓰기를 무시하고 부분 일치한다', () {
      expect(KoreanText.matches(team, '한강리버'), isTrue);
      expect(KoreanText.matches(team, '리버베어스'), isTrue);
    });

    test('초성만 입력해도 찾는다', () {
      expect(KoreanText.matches(team, 'ㅎㄱ'), isTrue);
      expect(KoreanText.matches(team, 'ㅎㄱㄹㅂㅂㅇㅅ'), isTrue);
    });

    test('관련 없는 질의는 걸러진다', () {
      expect(KoreanText.matches(team, '부산'), isFalse);
      expect(KoreanText.matches(team, 'ㅂㅅ'), isFalse);
    });

    test('별칭으로도 찾을 수 있다', () {
      expect(
        KoreanText.matches('한강 리버베어스', '리버스', aliases: <String>['리버스']),
        isTrue,
      );
    });

    test('빈 질의는 모두 통과시킨다', () {
      expect(KoreanText.matches(team, ''), isTrue);
      expect(KoreanText.matches(team, '   '), isTrue);
    });
  });

  group('SQL 경로와 동일한 키', () {
    test('searchKey는 정규형과 초성을 모두 담는다', () {
      final key = KoreanText.searchKey('한강 리버베어스');
      expect(key, contains('한강리버베어스'));
      expect(key, contains('ㅎㄱㄹㅂㅂㅇㅅ'));
    });

    test('queryKey는 자모 전용 입력을 초성으로 처리한다', () {
      expect(KoreanText.queryKey('ㅅㅇ'), 'ㅅㅇ');
      expect(KoreanText.queryKey('서울'), '서울');
    });

    test('저장 키가 질의 키를 포함하면 인메모리 매칭과 결과가 같다', () {
      // The DB does `search_key LIKE '%q%'`; this asserts the two agree.
      const name = '수원 필드메이커스';
      for (final query in <String>['수원', 'ㅅㅇ', '필드', 'ㅍㄷㅁㅇㅋㅅ']) {
        final sqlWouldMatch = KoreanText.searchKey(name)
            .contains(KoreanText.queryKey(query));
        expect(sqlWouldMatch, KoreanText.matches(name, query), reason: query);
      }
    });
  });

  group('정렬 점수', () {
    test('정확·접두 일치가 중간 일치보다 높다', () {
      final exact = KoreanText.score('서울', '서울');
      final prefix = KoreanText.score('서울 스타즈', '서울');
      final middle = KoreanText.score('강남 서울클럽', '서울');
      expect(exact, greaterThan(prefix));
      expect(prefix, greaterThan(middle));
      expect(middle, greaterThan(0));
    });

    test('일치하지 않으면 0', () {
      expect(KoreanText.score('부산 씨걸스', '대구'), 0);
    });
  });

  group('조사 선택', () {
    test('받침 유무에 따라 목적격 조사가 달라진다', () {
      expect(KoreanText.objectParticle('팀'), '을');
      expect(KoreanText.objectParticle('선수'), '를');
    });

    test('주격·주제격 조사', () {
      expect(KoreanText.subjectParticle('팀'), '이');
      expect(KoreanText.subjectParticle('경기'), '가');
      expect(KoreanText.topicParticle('팀'), '은');
      expect(KoreanText.topicParticle('경기'), '는');
    });

    test('방향 조사는 ㄹ 받침을 예외 처리한다', () {
      expect(KoreanText.directionParticle('서울'), '로');
      expect(KoreanText.directionParticle('구장'), '으로');
      expect(KoreanText.directionParticle('경기'), '로');
    });
  });
}
