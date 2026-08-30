import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/shell.dart';
import '../../core/analytics/analytics.dart';
import '../../core/design_system/components/game_widgets.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/components/provenance_widgets.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../core/utils/kst.dart';
import '../../data/models/audience.dart';
import '../../data/models/weather.dart';
import '../../data/repositories/game_repository.dart';
import '../discover/widgets/featured_card.dart';
import '../discover/widgets/story_card.dart';
import 'home_modules.dart';

/// The home screen.
///
/// Renders whatever module order [HomeModule.resolveOrder] gives it. Every
/// module reads from the local database, so the first frame is real content —
/// there is no spinner gate and no waiting on the network.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audience = ref.watch(audienceProvider);
    final sync = ref.watch(syncControllerProvider);
    final now = DateTime.now().toUtc();
    final modules = HomeModule.resolveOrder(audience);

    final subtitle = sync.lastSuccessAt == null
        ? '아직 갱신되지 않음'
        : '${KoDate.relative(sync.lastSuccessAt!, now)} 갱신';

    return Scaffold(
      appBar: WbPrimaryAppBar(title: '여자야구', subtitle: subtitle),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(syncControllerProvider.notifier).refresh(force: true);
        },
        child: ListView.builder(
          // Always scrollable so pull-to-refresh works even when short.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: WbSpace.xxl),
          itemCount: modules.length,
          itemBuilder: (context, index) => _HomeModuleView(
            module: modules[index],
            audience: audience,
            now: now,
          ),
        ),
      ),
    );
  }
}

class _HomeModuleView extends ConsumerWidget {
  const _HomeModuleView({
    required this.module,
    required this.audience,
    required this.now,
  });

  final HomeModule module;
  final AudiencePreference audience;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = audience.collapsedModules.contains(module.key);

    if (module == HomeModule.modeNudge) {
      return _ModeNudge(audience: audience);
    }

    // Built even when collapsed: the module is what knows whether it has
    // content, and that decides whether the heading appears at all.
    final body = switch (module) {
      HomeModule.featuredTopic => _FeaturedModule(now: now),
      HomeModule.programRecap => _ProgramRecapModule(now: now),
      HomeModule.weekendNearby => _WeekendNearbyModule(now: now),
      HomeModule.topStories => _StoriesModule(now: now, personalised: false),
      HomeModule.storiesForYou => _StoriesModule(now: now, personalised: true),
      HomeModule.beginnerGuide => const _BeginnerGuideModule(),
      HomeModule.officialVideos => const _VideosModule(),
      HomeModule.myNextGame => _MyNextGameModule(now: now),
      HomeModule.weatherOutlook => _WeatherOutlookModule(now: now),
      HomeModule.scheduleSummary => _ScheduleSummaryModule(now: now),
      HomeModule.myStanding => _MyStandingModule(now: now),
      HomeModule.leaguePulse => _LeaguePulseModule(now: now),
      HomeModule.leaderboardHighlights => const _LeaderboardModule(),
      HomeModule.myTeamNews => _StoriesModule(now: now, personalised: true),
      HomeModule.officialNotices => _NoticesModule(now: now),
      HomeModule.recentResults => _GameListModule(now: now, upcoming: false),
      HomeModule.upcomingGames => _GameListModule(now: now, upcoming: true),
      HomeModule.startPlaying => const _StartPlayingModule(),
      HomeModule.modeNudge => const SizedBox.shrink(),
    };

    // The heading is no longer drawn here. A module knows whether it has
    // anything to show and only it can say so, so it renders its own frame —
    // see [_ModuleFrame]. Drawing the heading unconditionally left eleven
    // modules able to produce a title with blank space under it.
    return _ModuleScope(module: module, collapsed: collapsed, child: body);
  }
}

/// Carries the current module down to the [_ModuleFrame] inside it.
///
/// Passing `module` and `collapsed` through eleven constructors would work and
/// would also be eleven chances to forget one.
class _ModuleScope extends InheritedWidget {
  const _ModuleScope({
    required this.module,
    required this.collapsed,
    required super.child,
  });

  final HomeModule module;
  final bool collapsed;

  static _ModuleScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ModuleScope>();
    assert(scope != null, '_ModuleFrame must be used inside a home module');
    return scope!;
  }

  @override
  bool updateShouldNotify(_ModuleScope oldWidget) =>
      oldWidget.module != module || oldWidget.collapsed != collapsed;
}

