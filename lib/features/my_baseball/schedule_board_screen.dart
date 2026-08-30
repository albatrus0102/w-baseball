import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/design_system/components/game_widgets.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../core/utils/kst.dart';
import '../../data/models/domain.dart';
import '../../data/models/weather.dart';
import '../../data/repositories/game_repository.dart';

/// The 30-day schedule + weather board.
///
/// The central honesty constraint of this screen: 기상청 publishes a daily
/// forecast only to about D+10 (단기 D+0~2, 중기 D+3~10). So days inside that
/// window show a weather risk badge, and days beyond it show `예보 전` — never
/// an invented icon or a specific high/low. A 30-day *schedule* is useful; a
/// 30-day daily forecast would be fiction.
class ScheduleBoardScreen extends ConsumerStatefulWidget {
  const ScheduleBoardScreen({super.key});

  @override
  ConsumerState<ScheduleBoardScreen> createState() =>
      _ScheduleBoardScreenState();
}

class _ScheduleBoardScreenState extends ConsumerState<ScheduleBoardScreen> {
  late DateTime _visibleMonth;
  String? _selectedDayKey;
  bool _listView = false;

  @override
  void initState() {
    super.initState();
    final today = Kst.todayKst(DateTime.now().toUtc());
    _visibleMonth = DateTime(today.year, today.month);
    _selectedDayKey = Kst.dayKeyOfKstDate(today);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final followed =
        ref.watch(followedTeamIdsProvider).value ?? const <String>{};
    final monthKey = Kst.monthKeyOfKstDate(_visibleMonth);

    final dayStart = Kst.startOfKstDayUtc(now);
    final query = GameQuery(
      fromUtc: dayStart.subtract(const Duration(days: 1)),
      toUtc: dayStart.add(const Duration(days: 31)),
      teamIds: followed.toList()..sort(),
      limit: 200,
    );
    final games = ref.watch(gamesProvider(query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('30일 일정'),
        actions: <Widget>[
          IconButton(
            tooltip: _listView ? '달력 보기' : '목록 보기',
            onPressed: () => setState(() => _listView = !_listView),
            icon: Icon(
              _listView
                  ? Icons.calendar_month_rounded
                  : Icons.view_list_rounded,
            ),
          ),
        ],
      ),
      body: games.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.all(WbSpace.screen),
          itemCount: 4,
          itemBuilder: (context, _) => const Padding(
            padding: EdgeInsets.only(bottom: WbSpace.sm),
            child: WbGameRowSkeleton(),
          ),
        ),
        error: (_, _) => WbEmptyState(
          icon: Icons.error_outline_rounded,
          tone: WbBadgeTone.danger,
          title: '일정을 불러오지 못했습니다',
        ),
        data: (list) {
          if (list.isEmpty) {
            return WbEmptyState(
              icon: Icons.event_note_outlined,
              title: '앞으로 30일간 등록된 경기가 없습니다',
              message: followed.isEmpty
                  ? '팀을 팔로우하면 그 팀의 일정만 모아 보여드립니다.'
                  : '공식 일정이 공개되면 자동으로 채워집니다.',
              primaryLabel: '일정 제보하기',
              onPrimary: () => context.push(WbRoutes.submissions),
            );
          }

          final byDay = <String, List<GameCard>>{};
          for (final card in list) {
            byDay
                .putIfAbsent(
                  Kst.dayKey(card.game.startTimeUtc),
                  () => <GameCard>[],
                )
                .add(card);
          }

          final risks = ref
              .watch(
                weatherRisksProvider(
                  WeatherRiskQuery.of(<String, DateTime>{
                    for (final g in list) g.game.id: g.game.startTimeUtc,
                  }),
                ),
              )
              .value;

          if (_listView) {
            return _ListMode(byDay: byDay, now: now, risks: risks);
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: WbSpace.xxl),
            children: <Widget>[
              _MonthHeader(
                month: _visibleMonth,
                onPrevious: () => setState(() {
                  _visibleMonth = DateTime(
                    _visibleMonth.year,
                    _visibleMonth.month - 1,
                  );
                }),
                onNext: () => setState(() {
                  _visibleMonth = DateTime(
                    _visibleMonth.year,
                    _visibleMonth.month + 1,
                  );
                }),
              ),
              _MonthGrid(
                month: _visibleMonth,
                monthKey: monthKey,
                byDay: byDay,
                risks: risks ?? const <String, WeatherRisk>{},
                now: now,
                selectedDayKey: _selectedDayKey,
                onSelect: (key) => setState(() => _selectedDayKey = key),
              ),
              const _ForecastLegend(),
              if (_selectedDayKey != null)
                _DayDetail(
                  dayKey: _selectedDayKey!,
                  games: byDay[_selectedDayKey!] ?? const <GameCard>[],
                  risks: risks ?? const <String, WeatherRisk>{},
                  now: now,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        WbSpace.md,
        WbSpace.sm,
        WbSpace.sm,
      ),
      child: Row(
        children: <Widget>[
          Text(
            KoDate.monthYear(month),
            style: WbType.section.copyWith(color: c.ink),
          ),
          const Spacer(),
          WbTapTarget(
            onTap: onPrevious,
            semanticLabel: '이전 달',
            child: Icon(Icons.chevron_left_rounded, color: c.ink),
          ),
          WbTapTarget(
            onTap: onNext,
            semanticLabel: '다음 달',
            child: Icon(Icons.chevron_right_rounded, color: c.ink),
          ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.monthKey,
    required this.byDay,
    required this.risks,
    required this.now,
    required this.selectedDayKey,
    required this.onSelect,
  });

  final DateTime month;
  final String monthKey;
  final Map<String, List<GameCard>> byDay;
  final Map<String, WeatherRisk> risks;
  final DateTime now;
  final String? selectedDayKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // ISO weekday: Mon=1. Grid starts on Sunday, so shift.
    final leadingBlanks = first.weekday % 7;
    final todayKey = Kst.dayKey(now);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              for (final label in const <String>[
                '일',
                '월',
                '화',
                '수',
                '목',
                '금',
                '토',
              ])
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: WbType.micro.copyWith(color: c.inkMuted),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: WbSpace.sm),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.78,
              mainAxisSpacing: WbSpace.xs,
              crossAxisSpacing: WbSpace.xs,
            ),
            itemCount: leadingBlanks + daysInMonth,
            itemBuilder: (context, index) {
              if (index < leadingBlanks) return const SizedBox.shrink();
              final day = index - leadingBlanks + 1;
              final date = DateTime(month.year, month.month, day);
              final key = Kst.dayKeyOfKstDate(date);
              final games = byDay[key] ?? const <GameCard>[];
              final isToday = key == todayKey;
              final isSelected = key == selectedDayKey;

              // Worst risk of the day drives the badge.
              WeatherRisk? worst;
              for (final g in games) {
                final risk = risks[g.game.id];
                if (risk == null) continue;
                if (worst == null ||
                    risk.level.severity > worst.level.severity) {
                  worst = risk;
                }
              }

              final horizon = ForecastHorizon.between(now, date.toUtc());
              final hasChange = games.any((g) => g.game.status.isDisrupted);

              return _DayCell(
                day: day,
                isToday: isToday,
                isSelected: isSelected,
                gameCount: games.length,
                hasFavorite: games.any((g) => g.involvesFavorite),
                hasChange: hasChange,
                risk: worst,
                horizon: horizon,
                onTap: () => onSelect(key),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.gameCount,
    required this.hasFavorite,
    required this.hasChange,
    required this.risk,
    required this.horizon,
    required this.onTap,
  });

  final int day;
  final bool isToday;
  final bool isSelected;
  final int gameCount;
  final bool hasFavorite;
  final bool hasChange;
  final WeatherRisk? risk;
  final ForecastHorizon horizon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final hasGames = gameCount > 0;

    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '$day일'
          '${hasGames ? ', $gameCount경기' : ', 경기 없음'}'
          '${hasFavorite ? ', 내 팀 경기' : ''}'
          '${hasChange ? ', 일정 변경' : ''}'
          '${risk == null ? '' : ', ${risk!.level.labelKo}'}',
      child: ExcludeSemantics(
        child: Material(
          color: isSelected
              ? c.brand
              : (hasGames ? c.surface : Colors.transparent),
          borderRadius: WbRadius.chipAll,
          child: InkWell(
            onTap: onTap,
            borderRadius: WbRadius.chipAll,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: WbRadius.chipAll,
                border: Border.all(
                  color: isSelected
                      ? c.brand
                      : (isToday
                            ? c.action
                            : (hasGames ? c.divider : Colors.transparent)),
                  width: isToday && !isSelected ? 1.5 : 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    '$day',
                    style: WbType.tabularSmall.copyWith(
                      color: isSelected
                          ? c.surface
                          : (hasGames ? c.ink : c.inkMuted),
                      fontWeight: hasGames ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (hasGames)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        // Shape, not just colour: a filled square for a
                        // followed team, a hollow dot otherwise.
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: hasFavorite
                                ? BoxShape.rectangle
                                : BoxShape.circle,
                            borderRadius: hasFavorite
                                ? BorderRadius.circular(1)
                                : null,
                            color: isSelected ? c.surface : c.brand,
                          ),
                        ),
                        if (hasChange) ...<Widget>[
                          const SizedBox(width: 2),
                          Icon(
                            Icons.priority_high_rounded,
                            size: 8,
                            color: isSelected ? c.surface : c.highlight,
                          ),
                        ],
                      ],
                    ),
                  const SizedBox(height: 2),
                  // Inside D+10 we can show a risk glyph; past it, a dash that
                  // reads "no forecast yet".
                  if (hasGames)
                    Text(
                      horizon == ForecastHorizon.beyondForecast
                          ? '–'
                          : _riskGlyph(risk),
                      style: WbType.micro.copyWith(
                        fontSize: 9,
                        color: isSelected
                            ? c.surface
                            : _riskColor(context, risk),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _riskGlyph(WeatherRisk? risk) {
    if (risk == null) return '·';
    return switch (risk.kind) {
      WeatherRiskKind.rain => '비',
      WeatherRiskKind.wind => '바람',
      WeatherRiskKind.heat => '더위',
      WeatherRiskKind.cold => '추위',
      WeatherRiskKind.none => '·',
    };
  }

  static Color _riskColor(BuildContext context, WeatherRisk? risk) {
    final c = WbTheme.of(context);
    if (risk == null) return c.inkMuted;
    return switch (risk.level) {
      WeatherRiskLevel.severe => c.danger,
      WeatherRiskLevel.caution => c.highlight,
      _ => c.inkMuted,
    };
  }
}

/// Explains the forecast horizon explicitly, so the dashes are understood as a
/// limit of meteorology rather than a bug.
class _ForecastLegend extends StatelessWidget {
  const _ForecastLegend();

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        WbSpace.md,
        WbSpace.screen,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(WbSpace.md),
        decoration: BoxDecoration(
          color: c.divider.withValues(alpha: 0.35),
          borderRadius: WbRadius.chipAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.info_outline_rounded, size: 14, color: c.inkMuted),
                const SizedBox(width: WbSpace.xs),
                Text(
                  '날씨 표기 기준',
                  style: WbType.captionStrong.copyWith(color: c.ink),
                ),
              ],
            ),
            const SizedBox(height: WbSpace.xs),
            Text(
              '0~2일 상세 예보 · 3~10일 범위와 강수확률 · 11일 이후는 일정만 표시(–)\n'
              '기상청 상세 예보는 10일까지 제공되므로 그 이후 일별 날씨는 표시하지 않습니다.',
              style: WbType.micro.copyWith(color: c.inkMuted, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayDetail extends ConsumerWidget {
  const _DayDetail({
    required this.dayKey,
    required this.games,
    required this.risks,
    required this.now,
  });

  final String dayKey;
  final List<GameCard> games;
  final Map<String, WeatherRisk> risks;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final date = DateTime.parse('${dayKey}T00:00:00Z');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WbSectionHeader(title: KoDate.monthDayWeekday(date)),
        if (games.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
            child: Text(
              '이 날짜에는 등록된 경기가 없습니다.',
              style: WbType.caption.copyWith(color: c.inkMuted),
            ),
          )
        else
          for (final card in games)
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
                weatherRisk: risks[card.game.id],
                onTap: () => context.push(WbRoutes.game(card.game.id)),
              ),
            ),
      ],
    );
  }
}

class _ListMode extends StatelessWidget {
  const _ListMode({
    required this.byDay,
    required this.now,
    required this.risks,
  });

  final Map<String, List<GameCard>> byDay;
  final DateTime now;
  final Map<String, WeatherRisk>? risks;

  @override
  Widget build(BuildContext context) {
    final keys = byDay.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: WbSpace.xxl),
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final key = keys[i];
        final date = DateTime.parse('${key}T00:00:00Z');
        final games = byDay[key]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            WbDayHeader(dayUtc: date, now: now, count: games.length),
            for (final card in games)
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
                  weatherRisk: risks?[card.game.id],
                  onTap: () => context.push(WbRoutes.game(card.game.id)),
                ),
              ),
          ],
        );
      },
    );
  }
}
