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
import '../../data/models/stats.dart';
import '../../data/repositories/game_repository.dart';

/// A season the user's followed team plays in, used for standings/leaderboards.
final _mySeasonProvider = FutureProvider.autoDispose<String?>((ref) async {
  final followed = await ref.watch(followedTeamIdsProvider.future);
  if (followed.isEmpty) return null;
  final detail = await ref.watch(teamDetailProvider(followed.first).future);
  final seasons = detail?.seasons ?? const [];
  return seasons.isEmpty ? null : seasons.first.id;
});

final _standingDetailProvider = FutureProvider.autoDispose<TeamStandingDetail?>(
  (ref) async {
    final followed = await ref.watch(followedTeamIdsProvider.future);
    final seasonId = await ref.watch(_mySeasonProvider.future);
    if (followed.isEmpty || seasonId == null) return null;
    return ref
        .watch(teamRepositoryProvider)
        .standingDetail(followed.first, seasonId);
  },
);

/// The player / staff dashboard, built entirely from public data.
///
/// First version deliberately excludes team chat, attendance, dues and private
/// schedules — those need an account and a privacy policy. The interfaces and
/// flags for them exist; the screens do not.
class MyBaseballScreen extends ConsumerWidget {
  const MyBaseballScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followed =
        ref.watch(followedTeamIdsProvider).value ?? const <String>{};
    final now = ref.watch(clockProvider)();

    return Scaffold(
      appBar: const WbPrimaryAppBar(title: '마이야구'),
      body: followed.isEmpty
          ? const _EmptySetup()
          : RefreshIndicator(
              onRefresh: () => ref
                  .read(syncControllerProvider.notifier)
                  .refresh(force: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: WbSpace.xxl),
                children: <Widget>[
                  _MyTeamHeader(teamId: followed.first),
                  _NextGameBlock(teamId: followed.first, now: now),
                  const _ScheduleBoardEntry(),
                  _StandingBlock(now: now),
                  _LeaguePulseBlock(now: now),
                  const _LeaderboardEntry(),
                ],
              ),
            ),
    );
  }
}

/// No team followed yet — never a dead end.
class _EmptySetup extends ConsumerWidget {
  const _EmptySetup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    return ListView(
      padding: const EdgeInsets.all(WbSpace.screen),
      children: <Widget>[
        WbCard(
          emphasized: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('내 팀을 선택해 주세요', style: WbType.title.copyWith(color: c.ink)),
              const SizedBox(height: WbSpace.sm),
              Text(
                '팀을 하나 고르면 다음 일정과 구장, 경기일 날씨 위험, 팀 순위와 기록을 '
                '이 화면에서 바로 볼 수 있습니다. 로그인은 필요 없어요.',
                style: WbType.body.copyWith(color: c.inkMuted, height: 1.6),
              ),
              const SizedBox(height: WbSpace.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await ref
                        .read(analyticsProvider)
                        .log(AnalyticsEvent.myBaseballConfigured);
                    if (context.mounted) context.push(WbRoutes.teams);
                  },
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('팀 찾기'),
                ),
              ),
              const SizedBox(height: WbSpace.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  // If their team is not in the data set, the answer is to add
                  // it — not to leave them stuck.
                  onPressed: () => context.push(WbRoutes.submissions),
                  child: const Text('우리 팀이 없어요 · 등록하기'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: WbSpace.lg),
        WbEmptyState(
          compact: true,
          icon: Icons.info_outline_rounded,
          title: '무엇을 볼 수 있나요?',
          message:
              '30일 일정 달력, 경기일 날씨 위험, 팀 순위와 최근 흐름, '
              '리그 진행 상황, 부문별 개인 기록 순위입니다.',
        ),
      ],
    );
  }
}