/// Placeholder shown while a module's query is still running.
///
/// Loading and "there is nothing" are different answers and used to render the
/// same way: `AsyncValue.value` is null in both cases, so a section vanished
/// while it loaded and then reappeared, moving everything below it. A skeleton
/// keeps the page still and tells the truth about which state it is in.
class _ModuleSkeleton extends StatelessWidget {
  const _ModuleSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: WbSpace.screen),
    child: WbSkeleton(height: 96, borderRadius: WbRadius.cardAll),
  );
}

/// Renders a module from an [AsyncValue], keeping loading distinct from empty.
///
/// `onData` returns null when the settled result really has nothing to show —
/// only then does the section collapse.
Widget? _moduleAsync<T>(
  AsyncValue<T> async,
  Widget? Function(T data) onData, {
  Widget? skeleton,
}) => async.when(
  data: onData,
  loading: () => skeleton ?? const _ModuleSkeleton(),
  // An error is not something to explain in a home module; the source
  // screen reports it. Collapsing is quieter than a red box on the home.
  error: (_, _) => null,
);

/// The heading plus a module's content, or nothing at all.
///
/// Every home module returns one of these. Passing `child: null` is how a
/// module says it has nothing — and what that means is decided here, once,
/// from [HomeModule.statesItsAbsence]: either the whole section disappears, or
/// the heading stays and the absence is stated.
class _ModuleFrame extends StatelessWidget {
  const _ModuleFrame({this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scope = _ModuleScope.of(context);
    final module = scope.module;
    final c = WbTheme.of(context);

    if (child == null && !module.statesItsAbsence) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ModuleHeader(module: module, collapsed: scope.collapsed),
        if (!scope.collapsed)
          child ??
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  WbSpace.screen,
                  0,
                  WbSpace.screen,
                  WbSpace.sm,
                ),
                child: Text(
                  module.emptyMessageKo,
                  style: WbType.body.copyWith(color: c.inkMuted, height: 1.5),
                ),
              ),
      ],
    );
  }
}

class _ModuleHeader extends ConsumerWidget {
  const _ModuleHeader({required this.module, required this.collapsed});

  final HomeModule module;
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final density = WbDensityScope.of(context);
    return Padding(
      // The gap above a module heading is the strongest density lever on this
      // screen: it decides how many modules a user sees before scrolling.
      padding: EdgeInsets.fromLTRB(
        WbSpace.screen,
        density.sectionGap,
        WbSpace.sm,
        density.blockGap,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              module.titleKo,
              style: WbType.section.copyWith(color: c.ink),
            ),
          ),
          if (module.isCollapsible)
            WbTapTarget(
              onTap: () => ref
                  .read(audienceControllerProvider)
                  .toggleModuleCollapsed(module.key),
              semanticLabel: collapsed
                  ? '${module.titleKo} 펼치기'
                  : '${module.titleKo} 접기',
              child: Icon(
                collapsed
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_up_rounded,
                size: 20,
                color: c.inkMuted,
              ),
            ),
        ],
      ),
    );
  }
}

/// A quiet way back to mode selection for users who skipped onboarding.
class _ModeNudge extends ConsumerWidget {
  const _ModeNudge({required this.audience});

