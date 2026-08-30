import 'package:flutter/material.dart';

import '../../../core/design_system/components/primitives.dart';
import '../../../core/design_system/components/provenance_widgets.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/typography.dart';
import '../../../core/utils/kst.dart';
import '../../../data/models/content.dart';

/// One event, one card — however many outlets covered it.
///
/// Duplicate articles about the same story are folded into a [StoryCluster]
/// upstream, so the reader sees the event once with its sources listed, rather
/// than five near-identical headlines.
class StoryClusterCard extends StatelessWidget {
  const StoryClusterCard({
    super.key,
    required this.cluster,
    required this.now,
    required this.onTap,
    this.showBeginnerContext = true,
    this.dense = false,
  });

  final StoryCluster cluster;
  final DateTime now;
  final VoidCallback onTap;
  final bool showBeginnerContext;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);

    return WbCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (cluster.isTopStory) ...<Widget>[
                const WbBadge(
                  label: '주요',
                  tone: WbBadgeTone.neutral,
                  dense: true,
                ),
                const SizedBox(width: WbSpace.sm),
              ],
              Expanded(
                child: Text(
                  KoDate.relative(cluster.lastUpdatedAt, now),
                  style: WbType.micro.copyWith(color: c.inkMuted),
                ),
              ),
              if (cluster.hasMultipleSources)
                Text(
                  '${cluster.sourceCount}개 매체',
                  style: WbType.micro.copyWith(color: c.inkMuted),
                ),
            ],
          ),
          const SizedBox(height: WbSpace.sm),
          Text(
            cluster.title,
            style: WbType.headline.copyWith(color: c.ink, height: 1.42),
            maxLines: dense ? 2 : 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (cluster.shortSummary != null && !dense) ...<Widget>[
            const SizedBox(height: WbSpace.sm),
            Text(
              cluster.shortSummary!,
              style: WbType.body.copyWith(color: c.inkMuted, height: 1.55),
              maxLines: WbClamp.summary,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (showBeginnerContext &&
              cluster.beginnerContext != null &&
              !dense) ...<Widget>[
            const SizedBox(height: WbSpace.md),
            WbExplainer(title: '처음이신가요?', body: cluster.beginnerContext!),
          ],
          const SizedBox(height: WbSpace.md),
          Row(
            children: <Widget>[
              Expanded(child: WbSummaryMethodBadge(meta: cluster.meta)),
            ],
          ),
          const WbInsetDivider(vertical: WbSpace.md),
          WbSourceLine(provenance: cluster.meta.provenance, now: now),
        ],
      ),
    );
  }
}

/// The list of outlets that covered a story.
///
/// Only the headline, outlet, timestamp, and the description the news API
/// itself returned are shown. Article bodies and outlet images are never
/// stored or reproduced — the link is the way to the full piece.
class StorySourceList extends StatelessWidget {
  const StorySourceList({
    super.key,
    required this.sources,
    required this.now,
    required this.onOpen,
  });

  final List<StorySource> sources;
  final DateTime now;
  final void Function(StorySource source) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    if (sources.isEmpty) {
      return Text(
        '연결된 원문이 없습니다.',
        style: WbType.caption.copyWith(color: c.inkMuted),
      );
    }

    return Column(
      children: <Widget>[
        for (final source in sources)
          Padding(
            padding: const EdgeInsets.only(bottom: WbSpace.sm),
            child: WbCard(
              onTap: () => onOpen(source),
              padding: const EdgeInsets.symmetric(
                horizontal: WbSpace.lg,
                vertical: WbSpace.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        source.outlet ?? '언론사 미상',
                        style: WbType.captionStrong.copyWith(color: c.brand),
                      ),
                      const SizedBox(width: WbSpace.sm),
                      Text(
                        KoDate.relative(source.publishedAt, now),
                        style: WbType.micro.copyWith(color: c.inkMuted),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 14,
                        color: c.inkMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: WbSpace.xs),
                  Text(
                    source.title,
                    style: WbType.body.copyWith(color: c.ink, height: 1.5),
                    maxLines: WbClamp.articleTitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (source.apiDescription != null) ...<Widget>[
                    const SizedBox(height: WbSpace.xs),
                    Text(
                      source.apiDescription!,
                      style: WbType.caption.copyWith(color: c.inkMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
