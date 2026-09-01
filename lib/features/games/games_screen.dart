import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/shell.dart';
import '../../core/design_system/components/game_widgets.dart';
import '../../core/design_system/components/notice_widgets.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/components/standings_widgets.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../core/utils/kst.dart';
import '../../data/models/domain.dart';
import '../../data/repositories/game_repository.dart';
import '../competitions/leaderboard_boards.dart';

/// `일정` / `결과` / `순위` — the three sections of the 경기 tab.
///
/// `순위` used to be reachable only through data-gated cards (a followed team
/// on 홈, or 마이야구) — so with no team followed, it was not reachable at
/// all. It is a named, always-present sibling of the other two now, exactly
/// as `WbAppShell`'s tab semantics already claimed.
enum GamesSection { schedule, results, standings }

/// `리그 순위` / `개인 순위` — the nested choice inside the 순위 section.
///
/// Named `league`, not `team`, because "팀 순위" reads as "my team's row" —
/// which is exactly the misreading that made the existing 홈 card
/// (`내 팀 순위`) invisible as a route to the *whole* table. This view always
/// renders every team, never scoped to a followed one; the name has to say so.
enum GamesStandingsView { league, individual }

/// Filter + date state for the games tab.
///
/// Held in a provider rather than local widget state so it survives navigating
/// to a detail screen, opening the in-app browser, and switching tabs — one of
/// the explicit acceptance criteria.
class GamesTabState {
  const GamesTabState({
    required this.dayKey,
    this.section = GamesSection.schedule,
    this.standingsView = GamesStandingsView.league,
    this.competitionIds = const <String>[],
    this.teamIds = const <String>[],
    this.statuses = const <GameStatus>[],
    this.level,
    this.favoritesOnly = false,
    this.landedOnNearest = false,
  });

  final String dayKey;

  /// True when the app moved the user off today because today had no games.
  /// Surfaced in the UI — silently showing a different date than the one the
  /// user expects is worse than the empty day it avoids.
  final bool landedOnNearest;

  /// `일정` / `결과` / `순위` segment.
  final GamesSection section;

  /// `리그 순위` / `개인 순위`, nested inside the `순위` segment.
  final GamesStandingsView standingsView;

  final List<String> competitionIds;
  final List<String> teamIds;
  final List<GameStatus> statuses;
  final CompetitionLevel? level;
  final bool favoritesOnly;

  GamesTabState copyWith({
    String? dayKey,
    GamesSection? section,
    GamesStandingsView? standingsView,
    List<String>? competitionIds,
    List<String>? teamIds,
    List<GameStatus>? statuses,
    CompetitionLevel? level,
    bool? favoritesOnly,
    bool? landedOnNearest,
    bool clearLevel = false,
  }) {
    return GamesTabState(
      dayKey: dayKey ?? this.dayKey,
      section: section ?? this.section,
      standingsView: standingsView ?? this.standingsView,
      competitionIds: competitionIds ?? this.competitionIds,
      teamIds: teamIds ?? this.teamIds,
      statuses: statuses ?? this.statuses,
      level: clearLevel ? null : (level ?? this.level),
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      landedOnNearest: landedOnNearest ?? this.landedOnNearest,
    );
  }

  GameQuery toQuery() => GameQuery(
    dayKey: dayKey,
    competitionIds: competitionIds,
    teamIds: teamIds,
    statuses: statuses,
    level: level,
    favoritesOnly: favoritesOnly,
    ascending: section != GamesSection.results,
  );

  int get activeFilterCount => toQuery().activeFilterCount;

  GamesTabState cleared() => GamesTabState(
    dayKey: dayKey,
    section: section,
    standingsView: standingsView,
  );
}

class GamesTabController extends Notifier<GamesTabState> {
  /// Set once the user picks a date themselves. After that the tab never
  /// moves on its own — an app that keeps re-deciding where you are is worse
  /// than one that starts in the wrong place.
  bool _userPickedDay = false;

  @override
  GamesTabState build() {
    final today = Kst.dayKey(ref.read(clockProvider)());
    // Opening on an empty today was measured as a whole extra tap for a
    // newcomer (T1′ in docs/task-benchmarks.md). Land on the nearest day that
    // actually has fixtures instead, and say so; `오늘로` in the app bar is
    // the way back.
    unawaited(_landOnNearestIfTodayIsEmpty(today));
    return GamesTabState(dayKey: today);
  }

