import 'package:flutter/material.dart';

import '../../../core/design_system/components/primitives.dart';
import '../../../core/design_system/components/provenance_widgets.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/typography.dart';
import '../../../core/utils/kst.dart';
import '../../../data/models/audience.dart';
import '../../../data/models/content.dart';
import '../../../data/repositories/content_repository.dart';

/// The lead card of the discover experience.
///
/// Editorial in feel — one strong headline, generous space, a single primary
/// action — in contrast to the dense, tabular cards used in 마이야구. Same
/// tokens, different information density.
class FeaturedHeroCard extends StatelessWidget {
  const FeaturedHeroCard({
    super.key,
    required this.item,
    required this.policy,
    required this.now,
    required this.onTap,
  });

  final FeaturedItem item;
  final SpoilerPolicy policy;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final topic = item.topic;
    final recap = item.latestRecap;
    final masked = item.isMasked(policy);

    return WbCard(
      emphasized: true,
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // A typographic banner rather than a stock photo: we only render an
          // image when its licence is explicitly cleared, and we never
          // generate one.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              WbSpace.lg,
              WbSpace.lg,
              WbSpace.lg,
              WbSpace.md,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  c.brand.withValues(alpha: 0.10),
                  c.action.withValues(alpha: 0.06),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    WbBadge(
                      label: _kindLabel(topic.kind),
                      tone: WbBadgeTone.live,
                      icon: _kindIcon(topic.kind),
                      dense: true,
                    ),
                    if (item.program?.broadcaster != null) ...<Widget>[
                      const SizedBox(width: WbSpace.sm),
                      Text(
                        item.program!.broadcaster!,
                        style: WbType.micro.copyWith(color: c.inkMuted),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: WbSpace.md),
                Text(
                  topic.title,
                  style: WbType.display.copyWith(color: c.ink, fontSize: 24),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (topic.subtitle != null) ...<Widget>[
                  const SizedBox(height: WbSpace.sm),
                  Text(
                    topic.subtitle!,
                    style: WbType.body.copyWith(
                      color: c.inkMuted,
                      height: 1.55,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(WbSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (item.latestEpisode != null) ...<Widget>[
                  _EpisodeLine(
                    episode: item.latestEpisode!,
                    season: item.programSeason,
                  ),
                  const SizedBox(height: WbSpace.md),
                ],
                if (recap != null) ...<Widget>[
                  WbSpoilerVeil(
                    masked: masked,
                    label: '이번 회차 결과가 포함되어 있습니다',
                    child: Text(
                      recap.whatHappened ?? recap.teaser ?? '',
                      style: WbType.body.copyWith(color: c.ink, height: 1.6),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: WbSpace.md),
                  WbSummaryMethodBadge(meta: recap.meta),
                  const SizedBox(height: WbSpace.md),
                ],
                if (item.programSeason != null)
                  _NextAirLine(
                    season: item.programSeason!,
                    now: now,
                    lastAiredAt: item.latestEpisode?.airedAt,
                  ),
                const WbInsetDivider(vertical: WbSpace.md),
                WbSourceLine(provenance: topic.meta.provenance, now: now),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _kindLabel(FeaturedTopicKind kind) => switch (kind) {
    FeaturedTopicKind.broadcast => '방송',
    FeaturedTopicKind.international => '국제대회',
    FeaturedTopicKind.domesticCompetition => '국내대회',
    FeaturedTopicKind.story => '이야기',
    FeaturedTopicKind.nearbyGames => '근처 경기',
    FeaturedTopicKind.gettingStarted => '입문',
  };

  static IconData _kindIcon(FeaturedTopicKind kind) => switch (kind) {
    FeaturedTopicKind.broadcast => Icons.tv_rounded,
    FeaturedTopicKind.international => Icons.public_rounded,
    FeaturedTopicKind.domesticCompetition => Icons.emoji_events_outlined,
    FeaturedTopicKind.story => Icons.auto_stories_outlined,
    FeaturedTopicKind.nearbyGames => Icons.place_outlined,
    FeaturedTopicKind.gettingStarted => Icons.school_outlined,
  };
}

class _EpisodeLine extends StatelessWidget {
  const _EpisodeLine({required this.episode, required this.season});

  final Episode episode;
  final ProgramSeason? season;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final aired = episode.airedAt;
    return Row(
      children: <Widget>[
        Icon(Icons.play_circle_outline_rounded, size: 15, color: c.action),
        const SizedBox(width: WbSpace.xs),
        Flexible(
          child: Text(
            <String?>[
              season?.title,
              '${episode.episodeNumber}회',
              if (aired != null) '${KoDate.monthDay(aired)} 방송',
            ].whereType<String>().join(' · '),
            style: WbType.captionStrong.copyWith(color: c.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// "다음 방송" derived only from the published weekly slot.
///
/// If the schedule is unknown, or the season has ended, nothing is shown — we
/// never guess an air date.
class _NextAirLine extends StatelessWidget {
  const _NextAirLine({
    required this.season,
    required this.now,
    this.lastAiredAt,
  });

  final ProgramSeason season;
  final DateTime now;

  /// Evidence that the published weekly slot is still being kept to.
  final DateTime? lastAiredAt;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final aired = lastAiredAt;
    final next = season.nextAirSlot(
      Kst.toKst(now),
      lastAiredAtKst: aired == null ? null : Kst.toKst(aired),
    );

    if (next == null) {
      if (!season.isActive) {
        return Text(
          '지난 시즌입니다. 다시보기와 인물 정보를 확인할 수 있어요.',
          style: WbType.caption.copyWith(color: c.inkMuted),
        );
      }
      return const SizedBox.shrink();
    }

    return Row(
      children: <Widget>[
        Icon(Icons.schedule_rounded, size: 14, color: c.inkMuted),
        const SizedBox(width: WbSpace.xs),
        // Korean date + time is long; at 130% text on a 360dp screen it must
        // wrap rather than run off the card.
        Expanded(
          child: Text(
            '다음 방송 ${KoDate.monthDayWeekday(Kst.fromKst(next))} '
            '${KoDate.time(Kst.fromKst(next))}',
            style: WbType.caption.copyWith(color: c.inkMuted),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Compact recap card for the home "방송 다시 보기" module.
class ProgramRecapCard extends StatelessWidget {
  const ProgramRecapCard({
    super.key,
    required this.item,
    required this.policy,
    required this.now,
    required this.onTap,
  });

  final FeaturedItem item;
  final SpoilerPolicy policy;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final recap = item.latestRecap;
    if (recap == null) return const SizedBox.shrink();
    final masked = item.isMasked(policy);

    return WbCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const WbBadge(
                label: '30초 요약',
                tone: WbBadgeTone.highlight,
                icon: Icons.bolt_rounded,
                dense: true,
              ),
              const Spacer(),
              if (item.latestEpisode != null)
                Text(
                  '${item.latestEpisode!.episodeNumber}회',
                  style: WbType.micro.copyWith(color: c.inkMuted),
                ),
            ],
          ),
          const SizedBox(height: WbSpace.md),
          WbSpoilerVeil(
            masked: masked,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (recap.whatHappened != null)
                  _RecapLine(label: '무슨 일이', text: recap.whatHappened!),
                if (recap.whyItMatters != null) ...<Widget>[
                  const SizedBox(height: WbSpace.sm),
                  _RecapLine(label: '왜 중요한가', text: recap.whyItMatters!),
                ],
                if (recap.whatToWatchNext != null) ...<Widget>[
                  const SizedBox(height: WbSpace.sm),
                  _RecapLine(label: '다음에 볼 것', text: recap.whatToWatchNext!),
                ],
              ],
            ),
          ),
          const SizedBox(height: WbSpace.md),
          WbSummaryMethodBadge(meta: recap.meta),
          const WbInsetDivider(vertical: WbSpace.md),
          WbSourceLine(provenance: recap.meta.provenance, now: now),
        ],
      ),
    );
  }
}

class _RecapLine extends StatelessWidget {
  const _RecapLine({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 66,
          child: Text(label, style: WbType.micro.copyWith(color: c.inkMuted)),
        ),
        Expanded(
          child: Text(
            text,
            style: WbType.body.copyWith(color: c.ink, height: 1.55),
          ),
        ),
      ],
    );
  }
}

/// "실제 여자야구와 연결" — only confirmed links.
///
/// An unconfirmed connection between a broadcast participant and a real player
/// is simply absent; we never infer a relationship to fill the block.
class RealBaseballLinks extends StatelessWidget {
  const RealBaseballLinks({
    super.key,
    required this.links,
    required this.onOpen,
  });

  final List<ContentEntityLink> links;
  final void Function(ContentEntityLink link) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final confirmed = links.where((l) => l.isConfirmedIdentity).toList();
    final related = links
        .where(
          (l) =>
              l.relation == ContentLinkRelation.opponent ||
              l.relation == ContentLinkRelation.relatedContext,
        )
        .toList();
    final all = <ContentEntityLink>[...confirmed, ...related];

    if (all.isEmpty) {
      return WbCard(
        child: Row(
          children: <Widget>[
            Icon(Icons.link_off_rounded, size: 16, color: c.inkMuted),
            const SizedBox(width: WbSpace.sm),
            Expanded(
              child: Text(
                '실제 팀·선수와의 공식 확인된 연결 정보가 아직 없습니다.',
                style: WbType.caption.copyWith(color: c.inkMuted, height: 1.5),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final link in all)
          Padding(
            padding: const EdgeInsets.only(bottom: WbSpace.sm),
            child: WbCard(
              onTap: () => onOpen(link),
              padding: const EdgeInsets.symmetric(
                horizontal: WbSpace.lg,
                vertical: WbSpace.md,
              ),
              child: Row(
                children: <Widget>[
                  Icon(_iconFor(link.toKind), size: 18, color: c.brand),
                  const SizedBox(width: WbSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          link.label ?? link.toId,
                          style: WbType.bodyStrong.copyWith(color: c.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: WbSpace.xxs),
                        Text(
                          link.relation.labelKo,
                          style: WbType.micro.copyWith(color: c.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.inkMuted),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static IconData _iconFor(ContentEntityKind kind) => switch (kind) {
    ContentEntityKind.team => Icons.groups_outlined,
    ContentEntityKind.person => Icons.person_outline_rounded,
    ContentEntityKind.competition ||
    ContentEntityKind.season => Icons.emoji_events_outlined,
    ContentEntityKind.game => Icons.sports_baseball_outlined,
    ContentEntityKind.venue => Icons.place_outlined,
    ContentEntityKind.guide => Icons.school_outlined,
    _ => Icons.link_rounded,
  };
}