  final AudiencePreference audience;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        WbSpace.md,
        WbSpace.screen,
        0,
      ),
      child: Material(
        color: c.brandSoft,
        borderRadius: WbRadius.chipAll,
        child: InkWell(
          borderRadius: WbRadius.chipAll,
          onTap: () => _showModeSheet(context, ref, audience),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WbSpace.md,
              vertical: WbSpace.sm,
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.tune_rounded, size: 15, color: c.brand),
                const SizedBox(width: WbSpace.sm),
                Expanded(
                  child: Text(
                    '지금 화면: ${audience.mode.shortLabelKo}',
                    style: WbType.caption.copyWith(color: c.ink),
                  ),
                ),
                Text(
                  '바꾸기',
                  style: WbType.captionStrong.copyWith(color: c.brand),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showModeSheet(
    BuildContext context,
    WidgetRef ref,
    AudiencePreference audience,
  ) async {
    final c = WbTheme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WbSpace.screen,
            0,
            WbSpace.screen,
            WbSpace.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('시작 화면', style: WbType.section.copyWith(color: c.ink)),
              const SizedBox(height: WbSpace.xs),
              Text(
                '홈 순서만 달라집니다. 기능은 잠기지 않아요.',
                style: WbType.caption.copyWith(color: c.inkMuted),
              ),
              const SizedBox(height: WbSpace.md),
              for (final mode in AudienceMode.values)
                RadioListTile<AudienceMode>(
                  value: mode,
                  // ignore: deprecated_member_use
                  groupValue: audience.mode,
                  // ignore: deprecated_member_use
                  onChanged: (value) async {
                    if (value == null) return;
                    await ref.read(audienceControllerProvider).setMode(value);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  title: Text(mode.labelKo, style: WbType.body),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Discover-leaning modules
// ---------------------------------------------------------------------------

class _FeaturedModule extends ConsumerWidget {
  const _FeaturedModule({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _ModuleFrame(child: _content(context, ref));

  /// Null means "nothing to show". [_ModuleFrame] decides what that looks
  /// like; this method only reports it.
  Widget? _content(BuildContext context, WidgetRef ref) {
    final featured = ref.watch(featuredProvider);
    final policy = ref.watch(spoilerPolicyProvider);

    return featured.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: WbSpace.screen),
        child: WbSkeleton(height: 180, borderRadius: WbRadius.heroAll),
      ),
      error: (_, _) => null,
      data: (items) {
        if (items.isEmpty) {
          // A season ending must not leave a hole. When nothing is active the
          // module explains itself and points at what is available.
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
            child: WbEmptyState(
              compact: true,
              icon: Icons.local_fire_department_outlined,
              title: '지금 진행 중인 화제 콘텐츠가 없습니다',
              message: '새 방송이나 대회가 시작되면 여기에 표시됩니다. 그동안 다가오는 경기를 살펴보세요.',
              primaryLabel: '경기 보기',
              onPrimary: () => context.go(WbRoutes.games),
            ),
          );
        }
        final lead = items.first;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
          child: FeaturedHeroCard(
            item: lead,
            policy: policy,
            now: now,
            onTap: () {
              ref
                  .read(analyticsProvider)
                  .log(
                    AnalyticsEvent.featuredTopicOpened,
                    properties: <String, Object?>{'screen': 'home'},
                  );
              context.push(WbRoutes.featuredTopic(lead.topic.id));
            },
          ),
        );
      },
    );
  }
}

class _ProgramRecapModule extends ConsumerWidget {
  const _ProgramRecapModule({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _ModuleFrame(child: _content(context, ref));

  /// Null means "nothing to show". [_ModuleFrame] decides what that looks
  /// like; this method only reports it.
  Widget? _content(BuildContext context, WidgetRef ref) {
    final featured = ref.watch(featuredProvider);
    final policy = ref.watch(spoilerPolicyProvider);

    return _moduleAsync(featured, (items) {
      final withRecap = items
          .where((i) => i.latestRecap != null && i.program != null)
          .toList();
      if (withRecap.isEmpty) return null;
      final item = withRecap.first;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
        child: ProgramRecapCard(
          item: item,
          policy: policy,
          now: now,
          onTap: () => context.push(WbRoutes.featuredTopic(item.topic.id)),
        ),
      );
    });
  }
}

class _WeekendNearbyModule extends ConsumerWidget {
  const _WeekendNearbyModule({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _ModuleFrame(child: _content(context, ref));

  /// Null means "nothing to show". [_ModuleFrame] decides what that looks
  /// like; this method only reports it.
  Widget? _content(BuildContext context, WidgetRef ref) {
    final audience = ref.watch(audienceProvider);
    final weekend = Kst.upcomingWeekendUtc(now);
    final query = GameQuery(
      fromUtc: weekend.startUtc,
      toUtc: weekend.endUtc,
      regionCodes: audience.regionCode == null
          ? const []
          : <String>[audience.regionCode!],
      limit: 3,
    );
    final games = ref.watch(gamesProvider(query));

    return games.when(
      loading: () => const _RowSkeletons(count: 2),
      error: (_, _) => null,
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
            child: WbEmptyState(
              compact: true,
              icon: Icons.event_available_outlined,
              title: audience.hasRegion
                  ? '${audience.regionLabel ?? '선택한 지역'}에 이번 주말 경기가 없습니다'
                  : '이번 주말 등록된 경기가 없습니다',
              message: audience.hasRegion
                  ? '지역을 넓히거나 다른 날짜의 경기를 확인해 보세요.'
                  : '지역을 설정하면 가까운 경기를 먼저 보여드립니다.',
              primaryLabel: '근처 경기 찾기',
              onPrimary: () => context.push(WbRoutes.nearby),
            ),
          );
        }
        return Column(
          children: <Widget>[
            for (final card in list)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  WbSpace.screen,
                  0,
                  WbSpace.screen,
                  WbSpace.sm,
                ),
                child: WbGameRow(
                  card: card,
                  now: now,
                  showDate: true,
                  onTap: () => context.push(WbRoutes.game(card.game.id)),
                ),
              ),
            _SeeAllButton(
              label: '근처 경기 전체 보기',
              onTap: () => context.push(WbRoutes.nearby),
            ),
          ],
        );
      },
    );
  }
}

class _StoriesModule extends ConsumerWidget {
  const _StoriesModule({required this.now, required this.personalised});

