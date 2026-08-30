import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/design_system/components/game_widgets.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/components/provenance_widgets.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../data/models/domain.dart';
import '../../data/models/stats.dart';

/// Competition detail: overview, standings, schedule, and official documents.
///
/// Standings are rendered as rows with a pinned team column rather than a wide
/// scrolling table; tapping a row opens the full line in a sheet. A knockout
/// stage is presented as vertical round cards, not a shrunken bracket.
class CompetitionScreen extends ConsumerStatefulWidget {
  const CompetitionScreen({super.key, required this.seasonId});

  final String seasonId;

  @override
  ConsumerState<CompetitionScreen> createState() => _CompetitionScreenState();
}

class _CompetitionScreenState extends ConsumerState<CompetitionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(competitionDetailProvider(widget.seasonId));
    final now = ref.watch(clockProvider)();

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
            title: '대회 정보를 불러오지 못했습니다',
          ),
        ),
        data: (value) {
          if (value == null) {
            return Scaffold(
              appBar: AppBar(),
              body: WbEmptyState(
                icon: Icons.search_off_rounded,
                title: '대회를 찾을 수 없습니다',
                primaryLabel: '뒤로',
                onPrimary: () => context.pop(),
              ),
            );
          }
          return Scaffold(
            appBar: AppBar(
              title: Text(value.competition.displayName),
              bottom: TabBar(
                controller: _tabs,
                tabs: const <Widget>[
                  Tab(text: '개요'),
                  Tab(text: '순위'),
                  Tab(text: '일정·결과'),
                ],
              ),
            ),
            body: TabBarView(
              controller: _tabs,
              children: <Widget>[
                _Overview(detail: value, now: now, seasonId: widget.seasonId),
                _Standings(detail: value, now: now),
                _Schedule(detail: value, now: now),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview({
    required this.detail,
    required this.now,
    required this.seasonId,
  });

  final CompetitionDetail detail;
  final DateTime now;
  final String seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final competition = detail.competition;
    final pulse = ref.watch(leaguePulseProvider(seasonId));

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        WbSpace.md,
        WbSpace.screen,
        WbSpace.xxl,
      ),
      children: <Widget>[
        WbCard(
          emphasized: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  WbBadge(label: competition.level.labelKo, dense: true),
                  const SizedBox(width: WbSpace.sm),
                  WbBadge(
                    label: detail.season.phase.labelKo,
                    tone: detail.season.phase == CompetitionPhase.ongoing
                        ? WbBadgeTone.live
                        : WbBadgeTone.muted,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: WbSpace.md),
              Text(
                detail.season.name,
                style: WbType.title.copyWith(color: c.ink),
              ),
              if (competition.description != null) ...<Widget>[
                const SizedBox(height: WbSpace.sm),
                Text(
                  competition.description!,
                  style: WbType.body.copyWith(color: c.inkMuted, height: 1.65),
                ),
              ],
              const WbInsetDivider(vertical: WbSpace.md),
              WbSourceLine(provenance: competition.provenance, now: now),
            ],
          ),
        ),
        const SizedBox(height: WbSpace.md),

        pulse.maybeWhen(
          data: (value) {
            if (value == null) return const SizedBox.shrink();
            return WbCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '진행 상황',
                    style: WbType.captionStrong.copyWith(color: c.brand),
                  ),
                  const SizedBox(height: WbSpace.sm),
                  Text(
                    value.headlineKo,
                    style: WbType.body.copyWith(color: c.ink, height: 1.6),
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
                  const SizedBox(height: WbSpace.md),
                  WbCoverageNote(coverage: value.coverage),
                ],
              ),
            );
          },
          orElse: () => const SizedBox.shrink(),
        ),

        if (detail.stages.isNotEmpty) ...<Widget>[
          const SizedBox(height: WbSpace.md),
          const WbSectionHeader(
            title: '단계',
            padding: EdgeInsets.only(bottom: WbSpace.md),
          ),
          // Rounds as vertical cards. A bracket shrunk to phone width is
          // unreadable, so we do not draw one.
          for (final stage in detail.stages)
            Padding(
              padding: const EdgeInsets.only(bottom: WbSpace.sm),
              child: WbCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: WbSpace.lg,
                  vertical: WbSpace.md,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        <String?>[
                          stage.name,
                          stage.groupLabel,
                        ].whereType<String>().join(' · '),
                        style: WbType.body.copyWith(color: c.ink),
                      ),
                    ),
                    Text(switch (stage.format) {
                      StageFormat.groupStage => '조별리그',
                      StageFormat.knockout => '토너먼트',
                      StageFormat.league => '리그',
                      StageFormat.friendly => '친선',
                      StageFormat.unknown => '',
                    }, style: WbType.micro.copyWith(color: c.inkMuted)),
                  ],
                ),
              ),
            ),
        ],

        if (competition.regulationsUrl != null ||
            competition.bracketUrl != null ||
            competition.resultsUrl != null) ...<Widget>[
          const SizedBox(height: WbSpace.md),
          const WbSectionHeader(
            title: '공식 문서',
            padding: EdgeInsets.only(bottom: WbSpace.md),
          ),
          Wrap(
            spacing: WbSpace.sm,
            runSpacing: WbSpace.sm,
            children: <Widget>[
              if (competition.regulationsUrl != null)
                OutlinedButton.icon(
                  onPressed: () => openSource(
                    context,
                    url: competition.regulationsUrl!,
                    title: '대회 규정',
                    sourceLabel: competition.provenance.sourceName,
                  ),
                  icon: const Icon(Icons.gavel_rounded, size: 16),
                  label: const Text('규정'),
                ),
              if (competition.bracketUrl != null)
                OutlinedButton.icon(
                  onPressed: () => openSource(
                    context,
                    url: competition.bracketUrl!,
                    title: '대진표',
                    sourceLabel: competition.provenance.sourceName,
                  ),
                  icon: const Icon(Icons.account_tree_outlined, size: 16),
                  label: const Text('대진표'),
                ),
              if (competition.resultsUrl != null)
                OutlinedButton.icon(
                  onPressed: () => openSource(
                    context,
                    url: competition.resultsUrl!,
                    title: '결과표',
                    sourceLabel: competition.provenance.sourceName,
                  ),
                  icon: const Icon(Icons.table_chart_outlined, size: 16),
                  label: const Text('결과표'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Standings extends StatelessWidget {
  const _Standings({required this.detail, required this.now});

  final CompetitionDetail detail;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    if (detail.standings.isEmpty) {
      return WbEmptyState(
        icon: Icons.emoji_events_outlined,
        title: '순위 정보가 아직 없습니다',
        message: '경기가 진행되고 공식 순위가 공개되면 표시됩니다.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        WbSpace.md,
        WbSpace.screen,
        WbSpace.xxl,
      ),
      children: <Widget>[
        WbCard(
          padding: const EdgeInsets.all(WbSpace.md),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  const SizedBox(width: 26),
                  const Expanded(child: SizedBox.shrink()),
                  for (final header in const <String>['경기', '승', '패', '무'])
                    SizedBox(
                      width: 34,
                      child: Text(
                        header,
                        textAlign: TextAlign.center,
                        style: WbType.micro.copyWith(color: c.inkMuted),
                      ),
                    ),
                  SizedBox(
                    width: 46,
                    child: Text(
                      '승률',
                      textAlign: TextAlign.center,
                      style: WbType.micro.copyWith(color: c.inkMuted),
                    ),
                  ),
                ],
              ),
              // The order is computed, so the reader is told what computed it.
              // A table that cannot explain itself is asking to be trusted on
              // looks alone.
              Padding(
                padding: const EdgeInsets.only(top: WbSpace.xs),
                child: Text(
                  StandingsRule.koreanDefault.explanationKo,
                  style: WbType.micro.copyWith(color: c.inkMuted, height: 1.5),
                ),
              ),
              if (detail.standings.any((r) => r.sourceRankDiffers))
                Padding(
                  padding: const EdgeInsets.only(top: WbSpace.xs),
                  child: Text(
                    '공식 발표 순위와 계산 결과가 다른 팀이 있습니다. '
                    '대회 규정이 다를 수 있어 공식 발표를 함께 확인하세요.',
                    style: WbType.micro.copyWith(color: c.action, height: 1.5),
                  ),
                ),
              const WbInsetDivider(vertical: WbSpace.sm),
              for (final row in detail.standings)
                InkWell(
                  onTap: () => _showRow(context, row),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: WbSpace.sm),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 26,
                          child: Text(
                            row.displayRank == null
                                ? '-'
                                : '${row.isTied ? 'T' : ''}${row.displayRank}',
                            style: WbType.tabular.copyWith(
                              color: row.isFavorite ? c.brand : c.inkMuted,
                            ),
                          ),
                        ),
                        // Pinned identity column; only numbers would scroll.
                        Expanded(
                          child: Row(
                            children: <Widget>[
                              if (row.isFavorite) ...<Widget>[
                                Icon(
                                  Icons.star_rounded,
                                  size: 13,
                                  color: c.highlight,
                                ),
                                const SizedBox(width: WbSpace.xs),
                              ],
                              Flexible(
                                child: Text(
                                  row.team.displayName,
                                  style: WbType.body.copyWith(
                                    color: c.ink,
                                    fontWeight: row.isFavorite
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final value in <int>[
                          row.snapshot.played,
                          row.snapshot.wins,
                          row.snapshot.losses,
                          row.snapshot.draws,
                        ])
                          SizedBox(
                            width: 34,
                            child: Text(
                              '$value',
                              textAlign: TextAlign.center,
                              style: WbType.tabular.copyWith(color: c.ink),
                            ),
                          ),
                        SizedBox(
                          width: 46,
                          child: Text(
                            row.snapshot.winRate == null
                                ? '-'
                                : row.snapshot.winRate!
                                      .toStringAsFixed(3)
                                      .substring(1),
                            textAlign: TextAlign.center,
                            style: WbType.tabular.copyWith(color: c.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: WbSpace.md),
        WbSourceLine(
          provenance: detail.standings.first.snapshot.provenance,
          now: now,
        ),
      ],
    );
  }

  Future<void> _showRow(BuildContext context, StandingRow row) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final c = WbTheme.of(context);
        final s = row.snapshot;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              WbSpace.screen,
              0,
              WbSpace.screen,
              WbSpace.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.team.displayName,
                  style: WbType.title.copyWith(color: c.ink),
                ),
                const SizedBox(height: WbSpace.md),
                for (final entry in <MapEntry<String, String>>[
                  MapEntry('순위', '${s.rank ?? '-'}'),
                  MapEntry('경기', '${s.played}'),
                  MapEntry('승', '${s.wins}'),
                  MapEntry('패', '${s.losses}'),
                  MapEntry('무', '${s.draws}'),
                  MapEntry(
                    '승률',
                    s.winRate == null
                        ? '-'
                        : s.winRate!.toStringAsFixed(3).substring(1),
                  ),
                  MapEntry('득점', '${s.runsScored}'),
                  MapEntry('실점', '${s.runsAllowed}'),
                  MapEntry('득실차', '${s.runDifferential}'),
                  MapEntry('승차', s.gamesBehind?.toStringAsFixed(1) ?? '-'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: WbSpace.xs),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 72,
                          child: Text(
                            entry.key,
                            style: WbType.caption.copyWith(color: c.inkMuted),
                          ),
                        ),
                        Text(
                          entry.value,
                          style: WbType.tabular.copyWith(color: c.ink),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: WbSpace.md),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push(WbRoutes.team(row.team.id));
                    },
                    child: const Text('팀 상세 보기'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Schedule extends StatelessWidget {
  const _Schedule({required this.detail, required this.now});

  final CompetitionDetail detail;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    if (detail.games.isEmpty) {
      return WbEmptyState(
        icon: Icons.event_note_outlined,
        title: '등록된 경기가 없습니다',
        message: '공식 일정이 공개되면 표시됩니다.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        WbSpace.md,
        WbSpace.screen,
        WbSpace.xxl,
      ),
      itemCount: detail.games.length,
      itemBuilder: (context, i) {
        final card = detail.games[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: WbSpace.sm),
          child: WbGameRow(
            card: card,
            now: now,
            showDate: true,
            showCompetition: false,
            onTap: () => context.push(WbRoutes.game(card.game.id)),
          ),
        );
      },
    );
  }
}
