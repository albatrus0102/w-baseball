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
    // `lib/features`뿐 아니라 `lib/core/design_system`도 본다: 그 안의 위젯들은
    // 여러 화면이 그대로 가져다 쓰는 공유 렌더링 계층이라, 여기서 벽시계를 직접
    // 읽으면 `lib/features`에서 읽는 것과 똑같이 "실행 시각에 따라 문구가
    // 달라지는" 결함이 되고, 오히려 퍼지는 범위는 더 넓다. 두 디렉터리 모두
    // 지금 위반이 0건이라 베이스라인 없이 바로 막는다.
    //
    // `lib/app`도 본다 — `app.dart`/`router.dart`/`shell.dart`는 위젯을 빌드하는
    // 코드이고 여기도 0건이라 같은 이유로 막는다. 다만 그 디렉터리의
    // `providers.dart`와 `bootstrap.dart`는 제외한다: 둘 다 여기서 걸린 결함과
    // 다른 종류다 — 화면이 매 빌드마다 다시 묻는 "지금 몇 시야"가 아니라, 실제로
    // 벌어진 일(동기화 성공, 앱 시작)의 시각을 그 순간에 한 번 기록하는 값이다.
    // `setLastSuccessfulSyncAt`이 시계를 고정한 채 기록하면 "방금 갱신됨"이
    // 영원히 고정된 값이 되어 버려, 오히려 이 테스트가 막으려는 것과 반대되는
    // 결함이 생긴다. `clockProvider`의 실제 구현체(630번 줄)도 여기 있어야 하고,
    // 당연히 자기 자신은 걸리면 안 된다.
    //
    // `lib/core/network`, `lib/core/platform` 같은 나머지 `lib/core`는 넓히지
    // 않는다: HTTP 재시도 backoff, 실제 OS 알림 예약처럼 화면 문구가 아니라
    // 실제 바깥 세계의 시각과 맞아야 하는 자리이고, 지금도 여러 건 있어
    // 베이스라인부터 만들어야 하는데 이 결함과 직접 관련이 없다.
    final found = <({String path, int line, String text})>[
      ...offenders('lib/features'),
      ...offenders('lib/core/design_system'),
      ...offenders('lib/app').where(
        (o) =>
            !o.path.contains('/app/providers.dart') &&
            !o.path.contains('/app/bootstrap.dart'),
      ),
    ];

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
        final window = lines.sublist((i - 3).clamp(0, i), i + 1).join(' ');
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

  test('콘텐츠를 쓸 때 검수 상태를 반드시 넘긴다', () {
    // The schema's own default for `review_status` is `reviewed`, and for
    // `summary_method` it is `manual` — together, "a person wrote this and a
    // person checked it". That is the exact claim the review ledger exists to
    // stop the app making on its own, and it is what an omitted column falls
    // through to.
    //
    // All nine writers pass `reviewStatus` today, via `_reviewOrPending`. This
    // catches the tenth. Changing the column defaults would be the deeper fix
    // and needs a schema migration; it is recorded in the backlog rather than
    // done in passing, because the defaults only govern rows nobody currently
    // writes.
    final source = File('lib/data/sync/content_sync.dart').readAsStringSync();

    const contentTables = <String>[
      'FeaturedTopics',
      'Programs',
      'ProgramSeasons',
      'Episodes',
      'EpisodeRecaps',
      'OfficialClips',
      'Storylines',
      'FeaturedPeople',
      'StoryClusters',
      'BeginnerGuides',
    ];

    final writers = <String>[];
    for (final table in contentTables) {
      if (source.contains('${table}Companion.insert(')) writers.add(table);
    }

    expect(
      source.split('reviewStatus:').length - 1,
      writers.length,
      reason:
          '콘텐츠 쓰기 지점 ${writers.length}곳 중 일부가 reviewStatus를 넘기지 않습니다. '
          '빠뜨리면 컬럼 기본값 reviewed로 저장되어, 아무도 검수하지 않은 레코드가 '
          '검수됐다고 기록됩니다. _reviewOrPending()을 쓰세요.',
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
    final providers = File('lib/app/providers.dart').readAsStringSync();

    expect(
      providers,
      contains('final clockProvider = Provider<WbClock>'),
      reason: 'clockProvider가 DateTime을 캐시하면 화면의 상대 시간이 멈춥니다',
    );
    expect(providers, contains('typedef WbClock = DateTime Function();'));
  });
}
