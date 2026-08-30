// Only `Value` is needed, and a bare drift import shadows the matchers
// `isNull` / `isNotNull` with its own column predicates.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/database/database.dart';
import 'package:w_baseball/data/models/weather.dart';
import 'package:w_baseball/data/repositories/weather_repository.dart';

/// The forecast-horizon rule, asserted.
///
/// 기상청 publishes 단기예보 to about D+2 and 중기예보 to D+10, and nothing
/// daily past that. The app's promise is that it never shows a number the
/// forecast does not support — a 25-days-out game gets "상세 예보 전", not an
/// icon and a temperature. The repository is where that is enforced, and it
/// had no tests: every guarantee in it rested on its own doc comment.
void main() {
  late WbDatabase db;
  // Pinned. Horizon is a function of the distance between now and first pitch,
  // so a live clock would move a fixture across a band mid-run.
  final now = DateTime.utc(2026, 8, 30, 9);

  setUp(() => db = WbDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  DriftWeatherRepository repo() =>
      DriftWeatherRepository(db: db, clock: () => now);

  Future<void> insert({
    required String gameId,
    required DateTime targetTimeUtc,
    required ForecastHorizon storedHorizon,
    required ForecastConfidence storedConfidence,
    double? temperatureC,
    double? temperatureMinC,
    double? temperatureMaxC,
    int? precipitationProbability,
    String? skyCondition,
    String? seasonalTendency,
    DateTime? issuedAt,
  }) async {
    await db
        .into(db.weatherForecasts)
        .insert(
          WeatherForecastsCompanion.insert(
            id: '$gameId-fc',
            venueId: 'venue-1',
            gameId: Value(gameId),
            targetTimeUtc: targetTimeUtc,
            horizon: storedHorizon.name,
            issuedAt: issuedAt ?? now,
            temperatureC: Value(temperatureC),
            temperatureMinC: Value(temperatureMinC),
            temperatureMaxC: Value(temperatureMaxC),
            precipitationProbability: Value(precipitationProbability),
            skyCondition: Value(skyCondition),
            confidence: Value(storedConfidence.name),
            seasonalTendency: Value(seasonalTendency),
            sourceName: 'demo',
            sourceUrl: 'https://example.test/demo',
            fetchedAt: now,
          ),
        );
  }

  group('예보 가능 구간', () {
    test('D+25 경기는 저장된 행이 있어도 unknown으로만 답한다', () async {
      // The short-circuit has to come before storage is consulted. A row that
      // should not exist must not be able to produce a number just because it
      // is there.
      final start = now.add(const Duration(days: 25));
      await insert(
        gameId: 'g-far',
        targetTimeUtc: start,
        storedHorizon: ForecastHorizon.shortTerm,
        storedConfidence: ForecastConfidence.high,
        temperatureC: 27.4,
        precipitationProbability: 80,
        skyCondition: 'rain',
      );

      final risk = await repo().riskForGame('g-far', start);

      expect(risk.horizon, ForecastHorizon.beyondForecast);
      expect(risk.level, WeatherRiskLevel.unknown);
      expect(risk.kind, WeatherRiskKind.none);
    });

    test('예보 구간 밖에서는 계절 경향만 전달한다', () async {
      final start = now.add(const Duration(days: 20));
      await insert(
        gameId: 'g-tendency',
        targetTimeUtc: start,
        storedHorizon: ForecastHorizon.beyondForecast,
        storedConfidence: ForecastConfidence.unknown,
        seasonalTendency: '평년보다 더울 가능성',
      );

      final risk = await repo().riskForGame('g-tendency', start);

      expect(risk.detail, '평년보다 더울 가능성');
      expect(risk.level, WeatherRiskLevel.unknown);
    });

    test('예보가 아예 없으면 unknown이다', () async {
      final risk = await repo().riskForGame(
        'g-none',
        now.add(const Duration(days: 2)),
      );
      expect(risk.level, WeatherRiskLevel.unknown);
    });
  });

  group('저장된 값의 재해석', () {
    test('중기 구간으로 넘어간 행의 정확한 기온은 사라진다', () async {
      // Written when the game was two days away, read when it is six. The
      // stored temperature was legitimate then and is false precision now.
      final start = now.add(const Duration(days: 6));
      await insert(
        gameId: 'g-slid',
        targetTimeUtc: start,
        storedHorizon: ForecastHorizon.shortTerm,
        storedConfidence: ForecastConfidence.high,
        temperatureC: 27.4,
        temperatureMinC: 22,
        temperatureMaxC: 29,
      );

      final f = await repo().watchForecast('g-slid').first;

      expect(f, isNotNull);
      expect(f!.horizon, ForecastHorizon.midTerm);
      expect(f.displayTemperature, isNull, reason: '중기예보에 정확한 기온을 보이면 안 됩니다');
      expect(f.displayTemperatureRange, isNotNull, reason: '범위는 허용됩니다');
    });

    test('같은 구간 안에서도 신뢰도는 남은 기간으로 다시 계산된다', () async {
      // The one that was actually wrong. Confidence turns over at D+6 *inside*
      // 중기예보, and the rewrite used to be skipped whenever the stored
      // horizon already matched — so a row issued at D+5 as 보통 still read
      // 보통 with the game nine days out. That overstates the forecast in the
      // direction people plan around.
      final start = now.add(const Duration(days: 9));
      await insert(
        gameId: 'g-stale',
        targetTimeUtc: start,
        storedHorizon: ForecastHorizon.midTerm,
        storedConfidence: ForecastConfidence.medium,
        temperatureMinC: 21,
        temperatureMaxC: 28,
      );

      final f = await repo().watchForecast('g-stale').first;

      expect(f!.horizon, ForecastHorizon.midTerm, reason: '구간 자체는 그대로입니다');
      expect(
        f.confidence,
        ForecastConfidence.low,
        reason: 'D+9 중기예보를 보통으로 말하면 안 됩니다',
      );
    });

    test('경기가 다가오면 신뢰도가 올라간다', () async {
      final start = now.add(const Duration(days: 4));
      await insert(
        gameId: 'g-near',
        targetTimeUtc: start,
        storedHorizon: ForecastHorizon.midTerm,
        storedConfidence: ForecastConfidence.low,
        temperatureMinC: 21,
        temperatureMaxC: 28,
      );

      final f = await repo().watchForecast('g-near').first;
      expect(f!.confidence, ForecastConfidence.medium);
    });
  });

  group('여러 경기 한 번에', () {
    test('경기별로 각자의 구간 규칙이 적용된다', () async {
      final soon = now.add(const Duration(days: 1));
      final far = now.add(const Duration(days: 30));
      await insert(
        gameId: 'g-soon',
        targetTimeUtc: soon,
        storedHorizon: ForecastHorizon.shortTerm,
        storedConfidence: ForecastConfidence.high,
        temperatureC: 24,
        precipitationProbability: 10,
      );
      await insert(
        gameId: 'g-far2',
        targetTimeUtc: far,
        storedHorizon: ForecastHorizon.shortTerm,
        storedConfidence: ForecastConfidence.high,
        temperatureC: 24,
        precipitationProbability: 90,
      );

      final risks = await repo().risksForGames({
        'g-soon': soon,
        'g-far2': far,
      });

      expect(risks['g-far2']!.horizon, ForecastHorizon.beyondForecast);
      expect(risks['g-far2']!.level, WeatherRiskLevel.unknown);
      expect(risks['g-soon']!.horizon, ForecastHorizon.shortTerm);
    });

    test('가장 최근 발표본을 쓴다', () async {
      final start = now.add(const Duration(days: 1));
      await insert(
        gameId: 'g-multi',
        targetTimeUtc: start,
        storedHorizon: ForecastHorizon.shortTerm,
        storedConfidence: ForecastConfidence.high,
        precipitationProbability: 10,
        issuedAt: now.subtract(const Duration(hours: 12)),
      );
      await db
          .into(db.weatherForecasts)
          .insert(
            WeatherForecastsCompanion.insert(
              id: 'g-multi-fc2',
              venueId: 'venue-1',
              gameId: const Value('g-multi'),
              targetTimeUtc: start,
              horizon: ForecastHorizon.shortTerm.name,
              issuedAt: now,
              precipitationProbability: const Value(90),
              confidence: Value(ForecastConfidence.high.name),
              sourceName: 'demo',
            sourceUrl: 'https://example.test/demo',
            fetchedAt: now,
            ),
          );

      final f = await repo().watchForecast('g-multi').first;
      expect(f!.displayPrecipitationProbability, 90);
    });

    test('빈 요청은 저장소를 건드리지 않고 빈 결과를 준다', () async {
      expect(await repo().risksForGames(const {}), isEmpty);
    });
  });

  group('갱신 시점', () {
    test('D+10을 넘으면 아직 받아올 것이 없다', () {
      expect(
        repo().needsRefresh(now.add(const Duration(days: 15)), null),
        isFalse,
      );
    });

    test('이미 시작한 경기는 갱신하지 않는다', () {
      expect(
        repo().needsRefresh(now.subtract(const Duration(hours: 1)), null),
        isFalse,
      );
    });

    test('임박한 경기일수록 자주 갱신한다', () {
      final tomorrow = now.add(const Duration(hours: 20));
      expect(
        repo().needsRefresh(tomorrow, now.subtract(const Duration(hours: 4))),
        isTrue,
      );
      expect(
        repo().needsRefresh(tomorrow, now.subtract(const Duration(hours: 2))),
        isFalse,
      );

      final inAWeek = now.add(const Duration(days: 7));
      expect(
        repo().needsRefresh(inAWeek, now.subtract(const Duration(hours: 4))),
        isFalse,
        reason: '일주일 뒤 경기를 4시간마다 다시 받을 이유가 없습니다',
      );
    });
  });

  group('구장 거리 계산', () {
    test('서울 잠실과 부산 사직 사이 거리가 실제와 맞는다', () {
      // ~325 km by great circle. A sign error or a degree/radian mix-up would
      // still produce a plausible-looking number, so the check is numeric.
      final km = haversineKm(
        lat1: 37.5121,
        lon1: 127.0719,
        lat2: 35.1940,
        lon2: 129.0615,
      );
      expect(km, closeTo(325, 15));
    });

    test('같은 지점은 0이다', () {
      expect(
        haversineKm(lat1: 37.5, lon1: 127.0, lat2: 37.5, lon2: 127.0),
        closeTo(0, 0.001),
      );
    });
  });
}
