import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/components/provenance_widgets.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../data/models/stats.dart';

/// Per-category individual leaderboards.
///
/// Rules this screen enforces visibly:
///  * every stat shows its definition and formula on demand,
///  * qualified and unqualified players are separated, with the threshold and
///    how it was derived stated,
///  * ties share a rank and are marked,
///  * data coverage is shown, so a partial tally is never read as official,
///  * records from different competitions are never summed — one season only,
///  * there is no composite rating and no AI grade.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key, required this.seasonId});

  final String seasonId;

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  StatCategory _category = StatCategory.batting;
  bool _qualifiedOnly = true;

  @override
  Widget build(BuildContext context) {
    final boards = ref.watch(leaderboardsProvider(widget.seasonId));
    final c = WbTheme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('개인 기록 순위')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WbSpace.screen,
              WbSpace.md,
              WbSpace.screen,
              WbSpace.sm,
            ),
            child: SegmentedButton<StatCategory>(
              segments: <ButtonSegment<StatCategory>>[
                for (final category in StatCategory.values)
                  ButtonSegment<StatCategory>(
                    value: category,
                    label: Text(category.labelKo),
                  ),
              ],
              selected: <StatCategory>{_category},
              onSelectionChanged: (s) => setState(() => _category = s.first),
              showSelectedIcon: false,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
            child: Row(
              children: <Widget>[
                WbFilterChip(
                  label: '규정 충족자만',
                  selected: _qualifiedOnly,
                  onTap: () => setState(() => _qualifiedOnly = !_qualifiedOnly),
                ),
                const Spacer(),
                Text(
                  '한 대회 기록만 집계',
                  style: WbType.micro.copyWith(color: c.inkMuted),
                ),
              ],
            ),
          ),
          Expanded(
            child: boards.when(
              loading: () => ListView.builder(
                padding: const EdgeInsets.all(WbSpace.screen),
                itemCount: 3,
                itemBuilder: (context, _) => const Padding(
                  padding: EdgeInsets.only(bottom: WbSpace.md),
                  child: WbSkeleton(
                    height: 160,
                    borderRadius: WbRadius.cardAll,
                  ),
                ),
              ),
              error: (_, _) => WbEmptyState(
                icon: Icons.error_outline_rounded,
                tone: WbBadgeTone.danger,
                title: '기록을 계산하지 못했습니다',
              ),
              data: (list) {
                final filtered = list
                    .where((b) => b.definition.category == _category)
                    .toList();
                if (filtered.isEmpty) {
                  return WbEmptyState(
                    icon: Icons.leaderboard_outlined,
                    title: '${_category.labelKo} 부문 공개 기록이 없습니다',
                    message:
                        '공식 기록지가 수집되면 부문별 순위를 계산합니다.\n'
                        '공개되지 않은 기록은 추정하지 않습니다.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    WbSpace.screen,
                    WbSpace.md,
                    WbSpace.screen,
                    WbSpace.xxl,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: WbSpace.md),
                    child: _LeaderboardCard(
                      board: filtered[i],
                      qualifiedOnly: _qualifiedOnly,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// What to say above a ranking about its cut-off.
///
/// Three different situations, and only one of them is a number. Teams play
/// different numbers of games, so 규정 타석 differs between them; printing a
/// single figure above a mixed table states something untrue for most of the
/// players under it.
String _qualificationNote(QualificationRule rule, Leaderboard board) {
  if (board.qualificationVariesByTeam) {
    return '${rule.labelKo}은 팀마다 다릅니다 — ${rule.descriptionKo} '
        '선수별로 각자 소속 팀의 경기 수로 계산했습니다.';
  }
  if (board.qualificationThreshold == null) {
    // We say so rather than inventing a cut-off.
    return '${rule.labelKo}은 팀 경기 수가 확인되면 계산됩니다. '
        '현재는 전체 기록을 표시합니다.';
  }
  return '${rule.labelKo} ${board.qualificationThreshold} 이상';
}

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({required this.board, required this.qualifiedOnly});

  final Leaderboard board;
  final bool qualifiedOnly;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final def = board.definition;
    final entries = qualifiedOnly ? board.qualified : board.entries;
    final unqualifiedCount = board.entries.length - board.qualified.length;

    return WbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  def.fullLabelKo,
                  style: WbType.section.copyWith(color: c.ink),
                ),
              ),
              WbTapTarget(
                onTap: () => _showDefinition(context, board),
                semanticLabel: '${def.shortLabelKo} 설명 보기',
                child: Icon(
                  Icons.help_outline_rounded,
                  size: 18,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: WbSpace.xs),
          Text(
            def.higherIsBetter ? '높을수록 좋은 기록' : '낮을수록 좋은 기록',
            style: WbType.micro.copyWith(color: c.inkMuted),
          ),
          const WbInsetDivider(vertical: WbSpace.md),

          if (entries.isEmpty)
            Text(
              qualifiedOnly && unqualifiedCount > 0
                  ? '자격 기준을 충족한 선수가 아직 없습니다. '
                        '"규정 충족자만"을 끄면 전체 기록을 볼 수 있습니다.'
                  : '집계된 기록이 없습니다.',
              style: WbType.caption.copyWith(color: c.inkMuted, height: 1.55),
            )
          else
            for (final entry in entries.take(10))
              Padding(
                padding: const EdgeInsets.only(bottom: WbSpace.sm),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${entry.rank ?? '-'}',
                        style: WbType.tabular.copyWith(
                          color: entry.rank == 1 ? c.brand : c.inkMuted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  entry.playerName,
                                  style: WbType.body.copyWith(color: c.ink),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (entry.isTied) ...<Widget>[
                                const SizedBox(width: WbSpace.xs),
                                Text(
                                  '공동',
                                  style: WbType.micro.copyWith(
                                    color: c.inkMuted,
                                  ),
                                ),
                              ],
                              if (!entry.qualifies) ...<Widget>[
                                const SizedBox(width: WbSpace.xs),
                                const WbBadge(
                                  label: '자격 미달',
                                  tone: WbBadgeTone.muted,
                                  dense: true,
                                ),
                              ],
                            ],
                          ),
                          if (entry.teamName != null)
                            Text(
                              entry.teamName!,
                              style: WbType.micro.copyWith(color: c.inkMuted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: WbSpace.sm),
                    Text(
                      def.format(entry.value),
                      style: WbType.tabular.copyWith(color: c.ink),
                    ),
                  ],
                ),
              ),

          const WbInsetDivider(vertical: WbSpace.md),
          if (def.qualification != null)
            Padding(
              padding: const EdgeInsets.only(bottom: WbSpace.sm),
              child: Text(
                _qualificationNote(def.qualification!, board),
                style: WbType.micro.copyWith(color: c.inkMuted, height: 1.5),
              ),
            ),
          WbCoverageNote(coverage: board.coverage),
          // The names in a demo season are obviously placeholders, but the
          // numbers are not — a screenshot of this table must not be mistakable
          // for an official record.
          if (board.provenance.isDemo)
            const Padding(
              padding: EdgeInsets.only(top: WbSpace.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: WbBadge(
                  label: '데모 데이터로 계산한 순위',
                  tone: WbBadgeTone.muted,
                  icon: Icons.science_outlined,
                  dense: true,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showDefinition(BuildContext context, Leaderboard board) {
    final def = board.definition;
    return showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final c = WbTheme.of(context);
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
                  def.fullLabelKo,
                  style: WbType.title.copyWith(color: c.ink),
                ),
                const SizedBox(height: WbSpace.md),
                Text(
                  def.descriptionKo,
                  style: WbType.body.copyWith(color: c.ink, height: 1.65),
                ),
                if (def.formulaKo != null) ...<Widget>[
                  const SizedBox(height: WbSpace.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(WbSpace.md),
                    decoration: BoxDecoration(
                      color: c.divider.withValues(alpha: 0.4),
                      borderRadius: WbRadius.chipAll,
                    ),
                    child: Text(
                      '산식 · ${def.formulaKo}',
                      style: WbType.tabular.copyWith(color: c.ink),
                    ),
                  ),
                ],
                if (def.qualification != null) ...<Widget>[
                  const SizedBox(height: WbSpace.md),
                  Text(
                    '자격 기준',
                    style: WbType.captionStrong.copyWith(color: c.ink),
                  ),
                  const SizedBox(height: WbSpace.xs),
                  Text(
                    def.qualification!.descriptionKo,
                    style: WbType.caption.copyWith(
                      color: c.inkMuted,
                      height: 1.6,
                    ),
                  ),
                ],
                const SizedBox(height: WbSpace.md),
                Text(
                  '동률은 같은 순위로 표시하고 "공동"으로 표기합니다. '
                  '서로 다른 대회의 기록은 합산하지 않습니다.',
                  style: WbType.micro.copyWith(color: c.inkMuted, height: 1.6),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
