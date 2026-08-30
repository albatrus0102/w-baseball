import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/network/circuit_breaker.dart';
import 'package:w_baseball/core/platform/notification_service.dart';
import 'package:w_baseball/core/utils/kst.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/data/models/content.dart';
import 'package:w_baseball/data/models/domain.dart';
import 'package:w_baseball/data/models/stats.dart';
import 'package:w_baseball/features/web_source/source_web_view_screen.dart';

void main() {
  group('KST 처리', () {
    test('UTC를 한국 시각으로 바꾼다', () {
      final utc = DateTime.utc(2026, 8, 30, 5); // 05:00Z
      expect(Kst.toKst(utc).hour, 14);
      expect(Kst.dayKey(utc), '2026-08-30');
      expect(Kst.monthKey(utc), '2026-08');
    });

    test('한국 기준 날짜 경계를 UTC와 혼동하지 않는다', () {
      // 2026-08-30 23:00 KST is 14:00Z on the same day.
      final lateEvening = DateTime.utc(2026, 8, 30, 14);
      expect(Kst.dayKey(lateEvening), '2026-08-30');

      // 2026-08-31 00:30 KST is 15:30Z on 2026-08-30.
      final justAfterMidnight = DateTime.utc(2026, 8, 30, 15, 30);
      expect(Kst.dayKey(justAfterMidnight), '2026-08-31');
    });

    test('왕복 변환이 안정적이다', () {
      final utc = DateTime.utc(2026, 8, 30, 5);
      expect(Kst.fromKst(Kst.toKst(utc)), utc);
    });

    test('하루의 시작·끝을 UTC 범위로 준다', () {
      final utc = DateTime.utc(2026, 8, 30, 5);
      final start = Kst.startOfKstDayUtc(utc);
      final end = Kst.endOfKstDayUtc(utc);
      expect(Kst.dayKey(start), '2026-08-30');
      expect(end.difference(start), const Duration(days: 1));
      expect(start.isBefore(utc), isTrue);
    });

    test('다가오는 주말 범위를 구한다', () {
      // 2026-08-30 is a Sunday; the window should be the current weekend.
      final sunday = DateTime.utc(2026, 8, 30, 3);
      final weekend = Kst.upcomingWeekendUtc(sunday);
      expect(
        weekend.endUtc.difference(weekend.startUtc),
        const Duration(days: 2),
      );
      expect(Kst.toKst(weekend.startUtc).weekday, DateTime.saturday);
    });

    test('상대 시각 표현', () {
      final now = DateTime.utc(2026, 8, 30, 12);
      expect(
        KoDate.relative(now.subtract(const Duration(minutes: 5)), now),
        '5분 전',
      );
      expect(
        KoDate.relative(now.subtract(const Duration(hours: 3)), now),
        '3시간 전',
      );
      expect(
        KoDate.relative(now.subtract(const Duration(days: 2)), now),
        '2일 전',
      );
    });

    test('오늘·내일 라벨', () {
      final now = DateTime.utc(2026, 8, 30, 3);
      expect(KoDate.relativeDayLabel(now, now), '오늘');
      expect(
        KoDate.relativeDayLabel(now.add(const Duration(days: 1)), now),
        '내일',
      );
      expect(
        KoDate.relativeDayLabel(now.add(const Duration(days: 5)), now),
        isNull,
      );
    });

    test('점수는 스크린리더용으로 "대"를 사용한다', () {
      expect(KoDate.scoreForScreenReader(5, 4), '5 대 4');
    });
  });

  group('순위 계산', () {
    LeaderboardEntry entry(
      String name,
      double value, {
      double qualifier = 100,
    }) => LeaderboardEntry(
      personId: name,
      playerName: name,
      value: value,
      qualifies: true,
      qualifierValue: qualifier,
    );

    test('높을수록 좋은 기록을 내림차순으로 정렬한다', () {
      final ranked = Leaderboard.rank(<LeaderboardEntry>[
        entry('A', 3),
        entry('B', 9),
        entry('C', 5),
      ], higherIsBetter: true);
      expect(ranked.map((e) => e.playerName), <String>['B', 'C', 'A']);
      expect(ranked.first.rank, 1);
    });

    test('낮을수록 좋은 기록은 오름차순으로 정렬한다', () {
      final ranked = Leaderboard.rank(<LeaderboardEntry>[
        entry('A', 3.2),
        entry('B', 1.1),
        entry('C', 5.0),
      ], higherIsBetter: false);
      expect(ranked.map((e) => e.playerName), <String>['B', 'A', 'C']);
    });

    test('동률은 같은 순위를 공유하고 표시된다', () {
      final ranked = Leaderboard.rank(<LeaderboardEntry>[
        entry('A', 5),
        entry('B', 5),
        entry('C', 3),
      ], higherIsBetter: true);
      expect(ranked[0].rank, 1);
      expect(ranked[1].rank, 1);
      expect(ranked[0].isTied, isTrue);
      expect(ranked[1].isTied, isTrue);
      // The next player takes the rank the tie consumed.
      expect(ranked[2].rank, 3);
      expect(ranked[2].isTied, isFalse);
    });

    test('자격 미달 선수는 자격 충족자 아래로 내려간다', () {
      final ranked = Leaderboard.rank(
        <LeaderboardEntry>[
          entry('낮은기록_충족', 2, qualifier: 100),
          entry('높은기록_미달', 9, qualifier: 5),
        ],
        higherIsBetter: true,
        thresholdFor: (_) => 50,
      );
      expect(ranked.first.playerName, '낮은기록_충족');
      expect(ranked.first.qualifies, isTrue);
      expect(ranked.last.qualifies, isFalse);
    });

    test('규정 타석은 팀 경기 수에 비례한다', () {
      const rule = QualificationRule(
        key: 'pa',
        labelKo: '규정 타석',
        descriptionKo: '',
        perTeamGame: 3.1,
      );
      expect(rule.threshold(10), 31);
      expect(rule.threshold(7), 22); // ceil(21.7)
    });

    test('팀 경기 수를 모르면 기준을 만들어내지 않는다', () {
      const rule = QualificationRule(
        key: 'pa',
        labelKo: '규정 타석',
        descriptionKo: '',
        perTeamGame: 3.1,
      );
      // null means "we don't know" — the UI then shows everyone and says so.
      expect(rule.threshold(null), isNull);
      expect(rule.threshold(0), isNull);
    });

    test('타율은 앞의 0을 뗀 한국식 표기를 쓴다', () {
      final avg = StatDefinition.byKey('avg')!;
      expect(avg.format(0.325), '.325');
      expect(avg.format(null), '-');
      final era = StatDefinition.byKey('era')!;
      expect(era.format(2.5), '2.50');
    });

    test('1.000은 잘리지 않는다', () {
      // The leading zero is dropped only when there is one. Cutting the first
      // character unconditionally turns a perfect day — 3타수 3안타, an
      // undefeated team — into .000, the worst number on the page, and it does
      // so precisely when someone is proudest of it.
      expect(formatRate(1), '1.000');
      expect(formatRate(0), '.000');
      expect(formatRate(0.325), '.325');
      expect(formatRate(null), '-');
    });

    test('ERA처럼 소수 두 자리인 값은 앞자리를 건드리지 않는다', () {
      // The convention is specific to three-decimal rate stats. An ERA of 0.90
      // is written 0.90, not .90.
      expect(formatRate(0.9, decimalPlaces: 2), '0.90');
    });

    test('종합 평점이나 AI 등급 항목은 존재하지 않는다', () {
      final keys = StatDefinition.defaults.map((d) => d.key).toSet();
      for (final forbidden in <String>[
        'rating',
        'grade',
        'score',
        'ai',
        'war',
      ]) {
        expect(keys.contains(forbidden), isFalse, reason: forbidden);
      }
    });
  });

  group('최근 흐름', () {
    Game game({
      required String winner,
      required String home,
      required String away,
    }) => Game(
      id: 'g',
      status: GameStatus.finalized,
      startTimeUtc: DateTime.utc(2026, 8, 1),
      homeTeamId: home,
      awayTeamId: away,
      homeScore: winner == home ? 5 : 2,
      awayScore: winner == home ? 2 : 5,
      provenance: Provenance(
        sourceName: 's',
        sourceUrl: 'https://example.org',
        fetchedAt: DateTime.utc(2026),
      ),
    );

    test('승·패를 팀 관점에서 해석한다', () {
      final g = game(winner: 'a', home: 'a', away: 'b');
      expect(TeamForm.resultFor(g, 'a'), FormResult.win);
      expect(TeamForm.resultFor(g, 'b'), FormResult.loss);
    });

    test('연기 경기는 무결과로 처리한다', () {
      final postponed = Game(
        id: 'g',
        status: GameStatus.postponed,
        startTimeUtc: DateTime.utc(2026, 8, 1),
        homeTeamId: 'a',
        awayTeamId: 'b',
        provenance: Provenance(
          sourceName: 's',
          sourceUrl: 'https://example.org',
          fetchedAt: DateTime.utc(2026),
        ),
      );
      expect(TeamForm.resultFor(postponed, 'a'), FormResult.noResult);
    });

    test('순위 변화는 상승을 양수로 표현한다', () {
      const form = TeamForm(
        teamId: 'a',
        results: <FormResult>[],
        previousRank: 5,
        currentRank: 2,
      );
      expect(form.rankDelta, 3);
    });

    test('요약 문구', () {
      const form = TeamForm(
        teamId: 'a',
        results: <FormResult>[
          FormResult.win,
          FormResult.win,
          FormResult.loss,
          FormResult.draw,
        ],
      );
      expect(form.summaryKo, '2승 1패 1무');
    });
  });

  group('리그 펄스', () {
    test('진출 확정·탈락을 단정하지 않는다', () {
      const pulse = LeaguePulse(
        seasonId: 's',
        competitionName: '데모 리그',
        completedGames: 8,
        totalScheduledGames: 20,
        currentStageName: '정규 리그',
        postponedCount: 1,
        coverage: DataCoverage(observed: 8, expected: 20),
      );
      final headline = pulse.headlineKo;
      expect(headline, contains('20경기 중 8경기 종료'));
      expect(headline, contains('연기 1경기'));
      // Wording must stay factual: no qualification claims.
      for (final forbidden in <String>['확정', '탈락', '진출']) {
        expect(headline.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('전체 일정을 모르면 진행률을 만들어내지 않는다', () {
      const pulse = LeaguePulse(
        seasonId: 's',
        competitionName: 'x',
        completedGames: 3,
        totalScheduledGames: 0,
        coverage: DataCoverage.unknown,
      );
      expect(pulse.progress, isNull);
      expect(pulse.progressLabelKo, '전체 일정 확인 중');
    });
  });

  group('데이터 완전도', () {
    test('전체를 모르면 비율을 계산하지 않는다', () {
      const coverage = DataCoverage(observed: 5, expected: 0);
      expect(coverage.isUnknown, isTrue);
      expect(coverage.ratio, isNull);
      expect(coverage.labelKo, '집계 범위 확인 중');
    });

    test('부분 집계는 그렇게 표시한다', () {
      const coverage = DataCoverage(observed: 6, expected: 10);
      expect(coverage.isComplete, isFalse);
      expect(coverage.ratio, 0.6);
      expect(coverage.labelKo, '10경기 중 6경기 집계');
    });
  });

  group('스포일러 정책', () {
    test('가리기 설정은 결과 이상만 가린다', () {
      const hide = SpoilerPolicy.hide;
      expect(hide.shouldMask(SpoilerLevel.none), isFalse);
      expect(hide.shouldMask(SpoilerLevel.mild), isFalse);
      expect(hide.shouldMask(SpoilerLevel.result), isTrue);
      expect(hide.shouldMask(SpoilerLevel.full), isTrue);
    });

    test('바로 보기 설정은 아무것도 가리지 않는다', () {
      for (final level in SpoilerLevel.values) {
        expect(SpoilerPolicy.reveal.shouldMask(level), isFalse);
      }
    });

    test('가릴 때는 스포일러 없는 teaser를 대신 보여준다', () {
      final recap = EpisodeRecap(
        id: 'r',
        episodeId: 'e',
        teaser: '수비 훈련이 중심입니다.',
        whatHappened: '블랙퀸즈가 이겼습니다.',
        meta: ContentMeta(
          provenance: Provenance(
            sourceName: 's',
            sourceUrl: 'https://example.org',
            fetchedAt: DateTime.utc(2026),
          ),
          publishedAt: DateTime.utc(2026),
          spoilerLevel: SpoilerLevel.result,
        ),
      );
      expect(recap.maskedHeadline(SpoilerPolicy.hide), '수비 훈련이 중심입니다.');
      expect(recap.maskedHeadline(SpoilerPolicy.reveal), '블랙퀸즈가 이겼습니다.');
    });
  });

  group('알림 카테고리', () {
    test('모든 카테고리가 개별적으로 켜고 꺼진다', () {
      var prefs = const NotificationPreference();
      for (final category in NotificationCategory.values) {
        expect(prefs.isEnabled(category), isFalse);
      }
      prefs = prefs.copyWith(
        enabled: <NotificationCategory>{NotificationCategory.weatherRisk},
      );
      expect(prefs.isEnabled(NotificationCategory.weatherRisk), isTrue);
      expect(prefs.isEnabled(NotificationCategory.standingsUpdate), isFalse);
    });

    test('설정 설명과 알림 이유 문구가 서로 다르다', () {
      // The settings row sits next to a switch. Reusing the notification's
      // "why you got this" line there made every *off* row claim the user had
      // turned it on.
      for (final category in NotificationCategory.values) {
        expect(category.descriptionKo, isNotEmpty, reason: category.name);
        expect(
          category.descriptionKo.contains('켜 두셨습니다'),
          isFalse,
          reason: '${category.name}: 설정 설명이 켜져 있다고 단정하면 안 됩니다',
        );
        expect(category.descriptionKo, isNot(category.reasonKo));
      }
    });

    test('모든 카테고리가 이유 문구를 가진다', () {
      for (final category in NotificationCategory.values) {
        expect(category.labelKo, isNotEmpty);
        expect(category.reasonKo, isNotEmpty);
      }
    });

    test('조용한 시간이 자정을 넘겨도 판정된다', () {
      const prefs = NotificationPreference(
        quietHoursStartMinute: 22 * 60,
        quietHoursEndMinute: 8 * 60,
      );
      expect(prefs.isWithinQuietHours(DateTime(2026, 8, 30, 23)), isTrue);
      expect(prefs.isWithinQuietHours(DateTime(2026, 8, 30, 3)), isTrue);
      expect(prefs.isWithinQuietHours(DateTime(2026, 8, 30, 12)), isFalse);
    });

    test('모드별 기본값이 다르다', () {
      expect(
        NotificationPreference.defaultsFor(AudienceMode.player),
        contains(NotificationCategory.myTeamGameDay),
      );
      expect(
        NotificationPreference.defaultsFor(AudienceMode.discover),
        contains(NotificationCategory.programEpisodeRecap),
      );
    });
  });

  group('알림 예약 계획', () {
    const planner = NotificationPlanner();
    final now = DateTime.utc(2026, 8, 30, 0);

    GameCard card({
      required String id,
      required DateTime start,
      GameStatus status = GameStatus.scheduled,
    }) {
      final provenance = Provenance(
        sourceName: 's',
        sourceUrl: 'https://example.org',
        fetchedAt: now,
      );
      Team team(String tid, String name) =>
          Team(id: tid, name: name, provenance: provenance);
      return GameCard(
        game: Game(
          id: id,
          status: status,
          startTimeUtc: start,
          homeTeamId: 'a',
          awayTeamId: 'b',
          provenance: provenance,
        ),
        homeTeam: team('a', '한강'),
        awayTeam: team('b', '남산'),
      );
    }

    test('켜 둔 리드타임만 예약한다', () {
      final planned = planner.plan(
        games: <GameCard>[
          card(id: 'g1', start: now.add(const Duration(days: 10))),
        ],
        preference: const NotificationPreference(
          enabled: <NotificationCategory>{NotificationCategory.myTeamGameDay},
        ),
        nowUtc: now,
      );
      expect(planned, hasLength(1));
      expect(planned.first.category, NotificationCategory.myTeamGameDay);
      expect(
        planned.first.scheduledForUtc,
        now.add(const Duration(days: 10)).subtract(const Duration(hours: 24)),
      );
    });

    test('연기·취소 경기에는 카운트다운 알림을 만들지 않는다', () {
      for (final status in <GameStatus>[
        GameStatus.postponed,
        GameStatus.cancelled,
      ]) {
        final planned = planner.plan(
          games: <GameCard>[
            card(
              id: 'g1',
              start: now.add(const Duration(days: 3)),
              status: status,
            ),
          ],
          preference: const NotificationPreference(
            enabled: <NotificationCategory>{
              NotificationCategory.myTeamGameDay,
              NotificationCategory.myTeamGameHour,
            },
          ),
          nowUtc: now,
        );
        expect(planned, isEmpty, reason: status.name);
      }
    });

    test('이미 지난 시점은 예약하지 않는다', () {
      final planned = planner.plan(
        games: <GameCard>[
          // 30 minutes away: the 24h and 7d alerts are already in the past.
          card(id: 'g1', start: now.add(const Duration(minutes: 30))),
        ],
        preference: const NotificationPreference(
          enabled: <NotificationCategory>{
            NotificationCategory.myTeamGameWeek,
            NotificationCategory.myTeamGameDay,
            NotificationCategory.myTeamGameHour,
          },
        ),
        nowUtc: now,
      );
      expect(planned, isEmpty);
    });

    test('조용한 시간에 걸리면 종료 후로 미루되 경기 시작을 넘기지 않는다', () {
      // Game at 2026-09-10 14:00 KST; the 24h alert lands at 14:00 KST the day
      // before, which is outside quiet hours, so it stays put.
      final start = Kst.fromKst(DateTime(2026, 9, 10, 14));
      final planned = planner.plan(
        games: <GameCard>[card(id: 'g1', start: start)],
        preference: const NotificationPreference(
          enabled: <NotificationCategory>{NotificationCategory.myTeamGameDay},
          quietHoursStartMinute: 22 * 60,
          quietHoursEndMinute: 8 * 60,
        ),
        nowUtc: now,
      );
      expect(planned, hasLength(1));
      final localHour = Kst.toKst(planned.first.scheduledForUtc).hour;
      expect(localHour, 14);
    });

    test('조용한 시간 안에 떨어지면 종료 시각으로 미룬다', () {
      // Game at 2026-09-10 06:00 KST -> 24h before is 06:00, inside 22:00-08:00.
      final start = Kst.fromKst(DateTime(2026, 9, 10, 6));
      final planned = planner.plan(
        games: <GameCard>[card(id: 'g1', start: start)],
        preference: const NotificationPreference(
          enabled: <NotificationCategory>{NotificationCategory.myTeamGameDay},
          quietHoursStartMinute: 22 * 60,
          quietHoursEndMinute: 8 * 60,
        ),
        nowUtc: now,
      );
      expect(planned, hasLength(1));
      expect(Kst.toKst(planned.first.scheduledForUtc).hour, 8);
    });

    test('알림 id는 결정적이라 재예약이 중복을 만들지 않는다', () {
      final first = NotificationPlanner.notificationId(
        NotificationCategory.myTeamGameDay,
        'game-1',
      );
      final second = NotificationPlanner.notificationId(
        NotificationCategory.myTeamGameDay,
        'game-1',
      );
      final other = NotificationPlanner.notificationId(
        NotificationCategory.myTeamGameHour,
        'game-1',
      );
      expect(first, second);
      expect(first, isNot(other));
      expect(first, greaterThanOrEqualTo(0));
    });

    test('일정이 바뀌면 basisTimeUtc가 달라져 재예약된다', () {
      final original = planner.plan(
        games: <GameCard>[
          card(id: 'g1', start: now.add(const Duration(days: 5))),
        ],
        preference: const NotificationPreference(
          enabled: <NotificationCategory>{NotificationCategory.myTeamGameDay},
        ),
        nowUtc: now,
      );
      final moved = planner.plan(
        games: <GameCard>[
          card(id: 'g1', start: now.add(const Duration(days: 6))),
        ],
        preference: const NotificationPreference(
          enabled: <NotificationCategory>{NotificationCategory.myTeamGameDay},
        ),
        nowUtc: now,
      );
      // Same OS id, different basis: reconcile() cancels and re-schedules.
      expect(moved.first.id, original.first.id);
      expect(moved.first.basisTimeUtc, isNot(original.first.basisTimeUtc));
    });

    test('알릴 것이 없으면 아무것도 만들지 않는다', () {
      expect(
        planner.plan(
          games: const <GameCard>[],
          preference: const NotificationPreference(
            enabled: <NotificationCategory>{NotificationCategory.myTeamGameDay},
          ),
          nowUtc: now,
        ),
        isEmpty,
      );
    });
  });

  group('서킷 브레이커', () {
    test('임계치까지는 열리지 않는다', () {
      var now = DateTime.utc(2026, 8, 30);
      final breaker = CircuitBreaker(
        name: 'test',
        failureThreshold: 3,
        clock: () => now,
      );
      breaker.recordFailure();
      breaker.recordFailure();
      expect(breaker.allowsRequest, isTrue);
      breaker.recordFailure();
      expect(breaker.allowsRequest, isFalse);
      expect(breaker.state, CircuitState.open);
    });

    test('성공하면 즉시 닫힌다', () {
      final breaker = CircuitBreaker(name: 'test', failureThreshold: 2);
      breaker.recordFailure();
      breaker.recordFailure();
      expect(breaker.allowsRequest, isFalse);
      breaker.recordSuccess();
      expect(breaker.allowsRequest, isTrue);
      expect(breaker.consecutiveFailures, 0);
    });

    test('reset 시간이 지나면 반열림 상태로 한 번 시도한다', () {
      var now = DateTime.utc(2026, 8, 30);
      final breaker = CircuitBreaker(
        name: 'test',
        failureThreshold: 1,
        resetTimeout: const Duration(minutes: 5),
        clock: () => now,
      );
      breaker.recordFailure();
      expect(breaker.state, CircuitState.open);

      now = now.add(const Duration(minutes: 6));
      expect(breaker.state, CircuitState.halfOpen);
      expect(breaker.allowsRequest, isTrue);
    });

    test('Retry-After를 존중해 그 전에는 열지 않는다', () {
      var now = DateTime.utc(2026, 8, 30);
      final breaker = CircuitBreaker(
        name: 'test',
        failureThreshold: 10,
        resetTimeout: const Duration(seconds: 1),
        clock: () => now,
      );
      breaker.recordFailure(retryAfter: const Duration(minutes: 30));
      expect(breaker.allowsRequest, isFalse);

      now = now.add(const Duration(minutes: 10));
      // Reset timeout has long passed, but the server said 30 minutes.
      expect(breaker.allowsRequest, isFalse);

      now = now.add(const Duration(minutes: 21));
      expect(breaker.allowsRequest, isTrue);
    });
  });

  group('백오프', () {
    test('지수적으로 증가하되 상한을 넘지 않는다', () {
      const policy = BackoffPolicy(
        initial: Duration(milliseconds: 100),
        max: Duration(seconds: 2),
      );
      // Full jitter, so assert the envelope rather than an exact value.
      for (var attempt = 1; attempt <= 8; attempt++) {
        final delay = policy.delayFor(attempt);
        expect(delay, lessThanOrEqualTo(const Duration(seconds: 2)));
        expect(delay, greaterThanOrEqualTo(Duration.zero));
      }
    });

    test('Retry-After가 있으면 그것을 쓴다', () {
      const policy = BackoffPolicy(max: Duration(seconds: 60));
      expect(
        policy.delayFor(1, retryAfter: const Duration(seconds: 12)),
        const Duration(seconds: 12),
      );
    });

    test('Retry-After도 상한을 넘지 않는다', () {
      const policy = BackoffPolicy(max: Duration(seconds: 10));
      expect(
        policy.delayFor(1, retryAfter: const Duration(hours: 1)),
        const Duration(seconds: 10),
      );
    });
  });

  group('인앱 브라우저 허용 목록', () {
    const allowed = <String>[
      'wbak.net',
      'kbsa.or.kr',
      'wbsc.org',
      'womensprobaseballleague.com',
    ];

    test('허용 도메인과 하위 도메인을 통과시킨다', () {
      expect(isAllowedInAppHost('https://www.wbak.net/home', allowed), isTrue);
      expect(isAllowedInAppHost('https://kbsa.or.kr/', allowed), isTrue);
      expect(
        isAllowedInAppHost(
          'https://stats.womensprobaseballleague.com/',
          allowed,
        ),
        isTrue,
      );
    });

    test('유사 도메인을 차단한다', () {
      // The classic suffix trick must not pass.
      expect(
        isAllowedInAppHost('https://wbak.net.evil.com/', allowed),
        isFalse,
      );
      expect(isAllowedInAppHost('https://notwbak.net/', allowed), isFalse);
      expect(isAllowedInAppHost('https://evil.com/wbak.net', allowed), isFalse);
    });

    test('http(s)가 아닌 스킴을 차단한다', () {
      expect(isAllowedInAppHost('javascript:alert(1)', allowed), isFalse);
      expect(isAllowedInAppHost('file:///etc/passwd', allowed), isFalse);
      expect(isAllowedInAppHost('intent://foo', allowed), isFalse);
      expect(isAllowedInAppHost('data:text/html,<h1>x', allowed), isFalse);
    });

    test('차단 사유를 사람이 읽을 수 있게 설명한다', () {
      expect(
        describeBlockedScheme('javascript:alert(1)'),
        contains('javascript'),
      );
      expect(describeBlockedScheme('https://www.wbak.net/'), isEmpty);
    });
  });

  group('관람 정보 기본값', () {
    test('확인되지 않은 경기는 무료 개방으로 추정하지 않는다', () {
      expect(AttendanceStatus.parse(null), AttendanceStatus.needsConfirmation);
      expect(AttendanceStatus.needsConfirmation.labelKo, '관람 가능 여부 확인 필요');
      final info = AttendanceInfo(
        gameId: 'g',
        status: AttendanceStatus.parse(null),
        provenance: Provenance(
          sourceName: 's',
          sourceUrl: 'https://example.org',
          fetchedAt: DateTime.utc(2026),
        ),
      );
      expect(info.isConfirmed, isFalse);
      expect(info.hasAdmissionInfo, isFalse);
      // Family suitability is never inferred either.
      expect(info.familyFriendlyConfirmed, isFalse);
    });
  });

  group('화제 콘텐츠 우선순위', () {
    Provenance p() => Provenance(
      sourceName: 's',
      sourceUrl: 'https://example.org',
      fetchedAt: DateTime.utc(2026),
    );

    FeaturedTopic topic(
      String id,
      FeaturedTopicKind kind, {
      int? priority,
      DateTime? until,
    }) => FeaturedTopic(
      id: id,
      kind: kind,
      title: id,
      priority: priority,
      activeUntil: until,
      meta: ContentMeta(provenance: p(), publishedAt: DateTime.utc(2026)),
    );

    test('방송이 끝나면 비활성이 되어 다음 주제가 올라온다', () {
      final now = DateTime.utc(2026, 12, 1);
      final ended = topic(
        'broadcast',
        FeaturedTopicKind.broadcast,
        until: DateTime.utc(2026, 11, 1),
      );
      final international = topic('intl', FeaturedTopicKind.international);

      expect(ended.isActiveAt(now), isFalse);
      expect(international.isActiveAt(now), isTrue);
    });

    test('기본 우선순위는 방송 → 국제 → 국내 → 이야기 → 근처 → 입문 순이다', () {
      final order = FeaturedTopicKind.values.toList()
        ..sort((a, b) => a.defaultPriority.compareTo(b.defaultPriority));
      expect(order, <FeaturedTopicKind>[
        FeaturedTopicKind.broadcast,
        FeaturedTopicKind.international,
        FeaturedTopicKind.domesticCompetition,
        FeaturedTopicKind.story,
        FeaturedTopicKind.nearbyGames,
        FeaturedTopicKind.gettingStarted,
      ]);
    });

    test('명시적 priority가 기본값을 이긴다', () {
      // A getting-started topic normally sorts last; an explicit priority
      // promotes it above a broadcast that is using its default.
      final guide = topic(
        'guide',
        FeaturedTopicKind.gettingStarted,
        priority: -1,
      );
      final broadcast = topic('b', FeaturedTopicKind.broadcast);
      expect(
        broadcast.effectivePriority,
        FeaturedTopicKind.broadcast.defaultPriority,
      );
      expect(guide.effectivePriority, lessThan(broadcast.effectivePriority));
    });
  });

  group('요약 방식 표시', () {
    Provenance p() => Provenance(
      sourceName: 's',
      sourceUrl: 'https://example.org',
      fetchedAt: DateTime.utc(2026),
    );

    test('AI 요약은 배지를 강제한다', () {
      expect(SummaryMethod.aiAssisted.requiresBadge, isTrue);
      expect(SummaryMethod.manual.requiresBadge, isFalse);
    });

    test('검수 전 자동 요약은 게시 가능 상태가 아니다', () {
      final pending = ContentMeta(
        provenance: p(),
        publishedAt: DateTime.utc(2026),
        summaryMethod: SummaryMethod.aiAssisted,
        reviewStatus: ReviewStatus.pending,
      );
      expect(pending.isPublishable, isFalse);
    });

    test('사실을 만들 수 없는 템플릿 요약은 검수 없이도 게시 가능하다', () {
      final template = ContentMeta(
        provenance: p(),
        publishedAt: DateTime.utc(2026),
        summaryMethod: SummaryMethod.template,
        reviewStatus: ReviewStatus.pending,
      );
      expect(template.isPublishable, isTrue);
    });
  });
}
