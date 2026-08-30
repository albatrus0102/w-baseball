import 'package:flutter/widgets.dart';

/// Design tokens for the 여자야구 app.
///
/// Concept: "modern sports editorial + the precision of a baseball scorebook".
/// Deliberately avoids the pink/ribbon shorthand for women's sport and the
/// neon-gradient look of betting apps. Authority comes from typography,
/// generous whitespace, and a restrained ink/navy/parchment base with a
/// small set of functional accents.
@immutable
class WbColors {
  const WbColors._();

  // Base ------------------------------------------------------------------
  static const ink = Color(0xFF111827);
  static const navy = Color(0xFF14213D);
  static const canvas = Color(0xFFF7F5F0);
  static const surface = Color(0xFFFFFFFF);

  // Accents ---------------------------------------------------------------
  static const coral = Color(0xFFF05D5E);
  static const teal = Color(0xFF168A86);
  static const gold = Color(0xFFD7A83E);

  // Support ---------------------------------------------------------------
  static const muted = Color(0xFF667085);
  static const divider = Color(0xFFE5E7EB);
  static const error = Color(0xFFC73939);

  // Derived light surfaces -------------------------------------------------
  static const canvasRaised = Color(0xFFFFFDF9);
  static const inkSoft = Color(0xFF2B3444);
  static const tealSoft = Color(0xFFE6F2F1);
  static const coralSoft = Color(0xFFFDECEC);
  static const goldSoft = Color(0xFFFAF1DC);
  static const navySoft = Color(0xFFE7EAF1);

  // Dark theme ------------------------------------------------------------
  // Not an inversion: surfaces are layered (canvas < surface < raised) so
  // elevation still reads, and accents are lifted for contrast on dark.
  static const darkCanvas = Color(0xFF0C1017);
  static const darkSurface = Color(0xFF151B24);
  static const darkRaised = Color(0xFF1E2632);
  static const darkDivider = Color(0xFF2C3543);
  static const darkInk = Color(0xFFF2F4F7);
  static const darkMuted = Color(0xFF98A2B3);
  static const darkCoral = Color(0xFFFF8384);
  static const darkTeal = Color(0xFF4FC3BE);
  static const darkGold = Color(0xFFE8C46B);
  static const darkError = Color(0xFFF17878);
}

/// 4dp base spacing scale. Use the named steps rather than raw numbers so
/// rhythm stays consistent across features.
@immutable
class WbSpace {
  const WbSpace._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double screen = 20; // horizontal screen gutter
  static const double xl = 24;
  static const double section = 32; // between major sections
  static const double xxl = 40;
}

@immutable
class WbRadius {
  const WbRadius._();

  static const Radius chip = Radius.circular(10);
  static const Radius card = Radius.circular(16);
  static const Radius hero = Radius.circular(20);
  static const Radius sheet = Radius.circular(24);

  static const BorderRadius chipAll = BorderRadius.all(chip);
  static const BorderRadius cardAll = BorderRadius.all(card);
  static const BorderRadius heroAll = BorderRadius.all(hero);
}

/// Minimum tappable sizes. Enforced by [WbTapTarget] in widgets/.
@immutable
class WbSize {
  const WbSize._();

  static const double minTap = 48;
  static const double buttonHeight = 48;
  static const double chipHeight = 36;
  static const double bottomBarHeight = 64;

  /// Thumb-reachable band measured from the bottom of the viewport. Primary
  /// actions on scrolling screens should live inside this.
  static const double thumbZone = 220;
}

/// Restrained motion. All durations sit in the 180-240ms band; the app checks
/// `MediaQuery.disableAnimations` before running any of them.
@immutable
class WbDuration {
  const WbDuration._();

  static const Duration instant = Duration(milliseconds: 90);
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 240);
}

@immutable
class WbBreakpoint {
  const WbBreakpoint._();

  /// Small phones (e.g. 320-359dp) need tighter gutters and 2-line clamps.
  static const double compact = 360;

  /// Large phones / small tablets can widen the content column.
  static const double expanded = 600;

  static bool isCompact(double width) => width < compact;
}

