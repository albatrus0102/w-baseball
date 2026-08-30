@Tags(<String>['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/design_system/tokens.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/features/discover/discover_screen.dart';
import 'package:w_baseball/features/discover/nearby_games_screen.dart';
import 'package:w_baseball/features/games/games_screen.dart';
import 'package:w_baseball/features/home/home_screen.dart';
import 'package:w_baseball/features/my_baseball/my_baseball_screen.dart';
import 'package:w_baseball/features/settings/data_sources_screen.dart';
import 'package:w_baseball/features/settings/more_screen.dart';
import 'package:w_baseball/features/settings/submissions_screen.dart';
import 'package:w_baseball/features/teams/teams_screen.dart';

import '../widget/harness.dart';

/// Captures review screenshots headlessly.
///
///     flutter test test/screenshots --update-goldens
///
/// Output lands in `docs/screenshots/`. These are **review artefacts, not
/// assertions**: they are excluded from the default run (`--exclude-tags
/// screenshots`) because pixel output depends on the host's fonts, and a
/// failing pixel diff should never block a build.
///
/// Korean glyphs need a real font. `flutter test` ships a placeholder face that
/// draws boxes, so a system Korean font is loaded when one is present; without
/// it the capture still runs and is simply less readable.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadIconFont();
    await _loadKoreanFont();
    Directory('docs/screenshots').createSync(recursive: true);
  });

  const discover = AudiencePreference(
    mode: AudienceMode.discover,
    onboardingCompleted: true,
    regionCode: '11',
    regionLabel: '서울',
  );
  const player = AudiencePreference(
    mode: AudienceMode.player,
    onboardingCompleted: true,
    regionCode: '11',
    regionLabel: '서울',
  );
  // The third mode is not a blend of the other two: `both` interleaves modules
  // by urgency instead of concatenating two lists, so it is the ordering no
  // other capture shows.
  const both = AudiencePreference(
    mode: AudienceMode.both,
    onboardingCompleted: true,
    regionCode: '11',
    regionLabel: '서울',
  );

  /// Fixed instant every screenshot is rendered at. Chosen to sit shortly
  /// after the seed's `generatedAt` so relative times read naturally.
  final goldenClock = DateTime.utc(2026, 8, 30, 9);

  /// One capture: a screen, at a size, in a theme.
  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required Widget screen,
    TestPhone phone = TestPhone.regular,
    Brightness brightness = Brightness.light,
    AudiencePreference? audience,
    bool seeded = true,
  }) async {
    // Golden images must be a function of the code alone. Without a frozen
    // clock the source line drifts from "방금 확인" to "7분 전 확인" between
    // runs, so an unchanged app fails its own goldens.
    final app = await buildTestApp(
      seedAssets: seeded,
      audience: audience,
      frozenNow: goldenClock,
    );
    addTearDown(app.dispose);
    await pumpScreen(tester, app, screen, phone: phone, brightness: brightness);
    await settle(tester);

    final suffix = brightness == Brightness.dark ? '_dark' : '';
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../../docs/screenshots/${name}_${phone.name}$suffix.png',
      ),
    );
  }

  // Same screen, same data, both densities — the pair a reviewer needs in
  // order to check that compact only spends whitespace.
  group('정보 밀도', () {
    testWidgets(
      '넓게 보기',
      (t) => capture(
        t,
        name: 'home_density_comfortable',
        screen: const HomeScreen(),
        audience: player.copyWith(densityOverride: WbDensity.comfortable),
      ),
    );

    testWidgets(
      '조밀하게 보기',
      (t) => capture(
        t,
        name: 'home_density_compact',
        screen: const HomeScreen(),
        audience: player.copyWith(densityOverride: WbDensity.compact),
      ),
    );
  });

  group('홈', () {
    testWidgets(
      '둘 다 · 라이트',
      (t) => capture(
        t,
        name: 'home_both',
        screen: const HomeScreen(),
        audience: both,
      ),
    );

    testWidgets(
      '둘 다 · 다크',
      (t) => capture(
        t,
        name: 'home_both',
        screen: const HomeScreen(),
        audience: both,
        brightness: Brightness.dark,
      ),
    );

    testWidgets(
      '입문자 · 라이트',
      (t) => capture(
        t,
        name: 'home_discover',
        screen: const HomeScreen(),
        audience: discover,
      ),
    );

    testWidgets(
      '입문자 · 다크',
      (t) => capture(
        t,
        name: 'home_discover',
        screen: const HomeScreen(),
        audience: discover,
        brightness: Brightness.dark,
      ),
    );

    testWidgets(
      '입문자 · 작은 화면',
      (t) => capture(
        t,
        name: 'home_discover',
        screen: const HomeScreen(),
        audience: discover,
        phone: TestPhone.small,
      ),
    );

    testWidgets(
      '입문자 · 큰 글자',
      (t) => capture(
        t,
        name: 'home_discover',
        screen: const HomeScreen(),
        audience: discover,
        phone: TestPhone.largeText,
      ),
    );

    testWidgets(
      '현역 · 라이트',
      (t) => capture(
        t,
        name: 'home_player',
        screen: const HomeScreen(),
        audience: player,
      ),
    );

    testWidgets(
      '현역 · 다크',
      (t) => capture(
        t,
        name: 'home_player',
        screen: const HomeScreen(),
        audience: player,
        brightness: Brightness.dark,
      ),
    );

    // The state a first launch with no data must still handle well.
    testWidgets(
      '빈 상태',
      (t) => capture(
        t,
        name: 'home_empty',
        screen: const HomeScreen(),
        audience: discover,
        seeded: false,
      ),
    );
  });

  group('경기', () {
    testWidgets(
      '일정 · 라이트',
      (t) => capture(
        t,
        name: 'games',
        screen: const GamesScreen(),
        audience: player,
      ),
    );

    testWidgets(
      '일정 · 다크',
      (t) => capture(
        t,
        name: 'games',
        screen: const GamesScreen(),
        audience: player,
        brightness: Brightness.dark,
      ),
    );

    testWidgets(
      '일정 · 작은 화면',
      (t) => capture(
        t,
        name: 'games',
        screen: const GamesScreen(),
        audience: player,
        phone: TestPhone.small,
      ),
    );

    testWidgets(
      '경기 없는 날',
      (t) => capture(
        t,
        name: 'games_empty',
        screen: const GamesScreen(),
        audience: player,
        seeded: false,
      ),
    );
  });

  group('발견', () {
    testWidgets(
      '라이트',
      (t) => capture(
        t,
        name: 'discover',
        screen: const DiscoverScreen(),
        audience: discover,
      ),
    );

    testWidgets(
      '다크',
      (t) => capture(
        t,
        name: 'discover',
        screen: const DiscoverScreen(),
        audience: discover,
        brightness: Brightness.dark,
      ),
    );

    testWidgets(
      '근처 경기',
      (t) => capture(
        t,
        name: 'nearby',
        screen: const NearbyGamesScreen(),
        audience: discover,
      ),
    );
  });

  group('마이야구', () {
    testWidgets(
      '팀 미선택',
      (t) => capture(
        t,
        name: 'my_baseball_setup',
        screen: const MyBaseballScreen(),
        audience: player,
      ),
    );
  });

  group('팀·설정', () {
    testWidgets(
      '팀 찾기',
      (t) => capture(
        t,
        name: 'teams',
        screen: const TeamsScreen(),
        audience: discover,
      ),
    );

    testWidgets(
      '더보기',
      (t) => capture(
        t,
        name: 'more',
        screen: const MoreScreen(),
        audience: player,
      ),
    );

    testWidgets(
      '데이터 출처',
      (t) => capture(
        t,
        name: 'data_sources',
        screen: const DataSourcesScreen(),
        audience: player,
      ),
    );

    testWidgets(
      '제보',
      (t) => capture(
        t,
        name: 'submissions',
        screen: const SubmissionsScreen(),
        audience: player,
      ),
    );
  });
}