  Future<void> _landOnNearestIfTodayIsEmpty(String today) async {
    final games = ref.read(gameRepositoryProvider);
    final todaysGames = await games.watchGames(GameQuery(dayKey: today)).first;
    if (todaysGames.isNotEmpty || _userPickedDay) return;

    final nearest = await games.nextDayWithGames(today, forward: true);
    if (nearest == null || _userPickedDay) return;
    state = state.copyWith(dayKey: nearest, landedOnNearest: true);
  }

  void setDay(String dayKey) {
    _userPickedDay = true;
    state = state.copyWith(dayKey: dayKey, landedOnNearest: false);
  }

  void setSection(GamesSection section) =>
      state = state.copyWith(section: section);

  void setStandingsView(GamesStandingsView view) =>
      state = state.copyWith(standingsView: view);

  void toggleCompetition(String id) {
    final next = state.competitionIds.toList();
    next.contains(id) ? next.remove(id) : next.add(id);
    state = state.copyWith(competitionIds: next);
  }

  void setLevel(CompetitionLevel? level) => state = level == null
      ? state.copyWith(clearLevel: true)
      : state.copyWith(level: level);

  void toggleStatus(GameStatus status) {
    final next = state.statuses.toList();
    next.contains(status) ? next.remove(status) : next.add(status);
    state = state.copyWith(statuses: next);
  }

  void toggleFavoritesOnly() =>
      state = state.copyWith(favoritesOnly: !state.favoritesOnly);

  void clearFilters() => state = state.cleared();

  void jumpToToday() {
    _userPickedDay = true;
    state = state.copyWith(
      dayKey: Kst.dayKey(ref.read(clockProvider)()),
      landedOnNearest: false,
    );
  }
}

final gamesTabProvider = NotifierProvider<GamesTabController, GamesTabState>(
  GamesTabController.new,
);

/// Days in the visible month that have games — drives the date strip dots.
final _monthGameDaysProvider = StreamProvider.family<Set<String>, String>((
  ref,
  monthKey,
) {
  return ref.watch(gameRepositoryProvider).watchGameDays(monthKey);
});

class GamesScreen extends ConsumerStatefulWidget {
  const GamesScreen({super.key, this.initialSection});

  /// From `?section=standings` on a deep link (see `router.dart`). Applied
  /// once per navigation to this route rather than read directly in `build`,
  /// because `gamesTabProvider`'s selected section is meant to persist across
  /// tab switches — a stale query parameter on a later, unrelated rebuild
  /// must not silently flip the section back.
  final GamesSection? initialSection;

  @override
  ConsumerState<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends ConsumerState<GamesScreen> {
  @override
  void initState() {
    super.initState();
    _applyInitialSection();
  }

  @override
  void didUpdateWidget(GamesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSection != null &&
        widget.initialSection != oldWidget.initialSection) {
      _applyInitialSection();
    }
  }

