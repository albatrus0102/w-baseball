import 'package:flutter/material.dart';

import '../../../core/design_system/components/primitives.dart';
import '../../../core/design_system/components/provenance_widgets.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/typography.dart';
import '../../../data/models/domain.dart';
import '../../../data/models/stats.dart';

/// Line score, batting and pitching.
///
/// Wide tables are the classic mobile failure in sports apps. The approach
/// here: the team-name column is pinned, only the numeric columns scroll
/// horizontally, and tapping a row opens a bottom sheet with that player's
/// full line rather than forcing a sideways hunt.
class BoxScoreSection extends StatefulWidget {
  const BoxScoreSection({
    super.key,
    required this.detail,
    this.showBeginner = true,
  });

  final GameDetail detail;
  final bool showBeginner;

  @override
  State<BoxScoreSection> createState() => _BoxScoreSectionState();
}

class _BoxScoreSectionState extends State<BoxScoreSection> {
  bool _showPitching = false;

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (detail.lineScore != null) ...<Widget>[
          const WbSectionHeader(title: '이닝별 점수'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
            child: _LineScoreTable(
              lineScore: detail.lineScore!,
              homeName: detail.card.homeTeam.displayName,
              awayName: detail.card.awayTeam.displayName,
            ),
          ),
        ],

        if (detail.game.summary != null) ...<Widget>[
          const WbSectionHeader(title: '경기 요약'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
            child: WbCard(
              child: Text(
                detail.game.summary!,
                style: WbType.body.copyWith(height: 1.65),
              ),
            ),
          ),
        ],

        if (detail.batting.isNotEmpty ||
            detail.pitching.isNotEmpty) ...<Widget>[
          const WbSectionHeader(title: '선수 기록'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
            child: SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text('타자')),
                ButtonSegment<bool>(value: true, label: Text('투수')),
              ],
              selected: <bool>{_showPitching},
              onSelectionChanged: (s) =>
                  setState(() => _showPitching = s.first),
              showSelectedIcon: false,
            ),
          ),
          const SizedBox(height: WbSpace.md),
          if (!_showPitching)
            _BattingTable(
              stats: detail.batting,
              homeTeamId: detail.card.homeTeam.id,
              homeName: detail.card.homeTeam.displayName,
              awayName: detail.card.awayTeam.displayName,
              showBeginner: widget.showBeginner,
            )
          else
            _PitchingTable(
              stats: detail.pitching,
              homeTeamId: detail.card.homeTeam.id,
              homeName: detail.card.homeTeam.displayName,
              awayName: detail.card.awayTeam.displayName,
              showBeginner: widget.showBeginner,
            ),
        ],
      ],
    );
  }
}

class _LineScoreTable extends StatelessWidget {
  const _LineScoreTable({
    required this.lineScore,
    required this.homeName,
    required this.awayName,
  });

  final GameLineScore lineScore;
  final String homeName;
  final String awayName;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final innings = lineScore.inningCount;

