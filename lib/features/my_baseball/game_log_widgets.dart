import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/analytics/analytics.dart';
import '../../core/design_system/components/notice_widgets.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../core/utils/kst.dart';
import '../../data/models/content.dart';
import '../../data/models/game_log.dart';
import '../../data/models/stats.dart' show formatRate;

/// 출전 일지: 내 기록.
///
/// Stage 1 (log entries, position history) plus Stage 2 (the optional stat
/// line and its OBP aggregate) — see the feature brief. This module is the
/// app's one write-driven surface: everything it shows is derived from what
/// the player typed herself, nothing is compared against anyone else, and
/// the app never turns a handful of entries into advice (no "뭘 더 해야
/// 할지" is ever generated here — `_GameLogSummary` only ever resurfaces her
/// own last note plus arithmetic on her own numbers, and `_ObpGuideLink`
/// only ever links to a guide).
///
/// Callers gate this on audience mode (player/both only, never discover) —
/// see `MyBaseballScreen`.
class GameLogModule extends ConsumerWidget {
  const GameLogModule({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(gameLogEntriesProvider);
    return entries.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: WbSpace.screen),
        child: WbSkeleton(height: 140, borderRadius: WbRadius.cardAll),
      ),
      // Fail-safe silence, matching every other module on this screen: a
      // failed read must not block the rest of the page.
      error: (_, _) => const SizedBox.shrink(),
      data: (list) => _GameLogSection(entries: list),
    );
  }
}

class _GameLogSection extends ConsumerWidget {
  const _GameLogSection({required this.entries});

  final List<GameLogEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audience = ref.watch(audienceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const WbSectionHeader(title: '내 기록'),
        if (entries.isEmpty)
          audience.gameLogNudgeDismissed
              ? const _GameLogCompactPrompt()
              : const _GameLogNudgeCard()
        else ...<Widget>[
          _GameLogSummary(entries: entries),
          const SizedBox(height: WbSpace.md),
          // Adds its own trailing gap only when it actually renders
          // something — an open goal is the exception, not the rule, and a
          // fixed gap here would shift every other capture that has none.
          _GameLogGoalCard(entries: entries),
          _PositionTimelineCard(entries: entries),
          const SizedBox(height: WbSpace.md),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WbSpace.screen,
                vertical: WbSpace.xxs,
              ),
              child: _GameLogEntryTile(entry: entry),
            ),
          const SizedBox(height: WbSpace.sm),
          const _GameLogPrivacyNote(),
        ],
      ],
    );
  }
}

