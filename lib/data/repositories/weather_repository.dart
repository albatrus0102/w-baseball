import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../core/database/database.dart';
import '../mappers/row_mappers.dart';
import '../models/weather.dart';

/// Weather for games, with the forecast-horizon rule enforced in one place.
///
/// The rule, restated because it is the whole point of this class: the 기상청
/// publishes 단기예보 out to about D+2 and 중기예보 out to D+10. There is no
/// daily forecast beyond that. So for a game 25 days away this repository
/// returns [WeatherRisk.unknownRisk] — not a guess, not an icon, not a
/// temperature — and the UI renders "예보 전".
abstract interface class WeatherRepository {
  /// Risk for one game. Always safe to call: returns `unknown` rather than
  /// throwing or inventing when there is no forecast.
  Future<WeatherRisk> riskForGame(String gameId, DateTime startTimeUtc);

  /// Risks for many games at once, for the calendar board.
  Future<Map<String, WeatherRisk>> risksForGames(
    Map<String, DateTime> gameTimes,
  );

  Stream<WeatherForecast?> watchForecast(String gameId);

  /// The horizon a given game falls into right now.
  ForecastHorizon horizonFor(DateTime startTimeUtc);

  /// True when the game is close enough that the forecast should be refreshed
  /// (7 / 3 / 1 days out are the recomputation points).
  bool needsRefresh(DateTime startTimeUtc, DateTime? lastIssuedAt);
}

