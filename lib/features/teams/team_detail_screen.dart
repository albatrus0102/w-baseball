import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/analytics/analytics.dart';
import '../../core/design_system/components/game_widgets.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/components/provenance_widgets.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../data/models/audience.dart';
import '../../data/models/domain.dart';

/// Team detail.
///
/// Ordered so that next fixture, recent results, competitions and joining
/// information all fall inside one scroll pass. Contact goes through official
/// channels only — no personal phone numbers, addresses or e-mail addresses
/// are modelled, so none can be displayed.
class TeamDetailScreen extends ConsumerWidget {
  const TeamDetailScreen({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(teamDetailProvider(teamId));
    final now = DateTime.now().toUtc();

    return Scaffold(
      body: detail.when(
        loading: () => Scaffold(
          appBar: AppBar(),
          body: const Padding(
            padding: EdgeInsets.all(WbSpace.screen),
            child: WbSkeleton(height: 200, borderRadius: WbRadius.cardAll),
          ),
        ),
        error: (_, _) => Scaffold(
          appBar: AppBar(),
          body: WbEmptyState(
            icon: Icons.error_outline_rounded,
            tone: WbBadgeTone.danger,
            title: '팀 정보를 불러오지 못했습니다',
          ),
        ),
        data: (value) {
          if (value == null) {
            return Scaffold(
              appBar: AppBar(),
              body: WbEmptyState(
                icon: Icons.search_off_rounded,
                title: '팀을 찾을 수 없습니다',
                primaryLabel: '뒤로',
                onPrimary: () => context.pop(),
              ),
            );
          }
          return _Body(detail: value, now: now);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.detail, required this.now});

  final TeamDetail detail;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final team = detail.team;
    final playerProfilesEnabled = ref
        .watch(appConfigProvider)
        .flags
        .playerProfilesEnabled;

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          title: Text(team.displayName),
          actions: <Widget>[
            IconButton(
              tooltip: detail.isFavorite ? '팔로우 해제' : '팔로우',
              onPressed: () async {
                final followed = await ref
                    .read(followRepositoryProvider)
                    .toggleFollow(
                      FollowKind.team,
                      team.id,
                      label: team.displayName,
                    );
                await ref.read(platformServicesProvider).haptics.selection();
                if (followed) {
                  await ref
                      .read(analyticsProvider)
                      .log(AnalyticsEvent.teamFollowed);
                }
              },
              icon: Icon(
                detail.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
              ),
            ),
          ],
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(WbSpace.screen),
            child: WbCard(
              emphasized: true,
              accentColor: WbTeamMark.parseHex(team.colorHex),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      WbTeamMark(
                        name: team.displayName,
                        colorHex: team.colorHex,
                        size: 46,
                      ),
                      const SizedBox(width: WbSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              team.name,
                              style: WbType.title.copyWith(color: c.ink),
                            ),
                            const SizedBox(height: WbSpace.xxs),
                            Text(
                              <String?>[
                                    KoreanRegion.byCode(team.region)?.name ??
                                        team.region,
                                    team.city,
                                    if (team.foundedYear != null)
                                      '${team.foundedYear}년 창단',
                                  ]
                                  .whereType<String>()
                                  .where((s) => s.isNotEmpty)
                                  .join(' · '),
                              style: WbType.caption.copyWith(color: c.inkMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Home ground, up here rather than only in the section four
                  // scrolls down. "다음 경기와 구장" was measured at two scrolls
                  // (M2); the full 주 활동 구장 section keeps its map and
                  // directions — this is a summary, not a move.
                  if (detail.homeVenue != null) ...<Widget>[
                    const SizedBox(height: WbSpace.sm),
                    InkWell(
                      onTap: () =>
                          context.push(WbRoutes.venue(detail.homeVenue!.id)),
                      borderRadius: WbRadius.chipAll,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: WbSpace.sm,
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.place_outlined,
                              size: 15,
                              color: c.inkMuted,
                            ),
                            const SizedBox(width: WbSpace.xs),
                            Expanded(
                              child: Text(
                                '주 활동 구장 · ${detail.homeVenue!.name}',
                                style: WbType.caption.copyWith(color: c.ink),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (team.introduction != null) ...<Widget>[
                    const SizedBox(height: WbSpace.md),
                    Text(
                      team.introduction!,
                      style: WbType.body.copyWith(
                        color: c.inkMuted,
                        height: 1.65,
                      ),
                    ),
                  ],
                  const WbInsetDivider(vertical: WbSpace.md),
                  WbSourceLine(provenance: team.provenance, now: now),
                ],
              ),
            ),
          ),
        ),

        // Joining info sits high for the "I want to play" journey.
        SliverToBoxAdapter(child: _JoinSection(team: team)),

        if (detail.nextGames.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const WbSectionHeader(title: '다음 경기'),
                for (final card in detail.nextGames)
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
              ],
            ),
          ),

        if (detail.recentGames.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const WbSectionHeader(title: '최근 결과'),
                for (final card in detail.recentGames)
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
              ],
            ),
          ),