/// "경기 하고 오셨나요? 1분이면 남길 수 있어요" — shown once, before the first
/// entry. Dismissible, not permanent furniture: mirrors the home screen's
/// mode nudge (`AudiencePreference.modeNudgeDismissed` /
/// `_ModeNudge` in `home_screen.dart`), which is the same "say it once, then
/// get out of the way" shape.
class _GameLogNudgeCard extends ConsumerWidget {
  const _GameLogNudgeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
      child: WbCard(
        emphasized: true,
        onTap: () => showGameLogEntrySheet(context, ref, entries: const []),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.brandSoft,
                borderRadius: WbRadius.chipAll,
              ),
              child: Icon(Icons.edit_note_rounded, size: 20, color: c.brand),
            ),
            const SizedBox(width: WbSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '경기 하고 오셨나요?',
                    style: WbType.headline.copyWith(color: c.ink),
                  ),
                  const SizedBox(height: WbSpace.xxs),
                  Text(
                    '1분이면 남길 수 있어요. 대회·상대·포지션을 고르기만 하면 됩니다.',
                    style: WbType.caption.copyWith(color: c.inkMuted),
                  ),
                ],
              ),
            ),
            WbTapTarget(
              onTap: () =>
                  ref.read(audienceControllerProvider).dismissGameLogNudge(),
              semanticLabel: '이 안내 닫기',
              child: Icon(Icons.close_rounded, size: 16, color: c.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// After the nudge is dismissed but before a first entry exists, 내 기록
/// stays reachable — it just stops asking. Same row shape as
/// `_ScheduleBoardEntry` elsewhere on this screen.
class _GameLogCompactPrompt extends ConsumerWidget {
  const _GameLogCompactPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
      child: WbCard(
        onTap: () => showGameLogEntrySheet(context, ref, entries: const []),
        child: Row(
          children: <Widget>[
            Icon(Icons.add_circle_outline_rounded, size: 22, color: c.brand),
            const SizedBox(width: WbSpace.md),
            Expanded(
              child: Text(
                '출전 기록 추가하기',
                style: WbType.headline.copyWith(color: c.ink),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.inkMuted),
          ],
        ),
      ),
    );
  }
}

/// How many games, and her own last note surfaced back to her — never advice
/// the app authored. See the feature brief's "no coaching" rule.
///
/// The count and the add-entry button go through `WbNoticeWithAction`,
/// which shares a row when they fit and stacks them when they don't — even
/// "1게임 기록" broke mid-syllable ("1게 / 임") against the button at 2.0x
/// text scale on a 360dp screen, since `WbType.title` is large enough that
/// the two together no longer fit one line at that scale.
class _GameLogSummary extends ConsumerWidget {
  const _GameLogSummary({required this.entries});

  final List<GameLogEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final last = entries.first; // watchEntries() is most-recent-first.
    final summary = GameLogStatSummary.from(entries);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
      child: WbCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            WbNoticeWithAction(
              text: _headerTextKo(summary),
              textStyle: WbType.title.copyWith(color: c.ink),
              actionLabel: '기록 추가',
              actionIcon: Icons.add_rounded,
              onAction: () =>
                  showGameLogEntrySheet(context, ref, entries: entries),
            ),
            if (last.note != null && last.note!.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: WbSpace.sm),
              Text(
                '지난 기록 · ${last.note}',
                style: WbType.caption.copyWith(color: c.inkMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (summary.batting != null) ...<Widget>[
              const SizedBox(height: WbSpace.md),
              _BattingSummaryBlock(
                batting: summary.batting!,
                hasPitching: summary.pitching != null,
              ),
              if (summary.gamesWithoutBattingStats > 0) ...<Widget>[
                const SizedBox(height: WbSpace.sm),
                Text(
                  '타격 기록이 없는 경기가 ${summary.gamesWithoutBattingStats}경기 있어요.',
                  style: WbType.caption.copyWith(color: c.inkMuted),
                ),
              ],
            ],
            if (summary.pitching != null) ...<Widget>[
              const SizedBox(height: WbSpace.md),
              _PitchingSummaryBlock(
                pitching: summary.pitching!,
                hasBatting: summary.batting != null,
              ),
            ],
            const SizedBox(height: WbSpace.sm),
            // Fixed on every summary card, not just the ones with a stat
            // line — see the feature brief.
            Text(
              '직접 기록한 개인 집계입니다. 공식 기록이 아닙니다.',
              style: WbType.micro.copyWith(color: c.inkMuted),
            ),
            const _ObpGuideLink(),
          ],
        ),
      ),
    );
  }

  /// "N게임 기록", plus her W-L-D record once at least one result has been
  /// recorded — never shown as `0승 0패 0무` for a log that is all
  /// "기록 안 함" so far.
  String _headerTextKo(GameLogStatSummary summary) {
    final base = '${entries.length}게임 기록';
    if (!summary.hasAnyResult) return base;
    return '$base · ${summary.wins}승 ${summary.losses}패 ${summary.draws}무';
  }
}

/// The 타자로 block of the 내 기록 aggregate card — plate appearances, OBP
/// (once [BattingStatSummary.meetsThreshold]), and the counting stats.
class _BattingSummaryBlock extends StatelessWidget {
  const _BattingSummaryBlock({
    required this.batting,
    required this.hasPitching,
  });

  final BattingStatSummary batting;

  /// Only prefixes the header with "타자로" when there is a 투수로 block to
  /// tell it apart from — a log with no pitching entries at all reads better
  /// without a role label that has nothing to contrast against.
  final bool hasPitching;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final prefix = hasPitching ? '타자로 — ' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$prefix${batting.plateAppearances}타석 (타격 기록이 있는 ${batting.gamesWithStats}경기)',
          style: WbType.captionStrong.copyWith(color: c.ink),
        ),
        const SizedBox(height: WbSpace.xxs),
        if (batting.meetsThreshold)
          Text(_obpLineKo(batting), style: WbType.body.copyWith(color: c.ink))
        else ...<Widget>[
          Text(
            '${batting.obpDenominator}타석 중 ${batting.reachedBaseCount}번 나갔어요',
            style: WbType.body.copyWith(color: c.ink),
          ),
          const SizedBox(height: WbSpace.xxs),
          Text(
            '출루율은 계산에 들어가는 타석이 ${BattingStatSummary.threshold}번 모이면 '
            '보여드려요. 지금 ${batting.obpDenominator}번이에요.',
            style: WbType.caption.copyWith(color: c.inkMuted),
          ),
        ],
        const SizedBox(height: WbSpace.xxs),
        Text(
          '안타 ${batting.hits} · 볼넷 ${batting.walks} · 삼진 ${batting.strikeouts} · '
          '타점 ${batting.runsBattedIn} · 도루 ${batting.stolenBases}',
          style: WbType.caption.copyWith(color: c.inkMuted),
        ),
        if (batting.gamesMissingSacrificeBunts > 0) ...<Widget>[
          const SizedBox(height: WbSpace.xxs),
          Text(
            '희생번트를 적지 않은 경기 ${batting.gamesMissingSacrificeBunts}경기는 '
            '0으로 계산했어요. 출루율이 실제보다 낮게 나올 수는 있어도 높게 나오지는 '
            '않아요.',
            style: WbType.micro.copyWith(color: c.inkMuted),
          ),
        ],
      ],
    );
  }

  /// "출루율 .438 (48타석 중 21번)", or, once 희생번트 has actually excluded
  /// something, "출루율 .457 (희생번트 2번 제외, 46번 중 21번)" — see
  /// `BattingStatSummary.obpDenominator`.
  String _obpLineKo(BattingStatSummary b) {
    final rate = formatRate(b.onBasePercentage);
    if (b.sacrificeBunts == 0) {
      return '출루율 $rate (${b.plateAppearances}타석 중 ${b.reachedBaseCount}번)';
    }
    return '출루율 $rate (희생번트 ${b.sacrificeBunts}번 제외, '
        '${b.obpDenominator}번 중 ${b.reachedBaseCount}번)';
  }
}

