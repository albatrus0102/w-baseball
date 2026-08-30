import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/design_system/components/provenance_widgets.dart';
import 'package:w_baseball/core/design_system/theme.dart';
import 'package:w_baseball/data/models/provenance.dart';

/// The source line is the app's central promise, so its verbs have to be true.
///
/// 확인 says a person checked this record. 갱신 says only that we refreshed it.
/// `verifiedAt` is the one field that distinguishes them, and since the review
/// ledger landed no generated record carries one — so the line spoke of
/// confirmation while showing a download time, on every card in the app.
void main() {
  final now = DateTime.utc(2026, 8, 30, 9);

  Provenance provenance({DateTime? verifiedAt, DateTime? fetchedAt}) =>
      Provenance(
        sourceName: 'demo-fixture',
        sourceUrl: 'https://example.test/detail',
        fetchedAt: fetchedAt ?? now,
        verifiedAt: verifiedAt,
      );

  Future<void> pump(WidgetTester tester, Provenance p) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WbTheme.light(),
        home: Scaffold(body: WbSourceLine(provenance: p, now: now)),
      ),
    );
  }

  testWidgets('사람이 확인하지 않았으면 갱신이라고 말한다', (tester) async {
    // The state every shipped record is in. Downloading a file is not
    // confirming a record.
    await pump(tester, provenance());

    expect(find.textContaining('갱신'), findsOneWidget);
    expect(
      find.textContaining('확인'),
      findsNothing,
      reason: '아무도 확인하지 않은 레코드를 확인했다고 말하면 안 됩니다',
    );
  });

  testWidgets('사람이 확인했으면 확인이라고 말한다', (tester) async {
    await pump(tester, provenance(verifiedAt: now));

    expect(find.textContaining('확인'), findsOneWidget);
  });

  testWidgets('확인 시각이 있으면 그 시각을 기준으로 말한다', (tester) async {
    // Fetched a moment ago, checked by a person two hours ago. The number the
    // user is being told about is the human check.
    await pump(
      tester,
      provenance(verifiedAt: now.subtract(const Duration(hours: 2))),
    );

    expect(find.textContaining('2시간 전 확인'), findsOneWidget);
  });

  testWidgets('오래된 정보 배지는 두 경우 모두에서 뜬다', (tester) async {
    // Staleness is about the timestamp, not about who produced it.
    await pump(
      tester,
      provenance(fetchedAt: now.subtract(const Duration(days: 2))),
    );

    expect(find.text('오래된 정보'), findsOneWidget);
  });

  testWidgets('스크린리더 문구도 같은 동사를 쓴다', (tester) async {
    // The visual line and the semantics label are written separately, so they
    // can disagree — and a screen-reader user has no way to notice.
    await pump(tester, provenance());

    final semantics = tester.getSemantics(find.byType(WbSourceLine));
    expect(semantics.label, contains('갱신'));
    expect(semantics.label, isNot(contains('확인')));
  });
}
