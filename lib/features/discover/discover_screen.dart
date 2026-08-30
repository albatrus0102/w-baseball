import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/shell.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../data/models/domain.dart';
import 'widgets/featured_card.dart';
import 'widgets/story_card.dart';

/// The entry point for people new to women's baseball.
///
/// Layout rhythm is deliberately varied — a tall editorial hero, a horizontal
/// rail, a quiet list — so it does not read as an endless stack of identical
/// rounded cards.
///
/// The two news sections are separate on purpose: `모두가 알아둘 주요 소식` is
/// identical for everyone, and `내 관심 소식` is personalised. Keeping both
/// visible is what stops a follow-driven feed becoming a filter bubble.
class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now().toUtc();
    final policy = ref.watch(spoilerPolicyProvider);
    final showBeginner = ref.watch(showBeginnerExplanationsProvider);
    final audience = ref.watch(audienceProvider);

    final featured = ref.watch(featuredProvider);
    final topStories = ref.watch(topStoriesProvider);
    final forYou = ref.watch(storiesForYouProvider);

    return Scaffold(
      appBar: const WbPrimaryAppBar(title: '발견', subtitle: '지금 여자야구에서 일어나는 일'),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(syncControllerProvider.notifier).refresh(force: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            // 1. Featured topic — the rotating lead slot.
            SliverToBoxAdapter(
              child: featured.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(WbSpace.screen),
                  child: WbSkeleton(
                    height: 200,
                    borderRadius: WbRadius.heroAll,
                  ),
                ),
                error: (_, _) => const SizedBox.shrink(),
                data: (items) {
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(WbSpace.screen),
                      child: WbEmptyState(
                        icon: Icons.explore_outlined,
                        title: '지금은 소개할 화제 콘텐츠가 없습니다',
                        message:
                            '새 방송이나 대회가 시작되면 가장 먼저 보여드립니다.\n'
                            '그동안 근처 경기와 팀을 둘러보세요.',
                        primaryLabel: '근처 경기 보기',
                        onPrimary: () => context.push(WbRoutes.nearby),
                        secondaryLabel: '팀 찾기',
                        onSecondary: () => context.push(WbRoutes.teams),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WbSpace.screen,
                      WbSpace.md,
                      WbSpace.screen,
                      0,
                    ),
                    child: FeaturedHeroCard(
                      item: items.first,
                      policy: policy,
                      now: now,
                      onTap: () => context.push(
                        WbRoutes.featuredTopic(items.first.topic.id),
                      ),
                    ),
                  );
                },
              ),
            ),

            // 2. Quick actions — a different visual rhythm from the hero.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  WbSpace.screen,
                  WbSpace.lg,
                  WbSpace.screen,
                  0,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.place_outlined,
                        label: '근처 경기',
                        caption: audience.regionLabel ?? '지역 선택',
                        onTap: () => context.push(WbRoutes.nearby),
                      ),
                    ),
                    const SizedBox(width: WbSpace.md),
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.groups_outlined,
                        label: '팀 찾기',
                        caption: '모집 중인 팀',
                        onTap: () => context.push(WbRoutes.teams),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. Other featured topics as a horizontal rail.
            featured.maybeWhen(
              data: (items) {
                final rest = items.skip(1).toList();
                if (rest.isEmpty) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                return SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const WbSectionHeader(title: '더 볼 만한 주제'),
                      SizedBox(
                        height: 140,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: WbSpace.screen,
                          ),
                          itemCount: rest.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: WbSpace.md),
                          itemBuilder: (context, i) {
                            final item = rest[i];
                            return SizedBox(
                              width: 230,
                              child: WbCard(
                                onTap: () => context.push(
                                  WbRoutes.featuredTopic(item.topic.id),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      item.topic.title,
                                      style: WbType.bodyStrong,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: WbSpace.xs),
                                    if (item.topic.subtitle != null)
                                      Expanded(
                                        child: Text(
                                          item.topic.subtitle!,
                                          style: WbType.caption.copyWith(
                                            color: WbTheme.of(context).inkMuted,
                                          ),
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
                      ),
                    ],
                  ),
                );
              },
              orElse: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            // 4. Non-personalised top stories.
            SliverToBoxAdapter(
              child: WbSectionHeader(
                title: '모두가 알아둘 주요 소식',
                subtitle: showBeginner ? '팔로우와 무관하게 같은 소식을 보여드립니다.' : null,
              ),
            ),
            _StorySliver(
              stories: topStories,
              now: now,
              showBeginner: showBeginner,
              emptyTitle: '주요 소식이 아직 없습니다',
            ),

            // 5. Personalised.
            SliverToBoxAdapter(
              child: WbSectionHeader(
                title: '내 관심 소식',
                subtitle: '팔로우한 팀·인물과 관련된 소식이 위로 올라옵니다.',
                actionLabel: '팔로우 관리',
                onAction: () => context.push(WbRoutes.notifications),
              ),
            ),
            _StorySliver(
              stories: forYou,
              now: now,
              showBeginner: showBeginner,
              emptyTitle: '표시할 소식이 없습니다',
            ),

            const SliverToBoxAdapter(child: SizedBox(height: WbSpace.xxl)),
          ],
        ),
      ),
    );
  }
}

