import 'package:flutter/material.dart';

import '../../../data/models/content.dart';
import '../../../data/models/provenance.dart';
import '../../utils/kst.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';
import 'primitives.dart';

/// Source attribution line.
///
/// Deliberately the quietest element on any card. Provenance must always be
/// present and must never outshout the content it describes — so this uses the
/// smallest type in the system, muted colour, and no background.
class WbSourceLine extends StatelessWidget {
  const WbSourceLine({
    super.key,
    required this.provenance,
    required this.now,
    this.onTap,
    this.compact,
  });

  final Provenance provenance;
  final DateTime now;
  final VoidCallback? onTap;

  /// Null means "follow the current [WbDensity]". Compact tightens the line;
  /// the source name and the link stay in both, because attribution is not a
  /// display preference.
  final bool? compact;

  @override
  Widget build(BuildContext context) {
    final isCompact = compact ?? !WbDensityScope.of(context).showsSecondaryLine;
    final c = WbTheme.of(context);

    // Whether *any* freshness verdict may be printed comes from the shell,
    // not from this record. Null (the fail-safe default — see
    // WbFreshnessScope) means no source line anywhere may currently render
    // one, so this falls back to stating a bare fact instead of judging it.
    final staleAfter = WbFreshnessScope.of(context);
    final canVerdict = staleAfter != null;
    final isStale = canVerdict && provenance.isStale(now, staleAfter);

    // Built once and reused for both the visible text and the semantics
    // label below, so the two cannot say different things — a screen-reader
    // user has no way to notice if a hand-written label quietly drifts from
    // what is actually on screen.
    final sourceLabel = _sourceLabel(provenance.sourceName);
    final String timePhrase;
    if (canVerdict) {
      final confirmed = KoDate.relative(provenance.lastConfirmedAt, now);
      // 확인 claims a person checked the record; 갱신 only claims we refreshed
      // it. Which one is true depends on whether `verifiedAt` exists, and
      // today it never does.
      final verb = provenance.isHumanConfirmed ? '확인' : '갱신';
      timePhrase = '$confirmed $verb';
    } else {
      // `~기준` ("as of") states a fact and claims nothing about a refresh
      // having happened — unlike `갱신`, which would be untrue here: nothing
      // was actually fetched from anywhere just now. An absolute date, not
      // `KoDate.relative`, because "2일 전 기준" reads like a judgement and
      // drifts on its own every day with no code change.
      timePhrase =
          '${KoDate.monthDayOrFullDate(provenance.lastConfirmedAt, now)} 기준';
    }

    final children = <Widget>[
      Text(
        '출처 $sourceLabel · $timePhrase',
        style: WbType.micro.copyWith(color: c.inkMuted),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      if (isStale)
        WbBadge(
          label: '오래된 정보',
          tone: WbBadgeTone.warning,
          icon: Icons.schedule_rounded,
          dense: true,
        ),
      if (provenance.isDemo)
        const WbBadge(
          label: '데모 데이터',
          tone: WbBadgeTone.muted,
          icon: Icons.science_outlined,
          dense: true,
        ),
    ];

    // Wrap, not Row+Flexible: the badges have no slack to give up. Shrinking
    // '데모 데이터' to fit would risk clipping the one label the provenance
    // policy says must never disappear, so instead a badge that doesn't fit
    // on the text's line drops to a line of its own — same trick already
    // used below for WbSummaryMethodBadge. Text keeps its own maxLines/
    // ellipsis, so it still degrades before it ever pushes a badge off.
    final row = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: WbSpace.sm,
      runSpacing: WbSpace.xs,
      children: children,
    );

    if (onTap == null) {
      return Semantics(
        label:
            '출처 $sourceLabel, $timePhrase'
            '${isStale ? ', 오래된 정보' : ''}'
            '${provenance.isDemo ? ', 데모 데이터' : ''}',
        child: ExcludeSemantics(child: row),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: WbRadius.chipAll,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: isCompact ? WbSpace.xs : WbSpace.sm,
        ),
        child: row,
      ),
    );
  }

  /// Human-readable source names. Unknown keys fall through unchanged rather
  /// than being hidden — an unattributed record must still look attributed.
  static String _sourceLabel(String sourceName) => switch (sourceName) {
    'wbak' => 'WBAK',
    'kbsa' => 'KBSA',
    'wbsc' => 'WBSC',
    'wpbl' => 'WPBL',
    'seed' => '앱 기본 데이터',
    'demo-fixture' => '앱 데모 데이터',
    'news-aggregate' => '뉴스 모음',
    'tving' => 'TVING',
    'static-manifest' => '공개 데이터셋',
    'manual-submission' => '사용자 제보',
    'derived' => '앱 계산',
    'app-editorial' => '앱 자체 작성',
    _ => sourceName,
  };
}

