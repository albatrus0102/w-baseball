import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/design_system/components/provenance_widgets.dart';
import 'package:w_baseball/core/design_system/theme.dart';
import 'package:w_baseball/core/design_system/tokens.dart';
import 'package:w_baseball/data/models/provenance.dart';

/// The source line is the app's central promise, so its verbs have to be true.
///
/// 확인 says a person checked this record. 갱신 says only that we refreshed it.
/// `verifiedAt` is the one field that distinguishes them, and since the review
/// ledger landed no generated record carries one — so the line spoke of
/// confirmation while showing a download time, on every card in the app.
///
/// A second axis was added alongside: whether the line may pass a freshness
/// *verdict* at all (a relative time plus, when warranted, "오래된 정보") or
/// must fall back to stating a bare "as of" fact. That permission comes from
/// `WbFreshnessScope`, not from the record — see the shell-level
/// `freshnessThresholdProvider`. Its default with no ancestor scope is `null`,
/// i.e. no verdict, which is why most tests below install one explicitly:
/// a bare `WbSourceLine` in a test is exactly the "forgot to provide the
/// scope" case the fail-safe exists for, and the last group of tests checks
/// that case on purpose.
void main() {
  final now = DateTime.utc(2026, 8, 30, 9);

  Provenance provenance({DateTime? verifiedAt, DateTime? fetchedAt}) =>
      Provenance(
        sourceName: 'demo-fixture',
        sourceUrl: 'https://example.test/detail',
        fetchedAt: fetchedAt ?? now,
        verifiedAt: verifiedAt,
      );

  /// Pumps a bare source line. Pass [staleAfter] to install a
  /// `WbFreshnessScope` above it (the "a remote is configured and has synced"
  /// state); omit it to test the no-scope fail-safe default.
  Future<void> pump(
    WidgetTester tester,
    Provenance p, {
    Duration? staleAfter,
  }) async {
    final line = WbSourceLine(provenance: p, now: now);
    await tester.pumpWidget(
      MaterialApp(
        theme: WbTheme.light(),
        home: Scaffold(
          body: staleAfter == null
              ? line
              : WbFreshnessScope(staleAfter: staleAfter, child: line),
        ),
      ),
    );
  }

  group('검증 가능(원격이 설정되고 동기화된) 상태', () {
    const verdict = Duration(hours: 12);

    testWidgets('사람이 확인하지 않았으면 갱신이라고 말한다', (tester) async {
      // The state every shipped record is in. Downloading a file is not
      // confirming a record.
      await pump(tester, provenance(), staleAfter: verdict);

      expect(find.textContaining('갱신'), findsOneWidget);
      expect(
        find.textContaining('확인'),
        findsNothing,
        reason: '아무도 확인하지 않은 레코드를 확인했다고 말하면 안 됩니다',
      );
    });

    testWidgets('사람이 확인했으면 확인이라고 말한다', (tester) async {
      await pump(tester, provenance(verifiedAt: now), staleAfter: verdict);

      expect(find.textContaining('확인'), findsOneWidget);
    });

    testWidgets('확인 시각이 있으면 그 시각을 기준으로 말한다', (tester) async {
      // Fetched a moment ago, checked by a person two hours ago. The number
      // the user is being told about is the human check.
      await pump(
        tester,
        provenance(verifiedAt: now.subtract(const Duration(hours: 2))),
        staleAfter: verdict,
      );

      expect(find.textContaining('2시간 전 확인'), findsOneWidget);
    });

    testWidgets('오래된 정보 배지는 두 경우 모두에서 뜬다', (tester) async {
      // Staleness is about the timestamp, not about who produced it.
      await pump(
        tester,
        provenance(fetchedAt: now.subtract(const Duration(days: 2))),
        staleAfter: verdict,
      );

      expect(find.text('오래된 정보'), findsOneWidget);
    });

    testWidgets('신선하면 오래된 정보 배지가 뜨지 않는다', (tester) async {
      // The other direction: a threshold that permits a verdict must not turn
      // into an unconditional badge. Only actually-old data earns it.
      await pump(tester, provenance(), staleAfter: verdict);

      expect(find.text('오래된 정보'), findsNothing);
    });

    testWidgets('스크린리더 문구도 같은 동사를 쓴다', (tester) async {
      // The visual line and the semantics label are written separately, so
      // they can disagree — and a screen-reader user has no way to notice.
      await pump(tester, provenance(), staleAfter: verdict);

      final semantics = tester.getSemantics(find.byType(WbSourceLine));
      expect(semantics.label, contains('갱신'));
      expect(semantics.label, isNot(contains('확인')));
    });

    testWidgets('스크린리더 문구도 오래된 정보 여부를 같이 말한다', (tester) async {
      // The verb agreeing is not enough on its own — the badge itself is the
      // one thing on this line a screen-reader user cannot otherwise see, so
      // its presence in the visible row and in the semantics label must
      // match in both directions.
      await pump(
        tester,
        provenance(fetchedAt: now.subtract(const Duration(days: 2))),
        staleAfter: verdict,
      );
      final stale = tester.getSemantics(find.byType(WbSourceLine));
      expect(stale.label, contains('오래된 정보'));

      await pump(tester, provenance(), staleAfter: verdict);
      final fresh = tester.getSemantics(find.byType(WbSourceLine));
      expect(fresh.label, isNot(contains('오래된 정보')));
    });

    // F-1a regression. Both badges together are what overflowed a narrow
    // phone at high text scale: the Row gave the source text a Flexible, but
    // neither badge could shrink, so at 2.0x their combined intrinsic width
    // alone exceeded the screen before the text even mattered.
    testWidgets('오래된 정보와 데모 배지가 동시에 떠도 좁은 화면·큰 글자에서 넘치지 않는다', (tester) async {
      final stale = Provenance(
        sourceName: 'demo-fixture',
        sourceUrl: 'https://example.test/detail',
        fetchedAt: now.subtract(const Duration(days: 2)),
        isDemo: true,
      );

      // Constrains the actual test surface, not just the MediaQuery data
      // handed to descendants — a MediaQuery.copyWith(size: ...) override
      // alone does not change the root RenderView's box constraints, so it
      // would not have reproduced the overflow this test exists to catch.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: WbTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child ?? const SizedBox.shrink(),
          ),
          home: Scaffold(
            // 280 stands in for what's actually left after a real card's
            // side padding and screen gutters eat into the 360dp probe
            // width — a bare 360 here (no surrounding chrome) does not
            // reproduce the overflow the audit measured on-screen.
            body: SizedBox(
              width: 280,
              child: WbFreshnessScope(
                staleAfter: verdict,
                child: WbSourceLine(provenance: stale, now: now),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No RenderFlex overflow was thrown during layout/paint.
      expect(tester.takeException(), isNull);

      // Not just "didn't overflow" — both labels must still be fully
      // present. A fix that shrank or dropped a badge to avoid overflow
      // would fail here even though the overflow assertion above would
      // pass.
      expect(find.text('오래된 정보'), findsOneWidget);
      expect(find.text('데모 데이터'), findsOneWidget);
    });
  });

  group('검증 불가(스코프가 없는) 상태 — 실패 안전값', () {
    // No `WbFreshnessScope` above these: the default for a screen (or, as
    // here, a test) that never installs one. The fail-safe must say *less*
    // than the verdict states above, never more — so even data old enough to
    // earn "오래된 정보" above must not show it here.
    final veryStale = provenance(
      fetchedAt: now.subtract(const Duration(days: 2)),
    );

    testWidgets('배지 없이 사실만 말하고, 갱신이나 확인이라고 말하지 않는다', (tester) async {
      await pump(tester, veryStale);

      expect(find.textContaining('기준'), findsOneWidget);
      expect(
        find.textContaining('갱신'),
        findsNothing,
        reason: '아무 원격도 실제로 동기화된 적이 없으면 갱신했다고 말하면 안 됩니다',
      );
      expect(find.textContaining('확인'), findsNothing);
    });

    testWidgets('실제로는 오래된 데이터라도 오래된 정보 배지를 띄우지 않는다', (tester) async {
      // The direction that matters most: silence must not quietly become
      // "up to date". This record is two days old — old enough to trip the
      // badge in the verdict-permitted group above — and here it must not.
      await pump(tester, veryStale);

      expect(find.text('오래된 정보'), findsNothing);
    });

    testWidgets('절대 날짜로 말하고, 그 문구가 스크린리더 라벨에도 그대로 있다', (tester) async {
      // fetchedAt is `now` minus two days: 8월 28일, not today's 8월 30일.
      await pump(tester, veryStale);

      expect(find.textContaining('8월 28일 기준'), findsOneWidget);
      final semantics = tester.getSemantics(find.byType(WbSourceLine));
      expect(semantics.label, contains('8월 28일'));
      expect(semantics.label, isNot(contains('오래된 정보')));
    });

    testWidgets('데모 배지는 검증 가능 여부와 무관하게 그대로 뜬다', (tester) async {
      // The demo marker is a separate policy and must not be swept up by the
      // freshness fail-safe.
      final demo = Provenance(
        sourceName: 'demo-fixture',
        sourceUrl: 'https://example.test/detail',
        fetchedAt: now,
        isDemo: true,
      );
      await pump(tester, demo);

      expect(find.text('데모 데이터'), findsOneWidget);
    });
  });
}