/// The 투수로 block of the 내 기록 aggregate card. No ERA, no earned/unearned
/// split — see `PitchingStatSummary` and `GameLogEntries.runsAllowed`'s doc.
class _PitchingSummaryBlock extends StatelessWidget {
  const _PitchingSummaryBlock({
    required this.pitching,
    required this.hasBatting,
  });

  final PitchingStatSummary pitching;

  /// Mirrors `_BattingSummaryBlock.hasPitching` — only labels the block
  /// "투수로" when a 타자로 block exists to distinguish it from.
  final bool hasBatting;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final prefix = hasBatting ? '투수로 — ' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$prefix${pitching.inningsLabelKo} (${pitching.gamesWithStats}경기)',
          style: WbType.captionStrong.copyWith(color: c.ink),
        ),
        const SizedBox(height: WbSpace.xxs),
        Text(
          '탈삼진 ${pitching.strikeouts} · 볼넷 ${pitching.walks} · '
          '실점 ${pitching.runsAllowed}',
          style: WbType.caption.copyWith(color: c.inkMuted),
        ),
      ],
    );
  }
}

/// "출루율이 뭐예요?" — links the existing beginner-guide anchor mechanism
/// rather than the app explaining stats inline. `stat:obp` ships in the
/// bundled seed content (`assets/seed/content/discover.json`).
class _ObpGuideLink extends ConsumerWidget {
  const _ObpGuideLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guides = ref.watch(_gameLogGuideProvider);
    final guide = guides.value;
    if (guide == null) return const SizedBox.shrink();
    final c = WbTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: WbSpace.xs),
      child: InkWell(
        onTap: () => context.push(WbRoutes.guide(guide.id)),
        child: Text(
          // Fixed text rather than derived from `guide.title` — the guide's
          // title ("출루율(OBP)이란?") is written for a detail-screen heading,
          // not for splicing into a question, and past attempts at string
          // surgery here produced "…이이 뭐예요?".
          '출루율이 뭐예요? →',
          style: WbType.caption.copyWith(color: c.brand),
        ),
      ),
    );
  }
}

final _gameLogGuideProvider = FutureProvider.autoDispose<BeginnerGuide?>((ref) {
  return ref.watch(contentRepositoryProvider).guideForAnchor('stat:obp');
});

/// "다음 경기에서 해볼 것" reflected back to her, unedited — never generated,
/// never judged. See this file's module doc and `GameLogGoalRepository`.
///
/// Shows nothing when there is no open goal — closed goals are stored (see
/// `GameLogGoals` in `tables.dart`) but deliberately never listed on this
/// screen; see the feature brief's "지난 것" section.
class _GameLogGoalCard extends ConsumerWidget {
  const _GameLogGoalCard({required this.entries});

