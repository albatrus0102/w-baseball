import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/design_system/components/primitives.dart';
import '../../../core/design_system/components/provenance_widgets.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/typography.dart';
import '../../../data/mappers/row_mappers.dart';
import '../../../data/models/content.dart';
import '../../../data/models/domain.dart';
import '../game_detail_screen.dart';

final _attendanceProvider = StreamProvider.family<AttendanceInfo?, String>((
  ref,
  gameId,
) {
  final db = ref.watch(databaseProvider);
  final select = db.select(db.attendanceInfos)
    ..where((t) => t.gameId.equals(gameId));
  return select.watchSingleOrNull().map((row) => row?.toDomain());
});

final _venueProvider = StreamProvider.family<Venue?, String>((ref, venueId) {
  final db = ref.watch(databaseProvider);
  final select = db.select(db.venues)
    ..where((t) => t.id.equals(venueId))
    ..orderBy([(t) => OrderingTerm(expression: t.name)]);
  return select.watchSingleOrNull().map((row) => row?.toDomain());
});

/// "관람 준비" — everything needed to decide whether and how to attend.
///
/// The governing rule: anything not explicitly confirmed is shown as
/// "확인 필요". We never infer that a game is free, open to the public, or
/// family-suitable from the absence of information.
class AttendanceSection extends ConsumerWidget {
  const AttendanceSection({super.key, required this.detail, required this.now});

  final GameDetail detail;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final game = detail.game;
    final venue = detail.card.venue;
    final attendance = ref.watch(_attendanceProvider(game.id)).value;
    final status = attendance?.status ?? AttendanceStatus.needsConfirmation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const WbSectionHeader(title: '관람 준비'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
          child: WbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    WbBadge(
                      label: status.labelKo,
                      tone: switch (status) {
                        AttendanceStatus.open => WbBadgeTone.positive,
                        AttendanceStatus.closed => WbBadgeTone.danger,
                        AttendanceStatus.needsConfirmation => WbBadgeTone.muted,
                      },
                      icon: switch (status) {
                        AttendanceStatus.open => Icons.check_circle_outline,
                        AttendanceStatus.closed => Icons.block_rounded,
                        AttendanceStatus.needsConfirmation =>
                          Icons.help_outline_rounded,
                      },
                    ),
                    if (attendance?.familyFriendlyConfirmed ??
                        false) ...<Widget>[
                      const SizedBox(width: WbSpace.sm),
                      const WbBadge(
                        label: '가족 관람 확인됨',
                        tone: WbBadgeTone.positive,
                        dense: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: WbSpace.md),

                // Venue + directions.
                if (venue != null) ...<Widget>[
                  _InfoRow(
                    icon: Icons.place_outlined,
                    label: venue.name,
                    value: venue.address ?? '주소 정보 없음',
                    onTap: venue.isRoutable
                        ? () => _openDirections(context, ref, venue)
                        : null,
                    actionLabel: venue.isRoutable ? '길찾기' : null,
                  ),
                  const WbInsetDivider(vertical: WbSpace.md),
                ] else
                  _InfoRow(
                    icon: Icons.place_outlined,
                    label: '구장 미정',
                    value: '확정되면 안내드립니다.',
                  ),

                // Weather sits inside the attendance block because it is part
                // of deciding whether to go, not a separate curiosity.
                GameWeatherPanel(
                  gameId: game.id,
                  startTimeUtc: game.startTimeUtc,
                ),
                const WbInsetDivider(vertical: WbSpace.md),

                _ConfirmationRow(
                  label: '관람료',
                  value: attendance?.admissionNote,
                  // Deliberately never "무료" by default.
                  unknownText: '확인 필요 — 무료 여부가 확인되지 않았습니다',
                ),
                _ConfirmationRow(
                  label: '입장 절차',
                  value: attendance?.entryProcedure,
                ),
                _ConfirmationRow(label: '좌석', value: attendance?.seatingNote),
                _ConfirmationRow(
                  label: '화장실',
                  value: attendance?.restroomAvailable == null
                      ? null
                      : (attendance!.restroomAvailable! ? '있음' : '없음'),
                ),
                _ConfirmationRow(
                  label: '매점',
                  value: attendance?.concessionAvailable == null
                      ? null
                      : (attendance!.concessionAvailable! ? '있음' : '없음'),
                ),

                if (attendance?.parkingUrl != null ||
                    attendance?.transitUrl != null) ...<Widget>[
                  const WbInsetDivider(vertical: WbSpace.md),
                  Wrap(
                    spacing: WbSpace.sm,
                    children: <Widget>[
                      if (attendance?.parkingUrl != null)
                        OutlinedButton.icon(
                          onPressed: () => openSource(
                            context,
                            url: attendance!.parkingUrl!,
                            title: '주차 안내',
                            sourceLabel: attendance.provenance.sourceName,
                          ),
                          icon: const Icon(
                            Icons.local_parking_outlined,
                            size: 16,
                          ),
                          label: const Text('주차 안내'),
                        ),
                      if (attendance?.transitUrl != null)
                        OutlinedButton.icon(
                          onPressed: () => openSource(
                            context,
                            url: attendance!.transitUrl!,
                            title: '대중교통 안내',
                            sourceLabel: attendance.provenance.sourceName,
                          ),
                          icon: const Icon(
                            Icons.directions_bus_outlined,
                            size: 16,
                          ),
                          label: const Text('대중교통'),
                        ),
                    ],
                  ),
                ],

                if (attendance != null) ...<Widget>[
                  const WbInsetDivider(vertical: WbSpace.md),
                  WbSourceLine(provenance: attendance.provenance, now: now),
                ] else ...<Widget>[
                  const SizedBox(height: WbSpace.md),
                  Text(
                    '관람 정보가 등록되지 않았습니다. 주최 측 공지를 확인해 주세요.',
                    style: WbType.micro.copyWith(color: c.inkMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openDirections(
    BuildContext context,
    WidgetRef ref,
    Venue venue,
  ) async {
    final ok = await ref
        .read(platformServicesProvider)
        .maps
        .openDirections(
          latitude: venue.latitude,
          longitude: venue.longitude,
          address: venue.address,
          label: venue.name,
        );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('지도 앱을 열지 못했습니다.')));
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.actionLabel,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: c.inkMuted),
        const SizedBox(width: WbSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: WbType.bodyStrong.copyWith(color: c.ink)),
              const SizedBox(height: WbSpace.xxs),
              Text(
                value,
                style: WbType.caption.copyWith(color: c.inkMuted, height: 1.5),
              ),
            ],
          ),
        ),
        if (onTap != null && actionLabel != null)
          TextButton(onPressed: onTap, child: Text(actionLabel!)),
      ],
    );
  }
}

/// A field whose absence means "not confirmed", never "no".
class _ConfirmationRow extends StatelessWidget {
  const _ConfirmationRow({
    required this.label,
    required this.value,
    this.unknownText = '확인 필요',
  });

  final String label;
  final String? value;
  final String unknownText;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final known = value != null && value!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WbSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: WbType.caption.copyWith(color: c.inkMuted),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (!known) ...<Widget>[
                  Icon(Icons.help_outline_rounded, size: 14, color: c.inkMuted),
                  const SizedBox(width: WbSpace.xs),
                ],
                Expanded(
                  child: Text(
                    known ? value! : unknownText,
                    style: WbType.caption.copyWith(
                      color: known ? c.ink : c.inkMuted,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Exposed so the venue screen can reuse the same lookup.
final venueByIdProvider = _venueProvider;
