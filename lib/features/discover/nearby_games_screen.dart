import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/analytics/analytics.dart';
import '../../core/design_system/components/game_widgets.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../core/platform/platform_services.dart';
import '../../core/utils/kst.dart';
import '../../data/models/audience.dart';
import '../../data/models/domain.dart';
import '../../data/models/weather.dart';
import '../../data/repositories/game_repository.dart';
import '../../data/repositories/weather_repository.dart';
import 'discover_screen.dart' show whyWatchLine;

enum _When { today, weekend, month }

/// Games you could actually go and watch.
///
/// Location is never required. The user picks a 시·도 and everything works from
/// its centre point. If they do grant location later, the coordinates are used
/// **on-device only**, for distance sorting — never stored, logged, or sent
/// anywhere. There is no background location use.
class NearbyGamesScreen extends ConsumerStatefulWidget {
  const NearbyGamesScreen({super.key});

  @override
  ConsumerState<NearbyGamesScreen> createState() => _NearbyGamesScreenState();
}

class _NearbyGamesScreenState extends ConsumerState<NearbyGamesScreen> {
  _When _when = _When.weekend;
  String? _regionCode;
  bool _attendableOnly = false;

  @override
  void initState() {
    super.initState();
    _regionCode = ref.read(audienceProvider).regionCode;
  }

  ({DateTime from, DateTime to}) _range(DateTime now) {
    return switch (_when) {
      _When.today => (
        from: Kst.startOfKstDayUtc(now),
        to: Kst.endOfKstDayUtc(now),
      ),
      _When.weekend => () {
        final weekend = Kst.upcomingWeekendUtc(now);
        return (from: weekend.startUtc, to: weekend.endUtc);
      }(),
      _When.month => () {
        final start = Kst.startOfKstDayUtc(now);
        return (from: start, to: start.add(const Duration(days: 30)));
      }(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    final range = _range(now);
    final region = KoreanRegion.byCode(_regionCode);

    final query = GameQuery(
      fromUtc: range.from,
      toUtc: range.to,
      regionCodes: _regionCode == null
          ? const <String>[]
          : <String>[_regionCode!],
      limit: 60,
    );
    final games = ref.watch(gamesProvider(query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('근처 경기'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: <Widget>[
              _WhenBar(
                value: _when,
                onChanged: (v) => setState(() => _when = v),
              ),
              _RegionBar(
                selected: _regionCode,
                attendableOnly: _attendableOnly,
                onRegion: (code) => setState(() => _regionCode = code),
                onToggleAttendable: () =>
                    setState(() => _attendableOnly = !_attendableOnly),
              ),
            ],
          ),
        ),
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
          title: '경기를 불러오지 못했습니다',
        ),
        data: (list) => _Results(
          games: list,
          now: now,
          region: region,
          when: _when,
          attendableOnly: _attendableOnly,
          onClearRegion: () => setState(() => _regionCode = null),
          onWidenWhen: () => setState(() => _when = _When.month),
        ),
      ),
    );
  }
}

class _WhenBar extends StatelessWidget {
  const _WhenBar({required this.value, required this.onChanged});

  final _When value;
  final ValueChanged<_When> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        0,
        WbSpace.screen,
        WbSpace.sm,
      ),
      child: SegmentedButton<_When>(
        segments: const <ButtonSegment<_When>>[
          ButtonSegment<_When>(value: _When.today, label: Text('오늘')),
          ButtonSegment<_When>(value: _When.weekend, label: Text('이번 주말')),
          ButtonSegment<_When>(value: _When.month, label: Text('30일')),
        ],
        selected: <_When>{value},
        onSelectionChanged: (s) => onChanged(s.first),
        showSelectedIcon: false,
      ),
    );
  }
}

class _RegionBar extends StatelessWidget {
  const _RegionBar({
    required this.selected,
    required this.attendableOnly,
    required this.onRegion,
    required this.onToggleAttendable,
  });