  /// Used only to resolve a goal's `entryId` to the game it was written
  /// after, for the "M월 D일 경기 뒤에 적음" line — see [_dateLabel].
  final List<GameLogEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(gameLogOpenGoalProvider).value;
    if (goal == null) return const SizedBox.shrink();
    final c = WbTheme.of(context);
    final repo = ref.read(gameLogGoalRepositoryProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        0,
        WbSpace.screen,
        WbSpace.md,
      ),
      child: WbCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '다음 경기에서 해볼 것',
              style: WbType.captionStrong.copyWith(color: c.ink),
            ),
            const SizedBox(height: WbSpace.xs),
            Text('"${goal.body}"', style: WbType.body.copyWith(color: c.ink)),
            const SizedBox(height: WbSpace.xxs),
            Text(
              _dateLabel(goal),
              style: WbType.caption.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: WbSpace.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                TextButton(
                  onPressed: () => repo.markDone(goal.id),
                  child: const Text('했어요'),
                ),
                TextButton(
                  onPressed: () =>
                      repo.carryForward(id: goal.id, body: goal.body),
                  child: const Text('다음에도'),
                ),
                TextButton(
                  onPressed: () => repo.dropGoal(goal.id),
                  child: const Text('지우기'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// "8월 23일 경기 뒤에 적음" when [goal] was written right after a specific
  /// logged game (its `entryId` resolves in [entries]), or a plainer "8월
  /// 23일에 적음" when it was not — a goal carried forward via "다음에도" has
  /// no entry to name. Falls back to [GameLogGoal.createdAt] either way.
  String _dateLabel(GameLogGoal goal) {
    GameLogEntry? linkedEntry;
    for (final entry in entries) {
      if (entry.id == goal.entryId) {
        linkedEntry = entry;
        break;
      }
    }
    if (linkedEntry != null) {
      return '${KoDate.monthDay(linkedEntry.playedAt)} 경기 뒤에 적음';
    }
    return '${KoDate.monthDay(goal.createdAt)}에 적음';
  }
}

/// "외야에서 포수로 전향" made visible — derived from the entries themselves,
/// never stored separately. See `derivePositionTimeline`.
class _PositionTimelineCard extends StatelessWidget {
  const _PositionTimelineCard({required this.entries});

  final List<GameLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final events = derivePositionTimeline(entries);
    if (events.isEmpty) return const SizedBox.shrink();
    final c = WbTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
      child: WbCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '포지션 히스토리',
              style: WbType.captionStrong.copyWith(color: c.ink),
            ),
            const SizedBox(height: WbSpace.sm),
            for (final event in events)
              Padding(
                padding: const EdgeInsets.only(bottom: WbSpace.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      KoDate.monthDay(event.date),
                      style: WbType.caption.copyWith(color: c.inkMuted),
                    ),
                    const SizedBox(width: WbSpace.sm),
                    Expanded(
                      child: Text(
                        event.isFirst
                            ? '${event.positionsLabelKo} 기록 시작'
                            : '${event.previousLabelKo} → ${event.positionsLabelKo}',
                        style: WbType.caption.copyWith(color: c.ink),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GameLogEntryTile extends ConsumerWidget {
  const _GameLogEntryTile({required this.entry});

  final GameLogEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final opponent = entry.opponentLabel;
    final competition = entry.competitionLabel;
    final venue = entry.venueLabel;

    final subtitleParts = <String>[
      if (competition != null && competition.isNotEmpty) competition,
      if (venue != null && venue.isNotEmpty) venue,
    ];

    return WbCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 56,
            child: Text(
              KoDate.monthDay(entry.playedAt),
              style: WbType.captionStrong.copyWith(color: c.ink),
            ),
          ),
          const SizedBox(width: WbSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  (opponent == null || opponent.isEmpty) ? '상대 미기록' : opponent,
                  style: WbType.body.copyWith(color: c.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitleParts.isNotEmpty) ...<Widget>[
                  const SizedBox(height: WbSpace.xxs),
                  Text(
                    subtitleParts.join(' · '),
                    style: WbType.caption.copyWith(color: c.inkMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (entry.positions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: WbSpace.xxs),
                  Text(
                    entry.positionsLabelKo,
                    style: WbType.caption.copyWith(color: c.inkMuted),
                  ),
                ],
                if (entry.note != null &&
                    entry.note!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: WbSpace.xxs),
                  Text(
                    entry.note!,
                    style: WbType.caption.copyWith(color: c.ink),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: WbSpace.sm),
          if (entry.result != GameLogResult.unspecified)
            WbBadge(
              label: entry.result.labelKo,
              tone: switch (entry.result) {
                GameLogResult.win => WbBadgeTone.positive,
                GameLogResult.loss => WbBadgeTone.danger,
                _ => WbBadgeTone.muted,
              },
              dense: true,
            ),
          WbTapTarget(
            onTap: () => _confirmDelete(context, ref),
            semanticLabel: '${KoDate.fullDate(entry.playedAt)} 기록 삭제',
            child: Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: c.inkMuted,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이 기록을 삭제할까요?'),
        content: const Text('삭제하면 되돌릴 수 없습니다.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(gameLogRepositoryProvider).deleteEntry(entry.id);
    await ref.read(analyticsProvider).log(AnalyticsEvent.gameLogEntryDeleted);
  }
}

/// The standing line the feature brief requires verbatim, plus the export
/// action. Never call this a 백업 — it explicitly is not one (there is no
/// server copy; the exported file is the only copy that survives a reinstall
/// until Stage 2's import exists).
///
/// Goes through `WbNoticeWithAction` — this sentence is long enough that an
/// inline button squeezes it to a narrow column at large text scales and
/// breaks a word mid-syllable (confirmed at 2.0x / 360dp: "이 기 / 기에만").
class _GameLogPrivacyNote extends ConsumerWidget {
  const _GameLogPrivacyNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
      child: WbNoticeWithAction(
        leading: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.smartphone_rounded, size: 14, color: c.inkMuted),
        ),
        text:
            '이 기록은 이 기기에만 저장됩니다. 기기를 바꾸면 옮겨지지 않으니, '
            '내보내기로 보관해 두세요.',
        textStyle: WbType.micro.copyWith(color: c.inkMuted, height: 1.5),
        actionLabel: '내보내기',
        onAction: () => exportGameLog(context, ref),
      ),
    );
  }
}

/// Exports every entry as `wb-myrecords-v1` JSON plus a CSV, and hands both
/// to the OS share sheet. Public so the entry sheet's "every ten entries"
/// nudge (see `_maybeOfferExport`) can call the same path.
Future<void> exportGameLog(BuildContext context, WidgetRef ref) async {
  final entries = ref.read(gameLogEntriesProvider).value ?? const [];
  if (entries.isEmpty) return;
  final now = ref.read(clockProvider)();
  final goals = await ref.read(gameLogGoalRepositoryProvider).allGoals();
  await ref
      .read(gameLogExportServiceProvider)
      .export(
        entries: entries,
        sharing: ref.read(platformServicesProvider).sharing,
        now: now,
        goals: goals,
      );
  await ref.read(analyticsProvider).log(AnalyticsEvent.gameLogExported);
}

// ---------------------------------------------------------------------------
// Entry sheet
// ---------------------------------------------------------------------------

/// Opens the quick-entry sheet. [entries] supplies the "remember the last
/// 대회/상대/포지션" defaults — most-recent-first, per `watchEntries()`.
///
/// The "every ten entries" export nudge is offered from *this* function, on
/// [context] — the calling screen's context, which stays mounted after the
/// sheet closes — rather than from inside the sheet itself, whose own
/// context is disposed the moment it pops.
Future<void> showGameLogEntrySheet(
  BuildContext context,
  WidgetRef ref, {
  required List<GameLogEntry> entries,
}) async {
  final now = ref.read(clockProvider)();
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _GameLogEntrySheet(
      last: entries.isEmpty ? null : entries.first,
      now: now,
    ),
  );
  if (added == true && context.mounted) {
    await _maybeOfferExport(context, ref);
  }
}

/// A gentle nudge around every ten entries — not a permanent banner, just a
/// one-off prompt right after the count crosses a multiple of ten.
Future<void> _maybeOfferExport(BuildContext context, WidgetRef ref) async {
  final count = await ref.read(gameLogRepositoryProvider).countEntries();
  if (count == 0 || count % 10 != 0) return;
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text('$count경기 기록했어요. 내보내기로 보관해 두세요.'),
      action: SnackBarAction(
        label: '내보내기',
        onPressed: () => exportGameLog(context, ref),
      ),
    ),
  );
}

class _GameLogEntrySheet extends ConsumerStatefulWidget {
  const _GameLogEntrySheet({required this.last, required this.now});

  final GameLogEntry? last;
  final DateTime now;

  @override
  ConsumerState<_GameLogEntrySheet> createState() => _GameLogEntrySheetState();
}

class _GameLogEntrySheetState extends ConsumerState<_GameLogEntrySheet> {
  late DateTime _dateKst; // KST calendar date, time-of-day zeroed.
  late final TextEditingController _competition;
  late final TextEditingController _opponent;
  late final TextEditingController _venue;
  late final TextEditingController _note;
  late final TextEditingController _goal;
  late Set<GameLogPosition> _positions;
  late GameLogResult _result;
  bool _saving = false;

  // --- stat line (Stage 2) -----------------------------------------------
  //
  // Deliberately never pre-filled from `widget.last`, unlike
  // 대회/상대/구장/포지션 above — a stat line is specific to the one game
  // just played, and carrying last game's numbers forward would be a bug,
  // not a convenience. `_statsExpanded` alone remembers a *preference*
  // (open or closed), never a value.
  late bool _statsExpanded;
  int _plateAppearances = 0;
  int _hits = 0;
  int _walks = 0;
  int _sacrificeBunts = 0;
  int _strikeouts = 0;
  int _runsBattedIn = 0;
  int _runsScored = 0;
  int _stolenBases = 0;
  int _inningsWhole = 0;
  int _inningsRemainderOuts = 0; // 0, 1, or 2 — the fractional part of 이닝.
  int _pitchingStrikeouts = 0;
  int _pitchingWalks = 0;
  int _runsAllowed = 0;

  bool get _isPitcher => _positions.contains(GameLogPosition.pitcher);

  @override
  void initState() {
    super.initState();
    final todayKst = Kst.toKst(widget.now);
    _dateKst = DateTime(todayKst.year, todayKst.month, todayKst.day);
    final last = widget.last;
    _competition = TextEditingController(text: last?.competitionLabel ?? '');
    _opponent = TextEditingController(text: last?.opponentLabel ?? '');
    _venue = TextEditingController(text: last?.venueLabel ?? '');
    _note = TextEditingController();
    _goal = TextEditingController();
    _positions = (last?.positions ?? const <GameLogPosition>[]).toSet();
    _result = GameLogResult.unspecified;
    _statsExpanded = ref.read(audienceProvider).gameLogStatsExpanded;
  }

  @override
  void dispose() {
    _competition.dispose();
    _opponent.dispose();
    _venue.dispose();
    _note.dispose();
    _goal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => ListView(
          key: const ValueKey('gameLogEntrySheetList'),
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            WbSpace.screen,
            WbSpace.lg,
            WbSpace.screen,
            WbSpace.xl,
          ),
          children: <Widget>[
            Text('경기 기록하기', style: WbType.section.copyWith(color: c.ink)),
            const SizedBox(height: WbSpace.lg),
            _DateStepper(
              date: _dateKst,
              now: widget.now,
              onChanged: (d) => setState(() => _dateKst = d),
            ),
            const SizedBox(height: WbSpace.lg),
            _QuickTextField(
              label: '대회',
              controller: _competition,
              recentValues: _recentValues((e) => e.competitionLabel),
              onChipTapped: () => setState(() {}),
            ),
            const SizedBox(height: WbSpace.md),
            _QuickTextField(
              label: '상대',
              controller: _opponent,
              recentValues: _recentValues((e) => e.opponentLabel),
              onChipTapped: () => setState(() {}),
            ),
            const SizedBox(height: WbSpace.md),
            _QuickTextField(
              label: '구장',
              controller: _venue,
              recentValues: _recentValues((e) => e.venueLabel),
              onChipTapped: () => setState(() {}),
            ),
            const SizedBox(height: WbSpace.lg),
            Text('포지션', style: WbType.captionStrong.copyWith(color: c.ink)),
            const SizedBox(height: WbSpace.sm),
            Wrap(
              spacing: WbSpace.sm,
              runSpacing: WbSpace.sm,
              children: <Widget>[
                for (final position in GameLogPosition.values)
                  WbFilterChip(
                    key: ValueKey('gameLogPositionChip_${position.wireValue}'),
                    label: position.labelKo,
                    selected: _positions.contains(position),
                    onTap: () => setState(() {
                      _positions.contains(position)
                          ? _positions.remove(position)
                          : _positions.add(position);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: WbSpace.lg),
            _buildStatSection(c),
            const SizedBox(height: WbSpace.lg),
            Text('결과', style: WbType.captionStrong.copyWith(color: c.ink)),
            const SizedBox(height: WbSpace.sm),
            Wrap(
              spacing: WbSpace.sm,
              children: <Widget>[
                for (final result in GameLogResult.values)
                  WbFilterChip(
                    label: result.labelKo,
                    selected: _result == result,
                    onTap: () => setState(() => _result = result),
                  ),
              ],
            ),
            const SizedBox(height: WbSpace.lg),
            TextField(
              key: const ValueKey('gameLogNoteField'),
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '한 줄 메모',
                hintText: '예: 병살 하나 잡음',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: WbSpace.md),
            // 다음 경기에서 해볼 것 — free text, deliberately not chips/a
            // stepper: this is the one field on the sheet that must be in
            // her own words to be hers at all. See the feature brief and
            // `_GameLogGoalCard` below, which only ever shows this sentence
            // back unedited. Left empty, nothing happens — no goal is
            // written or closed.
            TextField(
              key: const ValueKey('gameLogGoalField'),
              controller: _goal,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '다음 경기에서 해볼 것 (선택)',
                hintText: '예: 초구 공략',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: WbSpace.xl),
            SizedBox(
              width: double.infinity,
              height: WbSize.buttonHeight,
              child: FilledButton(
                key: const ValueKey('gameLogSaveButton'),
                onPressed: _saving ? null : _save,
                child: const Text('저장'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Up to 4 distinct, most-recent-first values already used for [pick] —
  /// the "remember the last 대회/상대/포지션" chips.
  List<String> _recentValues(String? Function(GameLogEntry) pick) {
    final entries = ref.read(gameLogEntriesProvider).value ?? const [];
    final seen = <String>{};
    final result = <String>[];
    for (final entry in entries) {
      final value = pick(entry)?.trim();
      if (value == null || value.isEmpty) continue;
      if (seen.add(value)) result.add(value);
      if (result.length >= 4) break;
    }
    return result;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final playedAt = Kst.fromKst(_dateKst);
    final pitching = _statsExpanded && _isPitcher;
    final savedEntry = await ref
        .read(gameLogRepositoryProvider)
        .addEntry(
          playedAt: playedAt,
          competitionLabel: _competition.text,
          opponentLabel: _opponent.text,
          venueLabel: _venue.text,
          positions: _positions.toList(growable: false),
          result: _result,
          note: _note.text,
          // Collapsed means "no stat line at all" — every one of these
          // stays null, which is what excludes the game from every
          // aggregate. See `GameLogEntries` in `tables.dart`.
          plateAppearances: _statsExpanded ? _plateAppearances : null,
          hits: _statsExpanded ? _hits : null,
          walks: _statsExpanded ? _walks : null,
          sacrificeBunts: _statsExpanded ? _sacrificeBunts : null,
          strikeouts: _statsExpanded ? _strikeouts : null,
          runsBattedIn: _statsExpanded ? _runsBattedIn : null,
          runsScored: _statsExpanded ? _runsScored : null,
          stolenBases: _statsExpanded ? _stolenBases : null,
          // The pitching fields stay null unless the section is both
          // expanded *and* 투수 is a recorded position — the sheet never
          // shows these controls otherwise, so there is nothing the player
          // actually entered to save.
          outsPitched: pitching
              ? _inningsWhole * 3 + _inningsRemainderOuts
              : null,
          pitchingStrikeouts: pitching ? _pitchingStrikeouts : null,
          pitchingWalks: pitching ? _pitchingWalks : null,
          runsAllowed: pitching ? _runsAllowed : null,
        );
    await ref.read(analyticsProvider).log(AnalyticsEvent.gameLogEntryAdded);
    // 다음 경기에서 해볼 것 — only when she actually wrote one. An empty
    // field means no goal at all, not an empty-string goal; see
    // `GameLogGoalRepository.setGoal`'s doc for what happens to any
    // previously open goal here.
    if (_goal.text.trim().isNotEmpty) {
      await ref
          .read(gameLogGoalRepositoryProvider)
          .setGoal(body: _goal.text, entryId: savedEntry.id);
    }
    if (_statsExpanded) {
      // One-way switch — see `AudiencePreference.gameLogStatsExpanded`'s
      // doc. Fired after a real save, not on every toggle, so idly opening
      // the section and closing it again without saving does not flip it.
      await ref.read(audienceControllerProvider).markGameLogStatsExpanded();
    }

    if (!mounted) return;
    // The export nudge is offered by the caller of `showGameLogEntrySheet`,
    // once this pop has actually landed — see that function's doc.
    Navigator.of(context).pop(true);
  }

  /// The 성적 (선택사항) section: collapsed by default (or per
  /// `AudiencePreference.gameLogStatsExpanded`), showing only a one-line
  /// hint until opened. See the feature brief: leaving it collapsed must
  /// cost a returning 1단계-only user zero extra taps.
  Widget _buildStatSection(WbSemanticColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: () => setState(() => _statsExpanded = !_statsExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: WbSpace.xxs),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '성적 (선택사항)',
                    style: WbType.captionStrong.copyWith(color: c.ink),
                  ),
                ),
                Icon(
                  _statsExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: c.inkMuted,
                ),
              ],
            ),
          ),
        ),
        if (!_statsExpanded)
          Padding(
            padding: const EdgeInsets.only(top: WbSpace.xxs),
            child: Text(
              '타석 수가 기억 안 나면 접어 두세요. 접힌 경기는 집계에서 뺍니다.',
              style: WbType.caption.copyWith(color: c.inkMuted),
            ),
          )
        else ...<Widget>[
          const SizedBox(height: WbSpace.xs),
          _StatStepper(
            label: '타석',
            value: _plateAppearances,
            onChanged: (v) => setState(() => _plateAppearances = v),
          ),
          _StatStepper(
            label: '안타',
            value: _hits,
            onChanged: (v) => setState(() => _hits = v),
          ),
          _StatStepper(
            label: '볼넷 (몸에 맞는 공 포함)',
            value: _walks,
            onChanged: (v) => setState(() => _walks = v),
          ),
          _StatStepper(
            label: '희생번트',
            value: _sacrificeBunts,
            onChanged: (v) => setState(() => _sacrificeBunts = v),
          ),
          _StatStepper(
            label: '삼진',
            value: _strikeouts,
            onChanged: (v) => setState(() => _strikeouts = v),
          ),
          _StatStepper(
            label: '타점',
            value: _runsBattedIn,
            onChanged: (v) => setState(() => _runsBattedIn = v),
          ),
          _StatStepper(
            label: '득점',
            value: _runsScored,
            onChanged: (v) => setState(() => _runsScored = v),
          ),
          _StatStepper(
            label: '도루',
            value: _stolenBases,
            onChanged: (v) => setState(() => _stolenBases = v),
          ),
          if (_isPitcher) ...<Widget>[
            const WbInsetDivider(vertical: WbSpace.sm),
            Text('투구', style: WbType.caption.copyWith(color: c.inkMuted)),
            const SizedBox(height: WbSpace.xxs),
            _StatStepper(
              label: '이닝',
              value: _inningsWhole,
              onChanged: (v) => setState(() => _inningsWhole = v),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: WbSpace.xxs),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '남은 아웃카운트',
                      style: WbType.body.copyWith(color: c.ink),
                    ),
                  ),
                  Wrap(
                    spacing: WbSpace.xs,
                    children: <Widget>[
                      for (final outs in const <int>[0, 1, 2])
                        WbFilterChip(
                          label: '$outs아웃',
                          selected: _inningsRemainderOuts == outs,
                          onTap: () =>
                              setState(() => _inningsRemainderOuts = outs),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            _StatStepper(
              label: '탈삼진',
              value: _pitchingStrikeouts,
              onChanged: (v) => setState(() => _pitchingStrikeouts = v),
            ),
            _StatStepper(
              label: '볼넷 (투구, 몸에 맞힘 포함)',
              value: _pitchingWalks,
              onChanged: (v) => setState(() => _pitchingWalks = v),
            ),
            _StatStepper(
              label: '실점',
              value: _runsAllowed,
              onChanged: (v) => setState(() => _runsAllowed = v),
            ),
          ],
        ],
      ],
    );
  }
}

/// One labelled row: a minus button, the current count, a plus button.
/// Never a keyboard — see the feature brief's "steppers and chips" rule and
/// `_DateStepper` above, which this mirrors. Every 성적 field this app
/// stores is a non-negative count, so the floor is fixed at 0 rather than
/// exposed as a parameter no caller would ever want to change.
class _StatStepper extends StatelessWidget {
  const _StatStepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WbSpace.xxs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: WbType.body.copyWith(color: c.ink)),
          ),
          WbTapTarget(
            onTap: value > 0 ? () => onChanged(value - 1) : null,
            semanticLabel: '$label 줄이기',
            child: Icon(
              Icons.remove_circle_outline_rounded,
              color: value > 0 ? c.ink : c.divider,
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: WbType.bodyStrong.copyWith(color: c.ink),
            ),
          ),
          WbTapTarget(
            onTap: () => onChanged(value + 1),
            semanticLabel: '$label 늘리기',
            child: Icon(Icons.add_circle_outline_rounded, color: c.ink),
          ),
        ],
      ),
    );
  }
}