  void _applyInitialSection() {
    final section = widget.initialSection;
    if (section == null) return;
    // Deferred: this can run before the first frame, and Riverpod forbids
    // mutating a provider while the widget tree is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(gamesTabProvider.notifier).setSection(section);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gamesTabProvider);
    final controller = ref.read(gamesTabProvider.notifier);
    final now = ref.watch(clockProvider)();
    final onStandings = state.section == GamesSection.standings;
    // Only the schedule/results sections need the game list; watching it
    // unconditionally would run a query the 순위 section never uses.
    final games = onStandings
        ? null
        : ref.watch(gamesProvider(state.toQuery()));

    final double scaleBump = (MediaQuery.textScalerOf(context).scale(1) - 1)
        .clamp(0, 1);

    return Scaffold(
      appBar: WbPrimaryAppBar(
        title: '경기',
        actions: <Widget>[
          // Date-scoped, like the strip and filter bar below — hidden on 순위,
          // which has no date to jump to.
          if (!onStandings)
            IconButton(
              tooltip: '오늘로',
              onPressed: controller.jumpToToday,
              icon: const Icon(Icons.today_rounded),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(
            onStandings ? 56 + 20 * scaleBump : 104 + 60 * scaleBump,
          ),
          child: Column(
            children: <Widget>[
              _Segment(
                section: state.section,
                onChanged: controller.setSection,
              ),
              // Hidden on 순위: a season table has no single date, so a date
              // strip above it would claim a date-scope this data doesn't have.
              if (!onStandings)
                _DateStrip(dayKey: state.dayKey, onSelect: controller.setDay),
            ],
          ),
        ),
      ),
      body: onStandings
          ? _StandingsSection(state: state, controller: controller, now: now)
          : Column(
              children: <Widget>[
                // Says out loud that the app chose this date. Landing
                // somewhere the user did not ask for is only acceptable if
                // they can see that it happened and get back in one tap.
                if (state.landedOnNearest)
                  _LandedNotice(
                    dayKey: state.dayKey,
                    onToday: controller.jumpToToday,
                  ),
                _FilterBar(state: state, controller: controller),
                Expanded(
                  child: games!.when(
                    loading: () => ListView.builder(
                      padding: const EdgeInsets.all(WbSpace.screen),
                      itemCount: 4,
                      itemBuilder: (context, _) => const Padding(
                        padding: EdgeInsets.only(bottom: WbSpace.sm),
                        child: WbGameRowSkeleton(),
                      ),
                    ),
                    error: (error, _) => WbEmptyState(
                      icon: Icons.cloud_off_rounded,
                      tone: WbBadgeTone.danger,
                      title: '경기 목록을 불러오지 못했습니다',
                      message: '저장된 데이터를 다시 읽어보세요.',
                      primaryLabel: '다시 시도',
                      onPrimary: () => ref.invalidate(gamesProvider),
                    ),
                    data: (list) =>
                        _GamesList(games: list, state: state, now: now),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.section, required this.onChanged});

  final GamesSection section;
  final ValueChanged<GamesSection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        0,
        WbSpace.screen,
        WbSpace.sm,
      ),
      child: SegmentedButton<GamesSection>(
        segments: const <ButtonSegment<GamesSection>>[
          ButtonSegment<GamesSection>(
            value: GamesSection.schedule,
            label: Text('일정'),
          ),
          ButtonSegment<GamesSection>(
            value: GamesSection.results,
            label: Text('결과'),
          ),
          ButtonSegment<GamesSection>(
            value: GamesSection.standings,
            label: Text('순위'),
          ),
        ],
        selected: <GamesSection>{section},
        onSelectionChanged: (selection) => onChanged(selection.first),
        showSelectedIcon: false,
      ),
    );
  }
}

/// The 순위 section: a nested `리그 순위` / `개인 순위` choice, plus the demo
/// notice every domestic standing currently needs.
///
/// Never data-gated. `standingsSeasonProvider` resolving to `null` is a
/// legitimate, common state — a fresh bundle with no synced standings yet —
/// and this still renders the segment plus an empty state rather than
/// disappearing, which is the exact failure this feature exists to fix.
class _StandingsSection extends ConsumerWidget {
  const _StandingsSection({
    required this.state,
    required this.controller,
    required this.now,
  });

  final GamesTabState state;
  final GamesTabController controller;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasonAsync = ref.watch(standingsSeasonProvider);
    // Loading and error both fall through as "nothing to show yet" here —
    // `.value` is null in both those states, same as a resolved `null`.
    final resolvedSeasonId = seasonAsync.value;
    final hasStandings = resolvedSeasonId != null;

    return Column(
      children: <Widget>[
        // Only shown once there is an actual season of standings to label —
        // a sentence claiming "the numbers you see are demo" when there are
        // no numbers on screen would say more than is true. The empty state
        // below already says what is true ("순위 정보가 아직 없습니다").
        if (hasStandings) const _StandingsDemoNotice(),
        if (hasStandings)
          _StandingsViewSegment(
            view: state.standingsView,
            onChanged: controller.setStandingsView,
          ),
        Expanded(
          child: seasonAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => WbEmptyState(
              icon: Icons.cloud_off_rounded,
              tone: WbBadgeTone.danger,
              title: '순위를 불러오지 못했습니다',
            ),
            data: (seasonId) {
              if (seasonId == null) {
                // The existing empty state, reused rather than hidden — see
                // the class doc above.
                return WbStandingsTable(
                  standings: const <StandingRow>[],
                  now: now,
                );
              }
              return state.standingsView == GamesStandingsView.league
                  ? _LeagueStandingsView(seasonId: seasonId, now: now)
                  : WbLeaderboardBoards(seasonId: seasonId);
            },
          ),
        ),
      ],
    );
  }
}

class _StandingsViewSegment extends StatelessWidget {
  const _StandingsViewSegment({required this.view, required this.onChanged});