/// Two information densities inside one design system.
///
/// A newcomer meeting a fixture card for the first time needs air around it and
/// a line spelling out what the numbers mean. A player checking six fixtures
/// before practice wants those six on one screen without scrolling. Serving one
/// of them well by hurting the other is the failure mode this enum exists to
/// avoid.
///
/// What density is allowed to change: padding, gaps, row height, and whether an
/// optional explanatory line renders. What it must never change: which
/// components a screen uses, the colour system, the wording of a label, or what
/// information is reachable. A screen is written once and must be correct in
/// both — otherwise this is two design systems wearing one name.
///
/// Minimum tap size is identical in both. Compact buys space from padding and
/// prose, never from reachability.
enum WbDensity {
  /// Default for [AudienceMode.discover]. Card-led, roomy, explanations on.
  comfortable(
    labelKo: '넓게 보기',
    descriptionKo: '카드가 크고 설명이 함께 나옵니다. 처음 보는 사람에게 좋습니다.',
    cardPadding: EdgeInsets.all(WbSpace.lg),
    rowPadding: EdgeInsets.symmetric(
      horizontal: WbSpace.lg,
      vertical: WbSpace.md,
    ),
    sectionGap: WbSpace.section,
    blockGap: WbSpace.lg,
    rowGap: WbSpace.sm,
    listRowMinHeight: 72,
    showsSecondaryLine: true,
  ),

  /// Default for [AudienceMode.player]. List-led, tight, explanations off.
  compact(
    labelKo: '조밀하게 보기',
    descriptionKo: '한 화면에 더 많은 경기가 들어옵니다. 자주 확인하는 사람에게 좋습니다.',
    cardPadding: EdgeInsets.symmetric(
      horizontal: WbSpace.md,
      vertical: WbSpace.md,
    ),
    rowPadding: EdgeInsets.symmetric(
      horizontal: WbSpace.md,
      vertical: WbSpace.sm,
    ),
    sectionGap: WbSpace.screen,
    blockGap: WbSpace.md,
    rowGap: WbSpace.xs,
    listRowMinHeight: 56,
    showsSecondaryLine: false,
  );

  const WbDensity({
    required this.labelKo,
    required this.descriptionKo,
    required this.cardPadding,
    required this.rowPadding,
    required this.sectionGap,
    required this.blockGap,
    required this.rowGap,
    required this.listRowMinHeight,
    required this.showsSecondaryLine,
  });

  final String labelKo;
  final String descriptionKo;
  final EdgeInsets cardPadding;

  /// Padding for a repeating list row, which can be tighter than a standalone
  /// card without the list becoming hard to scan.
  final EdgeInsets rowPadding;

  /// Space above a major section heading (a home module, a settings group).
  /// The strongest density lever on a scrolling screen: it decides how many
  /// sections fit before the first scroll.
  final double sectionGap;

  /// Space between blocks inside one section.
  final double blockGap;

  final double rowGap;

  /// Row height floor. Stays at or above [WbSize.minTap] in both densities.
  final double listRowMinHeight;

  /// Whether a widget's optional *explanatory* line renders — a source note
  /// spelled out in full, a beginner aside. Never factual content: a venue name
  /// or a status is shown in both densities, because hiding data behind a
  /// display setting makes the setting a feature gate.
  final bool showsSecondaryLine;

  static WbDensity parse(String? value) => switch (value) {
    'compact' => WbDensity.compact,
    'comfortable' => WbDensity.comfortable,
    _ => WbDensity.comfortable,
  };

  String get wireValue => name;
}

/// Carries the resolved [WbDensity] down the tree.
///
/// Density is read from context rather than threaded through every constructor:
/// a boolean passed by hand at each call site is how the two densities drift
/// apart, because nothing forces a new widget to participate.
class WbDensityScope extends InheritedWidget {
  const WbDensityScope({
    super.key,
    required this.density,
    required super.child,
  });

  final WbDensity density;

  /// Defaults to [WbDensity.comfortable] when no scope is present, so a widget
  /// rendered in a test or a preview still lays out correctly.
  static WbDensity of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WbDensityScope>()?.density ??
      WbDensity.comfortable;

  @override
  bool updateShouldNotify(WbDensityScope oldWidget) =>
      oldWidget.density != density;
}
