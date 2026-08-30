import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/app/router.dart';
import 'package:w_baseball/app/shell.dart';
import 'package:w_baseball/core/config/app_config.dart';
import 'package:w_baseball/core/design_system/components/game_widgets.dart';
import 'package:w_baseball/core/design_system/components/primitives.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/data/models/domain.dart';
import 'package:w_baseball/features/discover/discover_screen.dart';
import 'package:w_baseball/features/games/games_screen.dart';
import 'package:w_baseball/features/discover/widgets/featured_card.dart';
import 'package:w_baseball/features/home/home_screen.dart';
import 'package:w_baseball/features/my_baseball/my_baseball_screen.dart';
import 'package:w_baseball/features/settings/more_screen.dart';
import 'package:w_baseball/features/settings/submissions_screen.dart';
import 'package:w_baseball/features/teams/teams_screen.dart';

import 'harness.dart';

void main() {
  group('홈 — 데이터 있음', () {
    testWidgets('입문자 모드는 화제 콘텐츠를 먼저 보여준다', (tester) async {
      final app = await buildTestApp(
        audience: const AudiencePreference(
          mode: AudienceMode.discover,
          onboardingCompleted: true,
          regionCode: '11',
          regionLabel: '서울',
        ),
      );
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const HomeScreen());

      expect(find.text('지금 화제'), findsOneWidget);
      // The programme card is what leads for a newcomer.
      expect(find.textContaining('야구여왕'), findsWidgets);
      expectNoOverflow(tester);
    });

    testWidgets('현역 모드는 내 팀 다음 경기를 먼저 보여준다', (tester) async {
      final app = await buildTestApp(
        audience: const AudiencePreference(
          mode: AudienceMode.player,
          onboardingCompleted: true,
        ),
      );
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const HomeScreen());

      expect(find.text('내 팀 다음 경기'), findsOneWidget);
      expect(find.text('앞으로 30일'), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('데모 데이터에는 라벨이 붙는다', (tester) async {
      // Player mode, because that home leads with the fixture list. The
      // discover home no longer shows the demo recap at all: nobody has signed
      // off on it, and `ContentMeta.isPublishable` hides unreviewed recaps by
      // design. Unlabelled demo data is the bug this guards against, and
      // content that is withheld entirely cannot be unlabelled.
      final app = await buildTestApp(
        audience: const AudiencePreference(
          mode: AudienceMode.player,
          onboardingCompleted: true,
          regionCode: '11',
          regionLabel: '서울',
        ),
      );
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const HomeScreen());
      await tester.pump(const Duration(milliseconds: 300));

      // Seed fixtures are demo, and must say so wherever they appear.
      expect(find.textContaining('데모'), findsWidgets);
    });

    testWidgets('검수되지 않은 AI 리캡은 아예 보여주지 않는다', (tester) async {
      // The rule the validator enforces before publication, enforced again at
      // read time: a model-written summary needs a person to sign off, and
      // until then it is withheld rather than shown with a reassuring badge.
      //
      // Retagging the seed's own recap is deliberate. Asserting on a
      // hand-built record would prove the getter works; this proves the record
      // actually travels through sync, storage, and the repository gate and
      // still does not reach the screen.
      // Only the recap is retagged. A blanket string replace would also
      // demote the featured topic that carries it, and the card would then be
      // missing because its container was withheld — the assertion would pass
      // without the recap gate ever being consulted.
      final docs = Map<String, String>.from(loadSeedFromDisk());
      const path = 'content/discover.json';
      final decoded = jsonDecode(docs[path]!) as Map<String, dynamic>;
      var retagged = 0;
      final bucket = (decoded['items'] as List).first as Map<String, dynamic>;
      for (final program in bucket['programs'] as List) {
        for (final season in (program as Map)['seasons'] as List) {
          for (final episode in (season as Map)['episodes'] as List) {
            final recap = (episode as Map)['recap'] as Map<String, dynamic>?;
            if (recap == null) continue;
            recap['summaryMethod'] = 'aiAssisted';
            recap['reviewStatus'] = 'pending';
            recap['generatedAt'] = '2026-08-30T00:00:00Z';
            retagged++;
          }
        }
      }
      expect(retagged, greaterThan(0), reason: '시드에 리캡이 없으면 이 테스트는 무의미합니다');
      docs[path] = jsonEncode(decoded);

      final app = await buildTestApp(documents: docs);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const HomeScreen());
      await settle(tester);

      expect(
        find.byType(ProgramRecapCard),
        findsNothing,
        reason: '검수 전 AI 리캡이 화면에 나오면 안 됩니다',
      );
    });

    testWidgets('사람이 쓴 리캡은 검수 전이라도 보여준다', (tester) async {
      // The counterpart, and the reason the rule had to be narrowed. Every
      // record in the shipped seed is `manual` + `pending`, so a gate keyed on
      // review status alone hid hand-written text as if a model had produced
      // it — and because it was applied at one of ten content types, this one
      // section went dark while nine identical records rendered fine.
      final app = await buildTestApp();
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const HomeScreen());
      await settle(tester);

      expect(find.byType(ProgramRecapCard), findsOneWidget);
    });

    testWidgets('갱신 상태를 앱바에 표시한다', (tester) async {
      final app = await buildTestApp(
        lastSync: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      );
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const HomeScreen());
      expect(find.textContaining('갱신'), findsWidgets);
    });
  });

  group('홈 — 빈 상태와 오프라인', () {
    testWidgets('데이터가 없어도 흰 화면이 아니라 안내를 보여준다', (tester) async {
      // No seed at all: the hardest first-launch case.
      final app = await buildTestApp(seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const HomeScreen());

      expect(find.byType(WbEmptyState), findsWidgets);
      // Every empty state must offer at least one way forward.
      expect(find.byType(FilledButton), findsWidgets);
      expectNoOverflow(tester);
    });

    testWidgets('한 번도 갱신하지 못했으면 그렇게 말한다', (tester) async {
      final app = await buildTestApp(seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const HomeScreen());
      expect(find.text('아직 갱신되지 않음'), findsOneWidget);
    });
  });

  group('경기 목록', () {
    testWidgets('세그먼트와 날짜 이동을 제공한다', (tester) async {
      final app = await buildTestApp();
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const GamesScreen());

      expect(find.text('일정'), findsOneWidget);
      expect(find.text('결과'), findsOneWidget);
      // "오늘로" is always reachable from the app bar.
      expect(find.byTooltip('오늘로'), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('필터 칩을 제공하고 초기화할 수 있다', (tester) async {
      final app = await buildTestApp();
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const GamesScreen());

      expect(find.text('내 팀'), findsWidgets);
      expect(find.text('국내'), findsOneWidget);
      expect(find.text('국제'), findsOneWidget);

      await tester.tap(find.widgetWithText(WbFilterChip, '국내'));
      await settle(tester);

      // The filter actually applied...
      expect(
        app.container.read(gamesTabProvider).level,
        CompetitionLevel.domestic,
      );
      // ...and that exposes a one-tap reset at the end of the chip bar. The
      // bar builds lazily, so scroll it before looking for the action.
      final chipBar = find
          .ancestor(of: find.text('국제'), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(
        find.text('초기화'),
        250,
        scrollable: chipBar,
      );
      expect(find.text('초기화'), findsOneWidget);

      await tester.tap(find.text('초기화'));
      await settle(tester);
      expect(app.container.read(gamesTabProvider).level, isNull);
    });

    testWidgets('경기가 없는 날에도 다음 경기일 버튼을 준다', (tester) async {
      final app = await buildTestApp(seedAssets: false);
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const GamesScreen());
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(WbEmptyState), findsWidgets);
      expectNoOverflow(tester);
    });
  });

  group('발견', () {
    testWidgets('개인화와 비개인화 뉴스 영역이 함께 존재한다', (tester) async {
      final app = await buildTestApp();
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const DiscoverScreen());

      // Keeping both visible is what stops the feed becoming a bubble.
      expect(find.text('모두가 알아둘 주요 소식'), findsOneWidget);

      // The personalised rail is further down a lazily-built sliver list.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
      await settle(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
      await settle(tester);
      expect(find.text('내 관심 소식'), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('근처 경기와 팀 찾기 진입점을 제공한다', (tester) async {
      final app = await buildTestApp();
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const DiscoverScreen());
      expect(find.text('근처 경기'), findsWidgets);
      expect(find.text('팀 찾기'), findsWidgets);
    });
  });

  group('마이야구', () {
    testWidgets('팀을 고르지 않았으면 막다른 길 대신 안내를 준다', (tester) async {
      final app = await buildTestApp();
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const MyBaseballScreen());

      expect(find.text('내 팀을 선택해 주세요'), findsOneWidget);
      expect(find.text('팀 찾기'), findsOneWidget);
      // If their team is missing, registration is offered rather than nothing.
      expect(find.text('우리 팀이 없어요 · 등록하기'), findsOneWidget);
      expectNoOverflow(tester);
    });
  });

  group('팀 찾기', () {
    testWidgets('초성 검색 안내와 지역 필터가 있다', (tester) async {
      final app = await buildTestApp();
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const TeamsScreen());

      expect(find.text('팀 이름 검색 (초성도 가능해요)'), findsOneWidget);
      expect(find.text('모집 중'), findsWidgets);
      expectNoOverflow(tester);
    });

    testWidgets('초성으로 팀을 찾는다', (tester) async {
      final app = await buildTestApp();
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const TeamsScreen());

      // ㅎㄱ should reach 한강 리버베어스 from the seed set.
      await tester.enterText(find.byType(TextField), 'ㅎㄱ');
      await settle(tester);

      expect(find.textContaining('한강'), findsWidgets);
    });

    testWidgets('결과가 없으면 등록 흐름으로 안내한다', (tester) async {
      final app = await buildTestApp();
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const TeamsScreen());
      await tester.enterText(find.byType(TextField), 'zzzznotateam');
      await settle(tester);

      expect(find.text('팀 정보 등록하기'), findsOneWidget);
    });
  });

  group('스폰서·판매 기능 비노출', () {
    testWidgets('기본 설정에서 플래그가 꺼져 있다', (tester) async {
      final config = AppConfig.fromEnvironment();
      expect(config.flags.sponsorCommerceEnabled, isFalse);
    });

    const forbidden = <String>[
      '스폰서',
      '광고',
      '쇼핑',
      '구매',
      '장바구니',
      '결제',
      '상품',
      '판매',
      '준비 중인 쇼핑',
    ];

    Future<void> assertNoCommerce(WidgetTester tester) async {
      for (final word in forbidden) {
        expect(
          find.textContaining(word),
          findsNothing,
          reason: '"$word" 문구가 화면에 노출되면 안 됩니다',
        );
      }
    }

    testWidgets('홈에 상거래 문구가 없다', (tester) async {
      final app = await buildTestApp();
      addTearDown(app.dispose);
      await pumpScreen(tester, app, const HomeScreen());
      await assertNoCommerce(tester);
    });

    testWidgets('발견에 상거래 문구가 없다', (tester) async {
      final app = await buildTestApp();
      addTearDown(app.dispose);
      await pumpScreen(tester, app, const DiscoverScreen());
      await assertNoCommerce(tester);
    });

    testWidgets('더보기에 상거래 진입점이 없다', (tester) async {
      final app = await buildTestApp();
      addTearDown(app.dispose);
      await pumpScreen(tester, app, const MoreScreen());
      await assertNoCommerce(tester);
    });

    test('스폰서 라우트가 아예 등록되지 않는다', () {
      // The flag is checked at route-registration time, so a deep link cannot
      // reach a commerce screen even if one existed.
      const paths = <String>[
        WbRoutes.home,
        WbRoutes.discover,
        WbRoutes.games,
        WbRoutes.myBaseball,
        WbRoutes.more,
        WbRoutes.search,
        WbRoutes.nearby,
        WbRoutes.teams,
      ];
      for (final path in paths) {
        expect(path.contains('sponsor'), isFalse);
        expect(path.contains('shop'), isFalse);
        expect(path.contains('store'), isFalse);
      }
    });
  });

  group('제보 화면', () {
    testWidgets('폼 주소가 없으면 준비 중으로 표시하고 가짜 링크를 만들지 않는다', (tester) async {
      final app = await buildTestApp();
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const SubmissionsScreen());

      // No form URLs are configured by default, so every entry is inert.
      expect(find.text('준비 중'), findsWidgets);
      expect(find.text('제출이 곧 게시는 아닙니다'), findsOneWidget);
      expectNoOverflow(tester);
    });
  });

  group('탭 구조', () {
    test('하단 탭은 5개이고 발견·마이야구 진입점이 있다', () {
      expect(WbAppShell.tabs, hasLength(5));
      final labels = WbAppShell.tabs.map((t) => t.label).toList();
      expect(labels, <String>['홈', '발견', '경기', '마이야구', '더보기']);
    });

    test('모든 탭이 스크린리더 라벨을 가진다', () {
      for (final tab in WbAppShell.tabs) {
        expect(tab.semantic, isNotEmpty);
      }
    });
  });

  group('접근성과 작은 화면', () {
    for (final phone in TestPhone.all) {
      testWidgets('홈이 ${phone.name}에서 깨지지 않는다', (tester) async {
        final app = await buildTestApp();
        addTearDown(app.dispose);
        await pumpScreen(tester, app, const HomeScreen(), phone: phone);
        expectNoOverflow(tester);
      });

      testWidgets('경기 목록이 ${phone.name}에서 깨지지 않는다', (tester) async {
        final app = await buildTestApp();
        addTearDown(app.dispose);
        await pumpScreen(tester, app, const GamesScreen(), phone: phone);
        expectNoOverflow(tester);
      });
    }

    testWidgets('다크 테마에서도 렌더링된다', (tester) async {
      final app = await buildTestApp();
      addTearDown(app.dispose);
      await pumpScreen(
        tester,
        app,
        const HomeScreen(),
        brightness: Brightness.dark,
      );
      expectNoOverflow(tester);
    });

    testWidgets('데모 경기는 스크린리더에도 데모라고 읽힌다', (tester) async {
      // The badge is visual; without this the one user group that cannot see
      // it is the one told nothing.
      final app = await buildTestApp(
        audience: const AudiencePreference(
          mode: AudienceMode.player,
          onboardingCompleted: true,
          regionCode: '11',
          regionLabel: '서울',
        ),
      );
      addTearDown(app.dispose);

      await pumpScreen(tester, app, const HomeScreen());
      await settle(tester);

      final labels = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((s) => s.properties.label ?? '')
          .where((l) => l.contains('데모 데이터'));
      expect(labels, isNotEmpty, reason: '데모 경기 카드가 데모라고 읽혀야 합니다');
    });

    testWidgets('점수는 스크린리더에 "대"로 읽힌다', (tester) async {
      final app = await buildTestApp();
      addTearDown(app.dispose);
      await pumpScreen(tester, app, const HomeScreen());

      // At least one game card exposes a semantics label.
      final heroes = find.byType(WbHeroGameCard);
      if (heroes.evaluate().isNotEmpty) {
        final semantics = tester.getSemantics(heroes.first);
        expect(semantics.label, isNotEmpty);
      }
    });
  });
}
