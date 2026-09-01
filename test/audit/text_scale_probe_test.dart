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
    for (final entry in <(String, Widget)>[('홈-입문자', const HomeScreen())]) {
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
          phone: TestPhone(
            'probe_d_$scale',
            const Size(360, 640),
            textScale: scale,
          ),
        );
        await settle(tester);
        await scrollToEnd(tester);
        tester.takeException();
        debugPrint(
          'PROBE|${entry.$1}|scale=$scale|'
          '${seen.isEmpty ? "OK" : seen.join(" || ")}',
        );
        // Asserted, not merely reported: 2.0 is what Android's accessibility
        // font setting can reach, and the app no longer clamps below it.
        expect(seen, isEmpty, reason: '${entry.$1} 화면이 글자 배율 ${scale}x에서 넘칩니다');
      });
    }
  }

  for (final scale in <double>[1.3, 1.4, 1.7, 2.0]) {
    for (final entry in <(String, Widget)>[
      ('홈', const HomeScreen()),
      ('경기', const GamesScreen()),
      ('마이야구', const MyBaseballScreen()),
      // Added after `AttendanceSection`'s status badges and the weather
      // forecast row (`GameWeatherPanel` in `game_detail_screen.dart`) were
      // found overflowing at every one of these scales — a `CustomScrollView`
      // screen that no overflow probe had ever scrolled into.
      ('경기 상세', const GameDetailScreen(gameId: 'game-demo-20260902-23')),
    ]) {
      testWidgets('PROBE: ${entry.$1} @ ${scale}x (360dp)', (tester) async {
        final app = await buildTestApp(
          audience: player,
          frozenNow: DateTime.utc(2026, 9, 2, 9),
        );
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
          phone: TestPhone(
            'probe_360_$scale',
            const Size(360, 640),
            textScale: scale,
          ),
        );
        await settle(tester);
        // `GameDetailScreen` is a `CustomScrollView` — without this, its
        // below-the-fold sliver content is never built, and this probe would
        // report "OK" for content it never actually measured.
        await scrollToEnd(tester);
        tester.takeException();

        debugPrint(
          'PROBE|${entry.$1}|scale=$scale|'
          '${seen.isEmpty ? "OK" : seen.join(" || ")}',
        );
        // Confirmed clean at every scale in this range before asserting —
        // see the report for this change. Asserted so a future regression
        // fails here instead of shipping unnoticed.
        expect(seen, isEmpty, reason: '${entry.$1} 화면이 글자 배율 ${scale}x에서 넘칩니다');
      });
    }
  }
}
