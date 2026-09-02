@Tags(<String>['screenshots'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/database/database.dart';
import 'package:w_baseball/core/design_system/tokens.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/features/discover/discover_screen.dart';
import 'package:w_baseball/features/discover/nearby_games_screen.dart';
import 'package:w_baseball/features/games/game_detail_screen.dart';
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
/// screenshots`) because a failing pixel diff should never block a build --
/// that is a policy choice, independent of whether the pixels themselves are
/// reproducible (see `_loadKoreanFont` below).
///
/// Korean glyphs need a real font. `flutter test` ships a placeholder face
/// that draws boxes. Since `assets/fonts/Pretendard-*.ttf` is checked into
/// this repo, `_loadBundledPretendard` below now registers it for every
/// capture, so a Hangul/Latin/digit-only screen renders the same face on
/// every host and in CI, not whatever Korean font that machine happens to
/// have. A system Korean font is still loaded as a fallback, but only for
/// glyphs Pretendard has no coverage for (Hanja, some symbols/emoji) -- no
/// screen captured today needs one, but if a future one does, its pixels go
/// back to depending on the host, same as before this change.
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
    // Lets a capture seed device-local rows (e.g. 출전 일지 entries) that
    // are not part of the bundled seed set and would otherwise need their
    // own full app-building duplicate of this helper.
    Future<void> Function(TestApp app)? seedLocalState,
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
    if (seedLocalState != null) await seedLocalState(app);
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

    // The new entry point this feature adds: 순위, reachable as a segment
    // rather than gated behind a followed team. No team is followed in any
    // of these captures, so this is exactly the state that used to make
    // standings unreachable — see `GamesTabState.section` in
    // `games_screen.dart`.
    testWidgets(
      '순위 · 라이트',
      (t) => capture(
        t,
        name: 'games_standings',
        screen: const GamesScreen(initialSection: GamesSection.standings),
        audience: player,
      ),
    );

    testWidgets(
      '순위 · 다크',
      (t) => capture(
        t,
        name: 'games_standings',
        screen: const GamesScreen(initialSection: GamesSection.standings),
        audience: player,
        brightness: Brightness.dark,
      ),
    );

    // Same failure this feature exists to close, made visible: no standings
    // anywhere, and the segment must still be there with the existing empty
    // state rather than disappearing.
    testWidgets(
      '순위 · 데이터 없음',
      (t) => capture(
        t,
        name: 'games_standings_empty',
        screen: const GamesScreen(initialSection: GamesSection.standings),
        audience: player,
        seeded: false,
      ),
    );

    // 경기 상세's quick-action bar with all four buttons, at the narrowest
    // screen and at both ends of the text-scale range the app allows.
    //
    // Captured because until this existed, nobody could look at that bar. No
    // bundled fixture carries `officialDetailUrl`, so the four-button branch
    // only appears once synced data supplies the field, and every screenshot
    // and audit probe in this repo had therefore only ever rendered the
    // three-button one. The branch nobody could see was the worse of the
    // two: it drew '공식 기록' into a label column 0.0dp wide at 1.0x, and
    // pushed the button off the screen edge at 2.0x. `_QuickActionBar` now
    // measures the labels and folds to 2x2 and then to a single column;
    // these two images are what that decision looks like.
    //
    // `game_detail_quick_actions_test.dart` is what *asserts* the labels stay
    // on one line — a golden cannot, since a pixel diff must never block a
    // build (see this file's own doc). This pair is here so a reviewer sees
    // the shape, not so a machine checks it.
    for (final scale in <double>[1.0, 2.0]) {
      testWidgets(
        '경기 상세 · 공식 기록 있음 · 글자 $scale배',
        (t) => capture(
          t,
          name: 'game_detail_official',
          screen: const GameDetailScreen(gameId: 'game-demo-20260902-23'),
          audience: player,
          phone: TestPhone(
            'small_360x640_text${(scale * 100).round()}',
            const Size(360, 640),
            textScale: scale,
          ),
          // The field the four-button branch depends on, written straight to
          // the row the sync engine just created rather than into the seed
          // documents, so this capture shares `capture`'s single app build
          // with every other one instead of needing its own.
          seedLocalState: (app) async {
            await (app.db.update(
              app.db.games,
            )..where((g) => g.id.equals('game-demo-20260902-23'))).write(
              const GamesCompanion(
                officialDetailUrl: Value('https://example.org/games/23'),
              ),
            );
          },
        ),
      );
    }
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

    // 내 기록 (출전 일지), before any entry exists — the "경기 하고 오셨나요?"
    // nudge card, since 내 기록 renders in player mode with no team followed.
    testWidgets(
      '내 기록 · 기록 없음',
      (t) => capture(
        t,
        name: 'my_baseball_game_log_empty',
        screen: const MyBaseballScreen(),
        audience: player,
      ),
    );

    // 내 기록 with entries: the count, 포지션 히스토리 (a recorded position
    // change), the entry list, and the "이 기기에만 저장됩니다" export line.
    testWidgets(
      '내 기록 · 기록 있음',
      (t) => capture(
        t,
        name: 'my_baseball_game_log',
        screen: const MyBaseballScreen(),
        audience: player,
        seedLocalState: (app) async {
          await app.db
              .into(app.db.gameLogEntries)
              .insert(
                GameLogEntriesCompanion.insert(
                  playedAt: DateTime.utc(2026, 7, 12),
                  dayKey: '2026-07-12',
                  competitionLabel: const Value('동호인 리그'),
                  opponentLabel: const Value('남산 호크스'),
                  venueLabel: const Value('한강 보조경기장'),
                  positions: const Value('leftField'),
                  result: const Value('loss'),
                  createdAt: DateTime.utc(2026, 7, 12, 21),
                ),
              );
          final lastEntryId = await app.db
              .into(app.db.gameLogEntries)
              .insert(
                GameLogEntriesCompanion.insert(
                  playedAt: DateTime.utc(2026, 8, 23),
                  dayKey: '2026-08-23',
                  competitionLabel: const Value('동호인 리그'),
                  opponentLabel: const Value('한강 리버베어스'),
                  venueLabel: const Value('잠실보조경기장'),
                  positions: const Value('catcher'),
                  result: const Value('win'),
                  note: const Value('병살 하나 잡음, 도루 저지 성공'),
                  createdAt: DateTime.utc(2026, 8, 23, 21),
                  // A stat line below the OBP threshold (Stage 2) — shows
                  // the count-only summary line, not a rate, alongside the
                  // Stage 1 fields above.
                  plateAppearances: const Value(4),
                  hits: const Value(2),
                  walks: const Value(0),
                  sacrificeBunts: const Value(0),
                  strikeouts: const Value(1),
                  runsBattedIn: const Value(1),
                  runsScored: const Value(1),
                  stolenBases: const Value(1),
                ),
              );
          // Stage 3: 다음 경기에서 해볼 것 — an open goal written after the
          // game above, so `_GameLogGoalCard` actually renders in this
          // capture rather than staying the untested `SizedBox.shrink()`
          // case every other capture in this file exercises.
          await app.db
              .into(app.db.gameLogGoals)
              .insert(
                GameLogGoalsCompanion.insert(
                  body: '초구 공략',
                  entryId: Value(lastEntryId),
                  createdAt: DateTime.utc(2026, 8, 23, 21),
                ),
              );
        },
      ),
    );

    // Stage 2: enough batting to clear the OBP threshold, plus a pitching
    // line, a game whose 희생번트 was never recorded, and a game with no
    // stat line at all — one screenshot exercising every branch of the
    // aggregate card at once.
    testWidgets(
      '내 기록 · 성적 집계 (문턱 충족)',
      (t) => capture(
        t,
        name: 'my_baseball_game_log_stats_qualified',
        screen: const MyBaseballScreen(),
        audience: player,
        seedLocalState: (app) async {
          Future<void> insert(GameLogEntriesCompanion row) =>
              app.db.into(app.db.gameLogEntries).insert(row);

          await insert(
            GameLogEntriesCompanion.insert(
              playedAt: DateTime.utc(2026, 7, 5),
              dayKey: '2026-07-05',
              competitionLabel: const Value('동호인 리그'),
              opponentLabel: const Value('남산 호크스'),
              positions: const Value('catcher'),
              result: const Value('win'),
              createdAt: DateTime.utc(2026, 7, 5, 21),
              plateAppearances: const Value(8),
              hits: const Value(3),
              walks: const Value(1),
              sacrificeBunts: const Value(0),
              strikeouts: const Value(2),
              runsBattedIn: const Value(2),
              runsScored: const Value(1),
              stolenBases: const Value(1),
            ),
          );
          await insert(
            GameLogEntriesCompanion.insert(
              playedAt: DateTime.utc(2026, 7, 12),
              dayKey: '2026-07-12',
              competitionLabel: const Value('동호인 리그'),
              opponentLabel: const Value('한강 리버베어스'),
              positions: const Value('catcher'),
              result: const Value('loss'),
              createdAt: DateTime.utc(2026, 7, 12, 21),
              plateAppearances: const Value(9),
              hits: const Value(2),
              walks: const Value(2),
              sacrificeBunts: const Value(1),
              strikeouts: const Value(3),
              runsBattedIn: const Value(1),
              runsScored: const Value(2),
              stolenBases: const Value(0),
            ),
          );
          // 희생번트를 적지 않은 경기 — treated as 0, and noted as such.
          await insert(
            GameLogEntriesCompanion.insert(
              playedAt: DateTime.utc(2026, 7, 19),
              dayKey: '2026-07-19',
              competitionLabel: const Value('동호인 리그'),
              opponentLabel: const Value('남산 호크스'),
              positions: const Value('catcher'),
              result: const Value('win'),
              createdAt: DateTime.utc(2026, 7, 19, 21),
              plateAppearances: const Value(7),
              hits: const Value(3),
              walks: const Value(0),
              strikeouts: const Value(1),
              runsBattedIn: const Value(3),
              runsScored: const Value(1),
              stolenBases: const Value(0),
            ),
          );
          await insert(
            GameLogEntriesCompanion.insert(
              playedAt: DateTime.utc(2026, 7, 26),
              dayKey: '2026-07-26',
              competitionLabel: const Value('동호인 리그'),
              opponentLabel: const Value('한강 리버베어스'),
              positions: const Value('pitcher'),
              result: const Value('win'),
              createdAt: DateTime.utc(2026, 7, 26, 21),
              outsPitched: const Value(21),
              pitchingStrikeouts: const Value(6),
              pitchingWalks: const Value(3),
              runsAllowed: const Value(2),
            ),
          );
          await insert(
            GameLogEntriesCompanion.insert(
              playedAt: DateTime.utc(2026, 8, 2),
              dayKey: '2026-08-02',
              competitionLabel: const Value('동호인 리그'),
              opponentLabel: const Value('남산 호크스'),
              positions: const Value('pitcher'),
              result: const Value('loss'),
              createdAt: DateTime.utc(2026, 8, 2, 21),
              outsPitched: const Value(15),
              pitchingStrikeouts: const Value(4),
              pitchingWalks: const Value(2),
              runsAllowed: const Value(3),
            ),
          );
          // Logged the game itself, no stat line at all — Stage 1's shape.
          await insert(
            GameLogEntriesCompanion.insert(
              playedAt: DateTime.utc(2026, 8, 9),
              dayKey: '2026-08-09',
              competitionLabel: const Value('동호인 리그'),
              opponentLabel: const Value('한강 리버베어스'),
              positions: const Value('leftField'),
              result: const Value('draw'),
              createdAt: DateTime.utc(2026, 8, 9, 21),
            ),
          );
        },
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

/// Registers the fonts a capture needs, in two steps that must not mix.
///
/// 1. [_loadBundledPretendard] registers the five weights already shipped in
///    every build (`assets/fonts/`, declared in `pubspec.yaml`) under family
///    `Pretendard` -- the exact name [WbType] asks for. `flutter test` does
///    not read `pubspec.yaml`'s `fonts:` block on its own (verified in
///    `15886df`: capturing with and without that block produced identical
///    goldens), so without this call the bundle sits unused during tests
///    even though every release APK ships it. These assets are checked into
///    the repo, so this step succeeds identically on every machine and in
///    CI -- it is what makes a capture a function of the code alone rather
///    than of whichever Korean font happens to be installed on the host
///    that ran it.
/// 2. [_loadSystemFallbackFont] registers a system Korean face -- Malgun
///    Gothic on Windows, or whichever candidate exists -- but only under
///    [WbType]'s `fontFamilyFallback` names, **never** under `Pretendard`
///    itself. `fontFamilyFallback` is consulted per glyph, so this face
///    only ever draws a character Pretendard has no glyph for (Hanja, or a
///    symbol/emoji in a synced article title); it does not compete with the
///    bundled weights for anything Pretendard already covers. Registering a
///    second, unrelated font under `Pretendard` is exactly the bug this
///    file used to have: `malgun.ttf` and `malgunbd.ttf` were both added to
///    the `Pretendard` family, and it took reading Flutter's own
///    `FontLoader.load()` (`packages/flutter/lib/src/services/font_loader.dart`)
///    to confirm it loads strictly in call order, not completion order --
///    so that specific pairing was never actually racy. The risk it stood
///    in for is real regardless: two files with overlapping weight classes
///    inside one family invites the engine to pick between them by
///    whatever internal tie-break applies, which this codebase has no
///    control over and no test for. Keeping only one source of glyphs per
///    weight per family avoids relying on that tie-break at all.
///
/// What this does not fix: Linux CI has no `malgun.ttf`, so a capture
/// containing Hanja or an emoji is only guaranteed pixel-identical on a
/// host that has one of [_loadSystemFallbackFont]'s candidates, or has none
/// of them (in which case that one glyph is tofu everywhere, which is at
/// least consistent). Every screen captured today is pure Hangul/Latin/
/// digits, so a golden has not yet exercised that gap.
Future<void> _loadKoreanFont() async {
  await _loadBundledPretendard();
  await _loadSystemFallbackFont();
}

/// Registers `assets/fonts/Pretendard-*.ttf` under family `Pretendard`. Each
/// file's own `OS/2 usWeightClass` (400/500/600/700/800 -- verified in
/// `docs/design-system.md`) is what lets the engine's font matcher pick the
/// right weight for a given `TextStyle.fontWeight`: `FontLoader` has no API
/// to say "this file is the 700 weight", so five files with five distinct
/// embedded weight classes, registered under one family, is what makes
/// weight selection work at all here.
Future<void> _loadBundledPretendard() async {
  const assets = <String>[
    'assets/fonts/Pretendard-Regular.ttf',
    'assets/fonts/Pretendard-Medium.ttf',
    'assets/fonts/Pretendard-SemiBold.ttf',
    'assets/fonts/Pretendard-Bold.ttf',
    'assets/fonts/Pretendard-ExtraBold.ttf',
  ];
  final loader = FontLoader('Pretendard');
  var anyFound = false;
  for (final path in assets) {
    final file = File(path);
    if (!file.existsSync()) continue;
    anyFound = true;
    loader.addFont(
      file.readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
    );
  }
  if (!anyFound) {
    // Not fatal, but determinism ends here: every glyph, not just the ones
    // outside Pretendard's coverage, now falls back to whichever system
    // font `_loadSystemFallbackFont` finds below -- so from this point the
    // capture is once again a function of the host, not just the code.
    // ignore: avoid_print
    print(
      '[screenshots] assets/fonts/Pretendard-*.ttf not found; captures '
      'fall back to system fonts and are no longer host-independent',
    );
    return;
  }
  await loader.load();
}

/// Registers a system Korean face under [WbType]'s fallback family names
/// only (`Noto Sans KR` / `Apple SD Gothic Neo` / `Malgun Gothic` /
/// `sans-serif`, plus `Roboto` for widgets outside [WbType]) -- deliberately
/// not under `Pretendard`. See [_loadKoreanFont] for why the two must stay
/// separate.
Future<void> _loadSystemFallbackFont() async {
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
    // Not fatal: only glyphs outside Pretendard's coverage (Hanja, some
    // symbols/emoji) render as boxes; everything else is unaffected.
    // ignore: avoid_print
    print(
      '[screenshots] no Korean system font found; glyphs outside '
      "Pretendard's coverage will be boxes",
    );
    return;
  }

  for (final family in <String>[
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