    Widget cell(String text, {bool strong = false, double width = 30}) =>
        SizedBox(
          width: width,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: (strong ? WbType.tabular : WbType.tabularSmall).copyWith(
              color: strong ? c.ink : c.inkMuted,
            ),
          ),
        );

    Widget row(String label, List<int?> values, int? r, int? h, int? e) {
      return Row(
        children: <Widget>[
          // Pinned team column.
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: WbType.captionStrong.copyWith(color: c.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (var i = 0; i < innings; i++)
                    // `-` means the team did not bat, which is different from
                    // scoring zero.
                    cell(
                      i < values.length ? (values[i]?.toString() ?? '-') : '-',
                    ),
                  const SizedBox(width: WbSpace.sm),
                  cell(r?.toString() ?? '-', strong: true),
                  cell(h?.toString() ?? '-'),
                  cell(e?.toString() ?? '-'),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return WbCard(
      padding: const EdgeInsets.all(WbSpace.md),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const SizedBox(width: 72),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      for (var i = 1; i <= innings; i++) cell('$i'),
                      const SizedBox(width: WbSpace.sm),
                      cell('R', strong: true),
                      cell('H'),
                      cell('E'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const WbInsetDivider(vertical: WbSpace.sm),
          row(
            awayName,
            lineScore.awayInnings,
            lineScore.awayRuns,
            lineScore.awayHits,
            lineScore.awayErrors,
          ),
          const SizedBox(height: WbSpace.sm),
          row(
            homeName,
            lineScore.homeInnings,
            lineScore.homeRuns,
            lineScore.homeHits,
            lineScore.homeErrors,
          ),
        ],
      ),
    );
  }
}

class _BattingTable extends StatelessWidget {
  const _BattingTable({
    required this.stats,
    required this.homeTeamId,
    required this.homeName,
    required this.awayName,
    required this.showBeginner,
  });

  final List<BattingGameStat> stats;
  final String homeTeamId;
  final String homeName;
  final String awayName;
  final bool showBeginner;

  @override
  Widget build(BuildContext context) {
    final away = stats.where((s) => s.teamId != homeTeamId).toList();
    final home = stats.where((s) => s.teamId == homeTeamId).toList();

    return Column(
      children: <Widget>[
        if (showBeginner)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              WbSpace.screen,
              0,
              WbSpace.screen,
              WbSpace.md,
            ),
            child: WbExplainer(
              title: '이 기록은 무엇인가요?',
              body:
                  '타수(AB)는 타석 중 볼넷·희생타를 뺀 수, 안타(H)는 안타 수, '
                  '타점(RBI)은 내 타격으로 만든 득점입니다. 행을 누르면 전체 기록이 열립니다.',
            ),
          ),
        _TeamStatBlock(
          title: awayName,
          headers: const <String>['타수', '안타', '타점', '득점'],
          rows: away
              .map(
                (s) => _StatRow(
                  name: s.playerName,
                  subtitle: s.position,
                  values: <String>[
                    '${s.atBats}',
                    '${s.hits}',
                    '${s.rbi}',
                    '${s.runs}',
                  ],
                  detail: s,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: WbSpace.md),
        _TeamStatBlock(
          title: homeName,
          headers: const <String>['타수', '안타', '타점', '득점'],
          rows: home
              .map(
                (s) => _StatRow(
                  name: s.playerName,
                  subtitle: s.position,
                  values: <String>[
                    '${s.atBats}',
                    '${s.hits}',
                    '${s.rbi}',
                    '${s.runs}',
                  ],
                  detail: s,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _PitchingTable extends StatelessWidget {
  const _PitchingTable({
    required this.stats,
    required this.homeTeamId,
    required this.homeName,
    required this.awayName,
    required this.showBeginner,
  });

  final List<PitchingGameStat> stats;
  final String homeTeamId;
  final String homeName;
  final String awayName;
  final bool showBeginner;

  @override
  Widget build(BuildContext context) {
    final away = stats.where((s) => s.teamId != homeTeamId).toList();
    final home = stats.where((s) => s.teamId == homeTeamId).toList();

    List<_StatRow> rowsFor(List<PitchingGameStat> list) => list
        .map(
          (s) => _StatRow(
            name: s.playerName,
            subtitle: s.decision,
            values: <String>[
              s.inningsPitchedLabel,
              '${s.hitsAllowed}',
              '${s.earnedRuns}',
              '${s.strikeouts}',
            ],
            detail: s,
          ),
        )
        .toList();

    return Column(
      children: <Widget>[
        if (showBeginner)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              WbSpace.screen,
              0,
              WbSpace.screen,
              WbSpace.md,
            ),
            child: WbExplainer(
              title: '이 기록은 무엇인가요?',
              body:
                  '이닝(IP)은 던진 이닝 수로 5.1은 5와 3분의 1이닝입니다. '
                  '자책(ER)은 투수 책임 실점, 탈삼진(K)은 삼진으로 잡은 타자 수입니다.',
            ),
          ),
        _TeamStatBlock(
          title: awayName,
          headers: const <String>['이닝', '피안타', '자책', '탈삼진'],
          rows: rowsFor(away),
        ),
        const SizedBox(height: WbSpace.md),
        _TeamStatBlock(
          title: homeName,
          headers: const <String>['이닝', '피안타', '자책', '탈삼진'],
          rows: rowsFor(home),
        ),
      ],
    );
  }
}

class _StatRow {
  const _StatRow({
    required this.name,
    required this.values,
    required this.detail,
    this.subtitle,
  });

  final String name;
  final String? subtitle;
  final List<String> values;
  final Object detail;
}

class _TeamStatBlock extends StatelessWidget {
  const _TeamStatBlock({
    required this.title,
    required this.headers,
    required this.rows,
  });

  final String title;
  final List<String> headers;
  final List<_StatRow> rows;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
      child: WbCard(
        padding: const EdgeInsets.all(WbSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: WbType.captionStrong.copyWith(color: c.brand)),
            const SizedBox(height: WbSpace.sm),
            Row(
              children: <Widget>[
                const SizedBox(width: 96),
                for (final header in headers)
                  SizedBox(
                    width: 44,
                    child: Text(
                      header,
                      textAlign: TextAlign.center,
                      style: WbType.micro.copyWith(color: c.inkMuted),
                    ),
                  ),
              ],
            ),
            const WbInsetDivider(vertical: WbSpace.sm),
            for (final row in rows)
              InkWell(
                onTap: () => _showRowDetail(context, row, headers),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: WbSpace.sm),
                  child: Row(
                    children: <Widget>[
                      // Pinned identity column; only the numbers would scroll
                      // if the screen were narrower.
                      SizedBox(
                        width: 96,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              row.name,
                              style: WbType.body.copyWith(color: c.ink),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (row.subtitle != null)
                              Text(
                                row.subtitle!,
                                style: WbType.micro.copyWith(color: c.inkMuted),
                              ),
                          ],
                        ),
                      ),
                      for (final value in row.values)
                        SizedBox(
                          width: 44,
                          child: Text(
                            value,
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
    );
  }

  Future<void> _showRowDetail(
    BuildContext context,
    _StatRow row,
    List<String> headers,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final c = WbTheme.of(context);
        final detail = row.detail;
        final entries = <MapEntry<String, String>>[];

        if (detail is BattingGameStat) {
          entries.addAll(<MapEntry<String, String>>[
            MapEntry('타순', detail.battingOrder?.toString() ?? '-'),
            MapEntry('포지션', detail.position ?? '-'),
            MapEntry('타수', '${detail.atBats}'),
            MapEntry('안타', '${detail.hits}'),
            MapEntry('2루타', '${detail.doubles}'),
            MapEntry('3루타', '${detail.triples}'),
            MapEntry('홈런', '${detail.homeRuns}'),
            MapEntry('타점', '${detail.rbi}'),
            MapEntry('득점', '${detail.runs}'),
            MapEntry('볼넷', '${detail.walks}'),
            MapEntry('삼진', '${detail.strikeouts}'),
            MapEntry('도루', '${detail.stolenBases}'),
            MapEntry('타율', formatRate(detail.average)),
          ]);
        } else if (detail is PitchingGameStat) {
          entries.addAll(<MapEntry<String, String>>[
            MapEntry('결과', detail.decision ?? '-'),
            MapEntry('이닝', detail.inningsPitchedLabel),
            MapEntry('피안타', '${detail.hitsAllowed}'),
            MapEntry('실점', '${detail.runsAllowed}'),
            MapEntry('자책', '${detail.earnedRuns}'),
            MapEntry('볼넷', '${detail.walks}'),
            MapEntry('탈삼진', '${detail.strikeouts}'),
            MapEntry('피홈런', '${detail.homeRunsAllowed}'),
            MapEntry(
              '평균자책',
              detail.era == null ? '-' : detail.era!.toStringAsFixed(2),
            ),
          ]);
        }

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
                Text(row.name, style: WbType.title.copyWith(color: c.ink)),
                const SizedBox(height: WbSpace.md),
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: WbSpace.xs),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 84,
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
              ],
            ),
          ),
        );
      },
    );
  }
}