class _StorySliver extends StatelessWidget {
  const _StorySliver({
    required this.stories,
    required this.now,
    required this.showBeginner,
    required this.emptyTitle,
  });

  final AsyncValue<List<dynamic>> stories;
  final DateTime now;
  final bool showBeginner;
  final String emptyTitle;

  @override
  Widget build(BuildContext context) {
    return stories.when(
      loading: () => SliverList.builder(
        itemCount: 2,
        itemBuilder: (context, _) => const Padding(
          padding: EdgeInsets.fromLTRB(
            WbSpace.screen,
            0,
            WbSpace.screen,
            WbSpace.sm,
          ),
          child: WbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                WbSkeleton(width: 90, height: 12),
                SizedBox(height: WbSpace.md),
                WbSkeleton(height: 18),
                SizedBox(height: WbSpace.sm),
                WbSkeleton(width: 200, height: 18),
              ],
            ),
          ),
        ),
      ),
      error: (_, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(WbSpace.screen),
          child: WbEmptyState(
            compact: true,
            tone: WbBadgeTone.danger,
            icon: Icons.cloud_off_rounded,
            title: '소식을 불러오지 못했습니다',
            message: '저장된 데이터는 계속 볼 수 있습니다.',
          ),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
              child: WbEmptyState(
                compact: true,
                icon: Icons.newspaper_outlined,
                title: emptyTitle,
                message: '새 소식이 수집되면 여기에 묶어서 보여드립니다.',
              ),
            ),
          );
        }
        return SliverList.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final cluster = list[i];
            return Padding(
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
            );
          },
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return WbCard(
      onTap: onTap,
      padding: const EdgeInsets.all(WbSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: c.brand),
          const SizedBox(height: WbSpace.sm),
          Text(label, style: WbType.bodyStrong.copyWith(color: c.ink)),
          const SizedBox(height: WbSpace.xxs),
          Text(
            caption,
            style: WbType.micro.copyWith(color: c.inkMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Shared "watch this game" reasons used by nearby-game cards.
///
/// Only ever produced from facts we hold; when there is no factual reason the
/// line is omitted rather than filled with generated enthusiasm.
String? whyWatchLine(GameCard card, DateTime now) {
  final competition = card.competition;
  if (card.game.status == GameStatus.finalized) return null;

  if (card.involvesFavorite) return '팔로우한 팀의 경기입니다.';
  if (competition?.level == CompetitionLevel.international) {
    return '국제대회 경기입니다.';
  }
  final sameRegion =
      card.homeTeam.region != null &&
      card.homeTeam.region == card.awayTeam.region;
  if (sameRegion) return '같은 지역 팀끼리 맞붙습니다.';
  final days = card.game.startTimeUtc.difference(now).inDays;
  if (days >= 0 && days <= 2) return '곧 열리는 경기입니다.';
  return null;
}
