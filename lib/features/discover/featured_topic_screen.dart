import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/analytics/analytics.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/components/provenance_widgets.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../data/models/audience.dart';
import '../../data/models/content.dart';
import '../../data/repositories/content_repository.dart';
import 'widgets/featured_card.dart';

final _featuredTopicProvider = StreamProvider.family<FeaturedItem?, String>((
  ref,
  id,
) {
  return ref.watch(contentRepositoryProvider).watchFeaturedTopic(id);
});

/// A featured topic in full: the recap at two depths, who to watch, official
/// clips, and — the point of the whole screen — the confirmed links out to
/// real teams, players and fixtures.
class FeaturedTopicScreen extends ConsumerWidget {
  const FeaturedTopicScreen({super.key, required this.topicId});

  final String topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(_featuredTopicProvider(topicId));
    final policy = ref.watch(spoilerPolicyProvider);
    final now = ref.watch(clockProvider)();

    return Scaffold(
      body: item.when(
        loading: () => Scaffold(
          appBar: AppBar(),
          body: const Padding(
            padding: EdgeInsets.all(WbSpace.screen),
            child: WbSkeleton(height: 240, borderRadius: WbRadius.heroAll),
          ),
        ),
        error: (_, _) => Scaffold(
          appBar: AppBar(),
          body: WbEmptyState(
            icon: Icons.error_outline_rounded,
            tone: WbBadgeTone.danger,
            title: '콘텐츠를 불러오지 못했습니다',
          ),
        ),
        data: (value) {
          if (value == null) {
            return Scaffold(
              appBar: AppBar(),
              body: WbEmptyState(
                icon: Icons.search_off_rounded,
                title: '콘텐츠를 찾을 수 없습니다',
                primaryLabel: '뒤로',
                onPrimary: () => context.pop(),
              ),
            );
          }
          return _Body(item: value, policy: policy, now: now);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.item, required this.policy, required this.now});

  final FeaturedItem item;
  final SpoilerPolicy policy;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final recap = item.latestRecap;
    final masked = item.isMasked(policy);
    final showBeginner = ref.watch(showBeginnerExplanationsProvider);

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          title: Text(item.program?.title ?? item.topic.title),
          actions: <Widget>[
            if (item.program != null)
              IconButton(
                tooltip: item.isFollowingProgram ? '팔로우 해제' : '팔로우',
                onPressed: () async {
                  await ref
                      .read(followRepositoryProvider)
                      .toggleFollow(
                        FollowKind.program,
                        item.program!.id,
                        label: item.program!.title,
                      );
                  await ref.read(platformServicesProvider).haptics.selection();
                },
                icon: Icon(
                  item.isFollowingProgram
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                ),
              ),
          ],
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(WbSpace.screen),
            child: FeaturedHeroCard(
              item: item,
              policy: policy,
              now: now,
              onTap: () {},
            ),
          ),
        ),

        if (recap != null && recap.hasDeepSummary)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const WbSectionHeader(
                  title: '3분 이해',
                  subtitle: '배경과 실제 여자야구 맥락',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WbSpace.screen,
                  ),
                  child: WbCard(
                    child: WbSpoilerVeil(
                      masked: masked,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (recap.background != null) ...<Widget>[
                            Text(
                              recap.background!,
                              style: WbType.body.copyWith(
                                color: c.ink,
                                height: 1.7,
                              ),
                            ),
                            const SizedBox(height: WbSpace.md),
                          ],
                          if (recap.realBaseballContext != null)
                            WbExplainer(
                              title: '실제 여자야구와의 연결',
                              body: recap.realBaseballContext!,
                              icon: Icons.sports_baseball_outlined,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        if (item.people.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const WbSectionHeader(
                  title: '이번 회차 주목할 인물',
                  subtitle: '공식적으로 확인된 정보만 표시합니다.',
                ),
                for (final person in item.people)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WbSpace.screen,
                      0,
                      WbSpace.screen,
                      WbSpace.sm,
                    ),
                    child: _PersonCard(person: person),
                  ),
              ],
            ),
          ),

        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const WbSectionHeader(title: '실제 여자야구와 연결'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
                child: RealBaseballLinks(
                  links: item.links,
                  onOpen: (link) => _openLink(context, link),
                ),
              ),
            ],
          ),
        ),

        if (item.clips.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const WbSectionHeader(title: '공식 영상'),
                for (final clip in item.clips)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WbSpace.screen,
                      0,
                      WbSpace.screen,
                      WbSpace.sm,
                    ),
                    child: WbCard(
                      onTap: () {
                        ref
                            .read(analyticsProvider)
                            .log(
                              AnalyticsEvent.sourceOpened,
                              properties: <String, Object?>{
                                'screen': 'featured',
                              },
                            );
                        openSource(
                          context,
                          url: clip.url,
                          title: clip.title,
                          sourceLabel: clip.channelName ?? '공식 채널',
                        );
                      },
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.play_circle_outline_rounded,
                            size: 22,
                            color: c.action,
                          ),
                          const SizedBox(width: WbSpace.md),
                          Expanded(
                            child: Text(
                              clip.title,
                              style: WbType.body.copyWith(color: c.ink),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 15,
                            color: c.inkMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const WbSectionHeader(title: '더 알아보기'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
                child: Column(
                  children: <Widget>[
                    _LinkTile(
                      icon: Icons.place_outlined,
                      title: '가까운 여자야구 경기 보러 가기',
                      onTap: () => context.push(WbRoutes.nearby),
                    ),
                    const SizedBox(height: WbSpace.sm),
                    _LinkTile(
                      icon: Icons.groups_outlined,
                      title: '우리 지역 여자야구팀 찾기',
                      onTap: () => context.push(WbRoutes.teams),
                    ),
                    if (item.program?.officialUrl != null) ...<Widget>[
                      const SizedBox(height: WbSpace.sm),
                      _LinkTile(
                        icon: Icons.tv_rounded,
                        title: '프로그램 공식 페이지',
                        onTap: () => openSource(
                          context,
                          url: item.program!.officialUrl!,
                          title: item.program!.title,
                          sourceLabel: item.program!.broadcaster ?? '공식',
                        ),
                      ),
                    ],
                    if (item.program?.streamingUrl != null) ...<Widget>[
                      const SizedBox(height: WbSpace.sm),
                      _LinkTile(
                        icon: Icons.smart_display_outlined,
                        title: '다시보기',
                        onTap: () => openSource(
                          context,
                          url: item.program!.streamingUrl!,
                          title: '${item.program!.title} 다시보기',
                          sourceLabel: '공식 스트리밍',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        if (showBeginner)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(WbSpace.screen),
              child: WbExplainer(
                title: '여자야구가 처음이신가요?',
                body:
                    '경기는 9명이 공격과 수비를 번갈아 하며 정해진 이닝 동안 더 많은 점수를 '
                    '낸 팀이 이깁니다. 더보기에서 1분 입문 가이드를 볼 수 있어요.',
              ),
            ),
          ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              WbSpace.screen,
              0,
              WbSpace.screen,
              WbSpace.xxl,
            ),
            child: WbCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '출처와 검수',
                    style: WbType.captionStrong.copyWith(color: c.ink),
                  ),
                  const SizedBox(height: WbSpace.sm),
                  if (recap != null) WbSummaryMethodBadge(meta: recap.meta),
                  const SizedBox(height: WbSpace.sm),
                  WbSourceLine(
                    provenance: item.topic.meta.provenance,
                    now: now,
                  ),
                  if (item.topic.meta.isDemo) ...<Widget>[
                    const SizedBox(height: WbSpace.md),
                    Container(
                      padding: const EdgeInsets.all(WbSpace.md),
                      decoration: BoxDecoration(
                        color: c.highlightSoft,
                        borderRadius: WbRadius.chipAll,
                      ),
                      child: Text(
                        // Demo content is always labelled. We never present an
                        // unverified episode outcome as fact.
                        '이 콘텐츠는 앱 동작 확인용 데모입니다. 실제 방송 내용이나 결과가 아닙니다. '
                        '공식 회차 정보가 확인되면 교체됩니다.',
                        style: WbType.caption.copyWith(
                          color: c.ink,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openLink(BuildContext context, ContentEntityLink link) {
    switch (link.toKind) {
      case ContentEntityKind.team:
        context.push(WbRoutes.team(link.toId));
      case ContentEntityKind.game:
        context.push(WbRoutes.game(link.toId));
      case ContentEntityKind.season:
      case ContentEntityKind.competition:
        context.push(WbRoutes.competition(link.toId));
      case ContentEntityKind.venue:
        context.push(WbRoutes.venue(link.toId));
      case ContentEntityKind.storyCluster:
        context.push(WbRoutes.story(link.toId));
      case ContentEntityKind.guide:
        context.push(WbRoutes.guide(link.toId));
      case ContentEntityKind.person:
      case ContentEntityKind.program:
      case ContentEntityKind.programSeason:
      case ContentEntityKind.episode:
        // Player profiles are behind a feature flag; rather than opening a
        // screen that may be disabled, we surface the citation instead.
        final url = link.confirmedSourceUrl;
        if (url != null) {
          openSource(
            context,
            url: url,
            title: link.label ?? '공식 확인 자료',
            sourceLabel: '공식',
          );
        }
    }
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person});

  final FeaturedPerson person;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return WbCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // No photo unless the licence is cleared; a monogram otherwise.
          WbTeamMark(name: person.displayName, size: 40),
          const SizedBox(width: WbSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        person.displayName,
                        style: WbType.headline.copyWith(color: c.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (person.role != null) ...<Widget>[
                      const SizedBox(width: WbSpace.sm),
                      WbBadge(label: person.role!, dense: true),
                    ],
                  ],
                ),
                if (person.whyWatch != null) ...<Widget>[
                  const SizedBox(height: WbSpace.xs),
                  Text(
                    person.whyWatch!,
                    style: WbType.caption.copyWith(
                      color: c.inkMuted,
                      height: 1.5,
                    ),
                  ),
                ],
                if (!person.hasConfirmedRealLink) ...<Widget>[
                  const SizedBox(height: WbSpace.sm),
                  Text(
                    // Stated plainly rather than guessed at.
                    '실제 여자야구 팀·선수와의 연결은 공식 확인되지 않았습니다.',
                    style: WbType.micro.copyWith(color: c.inkMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return WbCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: WbSpace.lg,
        vertical: WbSpace.md,
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 19, color: c.brand),
          const SizedBox(width: WbSpace.md),
          Expanded(
            child: Text(title, style: WbType.body.copyWith(color: c.ink)),
          ),
          Icon(Icons.chevron_right_rounded, color: c.inkMuted),
        ],
      ),
    );
  }
}
