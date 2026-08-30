import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Rules about the source itself, for failures no running app reveals.
///
/// Each one here started as a real defect with the same shape: a correct
/// mechanism existed, and the calling code walked past it. Nothing crashed,
/// nothing looked wrong in review, and the only way to catch the next
/// occurrence is to read the source.
///
/// - A screen calling `DateTime.now()` renders correctly; it just renders
///   *differently* depending on when you looked, which made a real UI
///   regression and an afternoon produce the same golden diff.
/// - Trimming a rate string's first character is right for `0.325` and turns
///   `1.000` into `.000`.
/// - No remote image is rendered anywhere in this app today, which is the only
///   reason the licensing rule holds. One `Image.network` would end that.
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

  test('원격 이미지를 무조건 그리는 코드가 없다', () {
    // Today the app renders no images at all, so no unlicensed photo and no
    // minor's photo can reach a screen. That is not a decision anything
    // enforces — it is the state of not having built it yet, and one
    // `Image.network(topic.heroImageUrl!)` would end it silently.
    //
    // `ContentMeta` carries `heroImageLicense`, `FeaturedTopic` exposes
    // `canShowHeroImage`, and `Person` carries `isMinor`. Whoever adds the
    // first image has to route through them, so this test fails until the
    // exemption below is widened deliberately rather than by accident.
    const widgets = <String>[
      'Image.network',
      'NetworkImage(',
      'FadeInImage',
      'CachedNetworkImage',
    ];

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].trim();
        if (code.startsWith('//')) continue;
        if (widgets.any(code.contains)) {
          offenders.add(
            '  ${entity.path.replaceAll(r'\', '/')}:${i + 1}  $code',
          );
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '원격 이미지를 그리는 코드가 생겼습니다. 이용허락(heroImageLicense)과 '
          '미성년 여부(isMinor)를 먼저 확인하도록 바꾸고, 이 테스트를 그에 맞게 '
          '고치세요:\n${offenders.join('\n')}',
    );
  });

  test('이용허락과 미성년 확인 장치가 남아 있다', () {
    // The gates the rule above points at. If one is deleted as unused — and
    // `canShowHeroImage` currently has no callers, which is exactly how that
    // happens — the next person adding an image has nothing to route through.
    final content = File('lib/data/models/content.dart').readAsStringSync();
    expect(
      content,
      contains('bool get canShowHeroImage'),
      reason: '호출부가 없다고 지우면, 이미지를 추가하는 사람이 거칠 관문이 사라집니다',
    );
    expect(content, contains('heroImageLicense == LicenseStatus.permitted'));

    final domain = File('lib/data/models/domain.dart').readAsStringSync();
    expect(domain, contains('isMinor'));
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
