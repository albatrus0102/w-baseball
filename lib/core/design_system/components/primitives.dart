import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';

/// Section heading with an optional "전체 보기" action.
///
/// Home and discover screens show at most 3-5 items per section and hand the
/// rest to a dedicated screen through this action, rather than growing into an
/// infinite feed.
class WbSectionHeader extends StatelessWidget {
  const WbSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(
      WbSpace.screen,
      WbSpace.section,
      WbSpace.screen,
      WbSpace.md,
    ),
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: WbType.section.copyWith(color: c.ink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: WbSpace.xs),
                  Text(
                    subtitle!,
                    style: WbType.caption.copyWith(color: c.inkMuted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(width: WbSpace.sm),
            // Padded to a 48dp target without visually enlarging the label.
            Semantics(
              button: true,
              label: '$title $actionLabel',
              child: InkWell(
                onTap: onAction,
                borderRadius: WbRadius.chipAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WbSpace.sm,
                    vertical: WbSpace.md,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        actionLabel!,
                        style: WbType.captionStrong.copyWith(color: c.brand),
                      ),
                      const SizedBox(width: WbSpace.xxs),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: c.brand,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Badge tone. Colour is never the only signal — every tone pairs with a
/// label, and most call sites also pass an icon.
enum WbBadgeTone { neutral, live, positive, warning, danger, muted, highlight }

class WbBadge extends StatelessWidget {
  const WbBadge({
    super.key,
    required this.label,
    this.tone = WbBadgeTone.neutral,
    this.icon,
    this.dense = false,
  });

  final String label;
  final WbBadgeTone tone;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final (Color bg, Color fg) = switch (tone) {
      WbBadgeTone.neutral => (c.brandSoft, c.brand),
      WbBadgeTone.live => (c.actionSoft, c.action),
      WbBadgeTone.positive => (c.verifiedSoft, c.verified),
      WbBadgeTone.warning => (c.highlightSoft, c.highlight),
      WbBadgeTone.danger => (c.actionSoft, c.danger),
      WbBadgeTone.muted => (c.divider.withValues(alpha: 0.45), c.inkMuted),
      WbBadgeTone.highlight => (c.highlightSoft, c.highlight),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? WbSpace.sm : WbSpace.md - 2,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(color: bg, borderRadius: WbRadius.chipAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: dense ? 12 : 13, color: fg),
            const SizedBox(width: WbSpace.xs),
          ],
          // Flexible so a long status note ellipsizes rather than forcing the
          // surrounding row past the screen edge.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WbType.label.copyWith(
                color: fg,
                fontSize: dense ? 11 : 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The app's standard card surface.
///
/// One shape, one border treatment, no drop shadows: elevation is expressed
/// with a hairline border and a surface step, which stays legible in dark mode
/// where shadows disappear.
class WbCard extends StatelessWidget {
  const WbCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.accentColor,
    this.emphasized = false,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Null means "use the current [WbDensity]". A screen only passes this when
  /// it has a layout reason of its own, so density changes reach every card
  /// that did not opt out.
  final EdgeInsets? padding;

  /// Rendered as a 4dp rail on the leading edge. Used sparingly for team
  /// colour, never as a card fill.
  final Color? accentColor;

  /// Hero treatment: raised surface and a stronger border.
  final bool emphasized;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolvedPadding = padding ?? WbDensityScope.of(context).cardPadding;
    final c = WbTheme.of(context);
    final radius = emphasized ? WbRadius.heroAll : WbRadius.cardAll;

    final borderColor = emphasized
        ? c.brand.withValues(alpha: 0.18)
        : c.divider;

    // The accent rail is a positioned overlay, not a Row child and not a
    // coloured border side:
    //  * a Row with CrossAxisAlignment.stretch would demand a bounded height,
    //    which a card inside a scrolling column does not have;
    //  * a Border with one differently-coloured side cannot carry a radius.
    // A Stack sized by its single non-positioned child avoids both.
    Widget content = Container(
      decoration: BoxDecoration(
        color: emphasized ? c.surfaceRaised : c.surface,
        borderRadius: radius,
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Padding(padding: resolvedPadding, child: child),
          if (accentColor != null)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(color: accentColor!),
            ),
        ],
      ),
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, borderRadius: radius, child: content),
      );
    }

    if (semanticLabel != null) {
      content = Semantics(
        label: semanticLabel,
        button: onTap != null,
        container: true,
        child: ExcludeSemantics(child: content),
      );
    }

    return content;
  }
}

/// A skeleton block that mimics the real layout.
///
/// Used instead of a centred spinner everywhere. The shape of the skeleton
/// should match what is about to appear, so the screen does not visibly
/// re-flow when data lands.
class WbSkeleton extends StatefulWidget {
  const WbSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  final double? width;
  final double height;
  final BorderRadius borderRadius;

  @override
  State<WbSkeleton> createState() => _WbSkeletonState();
}

