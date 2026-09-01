import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/components/standings_widgets.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../data/models/stats.dart';

/// Category-selectable individual leaderboards for one season: the category
/// segmented control, the "규정 충족자만" toggle, and the ranked cards.
///
/// Extracted from `LeaderboardScreen` (`lib/features/my_baseball/leaderboard_
/// screen.dart`) so the games tab's 순위 section can embed the exact same
/// content instead of pushing to `/my/leaderboard/:seasonId` — that route
/// lives in the 마이야구 shell branch, and pushing it from 경기 would switch
/// the bottom tab out from under the user. `LeaderboardScreen` now wraps this
/// in its own `Scaffold`; the games tab embeds it directly under its own app
/// bar instead.
class WbLeaderboardBoards extends ConsumerStatefulWidget {
  const WbLeaderboardBoards({super.key, required this.seasonId});

  final String seasonId;

  @override
  ConsumerState<WbLeaderboardBoards> createState() =>
      _WbLeaderboardBoardsState();
}

class _WbLeaderboardBoardsState extends ConsumerState<WbLeaderboardBoards> {
  StatCategory _category = StatCategory.batting;
  bool _qualifiedOnly = true;

  @override
  Widget build(BuildContext context) {
    final boards = ref.watch(leaderboardsProvider(widget.seasonId));
    final c = WbTheme.of(context);

    return Column(
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
                child: WbSkeleton(height: 160, borderRadius: WbRadius.cardAll),
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
                  child: WbLeaderboardCard(
                    board: filtered[i],
                    qualifiedOnly: _qualifiedOnly,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