  final String? selected;
  final bool attendableOnly;
  final ValueChanged<String?> onRegion;
  final VoidCallback onToggleAttendable;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: WbSpace.screen,
          vertical: WbSpace.sm,
        ),
        children: <Widget>[
          WbFilterChip(
            label: '관람 가능 확인됨',
            icon: Icons.verified_outlined,
            selected: attendableOnly,
            onTap: onToggleAttendable,
          ),
          const SizedBox(width: WbSpace.sm),
          WbFilterChip(
            label: '전체 지역',
            selected: selected == null,
            onTap: () => onRegion(null),
          ),
          for (final region in KoreanRegion.all) ...<Widget>[
            const SizedBox(width: WbSpace.sm),
            WbFilterChip(
              label: region.name,
              selected: selected == region.code,
              onTap: () =>
                  onRegion(selected == region.code ? null : region.code),
              onRemove: selected == region.code ? () => onRegion(null) : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({
    required this.games,
    required this.now,
    required this.region,
    required this.when,
    required this.attendableOnly,
    required this.onClearRegion,
    required this.onWidenWhen,
  });

  final List<GameCard> games;
  final DateTime now;
  final KoreanRegion? region;
  final _When when;
  final bool attendableOnly;
  final VoidCallback onClearRegion;
  final VoidCallback onWidenWhen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (games.isEmpty) {
      return WbEmptyState(
        icon: Icons.travel_explore_outlined,
        title: region == null
            ? '조건에 맞는 경기가 없습니다'
            : '${region!.name}에 해당 기간 경기가 없습니다',
        message: '기간을 넓히거나 다른 지역을 선택해 보세요.',
        primaryLabel: when == _When.month ? null : '30일 범위로 보기',
        onPrimary: when == _When.month ? null : onWidenWhen,
        secondaryLabel: region == null ? null : '전체 지역 보기',
        onSecondary: region == null ? null : onClearRegion,
      );
    }

    final risks = ref
        .watch(
          weatherRisksProvider(
            WeatherRiskQuery.of(<String, DateTime>{
              for (final g in games) g.game.id: g.game.startTimeUtc,
            }),
          ),
        )
        .value;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        WbSpace.md,
        WbSpace.screen,
        WbSpace.xxl,
      ),
      itemCount: games.length,
      itemBuilder: (context, i) {
        final card = games[i];
        final venue = card.venue;
        final distance =
            (region != null && venue != null && venue.hasCoordinates)
            // Computed here, on the device, from a region centroid the user
            // chose. No coordinates leave this function.
            ? haversineKm(
                lat1: region!.latitude,
                lon1: region!.longitude,
                lat2: venue.latitude!,
                lon2: venue.longitude!,
              )
            : null;

        return Padding(
          padding: const EdgeInsets.only(bottom: WbSpace.md),
          child: _NearbyCard(
            card: card,
            now: now,
            risk: risks?[card.game.id],
            distanceKm: distance,
          ),
        );
      },
    );
  }
}

class _NearbyCard extends ConsumerWidget {
  const _NearbyCard({
    required this.card,
    required this.now,
    required this.risk,
    required this.distanceKm,
  });

  final GameCard card;
  final DateTime now;
  final WeatherRisk? risk;
  final double? distanceKm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final game = card.game;
    final saved = ref.watch(savedGameIdsProvider).value ?? const <String>{};
    final isSaved = saved.contains(game.id);
    final why = whyWatchLine(card, now);