/// Badge stating how a summary was produced and whether a person checked it.
///
/// Required next to every generated summary. An `aiAssisted` summary always
/// shows the badge plus its generation time; a template summary is labelled
/// but quieter, since it cannot invent facts.
class WbSummaryMethodBadge extends StatelessWidget {
  const WbSummaryMethodBadge({
    super.key,
    required this.meta,
    this.showReviewStatus = true,
  });

  final ContentMeta meta;
  final bool showReviewStatus;

  @override
  Widget build(BuildContext context) {
    final tone = switch (meta.summaryMethod) {
      SummaryMethod.aiAssisted => WbBadgeTone.warning,
      SummaryMethod.template => WbBadgeTone.muted,
      SummaryMethod.manual => WbBadgeTone.positive,
    };
    final icon = switch (meta.summaryMethod) {
      SummaryMethod.aiAssisted => Icons.auto_awesome_outlined,
      SummaryMethod.template => Icons.dataset_outlined,
      SummaryMethod.manual => Icons.edit_outlined,
    };

    return Wrap(
      spacing: WbSpace.xs,
      runSpacing: WbSpace.xs,
      children: <Widget>[
        WbBadge(
          label: meta.summaryMethod.labelKo,
          tone: tone,
          icon: icon,
          dense: true,
        ),
        if (showReviewStatus && meta.reviewStatus != ReviewStatus.reviewed)
          WbBadge(
            label: meta.reviewStatus.labelKo,
            tone: WbBadgeTone.muted,
            icon: Icons.pending_outlined,
            dense: true,
          ),
        if (meta.reviewStatus == ReviewStatus.reviewed &&
            meta.summaryMethod != SummaryMethod.manual)
          const WbBadge(
            label: '사람 검수',
            tone: WbBadgeTone.positive,
            icon: Icons.verified_outlined,
            dense: true,
          ),
        if (meta.isDemo)
          const WbBadge(
            label: '데모',
            tone: WbBadgeTone.muted,
            icon: Icons.science_outlined,
            dense: true,
          ),
      ],
    );
  }
}

/// How complete the underlying data is.
///
/// Shown next to any aggregate — standings, leaderboards — so a partial tally
/// is never mistaken for the official final count.
class WbCoverageNote extends StatelessWidget {
  const WbCoverageNote({super.key, required this.coverage, this.dense = false});

  final DataCoverage coverage;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final ratio = coverage.ratio;

