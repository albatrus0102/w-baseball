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
import '../../core/utils/kst.dart';
import '../../data/repositories/game_repository.dart';
import '../games/widgets/attendance_section.dart';

/// A venue plus the fixtures scheduled there.
///
/// Directions are one tap — the user never has to copy an address by hand.
class VenueScreen extends ConsumerWidget {
  const VenueScreen({super.key, required this.venueId});

  final String venueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final now = DateTime.now().toUtc();
    final venue = ref.watch(venueByIdProvider(venueId));

    return Scaffold(
      appBar: AppBar(title: const Text('경기장')),
      body: venue.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(WbSpace.screen),
          child: WbSkeleton(height: 160, borderRadius: WbRadius.cardAll),
        ),
        error: (_, _) => WbEmptyState(
          icon: Icons.error_outline_rounded,
          tone: WbBadgeTone.danger,
          title: '경기장 정보를 불러오지 못했습니다',
        ),
        data: (value) {
          if (value == null) {
            return WbEmptyState(
              icon: Icons.search_off_rounded,
              title: '경기장을 찾을 수 없습니다',
              primaryLabel: '뒤로',
              onPrimary: () => context.pop(),
            );
          }

          final games = ref.watch(
            gamesProvider(GameQuery(fromUtc: Kst.hourBucket(now), limit: 30)),
          );

          return ListView(
            padding: const EdgeInsets.only(bottom: WbSpace.xxl),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(WbSpace.screen),
                child: WbCard(
                  emphasized: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        value.name,
                        style: WbType.title.copyWith(color: c.ink),
                      ),
                      const SizedBox(height: WbSpace.sm),
                      Text(
                        value.address ?? '주소 정보가 없습니다',
                        style: WbType.body.copyWith(color: c.inkMuted),
                      ),
                      if (value.capacity != null) ...<Widget>[
                        const SizedBox(height: WbSpace.xs),
                        Text(
                          '수용 인원 약 ${value.capacity}석',
                          style: WbType.caption.copyWith(color: c.inkMuted),
                        ),
                      ],
                      if (value.surface != null) ...<Widget>[
                        const SizedBox(height: WbSpace.xs),
                        Text(
                          '구장 표면 ${value.surface}',
                          style: WbType.caption.copyWith(color: c.inkMuted),
                        ),
                      ],
                      const SizedBox(height: WbSpace.lg),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: value.isRoutable
                              ? () => _directions(context, ref, value)
                              : null,
                          icon: const Icon(Icons.directions_rounded, size: 18),
                          label: Text(
                            value.isRoutable ? '지도 앱으로 길찾기' : '위치 정보 없음',
                          ),
                        ),
                      ),
                      const WbInsetDivider(vertical: WbSpace.md),
                      WbSourceLine(provenance: value.provenance, now: now),
                    ],
                  ),
                ),
              ),
              const WbSectionHeader(title: '이 구장의 다가오는 경기'),
              games.maybeWhen(
                data: (list) {
                  final here = list
                      .where((g) => g.venue?.id == venueId)
                      .toList();
                  if (here.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: WbSpace.screen,
                      ),
                      child: WbEmptyState(
                        compact: true,
                        icon: Icons.event_busy_outlined,
                        title: '예정된 경기가 없습니다',
                      ),
                    );
                  }
                  return Column(
                    children: <Widget>[
                      for (final card in here)
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
                            onTap: () =>
                                context.push(WbRoutes.game(card.game.id)),
                          ),
                        ),
                    ],
                  );
                },
                orElse: () => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: WbSpace.screen),
                  child: WbGameRowSkeleton(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _directions(
    BuildContext context,
    WidgetRef ref,
    dynamic venue,
  ) async {
    final ok = await ref
        .read(platformServicesProvider)
        .maps
        .openDirections(
          latitude: venue.latitude as double?,
          longitude: venue.longitude as double?,
          address: venue.address as String?,
          label: venue.name as String,
        );
    if (ok) {
      await ref.read(analyticsProvider).log(AnalyticsEvent.directionsOpened);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('지도 앱을 열지 못했습니다.')));
    }
  }
}
