import 'package:meta/meta.dart';

import 'provenance.dart';

/// How far ahead a forecast reaches, and therefore what we are allowed to say.
///
/// This mirrors what the 기상청 actually publishes:
///  * 단기예보 — 3-hourly, down to 읍·면·동, issued 8×/day (02,05,…,23시),
///    covering roughly D+0 ~ D+2.
///  * 중기예보 — issued 2×/day (06, 18시), covering D+3 ~ D+10, split into
///    오전/오후 up to D+7 and daily from D+8.
///  * Beyond that there is no daily forecast. There is a long-range *outlook*
///    expressed as a tendency against normals, never as a daily icon.
///
/// The UI is bound to this enum so a 25-days-out game physically cannot render
/// a rain icon or a specific high/low temperature.
enum ForecastHorizon {
  /// D+0 ~ D+2. Detailed values are legitimate.
  shortTerm,

  /// D+3 ~ D+10. Ranges and probabilities with confidence, no false precision.
  midTerm,

  /// D+11 and beyond. Schedule only. Weather is shown as "상세 예보 전",
  /// optionally with a seasonal tendency.
  beyondForecast;

  static ForecastHorizon forLeadTime(Duration leadTime) {
    final days = leadTime.inHours / 24.0;
    if (days < 3) return ForecastHorizon.shortTerm;
    if (days <= 10) return ForecastHorizon.midTerm;
    return ForecastHorizon.beyondForecast;
  }

  static ForecastHorizon between(DateTime now, DateTime target) =>
      forLeadTime(target.difference(now));

  static ForecastHorizon parse(String? raw) => switch (raw) {
    'shortTerm' => ForecastHorizon.shortTerm,
    'midTerm' => ForecastHorizon.midTerm,
    _ => ForecastHorizon.beyondForecast,
  };

  String get wireValue => name;

  /// May we show a specific temperature number?
  bool get allowsExactTemperature => this == ForecastHorizon.shortTerm;

  /// May we show a temperature *range*?
  bool get allowsTemperatureRange => this != ForecastHorizon.beyondForecast;

  /// May we show a weather icon / precipitation probability at all?
  bool get allowsDailyCondition => this != ForecastHorizon.beyondForecast;

  String get labelKo => switch (this) {
    ForecastHorizon.shortTerm => '단기예보',
    ForecastHorizon.midTerm => '중기예보',
    ForecastHorizon.beyondForecast => '상세 예보 전',
  };

  String get explanationKo => switch (this) {
    ForecastHorizon.shortTerm => '3시간 단위 상세 예보 구간입니다.',
    ForecastHorizon.midTerm => '중기예보 구간으로, 기온은 범위로 제공됩니다.',
    ForecastHorizon.beyondForecast =>
      '기상청 상세 예보는 10일까지 제공됩니다. 이 날짜는 일정만 확인할 수 있습니다.',
  };
}

enum ForecastConfidence {
  high,
  medium,
  low,
  unknown;

  static ForecastConfidence parse(String? raw) => switch (raw) {
    'high' => ForecastConfidence.high,
    'medium' => ForecastConfidence.medium,
    'low' => ForecastConfidence.low,
    _ => ForecastConfidence.unknown,
  };

  String get wireValue => name;

  String get labelKo => switch (this) {
    ForecastConfidence.high => '신뢰도 높음',
    ForecastConfidence.medium => '신뢰도 보통',
    ForecastConfidence.low => '신뢰도 낮음',
    ForecastConfidence.unknown => '신뢰도 정보 없음',
  };

  /// Confidence naturally decays with lead time; this is the default when the
  /// provider does not supply its own figure.
  static ForecastConfidence forHorizon(ForecastHorizon horizon, Duration lead) {
    return switch (horizon) {
      ForecastHorizon.shortTerm => ForecastConfidence.high,
      ForecastHorizon.midTerm =>
        lead.inDays <= 6 ? ForecastConfidence.medium : ForecastConfidence.low,
      ForecastHorizon.beyondForecast => ForecastConfidence.unknown,
    };
  }
}