    return WbCard(
      onTap: () {
        ref.read(analyticsProvider).log(AnalyticsEvent.nearbyGameViewed);
        context.push(WbRoutes.game(game.id));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                KoDate.dateTime(game.startTimeUtc),
                style: WbType.captionStrong.copyWith(color: c.brand),
              ),
              const Spacer(),
              WbGameStatusBadge(status: game.status, dense: true),
            ],
          ),
          const SizedBox(height: WbSpace.md),
          Text(
            '${card.awayTeam.displayName} vs ${card.homeTeam.displayName}',
            style: WbType.headline.copyWith(color: c.ink),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (card.competition != null) ...<Widget>[
            const SizedBox(height: WbSpace.xxs),
            Text(
              card.competition!.displayName,
              style: WbType.caption.copyWith(color: c.inkMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: WbSpace.md),
          Row(
            children: <Widget>[
              Icon(Icons.place_outlined, size: 14, color: c.inkMuted),
              const SizedBox(width: WbSpace.xs),
              Expanded(
                child: Text(
                  <String?>[
                    card.venue?.name ?? '구장 미정',
                    if (distanceKm != null)
                      distanceKm! < 1 ? '1km 이내' : '약 ${distanceKm!.round()}km',
                  ].whereType<String>().join(' · '),
                  style: WbType.caption.copyWith(color: c.inkMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          // Only shown when we have a factual reason; never generated filler.
          if (why != null) ...<Widget>[
            const SizedBox(height: WbSpace.sm),
            Row(
              children: <Widget>[
                Icon(Icons.star_outline_rounded, size: 14, color: c.highlight),
                const SizedBox(width: WbSpace.xs),
                Expanded(
                  child: Text(
                    why,
                    style: WbType.caption.copyWith(color: c.ink),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: WbSpace.md),
          Wrap(
            spacing: WbSpace.xs,
            runSpacing: WbSpace.xs,
            children: <Widget>[
              // Absence of confirmation is stated, not assumed to mean "free".
              const WbBadge(
                label: '관람 가능 여부 확인 필요',
                tone: WbBadgeTone.muted,
                icon: Icons.help_outline_rounded,
                dense: true,
              ),
              if (risk != null && risk!.level != WeatherRiskLevel.clear)
                WbWeatherRiskBadge(risk: risk!),
            ],
          ),
          const WbInsetDivider(vertical: WbSpace.md),
          Row(
            children: <Widget>[
              _ActionButton(
                icon: isSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                label: '저장',
                active: isSaved,
                onTap: () async {
                  final nowSaved = await ref
                      .read(followRepositoryProvider)
                      .toggleSaved(SavedItemKind.game, game.id);
                  await ref.read(platformServicesProvider).haptics.selection();
                  if (nowSaved) {
                    await ref
                        .read(analyticsProvider)
                        .log(AnalyticsEvent.gameSaved);
                  }
                },
              ),
              _ActionButton(
                icon: Icons.event_available_outlined,
                label: '캘린더',
                onTap: () => _addToCalendar(context, ref),
              ),
              _ActionButton(
                icon: Icons.directions_outlined,
                label: '길찾기',
                onTap: () => _directions(context, ref),
              ),
              _ActionButton(
                icon: Icons.ios_share_rounded,
                label: '공유',
                onTap: () => ref
                    .read(platformServicesProvider)
                    .sharing
                    .shareText(
                      text:
                          '${card.awayTeam.displayName} vs ${card.homeTeam.displayName}\n'
                          '${KoDate.dateTime(game.startTimeUtc)}'
                          '${card.venue == null ? '' : ' · ${card.venue!.name}'}',
                      subject: '여자야구 경기',
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addToCalendar(BuildContext context, WidgetRef ref) async {
    final services = ref.read(platformServicesProvider);
    final ok = await services.calendar.addEvent(
      CalendarEvent(
        title: '${card.awayTeam.displayName} vs ${card.homeTeam.displayName}',
        startUtc: card.game.startTimeUtc,
        endUtc: card.game.startTimeUtc.add(const Duration(hours: 2)),
        location: card.venue?.name,
        description: card.competition?.displayName,
      ),
    );
    if (ok) {
      await ref.read(analyticsProvider).log(AnalyticsEvent.calendarAdded);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사용할 수 있는 캘린더 앱을 찾지 못했습니다.')),
      );
    }
  }

  Future<void> _directions(BuildContext context, WidgetRef ref) async {
    final venue = card.venue;
    if (venue == null || !venue.isRoutable) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('구장 위치 정보가 아직 없습니다.')));
      }
      return;
    }
    final ok = await ref
        .read(platformServicesProvider)
        .maps
        .openDirections(
          latitude: venue.latitude,
          longitude: venue.longitude,
          address: venue.address,
          label: venue.name,
        );
    if (ok) {
      await ref.read(analyticsProvider).log(AnalyticsEvent.directionsOpened);
    }
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: WbRadius.chipAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: WbSpace.sm),
          child: Column(
            children: <Widget>[
              Icon(icon, size: 19, color: active ? c.brand : c.inkMuted),
              const SizedBox(height: WbSpace.xxs),
              Text(
                label,
                style: WbType.micro.copyWith(
                  color: active ? c.brand : c.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
