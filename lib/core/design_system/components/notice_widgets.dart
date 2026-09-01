import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';

/// An optional leading icon, a sentence, and a trailing action — sharing a
/// row when the sentence fits beside the action, otherwise dropping the
/// action to its own line below.
///
/// This shape appears five times in the app (경기 tab's "오늘 경기가 없어…"
/// banner, 내 기록's storage notice and its "N게임 기록" summary, 관람 준비의
/// venue row, 더보기's sync banner) and every one of them, hand-written as a
/// plain `Row`, broke the same way: `Expanded(Text)` beside a same-row button
/// never overflows — `Expanded` absorbs the squeeze — so it draws no test
/// failure, but at a long-enough sentence or a large-enough text scale the
/// text gets pressed into a column so narrow that Korean words split across
/// the wrap point. `scripts/validate/find_squeezed_rows.py` finds the shape;
/// this widget is the fix applied once instead of by hand at each call site,
/// after the same fix landed by hand five separate times in one day and one
/// of those hand-written fixes turned out to have a wrong doc comment
/// ("this sentence is short enough to always fit") that nobody caught until
/// the sentence's dynamic date pushed it over at 2.0x.
///
/// The one-line-or-below decision is measured per build with [TextPainter],
/// not assumed from a fixed text-scale threshold — a short sentence can stay
/// inline past 2.0x, and a long one can already need the drop at 1.3x, and
/// the only way to know which is to lay the actual text out. See
/// [WbSpoilerVeil] in `provenance_widgets.dart` for the precedent of
/// measuring rather than guessing.
class WbNoticeWithAction extends StatelessWidget {
  const WbNoticeWithAction({
    super.key,
    this.leading,
    required this.text,
    required this.textStyle,
    this.secondary,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  /// Rendered to the left of [text], already padded/sized by the caller
  /// (each call site tunes its own icon size and baseline nudge — see
  /// existing call sites for the `Padding(top: 2)` most of them use to sit
  /// an icon against a cap-height line rather than a full line box).
  final Widget? leading;

  /// The sentence this widget decides whether to share a line with
  /// [actionLabel] over. Measured at its real style and the current
  /// [MediaQuery] text scale — never shrunk or ellipsised by this widget.
  final String text;
  final TextStyle textStyle;

  /// Extra content under [text] — e.g. `_InfoRow`'s address line. Always
  /// rendered on its own line(s) regardless of the inline/below decision,
  /// which is based on [text] alone: unlike [text], `secondary` in this
  /// app's one caller is already expected to wrap across several lines by
  /// design (a street address), so it was never the "was one line, got
  /// squeezed to many" failure this widget exists to fix.
  final Widget? secondary;

  /// Null (together with [onAction]) renders [text]/[secondary] with no
  /// action at all — e.g. `_InfoRow`'s venue-not-yet-set branch, which has
  /// no 길찾기 to offer.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Non-null selects the emphasized (`FilledButton.icon`) action used by
  /// the 내 기록 summary's "기록 추가"; null selects the quiet `TextButton`
  /// every other call site uses.
  final IconData? actionIcon;

  bool get _hasAction => actionLabel != null && onAction != null;

  @override
  Widget build(BuildContext context) {
    final content = secondary == null
        ? Text(text, style: textStyle)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(text, style: textStyle),
              const SizedBox(height: WbSpace.xxs),
              secondary!,
            ],
          );

    if (!_hasAction) {
      return leading == null
          ? content
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                leading!,
                const SizedBox(width: WbSpace.sm),
                Expanded(child: content),
              ],
            );
    }

    final action = _buildAction();

    return LayoutBuilder(
      builder: (context, constraints) {
        final inline = _sentenceFitsInline(
          context,
          maxWidth: constraints.maxWidth,
        );

        final leadRow = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading!,
              const SizedBox(width: WbSpace.sm),
            ],
            Expanded(child: content),
            if (inline) ...<Widget>[const SizedBox(width: WbSpace.sm), action],
          ],
        );

        if (inline) return leadRow;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            leadRow,
            Align(alignment: Alignment.centerRight, child: action),
          ],
        );
      },
    );
  }

  Widget _buildAction() {
    final icon = actionIcon;
    if (icon != null) {
      return FilledButton.icon(
        onPressed: onAction,
        icon: Icon(icon, size: 18),
        label: Text(actionLabel!),
      );
    }
    return TextButton(onPressed: onAction, child: Text(actionLabel!));
  }

  /// Whether [text], at its real (unscaled-by-us, [MediaQuery]-scaled) size,
  /// fits on **one line** in [maxWidth] once the leading icon and the action
  /// button both take their own room. Below that, the action drops to its
  /// own line instead of squeezing [text] into a multi-line column that
  /// breaks a word mid-syllable — the defect this widget exists to remove.
  ///
  /// The action's width is [actionLabel]'s own text, measured with
  /// [TextPainter] the same way [text] is, plus [_actionChromeWidth] for the
  /// button's padding/icon, which is estimated rather than measured off a
  /// real [RenderBox] — that would need the button laid out first, which is
  /// not available inside the same [LayoutBuilder] pass that decides the
  /// layout it would be laid out into.
  bool _sentenceFitsInline(BuildContext context, {required double maxWidth}) {
    final textScaler = MediaQuery.textScalerOf(context);
    var available = maxWidth;
    if (leading != null) {
      // Every current call site's leading icon is 14-18dp plus the
      // WbSpace.sm gap this widget adds next to it; icons do not scale with
      // text, so this allowance is fixed rather than measured.
      available -= 18 + WbSpace.sm;
    }
    available -= WbSpace.sm; // gap this widget adds before the action.
    available -= _actionWidth(textScaler);
    if (available <= 0) return false;

    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout(maxWidth: available);
    return !painter.didExceedMaxLines;
  }

  /// Estimated total width of the rendered action button: its own label
  /// text (measured, same as [text]) plus [_actionChromeWidth] for the
  /// button's padding/icon (estimated — see that method's doc).
  double _actionWidth(TextScaler textScaler) {
    // Both `filledButtonTheme` and `textButtonTheme` in `theme.dart` set
    // `textStyle: WbType.bodyStrong` — the actual style Material renders
    // [actionLabel] in, on every button kind this widget builds.
    final labelPainter = TextPainter(
      text: TextSpan(text: actionLabel, style: WbType.bodyStrong),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    return labelPainter.width +
        _actionChromeWidth(textScaler, hasIcon: actionIcon != null);
  }

  /// Estimated width an action button adds beyond its own label text.
  ///
  /// Built from the real numbers in `WbTheme` (`theme.dart`):
  /// `textButtonTheme` sets no padding of its own, so a plain `TextButton`
  /// falls back to Material 3's default (`EdgeInsets.symmetric(horizontal:
  /// 12)` at 1.0x); `filledButtonTheme` explicitly sets
  /// `EdgeInsets.symmetric(horizontal: WbSpace.xl)` (24), plus this widget's
  /// own 18dp icon and `WbSpace.sm` gap for the one call site
  /// (`FilledButton.icon`) that has an icon.
  ///
  /// Material also grows a button's own padding as the text-scale factor
  /// rises (`ButtonStyleButton`'s accessibility affordance) — not modelled
  /// exactly here, since that is Material's private implementation and not
  /// something this measurement should depend on breaking in step with.
  /// Instead the whole allowance below scales with [textScaler] as a
  /// generous stand-in, so this estimate does not fall behind Material's own
  /// growth at large scales. Deliberately generous throughout: the only
  /// failure mode this measurement must avoid is claiming "fits" when it
  /// does not — the reverse (dropping the action below when it might have
  /// just fit) is the safe direction, and is also this widget's job on
  /// every genuinely-too-long sentence anyway.
  double _actionChromeWidth(TextScaler textScaler, {required bool hasIcon}) {
    final basePadding = hasIcon ? WbSpace.xl * 2 : 24.0;
    final iconAllowance = hasIcon ? 18 + WbSpace.sm : 0.0;
    final growth = textScaler.scale(1).clamp(1.0, 2.0);
    return (basePadding + iconAllowance) * growth;
  }
}