  final GamesStandingsView view;
  final ValueChanged<GamesStandingsView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        WbSpace.sm,
        WbSpace.screen,
        WbSpace.sm,
      ),
      child: SegmentedButton<GamesStandingsView>(
        segments: const <ButtonSegment<GamesStandingsView>>[
          ButtonSegment<GamesStandingsView>(
            value: GamesStandingsView.league,
            label: Text('리그 순위'),
          ),
          ButtonSegment<GamesStandingsView>(
            value: GamesStandingsView.individual,
            label: Text('개인 순위'),
          ),
        ],
        selected: <GamesStandingsView>{view},
        onSelectionChanged: (selection) => onChanged(selection.first),
        showSelectedIcon: false,
      ),
    );
  }
}

/// The whole season's team table — every team, never scoped to a followed
/// one. Wraps `WbStandingsTable` with this section's own loading/error states,
/// mirroring how `CompetitionScreen`'s 순위 tab handles the same provider.
class _LeagueStandingsView extends ConsumerWidget {
  const _LeagueStandingsView({required this.seasonId, required this.now});

  final String seasonId;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(competitionDetailProvider(seasonId));
    return detail.when(
      loading: () => ListView.builder(
        padding: const EdgeInsets.all(WbSpace.screen),
        itemCount: 4,
        itemBuilder: (context, _) => const Padding(
          padding: EdgeInsets.only(bottom: WbSpace.sm),
          child: WbSkeleton(height: 44, borderRadius: WbRadius.cardAll),
        ),
      ),
      error: (error, _) => WbEmptyState(
        icon: Icons.cloud_off_rounded,
        tone: WbBadgeTone.danger,
        title: '순위를 불러오지 못했습니다',
      ),
      data: (value) => WbStandingsTable(
        standings: value?.standings ?? const <StandingRow>[],
        now: now,
        onTeamTap: (id) => context.push(WbRoutes.team(id)),
      ),
    );
  }
}

/// Same container shape as `_LandedNotice` above; both hand the layout
/// decision to `WbNoticeWithAction` rather than assuming a same-row action
/// is safe. An earlier version of this doc comment claimed `_LandedNotice`'s
/// sentence was "short enough to share a line with its button at every
/// scale" — that turned out to be false (see `_LandedNotice`'s history), so
/// this widget no longer hand-writes the same claim about its own,
/// fixed-length sentence either; `WbNoticeWithAction` measures instead.
///
/// All domestic standings are demo data today, and the 경기 tab is where
/// that fact is easiest to miss, since the badges on the table and cards
/// below sit past a scroll.
class _StandingsDemoNotice extends StatelessWidget {
  const _StandingsDemoNotice();

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        WbSpace.sm,
        WbSpace.screen,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: WbSpace.md,
        vertical: WbSpace.xs,
      ),
      decoration: BoxDecoration(
        color: c.brandSoft,
        borderRadius: WbRadius.chipAll,
      ),
      child: WbNoticeWithAction(
        leading: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.science_outlined, size: 15, color: c.brand),
        ),
        text:
            '지금 보이는 순위는 앱 동작 확인용 데모 데이터입니다. '
            '공식 기록이 연동되면 교체됩니다.',
        textStyle: WbType.caption.copyWith(color: c.ink),
        actionLabel: '데이터 출처',
        onAction: () => context.push(WbRoutes.dataSources),
      ),
    );
  }
}

/// Seven-day strip with a dot on days that actually have games.
///
/// Sits above the list and inside thumb reach; the "오늘로" action is in the
/// app bar and duplicated by the empty state.
class _DateStrip extends ConsumerWidget {
  const _DateStrip({required this.dayKey, required this.onSelect});

  final String dayKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final selected = DateTime.parse('${dayKey}T00:00:00Z');
    final monthKey = dayKey.substring(0, 7);
    final gameDays =
        ref.watch(_monthGameDaysProvider(monthKey)).value ?? const <String>{};

    final days = <DateTime>[
      for (var i = -3; i <= 3; i++) selected.add(Duration(days: i)),
    ];

