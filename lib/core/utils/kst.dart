import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Korea Standard Time helpers.
///
/// Storage is always UTC / ISO-8601. Display is always Asia/Seoul unless a
/// fixture explicitly carries another zone, in which case the detail screen
/// can show the local time as a secondary line.
///
/// KST is UTC+9 with no daylight saving, so a fixed offset is exact rather
/// than an approximation. Non-Korean fixtures use the `timezone` package via
/// [LocalZone] where a real zone database is needed.
class Kst {
  const Kst._();

  static const Duration offset = Duration(hours: 9);
  static const String zoneId = 'Asia/Seoul';

  /// UTC instant → the wall-clock time a Korean user sees.
  static DateTime toKst(DateTime utc) => utc.toUtc().add(offset);

  /// A Korean wall-clock time → the UTC instant.
  static DateTime fromKst(DateTime kstWallClock) => DateTime.utc(
    kstWallClock.year,
    kstWallClock.month,
    kstWallClock.day,
    kstWallClock.hour,
    kstWallClock.minute,
    kstWallClock.second,
  ).subtract(offset);

  /// `yyyy-MM-dd` in KST. The grouping key for the schedule board.
  static String dayKey(DateTime utc) {
    final k = toKst(utc);
    return '${_p4(k.year)}-${_p2(k.month)}-${_p2(k.day)}';
  }

  /// `yyyy-MM` in KST. The partition key for published game files.
  static String monthKey(DateTime utc) {
    final k = toKst(utc);
    return '${_p4(k.year)}-${_p2(k.month)}';
  }

  static String dayKeyOfKstDate(DateTime kstDate) =>
      '${_p4(kstDate.year)}-${_p2(kstDate.month)}-${_p2(kstDate.day)}';

  static String monthKeyOfKstDate(DateTime kstDate) =>
      '${_p4(kstDate.year)}-${_p2(kstDate.month)}';

  /// Start of a KST day, as a UTC instant. Used for range queries.
  static DateTime startOfKstDayUtc(DateTime utc) {
    final k = toKst(utc);
    return DateTime.utc(k.year, k.month, k.day).subtract(offset);
  }

  static DateTime endOfKstDayUtc(DateTime utc) =>
      startOfKstDayUtc(utc).add(const Duration(days: 1));

  /// "Today" in KST, regardless of the device's own time zone. A user in
  /// Seoul and a user abroad watching Korean baseball should agree on which
  /// day a fixture belongs to.
  ///
  /// Returned as a UTC-flavoured value carrying KST calendar fields, which is
  /// the whole point: callers add days to it and subtract two of them from
  /// each other. Korea has no daylight saving, but the *device* may, and local
  /// arithmetic follows the device. Across a fall-back the gap between two
  /// consecutive local midnights is 23 hours, so `difference(...).inDays`
  /// truncates to 0 and tomorrow's fixture is labelled 오늘; adding five days
  /// to reach Saturday lands on Friday 23:00 and picks the wrong weekend. UTC
  /// days are always 24 hours, so none of that can happen.
  ///
  /// Reading `.year` / `.month` / `.day` / `.weekday` is unaffected by the
  /// flavour — those are the same fields either way.
  static DateTime todayKst(DateTime nowUtc) {
    final k = toKst(nowUtc);
    return DateTime.utc(k.year, k.month, k.day);
  }

  static bool isSameKstDay(DateTime a, DateTime b) => dayKey(a) == dayKey(b);

  /// The next Saturday+Sunday window in KST, as UTC bounds.
  /// If today *is* the weekend, returns the current one.
  static ({DateTime startUtc, DateTime endUtc}) upcomingWeekendUtc(
    DateTime nowUtc,
  ) {
    final today = todayKst(nowUtc);
    // ISO weekday: Sat = 6, Sun = 7.
    final daysUntilSaturday = switch (today.weekday) {
      DateTime.saturday => 0,
      DateTime.sunday => -1,
      final w => DateTime.saturday - w,
    };
    final saturday = today.add(Duration(days: daysUntilSaturday));
    final start = fromKst(
      DateTime(saturday.year, saturday.month, saturday.day),
    );
    return (startUtc: start, endUtc: start.add(const Duration(days: 2)));
  }

  /// Rounds an instant down to a whole [bucket].
  ///
  /// Query objects are used as Riverpod family keys, so any time value inside
  /// one must be stable across rebuilds. Feeding a raw `DateTime.now()` into a
  /// key mints a new provider on every frame, which is an endless rebuild
  /// loop. Quantising to the hour (or the day) keeps the key steady while the
  /// data stays fresh enough.
  static DateTime quantize(DateTime utc, Duration bucket) {
    final ms = utc.toUtc().millisecondsSinceEpoch;
    final size = bucket.inMilliseconds;
    if (size <= 0) return utc.toUtc();
    return DateTime.fromMillisecondsSinceEpoch(ms - (ms % size), isUtc: true);
  }

