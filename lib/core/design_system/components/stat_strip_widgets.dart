import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';

/// One number-over-label cell of a [WbStatStrip] — e.g. value `'2'`, label
/// `'게임'`.
@immutable
class WbStatCell {
  const WbStatCell({required this.value, required this.label});

  /// Rendered in [WbType.scoreRow] — short by convention (a game count, a
  /// W-L-D digit), never a sentence.
  final String value;

  /// Rendered in [WbType.caption] with [WbSemanticColors.inkMuted].
  final String label;
}

/// A bordered, rounded row of number-over-label cells — "2 / 게임 · 1 / 승 ·
/// 1 / 패 · 0 / 무" instead of the sentence "2게임 기록 · 1승 1패 0무".
///
/// Cells sit in one row separated by 1dp vertical dividers when they fit;
/// at a large text scale or a narrow width they no longer do, and the strip
/// folds to a 2-column grid instead — no divider drawn in that state, since
/// a vertical rule between grid rows would read as a table border it is not.
///
/// The fold point is measured per build with [TextPainter], the same way
/// `WbNoticeWithAction` (`notice_widgets.dart`) decides whether its sentence
/// shares a line with its action button — never a fixed text-scale
/// threshold. A cell's own natural width depends on both its digit count and
/// the current [TextScaler], and guessing a cutoff scale is exactly the
/// mistake that widget's doc records happening five times by hand before it
/// existed.
///
/// The whole strip carries one [semanticLabel] (see [Semantics]) rather than
/// letting a screen reader visit each cell in turn — "2게임 기록 · 1승 1패
/// 0무" is one fact, and reading "2, 게임, 1, 승, 1, 패, 0, 무" cell by cell
/// loses the sentence that ties the numbers together.
class WbStatStrip extends StatelessWidget {
  const WbStatStrip({super.key, required this.cells, this.semanticLabel});

  final List<WbStatCell> cells;

  /// Read by screen readers for the whole strip. The visible cells are
  /// excluded from the semantics tree (see [ExcludeSemantics] in [build]),
  /// so omitting this leaves the strip silent rather than reachable.
  final String? semanticLabel;

  /// Space a 1dp divider occupies including the gap on each side of it —
  /// used both to draw it and to reserve room for it when measuring.
  static const double _dividerAllowance = WbSpace.sm * 2 + 1;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final density = WbDensityScope.of(context);
    final padding = density == WbDensity.compact
        ? const EdgeInsets.symmetric(
            horizontal: WbSpace.md,
            vertical: WbSpace.sm,
          )
        : const EdgeInsets.symmetric(
            horizontal: WbSpace.lg,
            vertical: WbSpace.md,
          );

    final content = LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final singleRow =
            cells.length > 1 &&
            _fitsSingleRow(
              maxWidth: constraints.maxWidth,
              padding: padding,
              textScaler: textScaler,
            );

        return Container(
          padding: padding,
          decoration: BoxDecoration(
            border: Border.all(color: c.divider),
            borderRadius: WbRadius.cardAll,
          ),
          child: singleRow ? _buildRow(c: c, dividers: true) : _buildGrid(c: c),
        );
      },
    );

    return Semantics(
      label: semanticLabel,
      container: true,
      child: ExcludeSemantics(child: content),
    );
  }

  Widget _buildRow({required WbSemanticColors c, required bool dividers}) {
    final children = <Widget>[];
    for (var i = 0; i < cells.length; i++) {
      if (i > 0 && dividers) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WbSpace.sm),
            child: Container(width: 1, color: c.divider),
          ),
        );
      }
      children.add(Expanded(child: _CellView(cell: cells[i])));
    }
    return IntrinsicHeight(child: Row(children: children));
  }

  /// 2-column grid used once the cells no longer fit one row. Deliberately
  /// fixed at 2 columns rather than derived from [cells.length] — this
  /// widget's one call site always passes 4 cells (게임/승/패/무), which folds
  /// to a clean 2×2, and a 2-column wrap keeps every folded row's cells the
  /// widest possible without a vertical divider between them.
  Widget _buildGrid({required WbSemanticColors c}) {
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 2) {
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: WbSpace.sm));
      }
      final second = i + 1 < cells.length ? cells[i + 1] : null;
      rows.add(
        Row(
          children: <Widget>[
            Expanded(child: _CellView(cell: cells[i])),
            const SizedBox(width: WbSpace.sm),
            Expanded(
              child: second == null
                  ? const SizedBox.shrink()
                  : _CellView(cell: second),
            ),
          ],
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  /// Whether every cell, laid out at its own natural (unwrapped) width at
  /// the current [TextScaler], fits [maxWidth] side by side with a divider
  /// between each pair and the strip's own [padding] around the outside.
  bool _fitsSingleRow({
    required double maxWidth,
    required EdgeInsets padding,
    required TextScaler textScaler,
  }) {
    var available = maxWidth - padding.horizontal;
    available -= _dividerAllowance * (cells.length - 1);
    if (available <= 0) return false;

    var total = 0.0;
    for (final cell in cells) {
      total += _cellIntrinsicWidth(cell, textScaler);
    }
    return total <= available;
  }

  double _cellIntrinsicWidth(WbStatCell cell, TextScaler textScaler) {
    final valueWidth = _measure(cell.value, WbType.scoreRow, textScaler);
    final labelWidth = _measure(cell.label, WbType.caption, textScaler);
    return valueWidth > labelWidth ? valueWidth : labelWidth;
  }

  double _measure(String text, TextStyle style, TextScaler textScaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    return painter.width;
  }
}

class _CellView extends StatelessWidget {
  const _CellView({required this.cell});

  final WbStatCell cell;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          cell.value,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: WbType.scoreRow.copyWith(color: c.ink),
        ),
        const SizedBox(height: WbSpace.xxs),
        Text(
          cell.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: WbType.caption.copyWith(color: c.inkMuted),
        ),
      ],
    );
  }
}