    // Each cell stacks three lines, so its height depends on the user's text
    // scale. A horizontal `ListView` needs a bounded height, and any formula
    // for that bound is a guess that eventually clips — scaling a constant got
    // it right at 130% and wrong at 200%. Seven cells are cheap to build, so
    // the strip sizes itself to its content instead.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < days.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: WbSpace.sm),
            Builder(
              builder: (context) {
                final day = days[i];
                final key = Kst.dayKeyOfKstDate(day);
                final isSelected = key == dayKey;
                final hasGames = gameDays.contains(key);

                return Semantics(
                  selected: isSelected,
                  button: true,
                  label:
                      '${day.month}월 ${day.day}일'
                      '${hasGames ? ', 경기 있음' : ', 경기 없음'}',
                  child: ExcludeSemantics(
                    child: Material(
                      color: isSelected ? c.brand : Colors.transparent,
                      borderRadius: WbRadius.chipAll,
                      child: InkWell(
                        onTap: () => onSelect(key),
                        borderRadius: WbRadius.chipAll,
                        child: Container(
                          width: 46,
                          padding: const EdgeInsets.symmetric(
                            vertical: WbSpace.sm,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: WbRadius.chipAll,
                            border: Border.all(
                              color: isSelected ? c.brand : c.divider,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text(
                                _weekdayKo(day.weekday),
                                style: WbType.micro.copyWith(
                                  color: isSelected ? c.surface : c.inkMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${day.day}',
                                style: WbType.tabular.copyWith(
                                  color: isSelected ? c.surface : c.ink,
                                ),
                              ),
                              const SizedBox(height: 3),
                              // A dot, not colour alone: days with fixtures are
                              // distinguishable in greyscale too.
                              Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: hasGames
                                      ? (isSelected ? c.surface : c.action)
                                      : Colors.transparent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  static String _weekdayKo(int weekday) => switch (weekday) {
    DateTime.monday => '월',
    DateTime.tuesday => '화',
    DateTime.wednesday => '수',
    DateTime.thursday => '목',
    DateTime.friday => '금',
    DateTime.saturday => '토',
    _ => '일',
  };
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.state, required this.controller});

  final GamesTabState state;
  final GamesTabController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final competitions = ref.watch(competitionsProvider).value ?? const [];

    // Same rule as the date strip above: a horizontal list needs a bounded
    // height, and a fixed one clips its chips as soon as the user scales text.
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final stripHeight = 52.0 * (scale > 1 ? scale : 1);

    return SizedBox(
      height: stripHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: WbSpace.screen,
          vertical: WbSpace.sm,
        ),
        children: <Widget>[
          WbFilterChip(
            label: '내 팀',
            icon: Icons.star_rounded,
            selected: state.favoritesOnly,
            onTap: controller.toggleFavoritesOnly,
            onRemove: state.favoritesOnly
                ? controller.toggleFavoritesOnly
                : null,
          ),
          const SizedBox(width: WbSpace.sm),
          WbFilterChip(
            label: '국내',
            selected: state.level == CompetitionLevel.domestic,
            onTap: () => controller.setLevel(
              state.level == CompetitionLevel.domestic
                  ? null
                  : CompetitionLevel.domestic,
            ),
          ),
          const SizedBox(width: WbSpace.sm),
          WbFilterChip(
            label: '국제',
            selected: state.level == CompetitionLevel.international,
            onTap: () => controller.setLevel(
              state.level == CompetitionLevel.international
                  ? null
                  : CompetitionLevel.international,
            ),
          ),
          for (final competition in competitions.take(6)) ...<Widget>[
            const SizedBox(width: WbSpace.sm),
            WbFilterChip(
              label: competition.displayName,
              selected: state.competitionIds.contains(competition.id),
              onTap: () => controller.toggleCompetition(competition.id),
              onRemove: state.competitionIds.contains(competition.id)
                  ? () => controller.toggleCompetition(competition.id)
                  : null,
            ),
          ],
          if (state.activeFilterCount > 0) ...<Widget>[
            const SizedBox(width: WbSpace.sm),
            TextButton.icon(
              onPressed: controller.clearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
              label: const Text('초기화'),
            ),
          ],
        ],
      ),
    );
  }
}

class _GamesList extends ConsumerWidget {
  const _GamesList({
    required this.games,
    required this.state,
    required this.now,
  });

  final List<GameCard> games;
  final GamesTabState state;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (games.isEmpty) return _EmptyDay(state: state, now: now);

    final risks = ref
        .watch(
          weatherRisksProvider(
            WeatherRiskQuery.of(<String, DateTime>{
              for (final g in games) g.game.id: g.game.startTimeUtc,
            }),
          ),
        )
        .value;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        0,
        WbSpace.screen,
        WbSpace.xxl,
      ),
      itemCount: games.length,
      itemBuilder: (context, i) {
        final card = games[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: WbSpace.sm),
          child: WbGameRow(
            card: card,
            now: now,
            weatherRisk: risks?[card.game.id],
            onTap: () => context.push(WbRoutes.game(card.game.id)),
          ),
        );
      },
    );
  }
}

/// An empty day is never a dead end.
///
/// It offers the previous and next days that actually have fixtures, so the
/// user never has to tap through blank dates one at a time.
class _EmptyDay extends ConsumerStatefulWidget {
  const _EmptyDay({required this.state, required this.now});