/// A forecast for one venue at one game time.
///
/// Note what is *not* here: there is no "condition icon" field that a
/// long-range record could populate. Anything a `beyondForecast` record could
/// carry is limited to [seasonalTendency].
@immutable
class WeatherForecast {
  const WeatherForecast({
    required this.id,
    required this.venueId,
    required this.targetTimeUtc,
    required this.horizon,
    required this.issuedAt,
    required this.provenance,
    this.gameId,
    this.forecastZone,
    this.temperatureC,
    this.temperatureMinC,
    this.temperatureMaxC,
    this.precipitationProbability,
    this.precipitationMm,
    this.windSpeedMs,
    this.humidityPercent,
    this.skyCondition,
    this.confidence = ForecastConfidence.unknown,
    this.seasonalTendency,
  });

  final String id;
  final String venueId;
  final String? gameId;

  final DateTime targetTimeUtc;
  final ForecastHorizon horizon;

  /// When the meteorological service issued this forecast. Always displayed —
  /// a 6-hour-old mid-range forecast means something different from a fresh one.
  final DateTime issuedAt;

  /// The service's own forecast district (예보구역), preserved rather than
  /// silently reduced to "the venue".
  final String? forecastZone;

  /// Only meaningful when [horizon] allows exact values.
  final double? temperatureC;
  final double? temperatureMinC;
  final double? temperatureMaxC;

  /// 0-100.
  final int? precipitationProbability;
  final double? precipitationMm;
  final double? windSpeedMs;
  final int? humidityPercent;

  /// Raw sky code from the provider, mapped for display.
  final String? skyCondition;

  final ForecastConfidence confidence;

  /// Long-range wording only, e.g. "평년보다 기온이 높을 가능성". Never a daily
  /// value. This is the only weather text permitted beyond D+10.
  final String? seasonalTendency;

  final Provenance provenance;

  /// Enforced at render time: even if a record somehow carries a temperature
  /// beyond the forecast horizon, we refuse to display it.
  double? get displayTemperature =>
      horizon.allowsExactTemperature ? temperatureC : null;

  ({double min, double max})? get displayTemperatureRange {
    if (!horizon.allowsTemperatureRange) return null;
    final lo = temperatureMinC;
    final hi = temperatureMaxC;
    if (lo == null || hi == null) return null;
    return (min: lo, max: hi);
  }

  int? get displayPrecipitationProbability =>
      horizon.allowsDailyCondition ? precipitationProbability : null;

  bool get isStaleForTarget {
    // Short-term forecasts are reissued every 3 hours; anything older than 6
    // is worth refreshing before we let a user plan around it.
    final age = targetTimeUtc.difference(issuedAt);
    return horizon == ForecastHorizon.shortTerm && age.inHours > 6;
  }
}

/// Severity of a weather concern.
enum WeatherRiskLevel {
  /// No notable concern in the data we hold.
  clear,

  /// Worth knowing about; bring something.
  watch,

  /// Meaningful chance of disruption; re-check the schedule.
  caution,

  /// Conditions commonly associated with cancellation.
  severe,

  /// We do not have a forecast for this time yet.
  unknown;

  String get wireValue => name;

  /// Deliberately non-committal wording. We never state that a game *will* be
  /// cancelled — that is the organiser's call, not a forecast's.
  String get labelKo => switch (this) {
    WeatherRiskLevel.clear => '특이사항 없음',
    WeatherRiskLevel.watch => '참고 필요',
    WeatherRiskLevel.caution => '준비 필요',
    WeatherRiskLevel.severe => '일정 재확인 권장',
    WeatherRiskLevel.unknown => '예보 전',
  };

  int get severity => switch (this) {
    WeatherRiskLevel.clear => 0,
    WeatherRiskLevel.unknown => 1,
    WeatherRiskLevel.watch => 2,
    WeatherRiskLevel.caution => 3,
    WeatherRiskLevel.severe => 4,
  };
}