/// Registers a Korean-capable system font so captures show real text.
Future<void> _loadKoreanFont() async {
  const candidates = <String>[
    r'C:\Windows\Fonts\malgun.ttf',
    r'C:\Windows\Fonts\malgunbd.ttf',
    '/System/Library/Fonts/AppleSDGothicNeo.ttc',
    '/usr/share/fonts/truetype/nanum/NanumGothic.ttf',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  ];

  final found = <String>[];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) found.add(path);
  }
  if (found.isEmpty) {
    // Not fatal: the capture still runs, it is just less legible.
    // ignore: avoid_print
    print('[screenshots] no Korean system font found; glyphs will be boxes');
    return;
  }

  // Register under every family the app asks for, plus the fallbacks, so the
  // text engine resolves Korean regardless of which name it tries first.
  for (final family in <String>[
    'Pretendard',
    'Noto Sans KR',
    'Apple SD Gothic Neo',
    'Malgun Gothic',
    'sans-serif',
    'Roboto',
  ]) {
    final loader = FontLoader(family);
    for (final path in found) {
      loader.addFont(
        File(path).readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
      );
    }
    await loader.load();
  }
}

/// Loads the Material icon font.
///
/// `flutter test` substitutes a placeholder face for every font, so icons
/// would otherwise render as empty boxes in a capture. The real face ships
/// inside the Flutter SDK cache.
Future<void> _loadIconFont() async {
  final root =
      Platform.environment['FLUTTER_ROOT'] ?? _flutterRootFromExecutable();
  if (root == null) return;

  final candidates = <String>[
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.ttf',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final loader = FontLoader(
      'MaterialIcons',
    )..addFont(file.readAsBytes().then((bytes) => ByteData.view(bytes.buffer)));
    await loader.load();
    return;
  }
}

/// Derives the SDK root from the running Dart executable when the environment
/// variable is not set (the usual case under `flutter test`).
String? _flutterRootFromExecutable() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6; i++) {
    if (Directory('${dir.path}/bin/cache/artifacts/material_fonts')
        .existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
