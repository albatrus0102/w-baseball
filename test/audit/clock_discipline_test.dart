import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Screens must not read the wall clock directly.
///
/// This is a source-level rule because the failure it prevents is invisible at
/// runtime. A screen that calls `DateTime.now()` renders correctly — it just
/// renders *differently* depending on when you looked. That made every golden
/// containing a relative time drift on its own: a screenshot captured at 09:00
/// showed "방금 확인" and the identical build re-checked at 14:00 showed
/// "5시간 전 확인", so a real UI regression and an afternoon were the same diff.
///
/// The fix is `clockProvider`, which a test pins. This test is what keeps the
/// next screen from quietly opting out of it.
void main() {
  /// Dart has no way to ask "was this identifier used" at test time, so the
  /// check is textual. It ignores comments, which legitimately name the API
  /// they are steering people away from.
  Iterable<({String path, int line, String text})> offenders(String dir) sync* {
    for (final entity in Directory(dir).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].trim();
        if (code.startsWith('//')) continue;
        if (code.contains('DateTime.now()')) {
          yield (
            path: entity.path.replaceAll(r'\', '/'),
            line: i + 1,
            text: code,
          );
        }
      }
    }
  }

  test('화면 코드는 벽시계를 직접 읽지 않는다', () {
    final found = offenders('lib/features').toList();

    expect(
      found,
      isEmpty,
      reason:
          '다음 위치에서 DateTime.now()를 직접 호출합니다. '
          'ref.watch(clockProvider)()로 바꾸세요 — 그래야 테스트가 시계를 고정할 수 있고 '
          '스크린샷이 실행 시각에 따라 달라지지 않습니다:\n'
          '${found.map((o) => '  ${o.path}:${o.line}  ${o.text}').join('\n')}',
    );
  });

  test('비율 표기의 앞자리를 화면에서 직접 자르지 않는다', () {
    // Same failure shape as the clock: a helper existed, was correct, and the
    // screens went around it. `formatRate` drops the leading zero only when
    // there is one; four call sites cut the first character outright, so a
    // 1.000 win rate rendered as .000 — an undefeated team shown bottom of the
    // table.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('stats.dart')) continue; // Defines formatRate.
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('substring(1)')) continue;
        // Only rate formatting is the concern; trimming a leading '/' off a
        // path is unrelated and legitimate.
        final window = lines
            .sublist((i - 3).clamp(0, i), i + 1)
            .join(' ');
        if (window.contains('toStringAsFixed(3)')) {
          offenders.add(
            '  ${entity.path.replaceAll(r'\', '/')}:${i + 1}  '
            '${lines[i].trim()}',
          );
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '다음 위치에서 비율 문자열의 앞자리를 직접 자릅니다. formatRate()를 쓰세요 — '
          '1.000이 .000으로 표시됩니다:\n${offenders.join('\n')}',
    );
  });

  test('시계는 값이 아니라 함수로 노출된다', () {
    // A cached `Provider<DateTime>` would satisfy the rule above and still be
    // wrong: read once at startup, "3분 전" would still say "3분 전" an hour
    // later. The function form is the part that has to hold.
    final providers = File(
      'lib/app/providers.dart',
    ).readAsStringSync();

    expect(
      providers,
      contains('final clockProvider = Provider<WbClock>'),
      reason: 'clockProvider가 DateTime을 캐시하면 화면의 상대 시간이 멈춥니다',
    );
    expect(providers, contains('typedef WbClock = DateTime Function();'));
  });
}