/// "오늘 / 어제 / 그제" plus a stepper, with a full date picker for anything
/// further back — the "under a minute" rule means the common case (played
/// today, entering tonight) takes zero taps here.
class _DateStepper extends StatelessWidget {
  const _DateStepper({
    required this.date,
    required this.now,
    required this.onChanged,
  });

  final DateTime date;

  /// The sheet's frozen instant (from `clockProvider`), not a fresh
  /// `DateTime.now()` — screens never read the wall clock directly, so a
  /// golden taken at 09:00 reads the same as one taken at 14:00.
  final DateTime now;

  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final todayKst = Kst.toKst(now);
    final today = DateTime(todayKst.year, todayKst.month, todayKst.day);
    return Row(
      children: <Widget>[
        IconButton(
          onPressed: () => onChanged(date.subtract(const Duration(days: 1))),
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: '하루 전',
        ),
        Expanded(
          child: InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(date.year - 3),
                lastDate: date.isAfter(today)
                    ? date
                    : today.add(const Duration(days: 1)),
              );
              if (picked != null) {
                onChanged(DateTime(picked.year, picked.month, picked.day));
              }
            },
            child: Center(
              child: Text(
                _labelKo(date, today),
                style: WbType.headline.copyWith(color: c.ink),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () => onChanged(date.add(const Duration(days: 1))),
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: '하루 후',
        ),
      ],
    );
  }

  String _labelKo(DateTime d, DateTime today) {
    final diff = today.difference(d).inDays;
    return switch (diff) {
      0 => '오늘 · ${KoDate.monthDayWeekday(Kst.fromKst(d))}',
      1 => '어제 · ${KoDate.monthDayWeekday(Kst.fromKst(d))}',
      2 => '그제 · ${KoDate.monthDayWeekday(Kst.fromKst(d))}',
      _ => KoDate.monthDayWeekday(Kst.fromKst(d)),
    };
  }
}