  /// The current hour, as a stable query bound.
  static DateTime hourBucket(DateTime utc) =>
      quantize(utc, const Duration(hours: 1));

  static String _p2(int v) => v.toString().padLeft(2, '0');
  static String _p4(int v) => v.toString().padLeft(4, '0');
}

/// Korean-language date and time formatting.
///
/// All formatters are built once; `intl` formatter construction is not free
/// and these are called per list row.
class KoDate {
  const KoDate._();

  static const String _locale = 'ko';

  static bool _localeReady = false;

  /// Korean date symbols must be registered before any formatter is built.
  /// Doing it here rather than only in `bootstrap()` means widget tests and
  /// unit tests get correct Korean output without extra setup.
  static DateFormat _formatter(String pattern) {
    if (!_localeReady) {
      initializeDateFormatting(_locale);
      _localeReady = true;
    }
    return DateFormat(pattern, _locale);
  }

  static final DateFormat _monthDay = _formatter('M월 d일');
  static final DateFormat _monthDayWeekday = _formatter('M월 d일 (E)');
  static final DateFormat _yearMonthDay = _formatter('yyyy년 M월 d일');
  static final DateFormat _time = _formatter('a h:mm');
  static final DateFormat _time24 = _formatter('HH:mm');
  static final DateFormat _weekday = _formatter('E');
  static final DateFormat _monthYear = _formatter('yyyy년 M월');

  static String monthDay(DateTime utc) => _monthDay.format(Kst.toKst(utc));

  static String monthDayWeekday(DateTime utc) =>
      _monthDayWeekday.format(Kst.toKst(utc));

  static String fullDate(DateTime utc) => _yearMonthDay.format(Kst.toKst(utc));

  /// `오후 2:30`
  static String time(DateTime utc) => _time.format(Kst.toKst(utc));

  /// `14:30` — used in dense tables where the 오전/오후 prefix costs width.
  static String time24(DateTime utc) => _time24.format(Kst.toKst(utc));

  static String weekday(DateTime utc) => _weekday.format(Kst.toKst(utc));

  static String monthYear(DateTime kstDate) => _monthYear.format(kstDate);

  /// `8월 30일 (토) 오후 2:30`
  static String dateTime(DateTime utc) =>
      '${monthDayWeekday(utc)} ${time(utc)}';

  /// A screen-reader-friendly rendering of a score: "5 대 4".
  static String scoreForScreenReader(int home, int away) => '$home 대 $away';

  /// Relative wording for freshness labels.
  static String relative(DateTime pastUtc, DateTime nowUtc) {
    final diff = nowUtc.difference(pastUtc);
    if (diff.isNegative) return '방금';
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}주 전';
    return monthDay(pastUtc);
  }

  /// Countdown wording for an upcoming fixture.
  static String until(DateTime futureUtc, DateTime nowUtc) {
    final diff = futureUtc.difference(nowUtc);
    if (diff.isNegative) return '진행/종료';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 후';
    if (diff.inHours < 24) return '${diff.inHours}시간 후';
    return '${diff.inDays}일 후';
  }

  /// "오늘" / "내일" / "모레" where it reads better than a date.
  static String? relativeDayLabel(DateTime utc, DateTime nowUtc) {
    final target = Kst.todayKst(utc);
    final today = Kst.todayKst(nowUtc);
    final days = target.difference(today).inDays;
    return switch (days) {
      0 => '오늘',
      1 => '내일',
      2 => '모레',
      -1 => '어제',
      _ => null,
    };
  }

  /// Day heading used by the games list: "오늘 · 8월 30일 (토)".
  static String dayHeading(DateTime utc, DateTime nowUtc) {
    final relative = relativeDayLabel(utc, nowUtc);
    final absolute = monthDayWeekday(utc);
    return relative == null ? absolute : '$relative · $absolute';
  }

  /// An absolute "as of" date: `monthDay`, or the full year-qualified date
  /// when [utc] falls in a different year than [nowUtc].
  ///
  /// Used wherever a source line states a fact instead of a freshness verdict
  /// (see `WbFreshnessScope`) — a bare "8월 30일" reads fine today but would be
  /// ambiguous for a record left over from a previous year, and the relative
  /// wording ("2일 전 기준") that would otherwise disambiguate is exactly what
  /// a fact-only line must not claim, since it drifts on its own every day
  /// with no code change.
  static String monthDayOrFullDate(DateTime utc, DateTime nowUtc) {
    final target = Kst.toKst(utc);
    final today = Kst.toKst(nowUtc);
    return target.year == today.year ? monthDay(utc) : fullDate(utc);
  }
}