class _WbSkeletonState extends State<WbSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the system "reduce motion" setting: hold a static tint instead
    // of pulsing.
    if (WbTheme.animationsEnabled(context)) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0.5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(
              c.skeleton,
              c.skeleton.withValues(alpha: 0.45),
              _controller.value,
            ),
            borderRadius: widget.borderRadius,
          ),
        );
      },
    );
  }
}

/// Empty / error / offline state.
///
/// Always offers at least one way forward — never a bare "no data" message.
class WbEmptyState extends StatelessWidget {
  const WbEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.tone = WbBadgeTone.neutral,
    this.compact = false,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final WbBadgeTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final iconColor = switch (tone) {
      WbBadgeTone.danger => c.danger,
      WbBadgeTone.warning => c.highlight,
      WbBadgeTone.positive => c.verified,
      _ => c.inkMuted,
    };

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: WbSpace.screen,
        vertical: compact ? WbSpace.xl : WbSpace.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: c.divider.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: iconColor),
            ),
            const SizedBox(height: WbSpace.lg),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: WbType.headline.copyWith(color: c.ink),
          ),
          if (message != null) ...<Widget>[
            const SizedBox(height: WbSpace.sm),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: WbType.caption.copyWith(color: c.inkMuted, height: 1.55),
            ),
          ],
          if (primaryLabel != null && onPrimary != null) ...<Widget>[
            const SizedBox(height: WbSpace.xl),
            FilledButton(onPressed: onPrimary, child: Text(primaryLabel!)),
          ],
          if (secondaryLabel != null && onSecondary != null) ...<Widget>[
            const SizedBox(height: WbSpace.sm),
            TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ],
      ),
    );
  }
}

/// Guarantees a 48×48dp hit area without changing visual size.
class WbTapTarget extends StatelessWidget {
  const WbTapTarget({
    super.key,
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget result = InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: WbSize.minTap,
          minHeight: WbSize.minTap,
        ),
        child: Center(child: child),
      ),
    );
    if (tooltip != null) {
      result = Tooltip(message: tooltip!, child: result);
    }
    if (semanticLabel != null) {
      result = Semantics(button: true, label: semanticLabel, child: result);
    }
    return result;
  }
}

/// Horizontal chip row with a removable-filter affordance.
class WbFilterChip extends StatelessWidget {
  const WbFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onRemove,
    this.icon,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// When set, the chip shows an × so an active filter can be cleared in one
  /// tap rather than reopening the filter sheet.
  final VoidCallback? onRemove;

  final IconData? icon;

  /// Result count previewed before the filter is applied.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final fg = selected ? c.surface : c.ink;
    final bg = selected ? c.brand : c.surface;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: bg,
        borderRadius: WbRadius.chipAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: WbRadius.chipAll,
          child: Container(
            constraints: const BoxConstraints(minHeight: WbSize.chipHeight),
            padding: const EdgeInsets.symmetric(horizontal: WbSpace.md),
            decoration: BoxDecoration(
              borderRadius: WbRadius.chipAll,
              border: Border.all(color: selected ? c.brand : c.divider),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 15, color: fg),
                  const SizedBox(width: WbSpace.xs),
                ],
                Text(label, style: WbType.captionStrong.copyWith(color: fg)),
                if (count != null) ...<Widget>[
                  const SizedBox(width: WbSpace.xs),
                  Text(
                    '$count',
                    style: WbType.tabularSmall.copyWith(
                      color: selected ? fg.withValues(alpha: 0.8) : c.inkMuted,
                    ),
                  ),
                ],
                if (onRemove != null) ...<Widget>[
                  const SizedBox(width: WbSpace.xs),
                  GestureDetector(
                    onTap: onRemove,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.close_rounded, size: 14, color: fg),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Typographic team monogram, used wherever a logo is not licensed.
///
/// Every team gets a consistent, dignified mark rather than a broken image or
/// a generic placeholder icon.
class WbTeamMark extends StatelessWidget {
  const WbTeamMark({
    super.key,
    required this.name,
    this.colorHex,
    this.size = 36,
  });

  final String name;
  final String? colorHex;
  final double size;

  static Color? parseHex(String? hex) {
    if (hex == null) return null;
    var value = hex.trim().replaceFirst('#', '');
    if (value.length == 6) value = 'FF$value';
    if (value.length != 8) return null;
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  /// First Hangul syllable, or first two Latin letters.
  String get _initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final first = trimmed.characters.first;
    final code = first.codeUnitAt(0);
    final isHangul = code >= 0xAC00 && code <= 0xD7A3;
    if (isHangul) return first;
    return trimmed.length >= 2
        ? trimmed.substring(0, 2).toUpperCase()
        : trimmed.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final accent = parseHex(colorHex) ?? c.brand;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      alignment: Alignment.center,
      child: Text(
        _initial,
        style: WbType.captionStrong.copyWith(
          color: accent,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

/// A thin divider used inside cards, aligned to content rather than full-bleed.
class WbInsetDivider extends StatelessWidget {
  const WbInsetDivider({super.key, this.vertical = WbSpace.md});

  final double vertical;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: vertical),
      child: Container(height: 1, color: c.divider),
    );
  }
}