  final GamesTabState state;
  final DateTime now;

  @override
  ConsumerState<_EmptyDay> createState() => _EmptyDayState();
}

class _EmptyDayState extends ConsumerState<_EmptyDay> {
  String? _previous;
  String? _next;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_EmptyDay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.dayKey != widget.state.dayKey) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = ref.read(gameRepositoryProvider);
    final previous = await repo.nextDayWithGames(
      widget.state.dayKey,
      forward: false,
    );
    final next = await repo.nextDayWithGames(widget.state.dayKey);
    if (!mounted) return;
    setState(() {
      _previous = previous;
      _next = next;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final controller = ref.read(gamesTabProvider.notifier);
    final hasFilters = widget.state.activeFilterCount > 0;

    return ListView(
      padding: const EdgeInsets.all(WbSpace.screen),
      children: <Widget>[
        WbEmptyState(
          icon: Icons.event_busy_outlined,
          title: hasFilters ? '조건에 맞는 경기가 없습니다' : '이 날짜에는 경기가 없습니다',
          message: hasFilters
              ? '필터를 지우면 더 많은 경기를 볼 수 있습니다.'
              : '가까운 경기일로 이동해 보세요.',
          primaryLabel: hasFilters ? '필터 초기화' : null,
          onPrimary: hasFilters ? controller.clearFilters : null,
        ),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(WbSpace.lg),
              child: WbSkeleton(width: 200, height: 40),
            ),
          )
        else
          // Wrap, not Row: two Korean button labels do not fit side by side on
          // a 360dp screen, and they must never be clipped.
          Wrap(
            alignment: WrapAlignment.center,
            spacing: WbSpace.sm,
            runSpacing: WbSpace.sm,
            children: <Widget>[
              if (_previous != null)
                OutlinedButton.icon(
                  onPressed: () => controller.setDay(_previous!),
                  icon: const Icon(Icons.chevron_left_rounded, size: 18),
                  label: Text('이전 경기일 ${_shortLabel(_previous!)}'),
                ),
              if (_next != null)
                OutlinedButton.icon(
                  onPressed: () => controller.setDay(_next!),
                  icon: const Icon(Icons.chevron_right_rounded, size: 18),
                  label: Text('다음 경기일 ${_shortLabel(_next!)}'),
                ),
            ],
          ),
        if (!_loading && _previous == null && _next == null)
          Padding(
            padding: const EdgeInsets.only(top: WbSpace.lg),
            child: Text(
              '아직 등록된 경기 일정이 없습니다.\n공식 일정이 공개되면 자동으로 표시됩니다.',
              textAlign: TextAlign.center,
              style: WbType.caption.copyWith(color: c.inkMuted, height: 1.6),
            ),
          ),
      ],
    );
  }

  static String _shortLabel(String dayKey) {
    final parts = dayKey.split('-');
    return '${int.parse(parts[1])}.${int.parse(parts[2])}';
  }
}

/// Explains an automatic date change, and offers the way back.
///
/// Same container shape as `_StandingsDemoNotice` below; both hand the
/// sentence/action arrangement itself to `WbNoticeWithAction`, which decides
/// per build whether the action fits beside the sentence or needs its own
/// line. This one interpolates a date (`KoDate.monthDay`), so its length is
/// not fixed — an earlier hand-written version of this widget assumed a
/// same-row button was always safe here and was wrong: at 2.0x text scale on
/// a 360dp screen it wrapped to four lines and broke "보여드립니다" mid-word.
class _LandedNotice extends StatelessWidget {
  const _LandedNotice({required this.dayKey, required this.onToday});

  final String dayKey;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final day = DateTime.parse('${dayKey}T00:00:00Z');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        WbSpace.sm,
        WbSpace.screen,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: WbSpace.md,
        vertical: WbSpace.xs,
      ),
      decoration: BoxDecoration(
        color: c.brandSoft,
        borderRadius: WbRadius.chipAll,
      ),
      child: WbNoticeWithAction(
        leading: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.event_available_outlined, size: 15, color: c.brand),
        ),
        text: '오늘은 경기가 없어 ${KoDate.monthDay(day)} 일정을 보여드립니다.',
        textStyle: WbType.caption.copyWith(color: c.ink),
        actionLabel: '오늘로',
        onAction: onToday,
      ),
    );
  }
}