  final DateTime now;
  final bool personalised;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _ModuleFrame(child: _content(context, ref));

  /// Null means "nothing to show". [_ModuleFrame] decides what that looks
  /// like; this method only reports it.
  Widget? _content(BuildContext context, WidgetRef ref) {
    final stories = personalised
        ? ref.watch(storiesForYouProvider)
        : ref.watch(topStoriesProvider);
    final showBeginner = ref.watch(showBeginnerExplanationsProvider);

    return stories.when(
      loading: () => const _RowSkeletons(count: 2),
      error: (_, _) => null,
      data: (list) {
        if (list.isEmpty) return null;
        return Column(
          children: <Widget>[
            for (final cluster in list.take(3))
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  WbSpace.screen,
                  0,
                  WbSpace.screen,
                  WbSpace.sm,
                ),
                child: StoryClusterCard(
                  cluster: cluster,
                  now: now,
                  showBeginnerContext: showBeginner,
                  onTap: () => context.push(WbRoutes.story(cluster.id)),
                ),
              ),
            if (list.length > 3)
              _SeeAllButton(
                label: '뉴스 전체 보기',
                onTap: () => context.go(WbRoutes.discover),
              ),
          ],
        );
      },
    );
  }
}

class _BeginnerGuideModule extends ConsumerWidget {
  const _BeginnerGuideModule();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _ModuleFrame(child: _content(context, ref));

  /// Null means "nothing to show". [_ModuleFrame] decides what that looks
  /// like; this method only reports it.
  Widget? _content(BuildContext context, WidgetRef ref) {
    final guides = ref.watch(_guidesProvider);
    return guides.when(
      loading: () => const _RowSkeletons(count: 1),
      error: (_, _) => null,
      data: (list) {
        if (list.isEmpty) return null;
        final guide = list.first;
        final c = WbTheme.of(context);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
          child: WbCard(
            onTap: () => context.push(WbRoutes.guide(guide.id)),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.verifiedSoft,
                    borderRadius: WbRadius.chipAll,
                  ),
                  child: Icon(
                    Icons.school_outlined,
                    size: 20,
                    color: c.verified,
                  ),
                ),
                const SizedBox(width: WbSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        guide.title,
                        style: WbType.headline.copyWith(color: c.ink),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (guide.readSeconds != null) ...<Widget>[
                        const SizedBox(height: WbSpace.xxs),
                        Text(
                          '${guide.readSeconds}초면 읽어요',
                          style: WbType.micro.copyWith(color: c.inkMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.inkMuted),
              ],
            ),
          ),
        );
      },
    );
  }
}

final _guidesProvider = StreamProvider.autoDispose((ref) {
  return ref.watch(contentRepositoryProvider).watchGuides();
});

final _videosProvider = StreamProvider.autoDispose((ref) {
  return ref.watch(contentRepositoryProvider).watchVideos(limit: 6);
});

final _noticesProvider = StreamProvider.autoDispose((ref) {
  return ref.watch(contentRepositoryProvider).watchNotices(limit: 3);
});

class _VideosModule extends ConsumerWidget {
  const _VideosModule();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _ModuleFrame(child: _content(context, ref));

