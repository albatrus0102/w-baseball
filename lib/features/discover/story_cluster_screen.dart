import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/analytics/analytics.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/components/provenance_widgets.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../core/utils/kst.dart';
import '../../data/models/content.dart';
import 'widgets/story_card.dart';

final _clusterProvider = StreamProvider.family<StoryCluster?, String>((
  ref,
  id,
) {
  return ref.watch(contentRepositoryProvider).watchStoryCluster(id);
});

/// One event, its summary, and every outlet that covered it.
///
/// Two summary depths, both attributed. Article bodies are never stored or
/// reproduced — only the headline, outlet, timestamp, and the description the
/// news API itself supplied, plus a link to the original.
class StoryClusterScreen extends ConsumerWidget {
  const StoryClusterScreen({super.key, required this.clusterId});

  final String clusterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cluster = ref.watch(_clusterProvider(clusterId));
    final now = ref.watch(clockProvider)();
    final showBeginner = ref.watch(showBeginnerExplanationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('소식')),
      body: cluster.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(WbSpace.screen),
          child: WbSkeleton(height: 200, borderRadius: WbRadius.cardAll),
        ),
        error: (_, _) => WbEmptyState(
          icon: Icons.error_outline_rounded,
          tone: WbBadgeTone.danger,
          title: '소식을 불러오지 못했습니다',
        ),
        data: (value) {
          if (value == null) {
            return WbEmptyState(
              icon: Icons.search_off_rounded,
              title: '소식을 찾을 수 없습니다',
              primaryLabel: '뒤로',
              onPrimary: () => context.pop(),
            );
          }
          final c = WbTheme.of(context);
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              WbSpace.screen,
              WbSpace.md,
              WbSpace.screen,
              WbSpace.xxl,
            ),
            children: <Widget>[
              Text(
                value.title,
                style: WbType.display.copyWith(color: c.ink, fontSize: 25),
              ),
              const SizedBox(height: WbSpace.sm),
              Text(
                '${KoDate.dateTime(value.firstPublishedAt)} 최초 보도 · '
                '${KoDate.relative(value.lastUpdatedAt, now)} 갱신',
                style: WbType.micro.copyWith(color: c.inkMuted),
              ),
              const SizedBox(height: WbSpace.lg),

              if (value.shortSummary != null) ...<Widget>[
                WbCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const WbBadge(
                        label: '30초 요약',
                        tone: WbBadgeTone.highlight,
                        icon: Icons.bolt_rounded,
                        dense: true,
                      ),
                      const SizedBox(height: WbSpace.md),
                      Text(
                        value.shortSummary!,
                        style: WbType.body.copyWith(color: c.ink, height: 1.7),
                      ),
                      if (value.whyItMatters != null) ...<Widget>[
                        const WbInsetDivider(vertical: WbSpace.md),
                        Text(
                          '왜 중요한가요?',
                          style: WbType.captionStrong.copyWith(color: c.brand),
                        ),
                        const SizedBox(height: WbSpace.xs),
                        Text(
                          value.whyItMatters!,
                          style: WbType.body.copyWith(
                            color: c.ink,
                            height: 1.65,
                          ),
                        ),
                      ],
                      const SizedBox(height: WbSpace.md),
                      WbSummaryMethodBadge(meta: value.meta),
                      if (value.meta.generatedAt != null) ...<Widget>[
                        const SizedBox(height: WbSpace.xs),
                        Text(
                          '${KoDate.dateTime(value.meta.generatedAt!)} 생성',
                          style: WbType.micro.copyWith(color: c.inkMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: WbSpace.md),
              ],

              if (showBeginner && value.beginnerContext != null) ...<Widget>[
                WbExplainer(title: '3분 이해 · 배경', body: value.beginnerContext!),
                const SizedBox(height: WbSpace.md),
              ],

              const WbSectionHeader(
                title: '보도한 매체',
                subtitle: '원문은 각 매체에서 확인해 주세요.',
                padding: EdgeInsets.only(top: WbSpace.md, bottom: WbSpace.md),
              ),
              StorySourceList(
                sources: value.sources,
                now: now,
                onOpen: (source) {
                  ref
                      .read(analyticsProvider)
                      .log(
                        AnalyticsEvent.sourceOpened,
                        properties: <String, Object?>{'screen': 'story'},
                      );
                  openSource(
                    context,
                    url: source.url,
                    title: source.title,
                    sourceLabel: source.outlet ?? '언론사',
                  );
                },
              ),

              const SizedBox(height: WbSpace.md),
              WbSourceLine(provenance: value.meta.provenance, now: now),
            ],
          );
        },
      ),
    );
  }
}
