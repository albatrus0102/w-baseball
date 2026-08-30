import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/features/games/games_screen.dart';
import 'package:w_baseball/features/home/home_screen.dart';
import 'package:w_baseball/features/my_baseball/my_baseball_screen.dart';

import '../widget/harness.dart';

/// Audit probe: the app clamps text scaling to 1.4 in `WbApp`, so a user who
/// sets Android to 200% gets 140%. This asks two things:
///   1. Do the layouts survive the app's *own* ceiling of 1.4?
///   2. How far past it would they survive, if the clamp were raised?
///
/// `pumpScreen` applies the requested scale directly and does not go through
/// `WbApp`'s clamp, which is what makes the question answerable at all.
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
    ]) {
      testWidgets('PROBE: ${entry.$1} @ ${scale}x (360dp)', (tester) async {
        final app = await buildTestApp(audience: player);
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
        tester.takeException();

        debugPrint(
          'PROBE|${entry.$1}|scale=$scale|'
          '${seen.isEmpty ? "OK" : seen.join(" || ")}',
        );
      });
    }
  }
}