  /// Null means "nothing to show". [_ModuleFrame] decides what that looks
  /// like; this method only reports it.
  Widget? _content(BuildContext context, WidgetRef ref) {
    final videos = ref.watch(_videosProvider);
    final c = WbTheme.of(context);

    return _moduleAsync(videos, (list) {
      if (list.isEmpty) return null;
      return SizedBox(
        height: 132,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(width: WbSpace.md),
          itemBuilder: (context, i) {
            final video = list[i];
            return SizedBox(
              width: 220,
              child: WbCard(
                padding: const EdgeInsets.all(WbSpace.md),
                onTap: () => openSource(
                  context,
                  url: video.url,
                  title: video.title,
                  sourceLabel: video.channelName ?? '공식 영상',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.play_circle_outline_rounded,
                          size: 16,
                          color: c.action,
                        ),
                        const SizedBox(width: WbSpace.xs),
                        Expanded(
                          child: Text(
                            video.channelName ?? '공식 채널',
                            style: WbType.micro.copyWith(color: c.inkMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: WbSpace.sm),
                    Expanded(
                      child: Text(
                        video.title,
                        style: WbType.bodyStrong.copyWith(color: c.ink),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Player-leaning modules
// ---------------------------------------------------------------------------

class _MyNextGameModule extends ConsumerWidget {
  const _MyNextGameModule({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _ModuleFrame(child: _content(context, ref));

  /// Null means "nothing to show". [_ModuleFrame] decides what that looks
  /// like; this method only reports it.
  Widget? _content(BuildContext context, WidgetRef ref) {
    final next = ref.watch(nextGameProvider);
    final followed =
        ref.watch(followedTeamIdsProvider).value ?? const <String>{};

    return next.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: WbSpace.screen),
        child: WbSkeleton(height: 170, borderRadius: WbRadius.heroAll),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
        child: WbEmptyState(
          compact: true,
          icon: Icons.error_outline_rounded,
          tone: WbBadgeTone.danger,
          title: '경기 정보를 불러오지 못했습니다',
          message: '저장된 데이터로 다른 화면은 계속 사용할 수 있습니다.',
          primaryLabel: '다시 시도',
          onPrimary: () =>
              ref.read(syncControllerProvider.notifier).refresh(force: true),
        ),
      ),
      data: (summary) {
        if (summary == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
            child: WbEmptyState(
              compact: true,
              icon: Icons.event_note_outlined,
              title: '예정된 경기가 없습니다',
              message: followed.isEmpty
                  ? '팀을 팔로우하면 다음 경기를 여기에서 먼저 보여드립니다.'
                  : '팔로우한 팀의 다음 일정이 아직 등록되지 않았습니다.',
              primaryLabel: followed.isEmpty ? '팀 찾기' : '전체 일정 보기',
              onPrimary: () => context.push(
                followed.isEmpty ? WbRoutes.teams : WbRoutes.games,
              ),
            ),
          );
        }

        final card = summary.card;
        final risks = ref.watch(
          weatherRisksProvider(
            WeatherRiskQuery.of(<String, DateTime>{
              card.game.id: card.game.startTimeUtc,
            }),
          ),
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
          child: WbHeroGameCard(
            card: card,
            now: now,
            isFavoriteDriven: summary.isFavoriteDriven,
            weatherRisk: risks.value?[card.game.id],
            onTap: () => context.push(WbRoutes.game(card.game.id)),
            onToggleFollow: () async {
              await ref
                  .read(followRepositoryProvider)
                  .toggleFollow(
                    FollowKind.team,
                    card.homeTeam.id,
                    label: card.homeTeam.displayName,
                  );
              await ref.read(platformServicesProvider).haptics.selection();
            },
          ),
        );
      },
    );
  }
}

class _WeatherOutlookModule extends ConsumerWidget {
  const _WeatherOutlookModule({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _ModuleFrame(child: _content(context, ref));

  /// Null means "nothing to show". [_ModuleFrame] decides what that looks
  /// like; this method only reports it.
  Widget? _content(BuildContext context, WidgetRef ref) {
    final next = ref.watch(nextGameProvider).value;
    if (next == null) return null;

    final game = next.card.game;
    final forecast = ref.watch(gameWeatherProvider(game.id));
    final horizon = ForecastHorizon.between(now, game.startTimeUtc);
    final c = WbTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
      child: WbCard(
        onTap: () => context.push(WbRoutes.game(game.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Wrap, not Row: at large text sizes the date and the forecast-
            // horizon badge no longer fit on one 360dp line, and neither may be
            // clipped — the badge is what stops a mid-range forecast being read
            // as a precise one.
            Wrap(
              spacing: WbSpace.sm,
              runSpacing: WbSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  KoDate.monthDayWeekday(game.startTimeUtc),
                  style: WbType.bodyStrong.copyWith(color: c.ink),
                ),
                WbBadge(
                  label: horizon.labelKo,
                  tone: horizon == ForecastHorizon.beyondForecast
                      ? WbBadgeTone.muted
                      : WbBadgeTone.neutral,
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: WbSpace.sm),
            forecast.when(
              loading: () => const WbSkeleton(width: 180, height: 16),
              error: (_, _) => Text(
                '날씨 정보를 불러오지 못했습니다.',
                style: WbType.caption.copyWith(color: c.inkMuted),
              ),
              data: (value) =>
                  _WeatherSummaryLine(forecast: value, horizon: horizon),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders exactly what the horizon permits and nothing more.
class _WeatherSummaryLine extends StatelessWidget {
  const _WeatherSummaryLine({required this.forecast, required this.horizon});

  final WeatherForecast? forecast;
  final ForecastHorizon horizon;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);

    // Past D+10 there is no daily forecast to show. We say so plainly instead
    // of rendering an icon that would imply knowledge we do not have.
    if (horizon == ForecastHorizon.beyondForecast) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.schedule_rounded, size: 15, color: c.inkMuted),
          const SizedBox(width: WbSpace.sm),
          Expanded(
            child: Text(
              forecast?.seasonalTendency ?? horizon.explanationKo,
              style: WbType.caption.copyWith(color: c.inkMuted, height: 1.5),
            ),
          ),
        ],
      );
    }

    final f = forecast;
    if (f == null) {
      return Text(
        '이 경기의 예보가 아직 저장되지 않았습니다.',
        style: WbType.caption.copyWith(color: c.inkMuted),
      );
    }

    final risk = WeatherRisk.evaluate(f);
    final range = f.displayTemperatureRange;
    final exact = f.displayTemperature;
    final pop = f.displayPrecipitationProbability;

    final parts = <String>[
      if (exact != null) '${exact.toStringAsFixed(0)}℃',
      if (exact == null && range != null)
        '${range.min.toStringAsFixed(0)}~${range.max.toStringAsFixed(0)}℃',
      if (pop != null) '강수 $pop%',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (risk.level != WeatherRiskLevel.clear) ...<Widget>[
              WbWeatherRiskBadge(risk: risk),
              const SizedBox(width: WbSpace.sm),
            ],
            Flexible(
              child: Text(
                parts.isEmpty ? '예보 값이 없습니다' : parts.join(' · '),
                style: WbType.body.copyWith(color: c.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: WbSpace.xs),
        Text(
          '${f.forecastZone ?? '예보구역 미상'} · '
          '${KoDate.dateTime(f.issuedAt)} 발표 · ${f.confidence.labelKo}',
          style: WbType.micro.copyWith(color: c.inkMuted),
        ),
      ],
    );
  }
}

class _ScheduleSummaryModule extends ConsumerWidget {
  const _ScheduleSummaryModule({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _ModuleFrame(child: _content(context, ref));

  /// Null means "nothing to show". [_ModuleFrame] decides what that looks
  /// like; this method only reports it.
  Widget? _content(BuildContext context, WidgetRef ref) {
    final followed =
        ref.watch(followedTeamIdsProvider).value ?? const <String>{};
    // Day-aligned bounds: a raw `now` would change the family key every frame.
    final from = Kst.startOfKstDayUtc(now);
    final query = GameQuery(
      fromUtc: from,
      toUtc: from.add(const Duration(days: 31)),
      teamIds: followed.toList()..sort(),
      limit: 30,
    );
    final games = ref.watch(gamesProvider(query));
    final c = WbTheme.of(context);

    return _moduleAsync(
      games,
      (list) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
        child: WbCard(
          onTap: () => context.push(WbRoutes.scheduleBoard),
          child: Row(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${list.length}경기',
                    style: WbType.scoreRow.copyWith(color: c.ink),
                  ),
                  Text('예정', style: WbType.micro.copyWith(color: c.inkMuted)),
                ],
              ),
              const SizedBox(width: WbSpace.lg),
              Expanded(
                child: Text(
                  list.isEmpty
                      ? '등록된 일정이 없습니다. 달력에서 다른 대회 일정을 확인해 보세요.'
                      : '달력에서 경기일과 날씨 위험을 한 번에 확인할 수 있습니다.',
                  style: WbType.caption.copyWith(
                    color: c.inkMuted,
                    height: 1.5,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.inkMuted),
            ],
          ),
        ),
      ),
      skeleton: const _RowSkeletons(count: 1),
    );
  }
}

class _MyStandingModule extends ConsumerWidget {
  const _MyStandingModule({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _ModuleFrame(child: _content(context, ref));

  /// Null means "nothing to show". [_ModuleFrame] decides what that looks
  /// like; this method only reports it.
  Widget? _content(BuildContext context, WidgetRef ref) {
    final followed =
        ref.watch(followedTeamIdsProvider).value ?? const <String>{};
    if (followed.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
        child: WbEmptyState(
          compact: true,
          icon: Icons.emoji_events_outlined,
          title: '팀을 선택하면 순위를 보여드립니다',
          primaryLabel: '팀 찾기',
          onPrimary: () => context.push(WbRoutes.teams),
        ),
      );
    }
    final detail = ref.watch(teamDetailProvider(followed.first));
    final c = WbTheme.of(context);

    return _moduleAsync(detail, (team) {
      if (team == null || team.standings.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
          child: WbEmptyState(
            compact: true,
            icon: Icons.emoji_events_outlined,
            title: '순위 정보가 아직 없습니다',
            message: '대회가 시작되면 순위와 최근 흐름을 보여드립니다.',
          ),
        );
      }
      final snapshot = team.standings.first;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
        child: WbCard(
          accentColor: WbTeamMark.parseHex(team.team.colorHex),
          onTap: () => context.push(WbRoutes.team(team.team.id)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      team.team.displayName,
                      style: WbType.headline.copyWith(color: c.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (snapshot.rank != null)
                    Text(
                      '${snapshot.rank}위',
                      style: WbType.scoreRow.copyWith(color: c.brand),
                    ),
                ],
              ),
              const SizedBox(height: WbSpace.sm),
              Text(
                '${snapshot.played}경기 ${snapshot.wins}승 ${snapshot.losses}패'
                '${snapshot.draws > 0 ? ' ${snapshot.draws}무' : ''}',
                style: WbType.tabular.copyWith(color: c.ink),
              ),
              const SizedBox(height: WbSpace.sm),
              WbSourceLine(provenance: snapshot.provenance, now: now),
            ],
          ),
        ),
      );
    }, skeleton: const _RowSkeletons(count: 1));
  }
}

class _LeaguePulseModule extends ConsumerWidget {
  const _LeaguePulseModule({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _ModuleFrame(child: _content(context, ref));

  /// Null means "nothing to show". [_ModuleFrame] decides what that looks
  /// like; this method only reports it.
  Widget? _content(BuildContext context, WidgetRef ref) {
    // Read straight from `ref` rather than nesting a `Consumer`. The nested
    // builder had to return a non-null Widget, which is what forced empty
    // states to be drawn as blank space under a heading.
    //
    // Each hop keeps its loading state, so the section holds its place instead
    // of disappearing and popping back as the chain resolves.
    return _moduleAsync(ref.watch(competitionsProvider), (competitions) {
      if (competitions.isEmpty) return null;
      return _moduleAsync(ref.watch(_firstSeasonProvider), (seasonId) {
        if (seasonId == null) return null;
        return _moduleAsync(ref.watch(leaguePulseProvider(seasonId)), (value) {
          if (value == null) return null;

          final c = WbTheme.of(context);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
            child: WbCard(
              onTap: () => context.push(WbRoutes.competition(seasonId)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    value.competitionName,
                    style: WbType.headline.copyWith(color: c.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: WbSpace.xs),
                  Text(
                    value.headlineKo,
                    style: WbType.caption.copyWith(color: c.inkMuted),
                  ),
                  if (value.progress != null) ...<Widget>[
                    const SizedBox(height: WbSpace.md),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: value.progress,
                        minHeight: 5,
                        backgroundColor: c.divider,
                        valueColor: AlwaysStoppedAnimation<Color>(c.brand),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        });
      });
    });
  }
}

/// The season the league-pulse and leaderboard modules describe.
final _firstSeasonProvider = FutureProvider.autoDispose<String?>((ref) async {
  final competitions = await ref.watch(competitionsProvider.future);
  if (competitions.isEmpty) return null;
  final seasons = await ref
      .watch(competitionRepositoryProvider)
      .watchSeasons(competitions.first.id)
      .first;
  return seasons.isEmpty ? null : seasons.first.id;
});

class _LeaderboardModule extends ConsumerWidget {
  const _LeaderboardModule();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _ModuleFrame(child: _content(context, ref));

  /// Null means "nothing to show". [_ModuleFrame] decides what that looks
  /// like; this method only reports it.
  Widget? _content(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);

    // The season lookup is itself async; reading `.value` here made the whole
    // section vanish while it resolved, and it never came back in a test that
    // stopped pumping first.
    return _moduleAsync(ref.watch(_firstSeasonProvider), (seasonId) {
      if (seasonId == null) return null;
      return _moduleAsync(ref.watch(leaderboardsProvider(seasonId)), (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
            child: WbEmptyState(
              compact: true,
              icon: Icons.leaderboard_outlined,
              title: '공개된 개인 기록이 아직 없습니다',
              message: '공식 기록지가 등록되면 부문별 순위를 보여드립니다.',
            ),
          );
        }
        return Column(
          children: <Widget>[
            for (final board in list.take(2))
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  WbSpace.screen,
                  0,
                  WbSpace.screen,
                  WbSpace.sm,
                ),
                child: WbCard(
                  onTap: () => context.push(WbRoutes.leaderboard(seasonId)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        board.definition.fullLabelKo,
                        style: WbType.captionStrong.copyWith(color: c.brand),
                      ),
                      const SizedBox(height: WbSpace.sm),
                      for (final entry in board.entries.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: WbSpace.xs),
                          child: Row(
                            children: <Widget>[
                              SizedBox(
                                width: 22,
                                child: Text(
                                  '${entry.rank ?? '-'}',
                                  style: WbType.tabularSmall.copyWith(
                                    color: c.inkMuted,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  entry.playerName,
                                  style: WbType.body.copyWith(color: c.ink),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                board.definition.format(entry.value),
                                style: WbType.tabular.copyWith(color: c.ink),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: WbSpace.xs),
                      WbCoverageNote(coverage: board.coverage, dense: true),
                    ],
                  ),
                ),
              ),
          ],
        );
      }, skeleton: const _RowSkeletons(count: 1));
    });
  }
}

class _NoticesModule extends ConsumerWidget {
  const _NoticesModule({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _ModuleFrame(child: _content(context, ref));

  /// Null means "nothing to show". [_ModuleFrame] decides what that looks
  /// like; this method only reports it.
  Widget? _content(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(_noticesProvider);
    final c = WbTheme.of(context);

    return _moduleAsync(notices, (list) {
      if (list.isEmpty) return null;
      return Column(
        children: <Widget>[
          for (final article in list)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WbSpace.screen,
                0,
                WbSpace.screen,
                WbSpace.sm,
              ),
              child: WbCard(
                onTap: () => openSource(
                  context,
                  url: article.url,
                  title: article.title,
                  sourceLabel: article.outlet ?? '공식 공지',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const WbBadge(
                          label: '공지',
                          tone: WbBadgeTone.neutral,
                          dense: true,
                        ),
                        const SizedBox(width: WbSpace.sm),
                        Text(
                          KoDate.monthDay(article.publishedAt),
                          style: WbType.micro.copyWith(color: c.inkMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: WbSpace.sm),
                    Text(
                      article.title,
                      style: WbType.bodyStrong.copyWith(color: c.ink),
                      maxLines: WbClamp.articleTitle,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: WbSpace.sm),
                    WbSourceLine(provenance: article.provenance, now: now),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _GameListModule extends ConsumerWidget {
  const _GameListModule({required this.now, required this.upcoming});

  final DateTime now;
  final bool upcoming;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _ModuleFrame(child: _content(context, ref));

  /// Null means "nothing to show". [_ModuleFrame] decides what that looks
  /// like; this method only reports it.
  Widget? _content(BuildContext context, WidgetRef ref) {
    // Hour-aligned so the key is stable between rebuilds.
    final bound = Kst.hourBucket(now);
    final query = upcoming
        ? GameQuery(fromUtc: bound, limit: 3)
        : GameQuery(toUtc: bound, ascending: false, limit: 3);
    final games = ref.watch(gamesProvider(query));

    return games.when(
      loading: () => const _RowSkeletons(count: 3),
      error: (_, _) => null,
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
            child: WbEmptyState(
              compact: true,
              icon: Icons.sports_baseball_outlined,
              title: upcoming ? '예정된 경기가 없습니다' : '최근 경기 결과가 없습니다',
              message: '데이터가 등록되면 여기에 표시됩니다.',
              primaryLabel: '전체 일정 보기',
              onPrimary: () => context.go(WbRoutes.games),
            ),
          );
        }
        return Column(
          children: <Widget>[
            for (final card in list)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  WbSpace.screen,
                  0,
                  WbSpace.screen,
                  WbSpace.sm,
                ),
                child: WbGameRow(
                  card: card,
                  now: now,
                  showDate: true,
                  onTap: () => context.push(WbRoutes.game(card.game.id)),
                ),
              ),
            _SeeAllButton(
              label: upcoming ? '일정 전체 보기' : '결과 전체 보기',
              onTap: () => context.go(WbRoutes.games),
            ),
          ],
        );
      },
    );
  }
}

class _StartPlayingModule extends StatelessWidget {
  const _StartPlayingModule();

  @override
  Widget build(BuildContext context) => _ModuleFrame(child: _content(context));

  /// Null means "nothing to show".
  Widget? _content(BuildContext context) {
    final c = WbTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
      child: WbCard(
        emphasized: true,
        onTap: () => context.push(WbRoutes.teams),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '직접 해보고 싶다면',
              style: WbType.captionStrong.copyWith(color: c.action),
            ),
            const SizedBox(height: WbSpace.xs),
            Text('가까운 여자야구팀 찾기', style: WbType.title.copyWith(color: c.ink)),
            const SizedBox(height: WbSpace.sm),
            Text(
              '지역별로 모집 중인 팀과 문의 방법을 볼 수 있어요. 초보 환영 팀도 있습니다.',
              style: WbType.caption.copyWith(color: c.inkMuted, height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeeAllButton extends StatelessWidget {
  const _SeeAllButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(onPressed: onTap, child: Text(label)),
      ),
    );
  }
}

class _RowSkeletons extends StatelessWidget {
  const _RowSkeletons({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (var i = 0; i < count; i++)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              WbSpace.screen,
              0,
              WbSpace.screen,
              WbSpace.sm,
            ),
            child: WbGameRowSkeleton(),
          ),
      ],
    );
  }
}