    return Row(
      children: <Widget>[
        Icon(
          coverage.isComplete
              ? Icons.check_circle_outline_rounded
              : Icons.donut_large_rounded,
          size: 14,
          color: coverage.isComplete ? c.verified : c.inkMuted,
        ),
        const SizedBox(width: WbSpace.xs),
        Flexible(
          child: Text(
            coverage.note ?? coverage.labelKo,
            style: WbType.micro.copyWith(color: c.inkMuted),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (ratio != null && !coverage.isComplete && !dense) ...<Widget>[
          const SizedBox(width: WbSpace.sm),
          SizedBox(
            width: 48,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 4,
                backgroundColor: c.divider,
                valueColor: AlwaysStoppedAnimation<Color>(c.brand),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Blurs content the user has asked not to see yet.
///
/// Applied consistently in cards, detail screens and notification bodies.
/// Revealing is always one deliberate tap, and the veil says what it is
/// hiding so the choice is informed.
class WbSpoilerVeil extends StatefulWidget {
  const WbSpoilerVeil({
    super.key,
    required this.masked,
    required this.child,
    this.label = '결과 스포일러가 포함되어 있습니다',
    this.revealLabel = '결과 보기',
    this.onRevealed,
  });

  /// When false the child renders normally — this widget stays in the tree so
  /// toggling the setting does not change layout.
  final bool masked;

  final Widget child;
  final String label;
  final String revealLabel;
  final VoidCallback? onRevealed;

  @override
  State<WbSpoilerVeil> createState() => _WbSpoilerVeilState();
}

class _WbSpoilerVeilState extends State<WbSpoilerVeil> {
  bool _revealed = false;

  @override
  void didUpdateWidget(WbSpoilerVeil oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-masking when the policy changes back is the expected behaviour.
    if (!oldWidget.masked && widget.masked) _revealed = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.masked || _revealed) return widget.child;

    final c = WbTheme.of(context);
    final labelStyle = WbType.caption.copyWith(color: c.inkMuted);
    final revealStyle = WbType.captionStrong.copyWith(color: c.brand);

    return Semantics(
      label: '${widget.label}. ${widget.revealLabel}하려면 두 번 탭하세요.',
      button: true,
      child: ExcludeSemantics(
        child: Stack(
          children: <Widget>[
            // The real content stays laid out underneath, so revealing does not
            // shift anything on screen.
            Opacity(opacity: 0.06, child: widget.child),
            Positioned.fill(
              child: Material(
                color: c.divider.withValues(alpha: 0.35),
                borderRadius: WbRadius.cardAll,
                child: InkWell(
                  borderRadius: WbRadius.cardAll,
                  onTap: () {
                    setState(() => _revealed = true);
                    widget.onRevealed?.call();
                  },
                  // The veil covers whatever it is hiding, which may be a very
                  // short card — sometimes only one line tall. It used to
                  // answer that with `FittedBox(fit: scaleDown)`, but that
                  // counter-scales text, which cancels the system font-size
                  // setting the same way this codebase never allows it to for
                  // body text. It also degraded badly in practice: over a
                  // one-line teaser the icon, explanation and reveal action
                  // were squeezed into that single line's height, rendering as
                  // an illegible smudge rather than a bigger veil. The mask
                  // itself is what matters, not the explanation sentence, so
                  // when there is not enough room for the full explanation at
                  // its real size, this drops straight to the reveal chip
                  // alone instead of shrinking anything.
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final fitsExplanation = _fitsFullExplanation(
                        constraints,
                        labelStyle: labelStyle,
                        revealStyle: revealStyle,
                        textScaler: MediaQuery.textScalerOf(context),
                      );
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(WbSpace.md),
                          child: fitsExplanation
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    Icon(
                                      Icons.visibility_off_outlined,
                                      size: 20,
                                      color: c.inkMuted,
                                    ),
                                    const SizedBox(height: WbSpace.sm),
                                    Text(
                                      widget.label,
                                      textAlign: TextAlign.center,
                                      style: labelStyle,
                                    ),
                                    const SizedBox(height: WbSpace.sm),
                                    Text(
                                      widget.revealLabel,
                                      style: revealStyle,
                                    ),
                                  ],
                                )
                              : Text(widget.revealLabel, style: revealStyle),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Whether the icon, [widget.label] and [widget.revealLabel] all fit inside
  /// [constraints] at their real (unscaled) size.
  ///
  /// Measured with [TextPainter] rather than assumed from a fixed pixel
  /// threshold, so a larger system font size — which this veil must never
  /// counter-scale away — correctly needs more room and correctly falls back
  /// to the compact chip sooner, instead of a stale constant clipping text at
  /// some scales and wasting space at others.
  bool _fitsFullExplanation(
    BoxConstraints constraints, {
    required TextStyle labelStyle,
    required TextStyle revealStyle,
    required TextScaler textScaler,
  }) {
    const horizontalPadding = WbSpace.md * 2;
    const verticalPadding = WbSpace.md * 2;
    final maxWidth = constraints.maxWidth - horizontalPadding;
    final maxHeight = constraints.maxHeight - verticalPadding;
    if (maxWidth <= 0 || maxHeight <= 0) return false;

    final labelPainter = TextPainter(
      text: TextSpan(text: widget.label, style: labelStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);

    final revealPainter = TextPainter(
      text: TextSpan(text: widget.revealLabel, style: revealStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);

    const iconSize = 20.0;
    const gap = WbSpace.sm;
    final neededHeight =
        iconSize + gap + labelPainter.height + gap + revealPainter.height;
    return neededHeight <= maxHeight;
  }
}

/// Inline beginner explainer ("왜 중요한가요?", "이 기록은 무엇인가요?").
///
/// Sits in the flow of the screen it explains rather than in a separate manual,
/// and disappears entirely when the user turns beginner explanations off.
class WbExplainer extends StatelessWidget {
  const WbExplainer({
    super.key,
    required this.title,
    required this.body,
    this.visible = true,
    this.icon = Icons.lightbulb_outline_rounded,
  });

  final String title;
  final String body;
  final bool visible;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final c = WbTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(WbSpace.md),
      decoration: BoxDecoration(
        color: c.highlightSoft,
        borderRadius: WbRadius.chipAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: c.highlight),
          const SizedBox(width: WbSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: WbType.captionStrong.copyWith(color: c.ink)),
                const SizedBox(height: WbSpace.xs),
                Text(
                  body,
                  style: WbType.caption.copyWith(color: c.ink, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