/// A free-text field with recent-value chips above it, so a repeat entry
/// needs zero typing — tap a chip and it fills the field. Still a real text
/// field underneath, since 대회/상대/구장 are explicitly free text.
class _QuickTextField extends StatelessWidget {
  const _QuickTextField({
    required this.label,
    required this.controller,
    required this.recentValues,
    required this.onChipTapped,
  });

  final String label;
  final TextEditingController controller;
  final List<String> recentValues;

  /// Called after a chip sets [controller]'s text, so the caller can
  /// `setState` — this widget is stateless and has no way to re-evaluate its
  /// own chips' `selected` highlight on its own; only the `TextField` itself
  /// listens to [controller] directly.
  final VoidCallback onChipTapped;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (recentValues.isNotEmpty) ...<Widget>[
          Wrap(
            spacing: WbSpace.xs,
            runSpacing: WbSpace.xs,
            children: <Widget>[
              for (final value in recentValues)
                WbFilterChip(
                  label: value,
                  selected: controller.text == value,
                  onTap: () {
                    controller.text = value;
                    onChipTapped();
                  },
                ),
            ],
          ),
          const SizedBox(height: WbSpace.xs),
        ],
        TextField(
          key: ValueKey('gameLogField_$label'),
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          style: WbType.body.copyWith(color: c.ink),
        ),
      ],
    );
  }
}