        if (detail.seasons.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const WbSectionHeader(title: '참가 대회'),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WbSpace.screen,
                  ),
                  child: Wrap(
                    spacing: WbSpace.sm,
                    runSpacing: WbSpace.sm,
                    children: <Widget>[
                      for (final season in detail.seasons)
                        WbFilterChip(
                          label: season.name,
                          selected: false,
                          onTap: () =>
                              context.push(WbRoutes.competition(season.id)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        if (detail.homeVenue != null)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const WbSectionHeader(title: '주 활동 구장'),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WbSpace.screen,
                  ),
                  child: WbCard(
                    onTap: () =>
                        context.push(WbRoutes.venue(detail.homeVenue!.id)),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.place_outlined, size: 19, color: c.brand),
                        const SizedBox(width: WbSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                detail.homeVenue!.name,
                                style: WbType.body.copyWith(color: c.ink),
                              ),
                              if (team.practiceArea != null)
                                Text(
                                  '연습 지역 ${team.practiceArea}',
                                  style: WbType.micro.copyWith(
                                    color: c.inkMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: c.inkMuted),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Roster only when the flag allows it, and never with photos.
        if (playerProfilesEnabled && detail.roster.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const WbSectionHeader(
                  title: '시즌 로스터',
                  subtitle: '공개된 이름·등번호·포지션만 표시합니다.',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WbSpace.screen,
                  ),
                  child: WbCard(
                    child: Column(
                      children: <Widget>[
                        for (final member in detail.roster)
                          // Minors are excluded entirely, regardless of flag.
                          if (!member.person.isMinor)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: WbSpace.xs,
                              ),
                              child: Row(
                                children: <Widget>[
                                  SizedBox(
                                    width: 34,
                                    child: Text(
                                      member.entry.jerseyNumber ?? '-',
                                      style: WbType.tabular.copyWith(
                                        color: c.inkMuted,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      member.person.name,
                                      style: WbType.body.copyWith(color: c.ink),
                                    ),
                                  ),
                                  if (member.entry.position != null)
                                    Text(
                                      member.entry.position!,
                                      style: WbType.caption.copyWith(
                                        color: c.inkMuted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

        SliverToBoxAdapter(child: _CorrectionFooter(team: team)),

        const SliverToBoxAdapter(child: SizedBox(height: WbSpace.xxl)),
      ],
    );
  }
}

class _JoinSection extends StatelessWidget {
  const _JoinSection({required this.team});

  final Team team;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
      child: WbCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                WbBadge(
                  label: team.recruitment.labelKo,
                  tone: team.isRecruiting
                      ? WbBadgeTone.positive
                      : WbBadgeTone.muted,
                  icon: team.isRecruiting
                      ? Icons.campaign_outlined
                      : Icons.info_outline_rounded,
                ),
              ],
            ),
            if (team.recruitmentTarget != null) ...<Widget>[
              const SizedBox(height: WbSpace.sm),
              Text(
                '모집 대상 · ${team.recruitmentTarget}',
                style: WbType.body.copyWith(color: c.ink),
              ),
            ],
            const SizedBox(height: WbSpace.md),
            // Contact is always through an official channel the team itself
            // published — never a personal number or address.
            if (team.officialUrl == null && team.contactUrl == null)
              Text(
                '공개된 문의 채널이 없습니다. 팀 관리자라면 정보를 등록해 주세요.',
                style: WbType.caption.copyWith(color: c.inkMuted, height: 1.55),
              )
            else
              Wrap(
                spacing: WbSpace.sm,
                runSpacing: WbSpace.sm,
                children: <Widget>[
                  if (team.officialUrl != null)
                    OutlinedButton.icon(
                      onPressed: () => openSource(
                        context,
                        url: team.officialUrl!,
                        title: '${team.displayName} 공식 채널',
                        sourceLabel: '팀 공식',
                      ),
                      icon: const Icon(Icons.public_rounded, size: 16),
                      label: const Text('공식 채널'),
                    ),
                  if (team.contactUrl != null)
                    FilledButton.icon(
                      onPressed: () => openSource(
                        context,
                        url: team.contactUrl!,
                        title: '${team.displayName} 가입 문의',
                        sourceLabel: '팀 공식',
                      ),
                      icon: const Icon(Icons.mail_outline_rounded, size: 16),
                      label: const Text('가입 문의'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CorrectionFooter extends ConsumerWidget {
  const _CorrectionFooter({required this.team});

  final Team team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final forms = ref.watch(appConfigProvider).forms;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        WbSpace.lg,
        WbSpace.screen,
        0,
      ),
      child: forms.teamRegistration.isEmpty
          ? Text(
              '팀 정보 수정 창구는 준비 중입니다.',
              style: WbType.caption.copyWith(color: c.inkMuted),
            )
          : SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final base = Uri.parse(forms.teamRegistration);
                  final uri = base.replace(
                    queryParameters: <String, String>{
                      ...base.queryParameters,
                      if (forms.entityIdField.isNotEmpty)
                        forms.entityIdField: 'team:${team.id}',
                      if (forms.sourceUrlField.isNotEmpty)
                        forms.sourceUrlField: team.provenance.sourceUrl,
                    },
                  );
                  openSource(
                    context,
                    url: uri.toString(),
                    title: '팀 정보 수정 요청',
                    sourceLabel: 'Google Forms',
                  );
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('팀 정보 수정 요청'),
              ),
            ),
    );
  }
}
