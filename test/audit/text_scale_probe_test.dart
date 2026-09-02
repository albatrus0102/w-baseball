import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/features/games/game_detail_screen.dart';
import 'package:w_baseball/features/games/games_screen.dart';
import 'package:w_baseball/features/home/home_screen.dart';
import 'package:w_baseball/features/my_baseball/my_baseball_screen.dart';

import '../widget/harness.dart';

/// Audit probe, at the text-scale ceiling `WbApp` actually enforces today:
/// 0.85 to 2.0 (raised from an earlier 1.4 cap — Android's own accessibility
/// font setting reaches 2.0, and capping below it would hide layouts from
/// the people who most need the larger text, not fix them). This checks
/// whether the layouts survive the full range the OS can hand them: 1.3,
/// 1.4, 1.7, 2.0 on a 360dp screen — the tightest width Android ships in any
/// volume.
///
/// `pumpScreen` applies the requested scale directly and does not go through
/// `WbApp`'s clamp, which is what makes the question answerable at all.
///
/// Both loops below scroll every `Scrollable` to its end before asserting
/// (see `scrollToEnd` in `../widget/harness.dart`). `GameDetailScreen` is a
/// `CustomScrollView`: content below the first screenful — `AttendanceSection`,
/// the weather forecast row — is never built by a bare `pumpScreen`, so an
/// unscrolled check here would silently skip it rather than prove it clean.
///
/// Every result — pass or fail — is reported with its measurement conditions
/// (see `_conditions`), because an overflow's pixel count means nothing
/// without the width, scale, fixture and scroll state that produced it.
/// The one game every 경기 상세 probe renders. Named once, and reported on
/// failure: a pixel count is only reproducible if the reader knows which
/// game produced it.
const _probeGameId = 'game-demo-20260902-23';

/// 360dp is the tightest width Android ships in any volume.
const _probeSize = Size(360, 640);

/// The measurement conditions behind a probe result, spelled out.
///
/// An overflow is reported in pixels, and that count depends entirely on the
/// width, the text scale, the fixture, and how far the screen was scrolled.
/// "overflowed by 96 pixels" on its own is not reproducible: measured at a
/// different width it comes back a different number, and whoever reads it
/// cannot tell a stale report from a second, separate defect. This bit us
/// already — the same two overflows were once filed as 48px/167px and
/// re-measured here as 96px/301px, and the gap cost a round trip to explain
/// even though both numbers were honest. So every failure carries what is
/// needed to reproduce its number exactly.
String _conditions({
  required double scale,
  required String audience,
  required String screen,
  required bool scrolledToEnd,
  DateTime? frozenNow,
  String fixture = '',
}) => <String>[
  '${_probeSize.width.toInt()}x${_probeSize.height.toInt()}dp',
  '글자 배율 ${scale}x',
  '관객 $audience',
  if (frozenNow != null) '고정 시계 ${frozenNow.toIso8601String()}',
  '화면 $screen${fixture.isEmpty ? '' : ' ($fixture)'}',
  // Never omitted, even when true. "not scrolled" and "scrolled and found
  // nothing" are different findings, and a report that does not say which
  // one it is cannot be trusted for a lazy `CustomScrollView`.
  scrolledToEnd ? '끝까지 스크롤함 (scrollToEnd)' : '스크롤 안 함',
].join(' · ');

