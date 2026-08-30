import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/components/provenance_widgets.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../data/models/content.dart';

final _guideProvider = StreamProvider.family<BeginnerGuide?, String>((ref, id) {
  return ref
      .watch(contentRepositoryProvider)
      .watchGuides()
      .map((list) => list.where((g) => g.id == id).firstOrNull);
});

/// A short explainer.
///
/// Guides are deliberately brief and anchored to a screen or a stat, rather
/// than collected into a long encyclopaedia that nobody opens.
class GuideScreen extends ConsumerWidget {
  const GuideScreen({super.key, required this.guideId});

  final String guideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guide = ref.watch(_guideProvider(guideId));
    final now = DateTime.now().toUtc();
    final c = WbTheme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('알아두기')),
      body: guide.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(WbSpace.screen),
          child: WbSkeleton(height: 180, borderRadius: WbRadius.cardAll),
        ),
        error: (_, _) => WbEmptyState(
          icon: Icons.error_outline_rounded,
          tone: WbBadgeTone.danger,
          title: '내용을 불러오지 못했습니다',
        ),
        data: (value) {
          if (value == null) {
            return WbEmptyState(
              icon: Icons.search_off_rounded,
              title: '내용을 찾을 수 없습니다',
              primaryLabel: '뒤로',
              onPrimary: () => context.pop(),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              WbSpace.screen,
              WbSpace.lg,
              WbSpace.screen,
              WbSpace.xxl,
            ),
            children: <Widget>[
              Text(
                value.title,
                style: WbType.display.copyWith(color: c.ink, fontSize: 25),
              ),
              if (value.readSeconds != null) ...<Widget>[
                const SizedBox(height: WbSpace.sm),
                Text(
                  '${value.readSeconds}초면 읽어요',
                  style: WbType.micro.copyWith(color: c.inkMuted),
                ),
              ],
              const SizedBox(height: WbSpace.lg),
              Text(
                value.body,
                style: WbType.body.copyWith(color: c.ink, height: 1.75),
              ),
              const SizedBox(height: WbSpace.xl),
              WbSourceLine(provenance: value.meta.provenance, now: now),
            ],
          );
        },
      ),
    );
  }
}
