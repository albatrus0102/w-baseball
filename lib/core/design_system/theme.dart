import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'typography.dart';

/// Semantic colours resolved per brightness. Widgets read these through
/// `WbTheme.of(context)` instead of hard-coding values from [WbColors], so the
/// dark theme can restructure surface layers rather than merely invert them.
@immutable
class WbSemanticColors extends ThemeExtension<WbSemanticColors> {
  const WbSemanticColors({
    required this.brand,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.ink,
    required this.inkMuted,
    required this.divider,
    required this.action,
    required this.actionSoft,
    required this.verified,
    required this.verifiedSoft,
    required this.highlight,
    required this.highlightSoft,
    required this.danger,
    required this.brandSoft,
    required this.skeleton,
    required this.scrim,
  });

  final Color brand;
  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color ink;
  final Color inkMuted;
  final Color divider;
  final Color action;
  final Color actionSoft;
  final Color verified;
  final Color verifiedSoft;
  final Color highlight;
  final Color highlightSoft;
  final Color danger;
  final Color brandSoft;
  final Color skeleton;
  final Color scrim;

  static const WbSemanticColors light = WbSemanticColors(
    brand: WbColors.navy,
    canvas: WbColors.canvas,
    surface: WbColors.surface,
    surfaceRaised: WbColors.canvasRaised,
    ink: WbColors.ink,
    inkMuted: WbColors.muted,
    divider: WbColors.divider,
    action: WbColors.coral,
    actionSoft: WbColors.coralSoft,
    verified: WbColors.teal,
    verifiedSoft: WbColors.tealSoft,
    highlight: WbColors.gold,
    highlightSoft: WbColors.goldSoft,
    danger: WbColors.error,
    brandSoft: WbColors.navySoft,
    skeleton: Color(0xFFEBEDEF),
    scrim: Color(0x66111827),
  );

  static const WbSemanticColors dark = WbSemanticColors(
    brand: Color(0xFF9FB3D9),
    canvas: WbColors.darkCanvas,
    surface: WbColors.darkSurface,
    surfaceRaised: WbColors.darkRaised,
    ink: WbColors.darkInk,
    inkMuted: WbColors.darkMuted,
    divider: WbColors.darkDivider,
    action: WbColors.darkCoral,
    actionSoft: Color(0xFF3A2224),
    verified: WbColors.darkTeal,
    verifiedSoft: Color(0xFF14312F),
    highlight: WbColors.darkGold,
    highlightSoft: Color(0xFF33290F),
    danger: WbColors.darkError,
    brandSoft: Color(0xFF1B2434),
    skeleton: Color(0xFF222B37),
    scrim: Color(0x99000000),
  );

