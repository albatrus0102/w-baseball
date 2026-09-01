import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/app/app.dart';
import 'package:w_baseball/app/router.dart';
import 'package:w_baseball/core/design_system/components/standings_widgets.dart';
import 'package:w_baseball/core/design_system/theme.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/features/games/games_screen.dart';
import 'package:w_baseball/features/my_baseball/my_baseball_screen.dart';

import 'harness.dart';

/// Covers the 경기 탭's `순위` section: the owner's own complaint was that
/// standings were unreachable ("팀순위 개인순위가 어디있는거야?"), so these tests
/// exist to keep the entry point itself from regressing — not just the table
/// underneath it.
void main() {
  Future<TestApp> pumpApp(
    WidgetTester tester, {
    required AudiencePreference audience,
    bool seedAssets = true,
    double textScale = 1.0,
  }) async {
    final app = await buildTestApp(audience: audience, seedAssets: seedAssets);
    addTearDown(app.dispose);

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
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: WbDensityHost(
                child: WbFreshnessHost(
                  child: widget ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return app;
  }

  // No team followed — the owner's actual state when they went looking for
  // standings and could not find them.
  const noTeamFollowed = AudiencePreference(
    mode: AudienceMode.discover,
    onboardingCompleted: true,
    regionCode: '11',
    regionLabel: '서울',
  );

  /// Index of the 경기 destination in the bottom `NavigationBar` — used to
  /// prove a tap never silently switches tabs.
  int selectedTabIndex(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  group('경기 탭의 순위 세그먼트', () {
    testWidgets('일정·결과와 나란히, 언제나 나타난다', (tester) async {
      await pumpApp(tester, audience: noTeamFollowed);

      await tester.tap(find.text('경기'));
      await settle(tester);

      expect(find.text('일정'), findsOneWidget);
      expect(find.text('결과'), findsOneWidget);
      expect(find.text('순위'), findsOneWidget);
    });

    testWidgets('팔로우한 팀이 없어도 나타나고, 전체 팀을 보여준다', (tester) async {
      await pumpApp(tester, audience: noTeamFollowed);

      await tester.tap(find.text('경기'));
      await settle(tester);
      await tester.tap(find.text('순위'));
      await settle(tester);

      // 리그 순위 is the default nested view.
      expect(find.text('리그 순위'), findsOneWidget);
      expect(find.text('개인 순위'), findsOneWidget);

      final table = tester.widget<WbStandingsTable>(
        find.byType(WbStandingsTable),
      );
      // Every team in the demo season, not one row for "my team" — nothing
      // here should have filtered by a followed team, because there is none.
      expect(
        table.standings.length,
        greaterThanOrEqualTo(4),
        reason: '데모 시즌의 팀 전체가 나와야 합니다 (팔로우한 팀 없음)',
      );
    });

    testWidgets('날짜 스트립·필터바·오늘로는 순위에서 숨는다', (tester) async {
      await pumpApp(tester, audience: noTeamFollowed);

      await tester.tap(find.text('경기'));
      await settle(tester);
      // Visible on 일정/결과: sanity check before asserting the negative.
      expect(find.text('내 팀'), findsWidgets);
      expect(find.byTooltip('오늘로'), findsOneWidget);

      await tester.tap(find.text('순위'));
      await settle(tester);

      expect(
        find.text('내 팀'),
        findsNothing,
        reason: '필터 바는 날짜 범위에 한정된 UI라 순위에는 맞지 않습니다',
      );
      expect(
        find.byTooltip('오늘로'),
        findsNothing,
        reason: '순위는 날짜가 아니라 시즌 단위라 오늘로 이동이 의미가 없습니다',
      );

      // Switching back restores them — this is a per-section toggle, not a
      // one-way loss of the controls.
      await tester.tap(find.text('일정'));
      await settle(tester);
      expect(find.text('내 팀'), findsWidgets);
      expect(find.byTooltip('오늘로'), findsOneWidget);
    });

    testWidgets('순위를 눌러도 하단 탭은 그대로다', (tester) async {
      await pumpApp(tester, audience: noTeamFollowed);

      await tester.tap(find.text('경기'));
      await settle(tester);
      final tabBefore = selectedTabIndex(tester);

      await tester.tap(find.text('순위'));
      await settle(tester);
      expect(
        selectedTabIndex(tester),
        tabBefore,
        reason: '순위 세그먼트는 경기 탭 안의 상태 전환일 뿐, 다른 탭으로 옮겨가면 안 됩니다',
      );

      // 개인 순위 embeds the leaderboard cards in place — it must not push
      // `/my/leaderboard/:seasonId`, which lives in the 마이야구 branch and
      // would otherwise switch the bottom tab out from under the user.
      await tester.tap(find.text('개인 순위'));
      await settle(tester);
      expect(
        selectedTabIndex(tester),
        tabBefore,
        reason: '개인 순위도 같은 탭 안에서 카드로 보여야 합니다',
      );
      expect(find.byType(MyBaseballScreen), findsNothing);
    });

    testWidgets('데모 데이터 안내와 데이터 출처 버튼을 보여준다', (tester) async {
      await pumpApp(tester, audience: noTeamFollowed);

      await tester.tap(find.text('경기'));
      await settle(tester);
      await tester.tap(find.text('순위'));
      await settle(tester);

      expect(find.textContaining('앱 동작 확인용 데모 데이터'), findsOneWidget);
      expect(find.text('데이터 출처'), findsOneWidget);
      final tabBefore = selectedTabIndex(tester);

      await tester.tap(find.text('데이터 출처'));
      await settle(tester);
      // A root-navigated push (like this one, and like `/team/:id`) covers
      // the whole shell — including its `NavigationBar` — while it is on
      // screen, the same as any full-screen detail route. That is expected
      // and is not what the trap this test guards against looks like: the
      // trap is the *branch* changing, provable once we come back.
      expect(find.text('데이터 출처'), findsWidgets); // this screen's own app bar
      expect(find.byType(NavigationBar), findsNothing);

      await tester.tap(find.byType(BackButton));
      await settle(tester);
      // 데이터 출처 lives under 더보기's path but is root-navigated (see
      // `router.dart`), specifically so this push never reassigns the
      // selected bottom tab away from 경기 — provable once we are back.
      expect(
        selectedTabIndex(tester),
        tabBefore,
        reason: '출처 화면에서 돌아오면 하단 탭이 그대로 경기여야 합니다',
      );
      expect(
        find.text('리그 순위'),
        findsOneWidget,
        reason: '순위 세그먼트 상태도 유지되어야 합니다',
      );
    });

    testWidgets('표시할 순위가 전혀 없어도 세그먼트는 사라지지 않는다', (tester) async {
      await pumpApp(tester, audience: noTeamFollowed, seedAssets: false);

      await tester.tap(find.text('경기'));
      await settle(tester);

      // Still there, with nothing to gate it — this is the exact failure the
      // feature exists to close.
      expect(find.text('순위'), findsOneWidget);

      await tester.tap(find.text('순위'));
      await settle(tester);
      expect(find.text('순위 정보가 아직 없습니다'), findsOneWidget);

      // The demo notice describes numbers on screen. With none shown, the
      // notice would be asserting something about data that does not exist
      // — so it must not appear here, unlike the seeded case above.
      expect(find.textContaining('앱 동작 확인용 데모 데이터'), findsNothing);
      expect(find.text('데이터 출처'), findsNothing);
      // The nested toggle has nothing to switch between either.
      expect(find.text('리그 순위'), findsNothing);
      expect(find.text('개인 순위'), findsNothing);
    });

    for (final scale in <double>[1.0, 2.0]) {
      testWidgets('데모 안내 문구는 글자 배율 ${scale}x에서도 넘치지 않는다', (tester) async {
        final seen = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (details) {
          final text = details.exception.toString();
          if (text.contains('overflowed')) {
            seen.add(text);
          } else {
            previous?.call(details);
          }
        };
        addTearDown(() => FlutterError.onError = previous);

        await pumpApp(tester, audience: noTeamFollowed, textScale: scale);
        await tester.tap(find.text('경기'));
        await settle(tester);
        await tester.tap(find.text('순위'));
        await settle(tester);
        tester.takeException();

        expect(
          seen,
          isEmpty,
          reason: '데모 안내 배너가 ${scale}x에서 넘칩니다: ${seen.join(" || ")}',
        );
        // The button is on its own line below the sentence (see
        // `_StandingsDemoNotice`), so it always reads as a whole label —
        // never a fragment wedged where a line happened to wrap.
        expect(find.text('데이터 출처'), findsOneWidget);
        expect(find.textContaining('앱 동작 확인용 데모 데이터'), findsOneWidget);
      });
    }

    testWidgets('?section=standings 딥링크는 탭 전환 없이 순위를 바로 연다', (tester) async {
      final app = await pumpApp(tester, audience: noTeamFollowed);

      app.container.read(routerProvider).go('/games?section=standings');
      await settle(tester);

      expect(find.byType(GamesScreen), findsOneWidget);
      expect(find.text('리그 순위'), findsOneWidget);
      expect(selectedTabIndex(tester), 2, reason: '경기는 다섯 탭 중 인덱스 2입니다');
    });
  });
}
