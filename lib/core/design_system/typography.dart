import 'package:flutter/material.dart';

/// Typography for Korean-first sports content.
///
/// Font strategy: we ship no font binaries. `Pretendard` / `Noto Sans KR` are
/// named first and the platform falls back to the Android system Korean face
/// when they are absent, so the app never renders tofu and we never bundle a
/// font whose licence we have not cleared. See docs/design-system.md.
///
/// Scores and record tables use [FontFeature.tabularFigures] so digits stay in
/// vertical alignment inside line-score and standings tables.
@immutable
class WbType {
  const WbType._();

  static const List<String> _koFallback = <String>[
    'Noto Sans KR',
    'Apple SD Gothic Neo',
    'Malgun Gothic',
    'sans-serif',
  ];

  static const String _family = 'Pretendard';

  static const List<FontFeature> _tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  static TextStyle _base({
    required double size,
    required FontWeight weight,
    required double height,
    double letterSpacing = 0,
    List<FontFeature>? features,
  }) {
    return TextStyle(
      fontFamily: _family,
      fontFamilyFallback: _koFallback,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: features,
      // Korean text sits low in the em box; trailing/leading trim keeps the
      // optical rhythm of mixed 한글 + Latin + digits lines even.
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  /// App bar / screen title.
  static final TextStyle display = _base(
    size: 28,
    weight: FontWeight.w800,
    height: 1.24,
    letterSpacing: -0.6,
  );

  static final TextStyle title = _base(
    size: 22,
    weight: FontWeight.w700,
    height: 1.30,
    letterSpacing: -0.4,
  );

  /// Section heading ("오늘의 경기", "진행 중인 대회").
  static final TextStyle section = _base(
    size: 17,
    weight: FontWeight.w700,
    height: 1.32,
    letterSpacing: -0.3,
  );

  /// Card headline — team names, competition names.
  static final TextStyle headline = _base(
    size: 16,
    weight: FontWeight.w600,
    height: 1.36,
    letterSpacing: -0.2,
  );

  static final TextStyle body = _base(
    size: 15,
    weight: FontWeight.w400,
    height: 1.52,
    letterSpacing: -0.1,
  );

  static final TextStyle bodyStrong = _base(
    size: 15,
    weight: FontWeight.w600,
    height: 1.52,
    letterSpacing: -0.1,
  );

  /// Secondary information — venue, competition sub-label.
  static final TextStyle caption = _base(
    size: 13,
    weight: FontWeight.w400,
    height: 1.42,
  );

  static final TextStyle captionStrong = _base(
    size: 13,
    weight: FontWeight.w600,
    height: 1.42,
  );

  /// Source attribution and timestamps. Deliberately the quietest style in the
  /// system — provenance must be present but must never outshout the content.
  static final TextStyle micro = _base(
    size: 11.5,
    weight: FontWeight.w500,
    height: 1.36,
    letterSpacing: 0.1,
  );

  /// Status badges, filter chips.
  static final TextStyle label = _base(
    size: 12.5,
    weight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.2,
  );

  // Numerals --------------------------------------------------------------

  /// Hero score on the home card.
  static final TextStyle scoreHero = _base(
    size: 40,
    weight: FontWeight.w800,
    height: 1.0,
    letterSpacing: -1.6,
    features: _tabular,
  );

  /// Score in a list row.
  static final TextStyle scoreRow = _base(
    size: 22,
    weight: FontWeight.w700,
    height: 1.0,
    letterSpacing: -0.8,
    features: _tabular,
  );

  /// Cells of line-score / standings / stat tables.
  static final TextStyle tabular = _base(
    size: 14,
    weight: FontWeight.w600,
    height: 1.2,
    features: _tabular,
  );

  static final TextStyle tabularSmall = _base(
    size: 12.5,
    weight: FontWeight.w500,
    height: 1.2,
    features: _tabular,
  );

  /// Kick-off time on an upcoming game card.
  static final TextStyle timeLarge = _base(
    size: 24,
    weight: FontWeight.w700,
    height: 1.05,
    letterSpacing: -0.8,
    features: _tabular,
  );

  static TextTheme textTheme(Color onSurface, Color onSurfaceMuted) {
    return TextTheme(
      displaySmall: display.copyWith(color: onSurface),
      headlineSmall: title.copyWith(color: onSurface),
      titleLarge: section.copyWith(color: onSurface),
      titleMedium: headline.copyWith(color: onSurface),
      bodyLarge: body.copyWith(color: onSurface),
      bodyMedium: body.copyWith(color: onSurface),
      bodySmall: caption.copyWith(color: onSurfaceMuted),
      labelLarge: bodyStrong.copyWith(color: onSurface),
      labelMedium: label.copyWith(color: onSurface),
      labelSmall: micro.copyWith(color: onSurfaceMuted),
    );
  }
}

/// Line-clamp policy. Korean team/competition names break awkwardly at
/// arbitrary points, so every surface declares an explicit max line count and
/// relies on ellipsis rather than letting the layout grow unpredictably.
@immutable
class WbClamp {
  const WbClamp._();

  static const int teamName = 2;
  static const int competitionName = 1;
  static const int articleTitle = 2;
  static const int venueName = 1;
  static const int summary = 3;
}
