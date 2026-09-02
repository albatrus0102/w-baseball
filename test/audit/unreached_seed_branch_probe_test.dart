import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/app/router.dart';
import 'package:w_baseball/core/design_system/theme.dart';
import 'package:w_baseball/features/competitions/competition_screen.dart';
import 'package:w_baseball/features/games/game_detail_screen.dart';
import 'package:w_baseball/features/teams/team_detail_screen.dart';

import '../widget/harness.dart';

/// Investigation evidence from the 2026-09-02 "unreached seed branch" audit,
/// NOT a permanent regression test -- it is not meant to run in
/// `tools/commit_gate.py` or CI, and asserts on injected data that does not
/// exist in the real seed.
///
/// Seed data never populates several optional fields (see
/// `Game.officialDetailUrl`, and empty `content/news.json` /
/// `content/videos.json`), so the branches gated on them have never once been
/// rendered by any test. This file injects those fields into a copy of the
/// real seed (via `buildTestApp(documents: ...)`) to actually render the
/// gated branches and see what happens, rather than guessing from reading the
/// widget code. Kept (rather than deleted after the one run that produced the
/// numbers in the audit report) so the numbers can be reproduced independently
/// instead of taken on faith. Whoever triages the audit findings should decide
/// whether to keep, delete, or fold pieces of this into real regression tests.
void main() {
  Future<TestApp> pumpWithDocuments(
    WidgetTester tester,
    Map<String, String> documents, {
    TestPhone phone = TestPhone.regular,
  }) async {
    final merged = Map<String, String>.of(loadSeedFromDisk())
      ..addAll(documents);
    final app = await buildTestApp(documents: merged);
    addTearDown(app.dispose);

    // `flutter test`'s default surface is a wide 800x600 desktop-like canvas,
    // which is not what shipped the original bug -- match a real phone width,
    // same as `pumpScreen` in harness.dart, so a squeeze that only appears at
    // phone width actually appears here too.
    tester.view.physicalSize = phone.size * tester.view.devicePixelRatio;
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = phone.size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: app.container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: ref.watch(routerProvider),
            theme: WbTheme.light(),
            locale: const Locale('ko', 'KR'),
            supportedLocales: const <Locale>[Locale('ko', 'KR')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, widget) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(phone.textScale)),
              child: widget ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return app;
  }

  const gameId = 'game-demo-20260831-01';

  Map<String, dynamic> loadGamesJson() {
    final raw = loadSeedFromDisk()['games/2026-08.json']!;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  testWidgets('① officialDetailUrl 채우면 빠른 동작 4버튼 Row가 기본 배율(1.0)에서 어떻게 되는가', (
    tester,
  ) async {
    final gamesJson = loadGamesJson();
    final items = gamesJson['items'] as List<dynamic>;
    final target = items.firstWhere((e) => (e as Map)['id'] == gameId) as Map;
    target['officialDetailUrl'] = 'https://example.org/box-score';

    final app = await pumpWithDocuments(tester, {
      'games/2026-08.json': jsonEncode(gamesJson),
    }, phone: TestPhone.small);
    app.container.read(routerProvider).go('/games/$gameId');
    await settle(tester);

    expect(find.byType(GameDetailScreen), findsOneWidget);

    // Check the quick-actions row *before* scrolling -- it sits right below
    // the hero card, near the top, so it is already built on first pump.
    // `SliverToBoxAdapter` children this far from the viewport get disposed
    // once scrolled past, so checking after `scrollToEnd` would find
    // nothing and give a false "not rendered" reading.
    final labelFinder = find.text('공식 기록');
    expect(
      labelFinder,
      findsOneWidget,
      reason: '공식 기록 버튼 자체가 렌더링됐어야 한다 (officialDetailUrl != null 분기)',
    );
    final size = tester.getSize(labelFinder);
    // ignore: avoid_print
    print(
      '[PROBE ①] 공식 기록 라벨 렌더 크기 = ${size.width} x ${size.height} '
      '(기본 텍스트 배율 1.0, regular phone)',
    );
    // Buttons row also contains 캘린더/알림/길찾기 -- capture their sizes too.
    for (final label in ['캘린더', '알림', '길찾기']) {
      final f = find.text(label);
      final n = f.evaluate().length;
      if (n == 1) {
        final s = tester.getSize(f);
        // ignore: avoid_print
        print('[PROBE ①] "$label" 라벨 렌더 크기 = ${s.width} x ${s.height}');
      } else {
        // ignore: avoid_print
        print('[PROBE ①] "$label" 매치 $n건 (중복이라 크기 생략)');
      }
    }

    await scrollToEnd(tester);
    expectNoOverflow(tester);
  });

  testWidgets('①b 위와 동일하되 130% 텍스트 배율 (find_squeezed_rows.py가 실제로 경고하는 조건)', (
    tester,
  ) async {
    final gamesJson = loadGamesJson();
    final items = gamesJson['items'] as List<dynamic>;
    final target = items.firstWhere((e) => (e as Map)['id'] == gameId) as Map;
    target['officialDetailUrl'] = 'https://example.org/box-score';

    final app = await pumpWithDocuments(tester, {
      'games/2026-08.json': jsonEncode(gamesJson),
    }, phone: TestPhone.largeText);
    app.container.read(routerProvider).go('/games/$gameId');
    await settle(tester);

    expect(find.byType(GameDetailScreen), findsOneWidget);

    final labelFinder = find.text('공식 기록');
    final n = labelFinder.evaluate().length;
    // ignore: avoid_print
    print('[PROBE ①b] "공식 기록" 매치 수 = $n (textScale=1.3, small phone)');
    if (n == 1) {
      final size = tester.getSize(labelFinder);
      // ignore: avoid_print
      print('[PROBE ①b] 공식 기록 라벨 렌더 크기 = ${size.width} x ${size.height}');
    }
    for (final label in ['캘린더', '알림', '길찾기']) {
      final f = find.text(label);
      final m = f.evaluate().length;
      if (m == 1) {
        final s = tester.getSize(f);
        // ignore: avoid_print
        print('[PROBE ①b] "$label" 라벨 렌더 크기 = ${s.width} x ${s.height}');
      } else {
        // ignore: avoid_print
        print('[PROBE ①b] "$label" 매치 $m건');
      }
    }

    final exception = tester.takeException();
    // ignore: avoid_print
    print('[PROBE ①b] takeException() = $exception');
  });

  testWidgets('①c 극단값: 폭 320, 텍스트 배율 2.0 (Android 접근성 최대)', (tester) async {
    final gamesJson = loadGamesJson();
    final items = gamesJson['items'] as List<dynamic>;
    final target = items.firstWhere((e) => (e as Map)['id'] == gameId) as Map;
    target['officialDetailUrl'] = 'https://example.org/box-score';

    const extreme = TestPhone('extreme_320', Size(320, 700), textScale: 2.0);
    final app = await pumpWithDocuments(tester, {
      'games/2026-08.json': jsonEncode(gamesJson),
    }, phone: extreme);
    app.container.read(routerProvider).go('/games/$gameId');
    await settle(tester);

    expect(find.byType(GameDetailScreen), findsOneWidget);

    final labelFinder = find.text('공식 기록');
    final n = labelFinder.evaluate().length;
    // ignore: avoid_print
    print('[PROBE ①c] "공식 기록" 매치 수 = $n (width=320, textScale=2.0)');
    if (n == 1) {
      final size = tester.getSize(labelFinder);
      // ignore: avoid_print
      print('[PROBE ①c] 공식 기록 라벨 렌더 크기 = ${size.width} x ${size.height}');
    }
    final exception = tester.takeException();
    // ignore: avoid_print
    print('[PROBE ①c] takeException() = $exception');
  });

  testWidgets('② news/videos 항목을 채우면 _RelatedSection이 어떻게 렌더되는가', (
    tester,
  ) async {
    final newsJson = <String, dynamic>{
      'schemaVersion': 1,
      'dataVersion': '2026.08.30',
      'generatedAt': '2026-08-30T00:00:00Z',
      'payloadKind': 'snapshot',
      'hasMore': false,
      'items': [
        {
          'id': 'article-probe-1',
          'title':
              '이것은 아주 길고 긴 기사 제목입니다 한강 리버베어스가 오늘 경기에서 보여준 활약을 다루는 매우 상세한 제목',
          'url': 'https://news.example.org/article-probe-1',
          'publishedAt': '2026-08-30T00:00:00Z',
          'outlet': null,
          'teamIds': ['team-demo-hangang'],
          'source': {
            'sourceName': 'news-aggregate',
            'sourceUrl': 'https://news.example.org/article-probe-1',
            'fetchedAt': '2026-08-30T00:00:00Z',
            'qualityStatus': 'autoVerified',
            'licenseStatus': 'linkOnly',
            'visibility': 'public',
            'isDemo': false,
          },
        },
      ],
    };
    final videosJson = <String, dynamic>{
      'schemaVersion': 1,
      'dataVersion': '2026.08.30',
      'generatedAt': '2026-08-30T00:00:00Z',
      'payloadKind': 'snapshot',
      'hasMore': false,
      'items': [
        {
          'id': 'video-probe-1',
          'title': '이것도 아주 길고 긴 영상 제목입니다 한강 리버베어스 하이라이트 모음 풀버전 다시보기 영상 제목 테스트',
          'url': 'https://video.example.org/video-probe-1',
          'publishedAt': '2026-08-30T00:00:00Z',
          'channelName': null,
          'teamIds': ['team-demo-hangang'],
          'source': {
            'sourceName': 'youtube',
            'sourceUrl': 'https://video.example.org/video-probe-1',
            'fetchedAt': '2026-08-30T00:00:00Z',
            'qualityStatus': 'autoVerified',
            'licenseStatus': 'linkOnly',
            'visibility': 'public',
            'isDemo': false,
          },
        },
      ],
    };

    final app = await pumpWithDocuments(tester, {
      'content/news.json': jsonEncode(newsJson),
      'content/videos.json': jsonEncode(videosJson),
    });
    app.container.read(routerProvider).go('/games/$gameId');
    await settle(tester);

    expect(find.byType(GameDetailScreen), findsOneWidget);
    await scrollToEnd(tester);
    expectNoOverflow(tester);

    expect(find.text('관련 소식'), findsOneWidget, reason: '_RelatedSection 헤더');
    expect(
      find.textContaining('뉴스'),
      findsWidgets,
      reason: 'outlet == null 폴백 라벨',
    );
    expect(
      find.textContaining('영상'),
      findsWidgets,
      reason: 'channelName == null 폴백 라벨',
    );
    // ignore: avoid_print
    print('[PROBE ②] _RelatedSection 렌더 성공, overflow 없음');
  });

  testWidgets('③ team.officialUrl/contactUrl 채우면 팀 상세 문의 Wrap이 어떻게 되는가', (
    tester,
  ) async {
    final teamsRaw = loadSeedFromDisk()['teams.json']!;
    final teamsJson = jsonDecode(teamsRaw) as Map<String, dynamic>;
    final items = teamsJson['items'] as List<dynamic>;
    final target =
        items.firstWhere((e) => (e as Map)['id'] == 'team-demo-hangang') as Map;
    target['officialUrl'] = 'https://example.org/hangang-official';
    target['contactUrl'] = 'https://example.org/hangang-contact';

    // Extra-tall viewport (not just `largeText`'s 360x640): `_JoinSection`
    // sits mid-page above `_CorrectionFooter`, and `CustomScrollView`
    // disposes slivers once scrolled well past them -- scrolling to the end
    // to force-build it would just unmount it again. A tall-enough canvas
    // means everything fits without scrolling, so nothing gets disposed.
    const tall = TestPhone(
      'tall_360x4000_text130',
      Size(360, 4000),
      textScale: 1.3,
    );
    final app = await pumpWithDocuments(tester, {
      'teams.json': jsonEncode(teamsJson),
    }, phone: tall);
    app.container.read(routerProvider).go('/team/team-demo-hangang');
    await settle(tester);

    expect(find.byType(TeamDetailScreen), findsOneWidget);
    expectNoOverflow(tester);

    expect(
      find.text('공식 채널'),
      findsOneWidget,
      reason: 'officialUrl != null 분기',
    );
    expect(find.text('가입 문의'), findsOneWidget, reason: 'contactUrl != null 분기');
    // ignore: avoid_print
    print('[PROBE ③] 공식 채널 + 가입 문의 버튼 렌더 성공, overflow 없음 (Wrap 레이아웃)');
  });

  testWidgets(
    '④ stage.groupLabel + 긴 이름 채우면 단계 Row(Expanded(Text)+Text)가 어떻게 되는가',
    (tester) async {
      final compRaw = loadSeedFromDisk()['competitions/2026.json']!;
      final compJson = jsonDecode(compRaw) as Map<String, dynamic>;
      final items = compJson['items'] as List<dynamic>;
      final demo = items.firstWhere(
        (e) => (e as Map)['id'] == 'comp-demo-league',
      ) as Map;
      final seasons = demo['seasons'] as List<dynamic>;
      final season = seasons.firstWhere(
        (e) => (e as Map)['id'] == 'season-demo-league-2026',
      ) as Map;
      final stages = season['stages'] as List<dynamic>;
      final stage = stages.first as Map;
      stage['name'] = '2026 데모 여자야구 리그 정규 시즌 전반기 정규 리그 예선 라운드 (연장전 포함)';
      stage['groupLabel'] = 'A조 · 수도권 예선 그룹 편성';

      const tall = TestPhone(
        'tall_360x4000_text130',
        Size(360, 4000),
        textScale: 1.3,
      );
      final app = await pumpWithDocuments(tester, {
        'competitions/2026.json': jsonEncode(compJson),
      }, phone: tall);
      app.container
          .read(routerProvider)
          .go('/competition/season-demo-league-2026');
      await settle(tester);

      expect(find.byType(CompetitionScreen), findsOneWidget);

      final exception = tester.takeException();
      // ignore: avoid_print
      print('[PROBE ④] takeException() = $exception');

      final f = find.textContaining('A조');
      final n = f.evaluate().length;
      // ignore: avoid_print
      print('[PROBE ④] "A조..." 텍스트 매치 수 = $n');
      if (n == 1) {
        final s = tester.getSize(f);
        // ignore: avoid_print
        print('[PROBE ④] 단계 이름 Row 렌더 크기 = ${s.width} x ${s.height}');
      }
    },
  );
}
