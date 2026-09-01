import 'package:flutter/material.dart';

import '../../../data/models/domain.dart';
import '../../../data/models/stats.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';
import 'primitives.dart';
import 'provenance_widgets.dart';

/// A season's team standings table: rank, W-L-D, win rate, with a pinned
/// identity column and a tap-through to the full line.
///
/// Extracted from `CompetitionScreen`'s 순위 tab so the games tab's 순위
/// section can show the same table — two copies of a standings table would
/// diverge the moment one of them gets a fix the other does not.
class WbStandingsTable extends StatelessWidget {
  const WbStandingsTable({
    super.key,
    required this.standings,
    required this.now,
    this.onTeamTap,
  });

  final List<StandingRow> standings;
  final DateTime now;

  /// Called with a team id when the reader asks for the full line. Null (the
  /// default) hides that action — navigation is a screen's job, not the
  /// design system's, so the caller decides how (or whether) to push.
  final ValueChanged<String>? onTeamTap;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    if (standings.isEmpty) {
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
              if (standings.any((r) => r.sourceRankDiffers))
                Padding(
                  padding: const EdgeInsets.only(top: WbSpace.xs),
                  child: Text(
                    '공식 발표 순위와 계산 결과가 다른 팀이 있습니다. '
                    '대회 규정이 다를 수 있어 공식 발표를 함께 확인하세요.',
                    style: WbType.micro.copyWith(color: c.action, height: 1.5),
                  ),
                ),
              const WbInsetDivider(vertical: WbSpace.sm),
              for (final row in standings)
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
                            formatRate(row.snapshot.winRate),
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
        WbSourceLine(provenance: standings.first.snapshot.provenance, now: now),
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
                  MapEntry('승률', formatRate(s.winRate)),
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
                      onTeamTap?.call(row.team.id);
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

/// What to say above a ranking about its cut-off.
///
/// Three different situations, and only one of them is a number. Teams play
/// different numbers of games, so 규정 타석 differs between them; printing a
/// single figure above a mixed table states something untrue for most of the
/// players under it.
String wbQualificationNoteKo(QualificationRule rule, Leaderboard board) {
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

/// One stat category's ranking — top entries, qualification note, coverage.
///
/// Extracted from `LeaderboardScreen` so the games tab's 순위 section can
/// embed the same cards. Pure and provider-free like the rest of the design
/// system: the category selection and data fetch live one layer up, in
/// `WbLeaderboardBoards` (`lib/features/competitions/leaderboard_boards.dart`).
class WbLeaderboardCard extends StatelessWidget {
  const WbLeaderboardCard({
    super.key,
    required this.board,
    required this.qualifiedOnly,
  });

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
                wbQualificationNoteKo(def.qualification!, board),
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
