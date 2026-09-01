import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/design_system/components/game_widgets.dart';
import 'package:w_baseball/core/design_system/components/provenance_widgets.dart';
import 'package:w_baseball/core/design_system/theme.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/data/models/domain.dart';
import 'package:w_baseball/features/home/home_screen.dart';

import 'harness.dart';

/// A designer proposed removing the home app-bar's "앱 기본 데이터 표시 중"
/// caption, arguing every card already carries its own source-and-date label
/// (`WbSourceLine`) so the honesty requirement is met elsewhere.
///
/// That argument does not hold for `WbGameRow` — the compact row used for
/// 이번 주말 가까운 경기, 다가오는 경기 and 최근 결과 on home. It shows a "데모"
/// badge only when the record is demo, and shows *nothing* for bundled
/// (non-demo `seed`) data: no `WbSourceLine`, no date, no source name. For a
/// user seeing only game rows, the masthead caption is the *only* place that
/// says the data is bundled rather than freshly synced. Removing it would
/// leave such a user with no way to learn that fact, so the caption stays
/// until `WbGameRow` itself carries provenance (tracked separately — see the
/// spawned follow-up task, not part of this change).
void main() {
  Provenance seedProvenance() => Provenance(
    sourceName: 'seed',
    sourceUrl: 'app://seed/fixture',
    fetchedAt: DateTime.utc(2026, 8, 30),
    // Deliberately not demo: bundled seed data is real (if illustrative)
    // fixture data, not the "데모" family this row does mark.
  );

  Team team(String id) =>
      Team(id: id, name: id, shortName: id, provenance: seedProvenance());

  GameCard nonDemoCard() => GameCard(
    game: Game(
      id: 'g1',
      startTimeUtc: DateTime.utc(2026, 8, 30, 9),
      status: GameStatus.scheduled,
      homeTeamId: 'home',
      awayTeamId: 'away',
      provenance: seedProvenance(),
    ),
    homeTeam: team('home'),
    awayTeam: team('away'),
  );

  testWidgets('WbGameRow는 비데모 데이터에 출처·날짜를 전혀 표시하지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WbTheme.light(),
        home: Scaffold(
          body: WbGameRow(
            card: nonDemoCard(),
            now: DateTime.utc(2026, 8, 30, 9),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(
      find.byType(WbSourceLine),
      findsNothing,
      reason:
          'WbGameRow는 WbSourceLine을 그리지 않습니다 — 이 테스트가 실패한다면 그 간극이 '
          '메워졌다는 뜻이므로, 마스트헤드 캡션을 남긴 근거를 다시 검토해야 합니다',
    );
    expect(find.textContaining('출처'), findsNothing);
    expect(find.textContaining('데모'), findsNothing);
  });

  testWidgets('원격이 설정되지 않았으면 앱 바 캡션이 기본 데이터임을 말한다', (tester) async {
    // Companion to the WbGameRow check above: as long as that gap exists,
    // this caption is load-bearing and must not be removed from home.
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
    expect(find.text('앱 기본 데이터 표시 중'), findsOneWidget);
  });
}