/// What kind of concern it is. Paired with an icon *and* text so the badge
/// never relies on colour alone.
enum WeatherRiskKind {
  rain,
  wind,
  heat,
  cold,
  none;

  String get wireValue => name;

  String get labelKo => switch (this) {
    WeatherRiskKind.rain => '강수',
    WeatherRiskKind.wind => '강풍',
    WeatherRiskKind.heat => '폭염',
    WeatherRiskKind.cold => '한파',
    WeatherRiskKind.none => '양호',
  };
}

/// Thresholds used to turn a forecast into a risk.
///
/// Config-driven and citable rather than hidden in an `if`. Defaults follow
/// 기상청 특보 기준 (폭염주의보 33℃, 한파주의보 −12℃, 강풍주의보 14m/s).
@immutable
class WeatherRiskThresholds {
  const WeatherRiskThresholds({
    this.rainProbabilityWatch = 40,
    this.rainProbabilityCaution = 60,
    this.rainProbabilitySevere = 80,
    this.rainfallMmCaution = 1.0,
    this.rainfallMmSevere = 5.0,
    this.windMsCaution = 9.0,
    this.windMsSevere = 14.0,
    this.heatCelsiusCaution = 31.0,
    this.heatCelsiusSevere = 33.0,
    this.coldCelsiusCaution = -6.0,
    this.coldCelsiusSevere = -12.0,
    this.sourceNote = '기상청 특보 발표 기준(폭염주의보 33℃, 한파주의보 -12℃, 강풍주의보 14m/s) 참고',
  });

  final int rainProbabilityWatch;
  final int rainProbabilityCaution;
  final int rainProbabilitySevere;
  final double rainfallMmCaution;
  final double rainfallMmSevere;
  final double windMsCaution;
  final double windMsSevere;
  final double heatCelsiusCaution;
  final double heatCelsiusSevere;
  final double coldCelsiusCaution;
  final double coldCelsiusSevere;

  /// Shown on the risk detail sheet so the numbers are attributable.
  final String sourceNote;

  static const WeatherRiskThresholds standard = WeatherRiskThresholds();
}

/// A computed risk for one game.
@immutable
class WeatherRisk {
  const WeatherRisk({
    required this.level,
    required this.kind,
    required this.horizon,
    this.forecast,
    this.detail,
    this.confidence = ForecastConfidence.unknown,
  });

  final WeatherRiskLevel level;
  final WeatherRiskKind kind;
  final ForecastHorizon horizon;
  final WeatherForecast? forecast;

  /// Short human phrase, e.g. "강수확률 70%".
  final String? detail;

  final ForecastConfidence confidence;

  bool get isActionable => level.severity >= WeatherRiskLevel.caution.severity;

  static const WeatherRisk unknownRisk = WeatherRisk(
    level: WeatherRiskLevel.unknown,
    kind: WeatherRiskKind.none,
    horizon: ForecastHorizon.beyondForecast,
  );