class DriftWeatherRepository implements WeatherRepository {
  DriftWeatherRepository({
    required this.db,
    this.thresholds = WeatherRiskThresholds.standard,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final WbDatabase db;
  final WeatherRiskThresholds thresholds;
  final DateTime Function() _clock;

  @override
  ForecastHorizon horizonFor(DateTime startTimeUtc) =>
      ForecastHorizon.between(_clock().toUtc(), startTimeUtc);

  @override
  Future<WeatherRisk> riskForGame(String gameId, DateTime startTimeUtc) async {
    final horizon = horizonFor(startTimeUtc);

    // Short-circuit before touching storage: beyond D+10 there is nothing we
    // are permitted to say about a specific day, whatever rows may exist.
    if (horizon == ForecastHorizon.beyondForecast) {
      final tendency = await _seasonalTendency(gameId);
      return WeatherRisk(
        level: WeatherRiskLevel.unknown,
        kind: WeatherRiskKind.none,
        horizon: horizon,
        detail: tendency,
      );
    }

    final row =
        await (db.select(db.weatherForecasts)
              ..where((t) => t.gameId.equals(gameId))
              ..orderBy([(t) => OrderingTerm.desc(t.issuedAt)])
              ..limit(1))
            .getSingleOrNull();

    if (row == null) return WeatherRisk.unknownRisk;

    final forecast = row.toDomain();
    // Trust the live horizon over the stored one: a forecast fetched a week
    // ago as mid-range may now be short-range, and vice versa.
    final corrected = _withHorizon(forecast, horizon);
    return WeatherRisk.evaluate(corrected, thresholds: thresholds);
  }

  @override
  Future<Map<String, WeatherRisk>> risksForGames(
    Map<String, DateTime> gameTimes,
  ) async {
    if (gameTimes.isEmpty) return const <String, WeatherRisk>{};

    final ids = gameTimes.keys.toSet();
    final rows =
        await (db.select(db.weatherForecasts)
              ..where((t) => t.gameId.isIn(ids))
              ..orderBy([(t) => OrderingTerm.desc(t.issuedAt)]))
            .get();

    // Newest issue per game.
    final latest = <String, WeatherForecastRow>{};
    for (final r in rows) {
      final gameId = r.gameId;
      if (gameId == null) continue;
      latest.putIfAbsent(gameId, () => r);
    }

    final out = <String, WeatherRisk>{};
    gameTimes.forEach((gameId, startTime) {
      final horizon = horizonFor(startTime);
      if (horizon == ForecastHorizon.beyondForecast) {
        out[gameId] = WeatherRisk(
          level: WeatherRiskLevel.unknown,
          kind: WeatherRiskKind.none,
          horizon: horizon,
        );
        return;
      }
      final row = latest[gameId];
      if (row == null) {
        out[gameId] = WeatherRisk.unknownRisk;
        return;
      }
      out[gameId] = WeatherRisk.evaluate(
        _withHorizon(row.toDomain(), horizon),
        thresholds: thresholds,
      );
    });
    return out;
  }

  @override
  Stream<WeatherForecast?> watchForecast(String gameId) {
    final select = db.select(db.weatherForecasts)
      ..where((t) => t.gameId.equals(gameId))
      ..orderBy([(t) => OrderingTerm.desc(t.issuedAt)])
      ..limit(1);
    return select.watchSingleOrNull().map((row) {
      if (row == null) return null;
      final forecast = row.toDomain();
      return _withHorizon(forecast, horizonFor(forecast.targetTimeUtc));
    });
  }

  @override
  bool needsRefresh(DateTime startTimeUtc, DateTime? lastIssuedAt) {
    final now = _clock().toUtc();
    final lead = startTimeUtc.difference(now);
    if (lead.isNegative) return false;
    if (lead.inDays > 10) return false; // Nothing to fetch yet.
    if (lastIssuedAt == null) return true;

    final age = now.difference(lastIssuedAt);
    // Recompute at the 7 / 3 / 1-day marks, and more often as the game nears.
    if (lead.inDays <= 1) return age > const Duration(hours: 3);
    if (lead.inDays <= 3) return age > const Duration(hours: 6);
    if (lead.inDays <= 7) return age > const Duration(hours: 12);
    return age > const Duration(hours: 24);
  }

  /// Rewrites the stored horizon to the live one and strips any values the new
  /// horizon does not permit. Defence in depth: even a bad row cannot leak a
  /// precise temperature into a long-range card.
  WeatherForecast _withHorizon(WeatherForecast f, ForecastHorizon horizon) {
    if (f.horizon == horizon) return f;
    return WeatherForecast(
      id: f.id,
      venueId: f.venueId,
      gameId: f.gameId,
      targetTimeUtc: f.targetTimeUtc,
      horizon: horizon,
      issuedAt: f.issuedAt,
      forecastZone: f.forecastZone,
      temperatureC: horizon.allowsExactTemperature ? f.temperatureC : null,
      temperatureMinC: horizon.allowsTemperatureRange
          ? f.temperatureMinC
          : null,
      temperatureMaxC: horizon.allowsTemperatureRange
          ? f.temperatureMaxC
          : null,
      precipitationProbability: horizon.allowsDailyCondition
          ? f.precipitationProbability
          : null,
      precipitationMm: horizon.allowsDailyCondition ? f.precipitationMm : null,
      windSpeedMs: horizon.allowsDailyCondition ? f.windSpeedMs : null,
      humidityPercent: f.humidityPercent,
      skyCondition: horizon.allowsDailyCondition ? f.skyCondition : null,
      confidence: ForecastConfidence.forHorizon(
        horizon,
        f.targetTimeUtc.difference(_clock().toUtc()),
      ),
      seasonalTendency: f.seasonalTendency,
      provenance: f.provenance,
    );
  }

  Future<String?> _seasonalTendency(String gameId) async {
    final row =
        await (db.select(db.weatherForecasts)
              ..where(
                (t) => t.gameId.equals(gameId) & t.seasonalTendency.isNotNull(),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.issuedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row?.seasonalTendency;
  }
}

/// Straight-line distance between two coordinates, in kilometres.
///
/// Used only on-device, to sort nearby games. The user's coordinates are never
/// written to storage, logs, or any network request.
double haversineKm({
  required double lat1,
  required double lon1,
  required double lat2,
  required double lon2,
}) {
  const earthRadiusKm = 6371.0;
  double toRad(double deg) => deg * math.pi / 180.0;

  final dLat = toRad(lat2 - lat1);
  final dLon = toRad(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(toRad(lat1)) *
          math.cos(toRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