  @override
  WbSemanticColors copyWith({
    Color? brand,
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? ink,
    Color? inkMuted,
    Color? divider,
    Color? action,
    Color? actionSoft,
    Color? verified,
    Color? verifiedSoft,
    Color? highlight,
    Color? highlightSoft,
    Color? danger,
    Color? brandSoft,
    Color? skeleton,
    Color? scrim,
  }) {
    return WbSemanticColors(
      brand: brand ?? this.brand,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      divider: divider ?? this.divider,
      action: action ?? this.action,
      actionSoft: actionSoft ?? this.actionSoft,
      verified: verified ?? this.verified,
      verifiedSoft: verifiedSoft ?? this.verifiedSoft,
      highlight: highlight ?? this.highlight,
      highlightSoft: highlightSoft ?? this.highlightSoft,
      danger: danger ?? this.danger,
      brandSoft: brandSoft ?? this.brandSoft,
      skeleton: skeleton ?? this.skeleton,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  WbSemanticColors lerp(ThemeExtension<WbSemanticColors>? other, double t) {
    if (other is! WbSemanticColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return WbSemanticColors(
      brand: c(brand, other.brand),
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surfaceRaised: c(surfaceRaised, other.surfaceRaised),
      ink: c(ink, other.ink),
      inkMuted: c(inkMuted, other.inkMuted),
      divider: c(divider, other.divider),
      action: c(action, other.action),
      actionSoft: c(actionSoft, other.actionSoft),
      verified: c(verified, other.verified),
      verifiedSoft: c(verifiedSoft, other.verifiedSoft),
      highlight: c(highlight, other.highlight),
      highlightSoft: c(highlightSoft, other.highlightSoft),
      danger: c(danger, other.danger),
      brandSoft: c(brandSoft, other.brandSoft),
      skeleton: c(skeleton, other.skeleton),
      scrim: c(scrim, other.scrim),
    );
  }
}

/// Accessor for semantic colours plus motion policy.
class WbTheme {
  const WbTheme._();

  static WbSemanticColors of(BuildContext context) =>
      Theme.of(context).extension<WbSemanticColors>() ?? WbSemanticColors.light;

  /// Honour the system "remove animations" accessibility setting.
  static bool animationsEnabled(BuildContext context) =>
      !MediaQuery.disableAnimationsOf(context);

  static Duration duration(BuildContext context, Duration value) =>
      animationsEnabled(context) ? value : Duration.zero;

  static ThemeData light() => _build(Brightness.light, WbSemanticColors.light);

  static ThemeData dark() => _build(Brightness.dark, WbSemanticColors.dark);

  static ThemeData _build(Brightness brightness, WbSemanticColors c) {
    final isLight = brightness == Brightness.light;
    final onAccent = isLight ? WbColors.surface : WbColors.darkCanvas;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.brand,
      onPrimary: onAccent,
      primaryContainer: c.brandSoft,
      onPrimaryContainer: c.ink,
      secondary: c.action,
      onSecondary: onAccent,
      secondaryContainer: c.actionSoft,
      onSecondaryContainer: c.ink,
      tertiary: c.verified,
      onTertiary: onAccent,
      tertiaryContainer: c.verifiedSoft,
      onTertiaryContainer: c.ink,
      error: c.danger,
      onError: onAccent,
      errorContainer: isLight
          ? const Color(0xFFFBE7E7)
          : const Color(0xFF3A1E1E),
      onErrorContainer: c.ink,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.inkMuted,
      surfaceContainerLowest: c.canvas,
      surfaceContainerLow: c.canvas,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceRaised,
      surfaceContainerHighest: c.surfaceRaised,
      outline: c.divider,
      outlineVariant: c.divider,
      shadow: const Color(0x1A000000),
      scrim: c.scrim,
      inverseSurface: c.ink,
      onInverseSurface: c.canvas,
      inversePrimary: c.brandSoft,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.canvas,
      textTheme: WbType.textTheme(c.ink, c.inkMuted),
      splashFactory: InkSparkle.splashFactory,
      // A single icon family across the whole app.
      iconTheme: IconThemeData(color: c.ink, size: 22),
      dividerTheme: DividerThemeData(color: c.divider, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: c.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: WbType.title.copyWith(color: c.ink),
        systemOverlayStyle: isLight
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: WbRadius.cardAll),
      ),
      // One button shape everywhere.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, WbSize.buttonHeight),
          backgroundColor: c.brand,
          foregroundColor: onAccent,
          textStyle: WbType.bodyStrong,
          shape: const RoundedRectangleBorder(borderRadius: WbRadius.chipAll),
          padding: const EdgeInsets.symmetric(horizontal: WbSpace.xl),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, WbSize.buttonHeight),
          foregroundColor: c.ink,
          textStyle: WbType.bodyStrong,
          side: BorderSide(color: c.divider),
          shape: const RoundedRectangleBorder(borderRadius: WbRadius.chipAll),
          padding: const EdgeInsets.symmetric(horizontal: WbSpace.lg),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, WbSize.minTap),
          foregroundColor: c.brand,
          textStyle: WbType.bodyStrong,
          shape: const RoundedRectangleBorder(borderRadius: WbRadius.chipAll),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: WbSize.bottomBarHeight,
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.brandSoft,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: WbRadius.chipAll,
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return WbType.micro.copyWith(
            color: selected ? c.ink : c.inkMuted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? c.brand : c.inkMuted,
            size: 24,
          );
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.divider,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: WbRadius.sheet),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.ink,
        contentTextStyle: WbType.body.copyWith(color: c.canvas),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: WbRadius.chipAll),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.action,
        linearMinHeight: 2,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      extensions: <ThemeExtension<dynamic>>[c],
    );
  }
}
