import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/data/models/content.dart';
import 'package:w_baseball/data/models/provenance.dart';

/// "다음 방송" is a claim about the future, so it needs evidence.
///
/// The app derives it from a published weekly slot — 목요일 22:00 — and that
/// slot never expires on its own. `finaleDate` and `isActive` exist precisely
/// for this and are both written once when a season is published and never
/// revised, so neither notices that a year has passed. Without a freshness
/// rule the card promises a broadcast for a programme that ended, in a
/// confident voice, forever.
void main() {
  ContentMeta meta() => ContentMeta(
    provenance: Provenance(
      sourceName: 's',
      sourceUrl: 'https://example.org',
      fetchedAt: DateTime.utc(2026),
    ),
    publishedAt: DateTime.utc(2026),
  );

  /// A weekly Thursday-22:00 season, matching the shape the seed publishes.
  ProgramSeason season({
    DateTime? premiere,
    DateTime? finale,
    bool isActive = true,
    int? dayOfWeek = DateTime.thursday,
    int? minuteOfDay = 22 * 60,
  }) => ProgramSeason(
    id: 'season-1',
    programId: 'program-1',
    seasonNumber: 2,
    title: '시즌 2',
    airDayOfWeek: dayOfWeek,
    airTimeMinuteOfDay: minuteOfDay,
    premiereDate: premiere ?? DateTime(2026, 7, 2),
    finaleDate: finale,
    isActive: isActive,
    meta: meta(),
  );

  // KST wall-clock instants: `nextAirSlot` works in the display calendar.
  final duringTheRun = DateTime(2026, 8, 30, 9);
  final lastAired = DateTime(2026, 8, 26, 22);

  group('다음 방송 추정', () {
    test('최근 회차가 있으면 다음 슬롯을 말한다', () {
      final next = season().nextAirSlot(
        duringTheRun,
        lastAiredAtKst: lastAired,
      );

      expect(next, isNotNull);
      expect(next!.weekday, DateTime.thursday);
      expect(next.isAfter(duringTheRun), isTrue);
    });

    test('세 주 넘게 방송이 없으면 다음 방송을 말하지 않는다', () {
      // The failure this exists for. The record still says `isActive: true`
      // with a Thursday slot, because nothing ever goes back and edits it.
      final muchLater = DateTime(2027, 3, 1);

      expect(
        season().nextAirSlot(muchLater, lastAiredAtKst: lastAired),
        isNull,
        reason: '끝난 방송의 다음 회차를 앱이 만들어내면 안 됩니다',
      );
    });

    test('경계는 3주다', () {
      // Just inside and just outside, so the window is a decision rather than
      // whatever the arithmetic happened to produce.
      final inside = lastAired.add(const Duration(days: 20));
      final outside = lastAired.add(const Duration(days: 22));

      expect(season().nextAirSlot(inside, lastAiredAtKst: lastAired), isNotNull);
      expect(season().nextAirSlot(outside, lastAiredAtKst: lastAired), isNull);
    });

    test('방영 전에는 편성일이 근거가 된다', () {
      // Nothing has aired yet and the schedule is still legitimate.
      final beforePremiere = DateTime(2026, 6, 28);

      expect(
        season(premiere: DateTime(2026, 7, 2)).nextAirSlot(beforePremiere),
        isNotNull,
      );
    });

    test('근거가 아무것도 없으면 말하지 않는다', () {
      expect(
        ProgramSeason(
          id: 'season-2',
          programId: 'program-1',
          seasonNumber: 1,
          title: '시즌 1',
          airDayOfWeek: DateTime.thursday,
          airTimeMinuteOfDay: 22 * 60,
          isActive: true,
          meta: meta(),
        ).nextAirSlot(duringTheRun),
        isNull,
      );
    });

    test('종영일이 있으면 그 뒤로는 말하지 않는다', () {
      // An explicit end date is stronger evidence than recency, and it is
      // still honoured on its own terms.
      expect(
        season(finale: DateTime(2026, 8, 27)).nextAirSlot(
          duringTheRun,
          lastAiredAtKst: lastAired,
        ),
        isNull,
      );
    });

    test('종영일이 있으면 최근 방송이 없어도 그 전까지는 말한다', () {
      // A published finale means someone stated the season's extent, so the
      // recency heuristic steps aside rather than second-guessing it.
      final gap = DateTime(2026, 10, 1);
      expect(
        season(finale: DateTime(2026, 12, 31)).nextAirSlot(gap),
        isNotNull,
      );
    });

    test('보관된 시즌은 슬롯이 남아 있어도 말하지 않는다', () {
      expect(
        season(isActive: false).nextAirSlot(
          duringTheRun,
          lastAiredAtKst: lastAired,
        ),
        isNull,
      );
    });

    test('편성 정보가 없으면 말하지 않는다', () {
      expect(
        season(dayOfWeek: null).nextAirSlot(
          duringTheRun,
          lastAiredAtKst: lastAired,
        ),
        isNull,
      );
      expect(
        season(minuteOfDay: null).nextAirSlot(
          duringTheRun,
          lastAiredAtKst: lastAired,
        ),
        isNull,
      );
    });
  });
}
