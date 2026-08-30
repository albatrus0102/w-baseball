import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/data/models/provenance.dart';
import 'package:w_baseball/data/models/weather.dart';

/// The 30-day honesty rule.
///
/// 기상청 publishes 단기예보 to about D+2 and 중기예보 to D+10. There is no daily
/// forecast beyond that. These tests pin that boundary so a future change
/// cannot quietly start showing an invented icon or temperature for a game
/// three weeks out.
void main() {
  final now = DateTime.utc(2026, 8, 30, 3);

  Provenance provenance() => Provenance(
    sourceName: 'kma',
    sourceUrl: 'https://www.weather.go.kr/',
    fetchedAt: now,
  );

  WeatherForecast forecast({
    required ForecastHorizon horizon,
    required DateTime target,
    double? temperatureC,
    double? minC,
    double? maxC,
    int? pop,
    double? wind,
    String? tendency,
  }) {
    return WeatherForecast(
      id: 'wx',
      venueId: 'venue',
      targetTimeUtc: target,
      horizon: horizon,
      issuedAt: now,
      temperatureC: temperatureC,
      temperatureMinC: minC,
      temperatureMaxC: maxC,
      precipitationProbability: pop,
      windSpeedMs: wind,
      seasonalTendency: tendency,
      provenance: provenance(),
    );
  }

  group('예보 구간 판정', () {
    test('D+0~2는 단기예보', () {
      expect(
        ForecastHorizon.between(now, now.add(const Duration(hours: 6))),
        ForecastHorizon.shortTerm,
      );
      expect(
        ForecastHorizon.between(now, now.add(const Duration(days: 2))),
        ForecastHorizon.shortTerm,
      );
    });

    test('D+3~10은 중기예보', () {
      expect(
        ForecastHorizon.between(now, now.add(const Duration(days: 3))),
        ForecastHorizon.midTerm,
      );
      expect(
        ForecastHorizon.between(now, now.add(const Duration(days: 10))),
        ForecastHorizon.midTerm,
      );
    });

    test('D+11 이후는 상세 예보 없음', () {
      expect(
        ForecastHorizon.between(now, now.add(const Duration(days: 11))),
        ForecastHorizon.beyondForecast,
      );
      expect(
        ForecastHorizon.between(now, now.add(const Duration(days: 30))),
        ForecastHorizon.beyondForecast,
      );
    });
  });

  group('구간별 표시 허용', () {
    test('정확한 기온은 단기예보에서만 허용된다', () {
      expect(ForecastHorizon.shortTerm.allowsExactTemperature, isTrue);
      expect(ForecastHorizon.midTerm.allowsExactTemperature, isFalse);
      expect(ForecastHorizon.beyondForecast.allowsExactTemperature, isFalse);
    });

    test('기온 범위는 중기예보까지 허용된다', () {
      expect(ForecastHorizon.midTerm.allowsTemperatureRange, isTrue);
      expect(ForecastHorizon.beyondForecast.allowsTemperatureRange, isFalse);
    });

    test('일별 날씨 아이콘·강수확률은 10일 이후 금지', () {
      expect(ForecastHorizon.beyondForecast.allowsDailyCondition, isFalse);
    });
  });

  group('표시 게이트', () {
    test('중기예보 레코드에 정확한 기온이 있어도 노출하지 않는다', () {
      final f = forecast(
        horizon: ForecastHorizon.midTerm,
        target: now.add(const Duration(days: 5)),
        temperatureC: 28,
        minC: 21,
        maxC: 30,
      );
      // The value exists in the record but must not reach the UI.
      expect(f.temperatureC, 28);
      expect(f.displayTemperature, isNull);
      expect(f.displayTemperatureRange, isNotNull);
    });

    test('예보 구간 밖에서는 범위도 강수확률도 노출하지 않는다', () {
      final f = forecast(
        horizon: ForecastHorizon.beyondForecast,
        target: now.add(const Duration(days: 21)),
        minC: 20,
        maxC: 29,
        pop: 60,
      );
      expect(f.displayTemperature, isNull);
      expect(f.displayTemperatureRange, isNull);
      expect(f.displayPrecipitationProbability, isNull);
    });
  });

  group('위험도 평가', () {
    test('예보 구간을 벗어나면 항상 unknown이며 경향만 남는다', () {
      final risk = WeatherRisk.evaluate(
        forecast(
          horizon: ForecastHorizon.beyondForecast,
          target: now.add(const Duration(days: 25)),
          pop: 90,
          temperatureC: 35,
          tendency: '평년보다 기온이 높을 가능성',
        ),
      );
      // Even with values present, nothing actionable may be claimed.
      expect(risk.level, WeatherRiskLevel.unknown);
      expect(risk.kind, WeatherRiskKind.none);
      expect(risk.detail, '평년보다 기온이 높을 가능성');
      expect(risk.isActionable, isFalse);
    });

    test('강수확률이 임계를 넘으면 준비/재확인 단계로 올라간다', () {
      final target = now.add(const Duration(days: 1));
      expect(
        WeatherRisk.evaluate(
          forecast(horizon: ForecastHorizon.shortTerm, target: target, pop: 45),
        ).level,
        WeatherRiskLevel.watch,
      );
      expect(
        WeatherRisk.evaluate(
          forecast(horizon: ForecastHorizon.shortTerm, target: target, pop: 65),
        ).level,
        WeatherRiskLevel.caution,
      );
      expect(
        WeatherRisk.evaluate(
          forecast(horizon: ForecastHorizon.shortTerm, target: target, pop: 85),
        ).level,
        WeatherRiskLevel.severe,
      );
    });

    test('폭염 기준(33도)에서 severe', () {
      final risk = WeatherRisk.evaluate(
        forecast(
          horizon: ForecastHorizon.shortTerm,
          target: now.add(const Duration(days: 1)),
          temperatureC: 34,
        ),
      );
      expect(risk.kind, WeatherRiskKind.heat);
      expect(risk.level, WeatherRiskLevel.severe);
    });

    test('강풍 기준(14m/s)에서 severe', () {
      final risk = WeatherRisk.evaluate(
        forecast(
          horizon: ForecastHorizon.shortTerm,
          target: now.add(const Duration(days: 1)),
          wind: 15,
        ),
      );
      expect(risk.kind, WeatherRiskKind.wind);
      expect(risk.level, WeatherRiskLevel.severe);
    });

    test('여러 위험이 겹치면 가장 심각한 것을 대표로 삼는다', () {
      final risk = WeatherRisk.evaluate(
        forecast(
          horizon: ForecastHorizon.shortTerm,
          target: now.add(const Duration(days: 1)),
          pop: 45,
          temperatureC: 34,
        ),
      );
      expect(risk.level, WeatherRiskLevel.severe);
      expect(risk.kind, WeatherRiskKind.heat);
    });

    test('예보가 없으면 unknown', () {
      expect(WeatherRisk.evaluate(null).level, WeatherRiskLevel.unknown);
    });

    test('경기 취소를 단정하지 않는 문구를 쓴다', () {
      // Wording is part of the contract: a forecast never decides a fixture.
      expect(WeatherRiskLevel.severe.labelKo, '일정 재확인 권장');
      expect(WeatherRiskLevel.caution.labelKo, '준비 필요');
      for (final level in WeatherRiskLevel.values) {
        expect(level.labelKo.contains('취소'), isFalse);
      }
    });
  });

  group('알림 재계산', () {
    test('실행 가능 여부가 바뀔 때만 의미 있는 변화로 본다', () {
      const clear = WeatherRisk(
        level: WeatherRiskLevel.clear,
        kind: WeatherRiskKind.none,
        horizon: ForecastHorizon.shortTerm,
      );
      const watch = WeatherRisk(
        level: WeatherRiskLevel.watch,
        kind: WeatherRiskKind.rain,
        horizon: ForecastHorizon.shortTerm,
      );
      const severe = WeatherRisk(
        level: WeatherRiskLevel.severe,
        kind: WeatherRiskKind.rain,
        horizon: ForecastHorizon.shortTerm,
      );

      expect(severe.isMeaningfullyDifferentFrom(clear), isTrue);
      // watch -> severe crosses into actionable, so it notifies.
      expect(severe.isMeaningfullyDifferentFrom(watch), isTrue);
      // Same level, same kind: nothing new to say.
      expect(watch.isMeaningfullyDifferentFrom(watch), isFalse);
    });
  });

  group('신뢰도', () {
    test('구간이 멀어질수록 낮아진다', () {
      expect(
        ForecastConfidence.forHorizon(
          ForecastHorizon.shortTerm,
          const Duration(days: 1),
        ),
        ForecastConfidence.high,
      );
      expect(
        ForecastConfidence.forHorizon(
          ForecastHorizon.midTerm,
          const Duration(days: 5),
        ),
        ForecastConfidence.medium,
      );
      expect(
        ForecastConfidence.forHorizon(
          ForecastHorizon.midTerm,
          const Duration(days: 9),
        ),
        ForecastConfidence.low,
      );
      expect(
        ForecastConfidence.forHorizon(
          ForecastHorizon.beyondForecast,
          const Duration(days: 20),
        ),
        ForecastConfidence.unknown,
      );
    });
  });
}