void main() {
  const player = AudiencePreference(
    mode: AudienceMode.player,
    onboardingCompleted: true,
    regionCode: '11',
    regionLabel: '서울',
  );

  const discover = AudiencePreference(
    mode: AudienceMode.discover,
    onboardingCompleted: true,
    regionCode: '11',
    regionLabel: '서울',
  );

  for (final scale in <double>[1.4]) {
    for (final entry in <(String, Widget, String)>[
      ('홈-입문자', const HomeScreen(), ''),
    ]) {
      testWidgets('PROBE: ${entry.$1} @ ${scale}x (360dp)', (tester) async {
        final app = await buildTestApp(audience: discover);
        addTearDown(app.dispose);
        final seen = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) {
          final text = details.exception.toString();
          if (text.contains('overflowed')) {
            seen.add(text);
          } else {
            previous?.call(details);
          }
        };
        addTearDown(() => FlutterError.onError = previous);
        await pumpScreen(
          tester,
          app,
          entry.$2,
          phone: TestPhone('probe_d_$scale', _probeSize, textScale: scale),
        );
        await settle(tester);
        await scrollToEnd(tester);
        tester.takeException();
        // Restored here and not only in the tear-down: `expect` below throws
        // its failure through `FlutterError.onError`, so leaving the override
        // in place swallows the report. The binding then asserts
        // "a test overrode FlutterError.onError" and the test sits until the
        // 10-minute timeout instead of failing with the message above — which
        // is exactly how this probe used to report a real overflow.
        FlutterError.onError = previous;
        final conditions = _conditions(
          scale: scale,
          audience: 'discover',
          screen: entry.$1,
          fixture: entry.$3,
          scrolledToEnd: true,
        );
        debugPrint(
          'PROBE|${entry.$1}|scale=$scale|'
          '${seen.isEmpty ? "OK" : seen.join(" || ")}|$conditions',
        );
        // Asserted, not merely reported: 2.0 is what Android's accessibility
        // font setting can reach, and the app no longer clamps below it.
        expect(
          seen,
          isEmpty,
          reason: '${entry.$1} 화면이 글자 배율 ${scale}x에서 넘칩니다\n$conditions',
        );
      });
    }
  }

  for (final scale in <double>[1.3, 1.4, 1.7, 2.0]) {
    for (final entry in <(String, Widget, String)>[
      ('홈', const HomeScreen(), ''),
      ('경기', const GamesScreen(), ''),
      ('마이야구', const MyBaseballScreen(), ''),
      // Added after `AttendanceSection`'s status badges and the weather
      // forecast row (`GameWeatherPanel` in `game_detail_screen.dart`) were
      // found overflowing at every one of these scales — a `CustomScrollView`
      // screen that no overflow probe had ever scrolled into.
      (
        '경기 상세',
        const GameDetailScreen(gameId: _probeGameId),
        'gameId=$_probeGameId',
      ),
    ]) {
      testWidgets('PROBE: ${entry.$1} @ ${scale}x (360dp)', (tester) async {
        // Hoisted out of the call so the failure message can name the clock
        // the screen was rendered against — a game's layout depends on how
        // far away it is.
        final frozenNow = DateTime.utc(2026, 9, 2, 9);
        final app = await buildTestApp(audience: player, frozenNow: frozenNow);
        addTearDown(app.dispose);

        // Capture the widget path of every overflow, not just the first, so the
        // report can name a file instead of a symptom.
        final seen = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) {
          final text = details.exception.toString();
          if (!text.contains('overflowed')) {
            previous?.call(details);
            return;
          }
          final path =
              details.informationCollector
                  ?.call()
                  .map((n) => n.toStringDeep())
                  .join(' ') ??
              '';
          final names = RegExp(r'(Wb[A-Za-z]+|_[A-Za-z]+)')
              .allMatches(path)
              .map((m) => m.group(0)!)
              .toSet()
              .take(6)
              .join(' / ');
          seen.add('$text  <- ${names.isEmpty ? "경로 없음" : names}');
        };
        addTearDown(() => FlutterError.onError = previous);

        await pumpScreen(
          tester,
          app,
          entry.$2,
          phone: TestPhone('probe_360_$scale', _probeSize, textScale: scale),
        );
        await settle(tester);
        // `GameDetailScreen` is a `CustomScrollView` — without this, its
        // below-the-fold sliver content is never built, and this probe would
        // report "OK" for content it never actually measured.
        await scrollToEnd(tester);
        tester.takeException();

        // Restored here and not only in the tear-down: `expect` below throws
        // its failure through `FlutterError.onError`, so leaving the override
        // in place swallows the report. The binding then asserts
        // "a test overrode FlutterError.onError" and the test sits until the
        // 10-minute timeout instead of failing with the message above — which
        // is exactly how this probe used to report a real overflow.
        FlutterError.onError = previous;
        final conditions = _conditions(
          scale: scale,
          audience: 'player',
          screen: entry.$1,
          fixture: entry.$3,
          scrolledToEnd: true,
          frozenNow: frozenNow,
        );
        debugPrint(
          'PROBE|${entry.$1}|scale=$scale|'
          '${seen.isEmpty ? "OK" : seen.join(" || ")}|$conditions',
        );
        // Confirmed clean at every scale in this range before asserting —
        // see the report for this change. Asserted so a future regression
        // fails here instead of shipping unnoticed.
        expect(
          seen,
          isEmpty,
          reason: '${entry.$1} 화면이 글자 배율 ${scale}x에서 넘칩니다\n$conditions',
        );
      });
    }
  }
}
