import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/app/providers.dart';
import 'package:w_baseball/data/models/stats.dart';

import '../widget/harness.dart';

/// 개인 기록 순위, end to end against the seeded data.
///
/// The schema, sync path, repository, models and UI for records all existed
/// and were unit-tested, but no data ever reached them: nothing produced
/// batting or pitching lines, so the leaderboards were permanently empty and
/// every rule below was exercised only against synthetic objects. These run
/// against what the app actually ships.
void main() {
  testWidgets('시드 데이터로 순위표가 만들어진다', (tester) async {
    final app = await buildTestApp();
    addTearDown(app.dispose);

    await tester.runAsync(() async {
      final repo = app.container.read(competitionRepositoryProvider);
      final boards = await repo.leaderboards('season-demo-league-2026');

      expect(boards, isNotEmpty, reason: '기록이 있는 시즌은 순위표가 나와야 합니다');

      for (final board in boards) {
        expect(board.entries, isNotEmpty, reason: board.definition.key);

        // Ranks must be dense and ordered: 1,1,3 is fine, 1,3,2 is not.
        var previous = 0;
        for (final entry in board.entries.where((e) => e.qualifies)) {
          expect(entry.rank, greaterThanOrEqualTo(previous));
          previous = entry.rank ?? previous;
        }

        // Unqualified players sort below every qualified one, so a leaderboard
        // never appears to be led by someone with three at-bats.
        final firstUnqualified = board.entries.indexWhere((e) => !e.qualifies);
        final lastQualified = board.entries.lastIndexWhere((e) => e.qualifies);
        if (firstUnqualified != -1 && lastQualified != -1) {
          expect(firstUnqualified, greaterThan(lastQualified));
        }
      }
    });
  });

  testWidgets('타율은 실제 타수·안타에서 계산된다', (tester) async {
    final app = await buildTestApp();
    addTearDown(app.dispose);

    await tester.runAsync(() async {
      final repo = app.container.read(competitionRepositoryProvider);
      final boards = await repo.leaderboards('season-demo-league-2026');
      final avg = boards.firstWhere((b) => b.definition.key == 'avg');

      for (final entry in avg.entries) {
        // A rate statistic cannot exceed 1.000, and a player with no at-bats
        // must not be given a value at all.
        expect(
          entry.value,
          inInclusiveRange(0.0, 1.0),
          reason: entry.playerName,
        );
      }
    });
  });

  testWidgets('기록이 없는 시즌은 순위표를 만들어내지 않는다', (tester) async {
    // The WBSC event has no box scores. An empty leaderboard is the honest
    // answer; a fabricated one would not be.
    final app = await buildTestApp();
    addTearDown(app.dispose);

    await tester.runAsync(() async {
      final repo = app.container.read(competitionRepositoryProvider);
      final boards = await repo.leaderboards('season-wbsc-wbwc-2026');
      expect(boards, isEmpty);
    });
  });

  testWidgets('데모 경기로 계산한 순위는 데모라고 밝힌다', (tester) async {
    // The aggregate used to hard-code `isDemo: false`, so a table built
    // entirely from demo fixtures presented itself as genuine. The player
    // names give it away today; they will not once real data lands beside it.
    final app = await buildTestApp();
    addTearDown(app.dispose);

    await tester.runAsync(() async {
      final repo = app.container.read(competitionRepositoryProvider);
      final boards = await repo.leaderboards('season-demo-league-2026');
      expect(boards, isNotEmpty);
      for (final board in boards) {
        expect(
          board.provenance.isDemo,
          isTrue,
          reason: '${board.definition.key}: 데모 경기 기록인데 데모로 표시되지 않습니다',
        );
      }
    });
  });

  testWidgets('종합 평점 같은 합성 지표는 없다', (tester) async {
    final app = await buildTestApp();
    addTearDown(app.dispose);

    await tester.runAsync(() async {
      final repo = app.container.read(competitionRepositoryProvider);
      final boards = await repo.leaderboards('season-demo-league-2026');
      for (final board in boards) {
        expect(
          StatCategory.values.contains(board.definition.category),
          isTrue,
          reason: '${board.definition.key}: 알 수 없는 부문',
        );
        expect(board.definition.fullLabelKo.contains('종합'), isFalse);
        expect(
          board.definition.fullLabelKo.toUpperCase().contains('AI'),
          isFalse,
        );
      }
    });
  });
}