  /// Derives a risk from a forecast.
  ///
  /// Beyond the forecast horizon this always returns [unknownRisk] regardless
  /// of what the record contains — the honesty rule is enforced in code, not
  /// left to the caller.
  static WeatherRisk evaluate(
    WeatherForecast? forecast, {
    WeatherRiskThresholds thresholds = WeatherRiskThresholds.standard,
  }) {
    if (forecast == null) return unknownRisk;
    if (forecast.horizon == ForecastHorizon.beyondForecast) {
      return WeatherRisk(
        level: WeatherRiskLevel.unknown,
        kind: WeatherRiskKind.none,
        horizon: forecast.horizon,
        forecast: forecast,
        detail: forecast.seasonalTendency,
      );
    }

    final candidates = <WeatherRisk>[];

    final pop = forecast.precipitationProbability;
    final mm = forecast.precipitationMm;
    if (pop != null || mm != null) {
      var level = WeatherRiskLevel.clear;
      if ((pop != null && pop >= thresholds.rainProbabilitySevere) ||
          (mm != null && mm >= thresholds.rainfallMmSevere)) {
        level = WeatherRiskLevel.severe;
      } else if ((pop != null && pop >= thresholds.rainProbabilityCaution) ||
          (mm != null && mm >= thresholds.rainfallMmCaution)) {
        level = WeatherRiskLevel.caution;
      } else if (pop != null && pop >= thresholds.rainProbabilityWatch) {
        level = WeatherRiskLevel.watch;
      }
      if (level != WeatherRiskLevel.clear) {
        candidates.add(
          WeatherRisk(
            level: level,
            kind: WeatherRiskKind.rain,
            horizon: forecast.horizon,
            forecast: forecast,
            detail: pop != null ? '강수확률 $pop%' : '예상 강수량 ${mm}mm',
            confidence: forecast.confidence,
          ),
        );
      }
    }

    final wind = forecast.windSpeedMs;
    if (wind != null) {
      final level = wind >= thresholds.windMsSevere
          ? WeatherRiskLevel.severe
          : wind >= thresholds.windMsCaution
          ? WeatherRiskLevel.caution
          : WeatherRiskLevel.clear;
      if (level != WeatherRiskLevel.clear) {
        candidates.add(
          WeatherRisk(
            level: level,
            kind: WeatherRiskKind.wind,
            horizon: forecast.horizon,
            forecast: forecast,
            detail: '풍속 ${wind.toStringAsFixed(1)}m/s',
            confidence: forecast.confidence,
          ),
        );
      }
    }

    // Use the exact temperature when we have one, otherwise the range edge.
    final high = forecast.temperatureC ?? forecast.temperatureMaxC;
    if (high != null) {
      final level = high >= thresholds.heatCelsiusSevere
          ? WeatherRiskLevel.severe
          : high >= thresholds.heatCelsiusCaution
          ? WeatherRiskLevel.caution
          : WeatherRiskLevel.clear;
      if (level != WeatherRiskLevel.clear) {
        candidates.add(
          WeatherRisk(
            level: level,
            kind: WeatherRiskKind.heat,
            horizon: forecast.horizon,
            forecast: forecast,
            detail: '최고 ${high.toStringAsFixed(0)}℃',
            confidence: forecast.confidence,
          ),
        );
      }
    }

    final low = forecast.temperatureC ?? forecast.temperatureMinC;
    if (low != null) {
      final level = low <= thresholds.coldCelsiusSevere
          ? WeatherRiskLevel.severe
          : low <= thresholds.coldCelsiusCaution
          ? WeatherRiskLevel.caution
          : WeatherRiskLevel.clear;
      if (level != WeatherRiskLevel.clear) {
        candidates.add(
          WeatherRisk(
            level: level,
            kind: WeatherRiskKind.cold,
            horizon: forecast.horizon,
            forecast: forecast,
            detail: '최저 ${low.toStringAsFixed(0)}℃',
            confidence: forecast.confidence,
          ),
        );
      }
    }

    if (candidates.isEmpty) {
      return WeatherRisk(
        level: WeatherRiskLevel.clear,
        kind: WeatherRiskKind.none,
        horizon: forecast.horizon,
        forecast: forecast,
        confidence: forecast.confidence,
      );
    }

    candidates.sort((a, b) => b.level.severity.compareTo(a.level.severity));
    return candidates.first;
  }

  /// True when a re-computed risk differs enough to be worth notifying about.
  /// Prevents "still might rain" pings every time a forecast is reissued.
  bool isMeaningfullyDifferentFrom(WeatherRisk previous) {
    if (level == previous.level && kind == previous.kind) return false;
    // Only notify on a crossing into or out of actionable territory.
    return isActionable != previous.isActionable ||
        (level.severity - previous.level.severity).abs() >= 2;
  }
}