class _MyTeamHeader extends ConsumerWidget {
  const _MyTeamHeader({required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final detail = ref.watch(teamDetailProvider(teamId));

    return detail.maybeWhen(
      data: (value) {
        if (value == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            WbSpace.screen,
            WbSpace.md,
            WbSpace.screen,
            0,
          ),
          child: Row(
            children: <Widget>[
              WbTeamMark(
                name: value.team.displayName,
                colorHex: value.team.colorHex,
                size: 40,
              ),
              const SizedBox(width: WbSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      value.team.displayName,
                      style: WbType.title.copyWith(color: c.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (value.team.region != null)
                      Text(
                        KoreanRegion.byCode(value.team.region)?.name ??
                            value.team.region!,
                        style: WbType.caption.copyWith(color: c.inkMuted),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => context.push(WbRoutes.team(teamId)),
                child: const Text('팀 상세'),
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _NextGameBlock extends ConsumerWidget {
  const _NextGameBlock({required this.teamId, required this.now});

  final String teamId;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = GameQuery(
      teamIds: <String>[teamId],
      fromUtc: Kst.hourBucket(now),
      limit: 1,
    );
    final games = ref.watch(gamesProvider(query));

    return games.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(WbSpace.screen),
        child: WbSkeleton(height: 170, borderRadius: WbRadius.heroAll),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(WbSpace.screen),
            child: WbEmptyState(
              compact: true,
              icon: Icons.event_note_outlined,
              title: '예정된 경기가 없습니다',
              message: '공식 일정이 등록되면 여기에 표시됩니다.',
              primaryLabel: '일정 변경 제보',
              onPrimary: () => context.push(WbRoutes.submissions),
            ),
          );
        }
        final card = list.first;
        final risks = ref.watch(
          weatherRisksProvider(
            WeatherRiskQuery.of(<String, DateTime>{
              card.game.id: card.game.startTimeUtc,
            }),
          ),
        );
        return Padding(
          padding: const EdgeInsets.all(WbSpace.screen),
          child: WbHeroGameCard(
            card: card,
            now: now,
            isFavoriteDriven: true,
            weatherRisk: risks.value?[card.game.id],
            onTap: () => context.push(WbRoutes.game(card.game.id)),
          ),
        );
      },
    );
  }
}

class _ScheduleBoardEntry extends ConsumerWidget {
  const _ScheduleBoardEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
      child: WbCard(
        onTap: () => context.push(WbRoutes.scheduleBoard),
        child: Row(
          children: <Widget>[
            Icon(Icons.calendar_month_rounded, size: 22, color: c.brand),
            const SizedBox(width: WbSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '30일 일정·날씨 보드',
                    style: WbType.headline.copyWith(color: c.ink),
                  ),
                  const SizedBox(height: WbSpace.xxs),
                  Text(
                    '경기일과 10일 이내 날씨 위험을 달력에서 확인합니다.',
                    style: WbType.caption.copyWith(color: c.inkMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.inkMuted),
          ],
        ),
      ),
    );
  }
}

/// Standings with rank movement, recent form, the nearest rival, the rules
/// link, and how complete the data is — never a bare number.
class _StandingBlock extends ConsumerWidget {
  const _StandingBlock({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final detail = ref.watch(_standingDetailProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const WbSectionHeader(title: '내 팀 순위'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
          child: detail.when(
            loading: () =>
                const WbSkeleton(height: 150, borderRadius: WbRadius.cardAll),
            error: (_, _) => WbEmptyState(
              compact: true,
              icon: Icons.error_outline_rounded,
              title: '순위를 계산하지 못했습니다',
            ),
            data: (value) {
              if (value == null) {
                return WbEmptyState(
                  compact: true,
                  icon: Icons.emoji_events_outlined,
                  title: '순위 정보가 아직 없습니다',
                  message: '대회가 진행되면 순위와 최근 흐름을 보여드립니다.',
                );
              }
              final snapshot = value.row.snapshot;
              final delta = value.form.rankDelta;

              return WbCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          '${snapshot.rank ?? '-'}',
                          style: WbType.scoreHero.copyWith(color: c.ink),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                            left: WbSpace.xs,
                            bottom: WbSpace.xs,
                          ),
                          child: Text(
                            '위 / ${value.totalTeams}팀',
                            style: WbType.caption.copyWith(color: c.inkMuted),
                          ),
                        ),
                        const Spacer(),
                        if (delta != null && delta != 0)
                          WbBadge(
                            // Movement is shown with an arrow *and* a number,
                            // so it does not depend on colour.
                            label: delta > 0 ? '$delta단계 상승' : '${-delta}단계 하락',
                            tone: delta > 0
                                ? WbBadgeTone.positive
                                : WbBadgeTone.warning,
                            icon: delta > 0
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            dense: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: WbSpace.md),
                    Text(
                      '${snapshot.played}경기 · ${snapshot.wins}승 '
                      '${snapshot.losses}패'
                      '${snapshot.draws > 0 ? ' ${snapshot.draws}무' : ''}'
                      '${snapshot.winRate == null ? '' : ' · 승률 '
                                '${snapshot.winRate!.toStringAsFixed(3).substring(1)}'}',
                      style: WbType.tabular.copyWith(color: c.ink),
                    ),
                    const SizedBox(height: WbSpace.md),
                    _FormStrip(form: value.form),
                    if (value.nextRival != null) ...<Widget>[
                      const WbInsetDivider(vertical: WbSpace.md),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.flag_outlined,
                            size: 15,
                            color: c.inkMuted,
                          ),
                          const SizedBox(width: WbSpace.sm),
                          Expanded(
                            child: Text(
                              '다음 경쟁 상대 · '
                              '${value.nextRival!.team.displayName}'
                              '${value.gamesBehindRival == null ? '' : ' '
                                        '(${value.gamesBehindRival!.abs().toStringAsFixed(1)}경기 차)'}',
                              style: WbType.caption.copyWith(color: c.ink),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const WbInsetDivider(vertical: WbSpace.md),
                    WbCoverageNote(coverage: value.coverage),
                    const SizedBox(height: WbSpace.sm),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: WbSourceLine(
                            provenance: snapshot.provenance,
                            now: now,
                          ),
                        ),
                        if (value.rulesUrl != null)
                          TextButton(
                            onPressed: () => openSource(
                              context,
                              url: value.rulesUrl!,
                              title: '순위 산정 규정',
                              sourceLabel: snapshot.provenance.sourceName,
                            ),
                            child: const Text('산정 기준'),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Last five results as W/L/D glyphs plus a text summary.
class _FormStrip extends StatelessWidget {
  const _FormStrip({required this.form});

  final TeamForm form;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    if (form.results.isEmpty) {
      return Text(
        '최근 경기 결과가 아직 없습니다.',
        style: WbType.caption.copyWith(color: c.inkMuted),
      );
    }

    Color colorFor(FormResult r) => switch (r) {
      FormResult.win => c.verified,
      FormResult.loss => c.danger,
      FormResult.draw => c.inkMuted,
      FormResult.noResult => c.divider,
    };

    return Semantics(
      label: '최근 ${form.results.length}경기 ${form.summaryKo}',
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            for (final result in form.results.reversed) ...<Widget>[
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorFor(result).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: colorFor(result).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  result.glyph,
                  style: WbType.label.copyWith(color: colorFor(result)),
                ),
              ),
              const SizedBox(width: WbSpace.xs),
            ],
            const SizedBox(width: WbSpace.xs),
            Text(
              '최근 ${form.results.length}경기 ${form.summaryKo}',
              style: WbType.caption.copyWith(color: c.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaguePulseBlock extends ConsumerWidget {
  const _LeaguePulseBlock({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final seasonId = ref.watch(_mySeasonProvider).value;
    if (seasonId == null) return const SizedBox.shrink();

    final pulse = ref.watch(leaguePulseProvider(seasonId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const WbSectionHeader(title: '리그 현황'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
          child: pulse.when(
            loading: () =>
                const WbSkeleton(height: 140, borderRadius: WbRadius.cardAll),
            error: (_, _) => const SizedBox.shrink(),
            data: (value) {
              if (value == null) return const SizedBox.shrink();
              return WbCard(
                onTap: () => context.push(WbRoutes.competition(seasonId)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      value.competitionName,
                      style: WbType.headline.copyWith(color: c.ink),
                    ),
                    const SizedBox(height: WbSpace.xs),
                    // Generated from counts only. It never claims a team has
                    // qualified or been eliminated — that needs the
                    // competition's tie-break rules, which we do not model.
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
                          minHeight: 6,
                          backgroundColor: c.divider,
                          valueColor: AlwaysStoppedAnimation<Color>(c.brand),
                        ),
                      ),
                    ],
                    if (value.thisWeekGames.isNotEmpty) ...<Widget>[
                      const WbInsetDivider(vertical: WbSpace.md),
                      Text(
                        '이번 주 주요 경기',
                        style: WbType.captionStrong.copyWith(color: c.ink),
                      ),
                      const SizedBox(height: WbSpace.sm),
                      for (final game in value.thisWeekGames.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: WbSpace.xs),
                          child: Text(
                            '${KoDate.monthDay(game.game.startTimeUtc)} · '
                            '${game.awayTeam.displayName} vs '
                            '${game.homeTeam.displayName}',
                            style: WbType.caption.copyWith(color: c.inkMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    if (value.hasDisruptions) ...<Widget>[
                      const SizedBox(height: WbSpace.sm),
                      Wrap(
                        spacing: WbSpace.xs,
                        children: <Widget>[
                          if (value.postponedCount > 0)
                            WbBadge(
                              label: '연기 ${value.postponedCount}',
                              tone: WbBadgeTone.warning,
                              dense: true,
                            ),
                          if (value.cancelledCount > 0)
                            WbBadge(
                              label: '취소 ${value.cancelledCount}',
                              tone: WbBadgeTone.danger,
                              dense: true,
                            ),
                          if (value.undecidedCount > 0)
                            WbBadge(
                              label: '미정 ${value.undecidedCount}',
                              tone: WbBadgeTone.muted,
                              dense: true,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: WbSpace.md),
                    WbCoverageNote(coverage: value.coverage, dense: true),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LeaderboardEntry extends ConsumerWidget {
  const _LeaderboardEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final seasonId = ref.watch(_mySeasonProvider).value;
    if (seasonId == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        WbSpace.lg,
        WbSpace.screen,
        0,
      ),
      child: WbCard(
        onTap: () async {
          await ref
              .read(analyticsProvider)
              .log(AnalyticsEvent.leaderboardViewed);
          if (context.mounted) {
            context.push(WbRoutes.leaderboard(seasonId));
          }
        },
        child: Row(
          children: <Widget>[
            Icon(Icons.leaderboard_outlined, size: 22, color: c.brand),
            const SizedBox(width: WbSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '개인 기록 순위',
                    style: WbType.headline.copyWith(color: c.ink),
                  ),
                  const SizedBox(height: WbSpace.xxs),
                  Text(
                    '타격·투구 부문별 선두와 자격 기준을 확인합니다.',
                    style: WbType.caption.copyWith(color: c.inkMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.inkMuted),
          ],
        ),
      ),
    );
  }
}
