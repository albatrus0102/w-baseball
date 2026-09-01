import 'package:meta/meta.dart';

import '../../core/design_system/tokens.dart';

/// Which home layout the user starts from.
///
/// This is a *presentation preference only*. It reorders home modules and
/// adjusts how much beginner explanation is shown. It never gates access:
/// every public feature is reachable in every mode.
enum AudienceMode {
  /// Getting to know women's baseball. Featured content and nearby games lead.
  discover,

  /// Plays or is involved with a team. Schedule, weather, standings lead.
  player,

  /// Both. Modules are interleaved by urgency rather than concatenated.
  both;

  static AudienceMode parse(String? raw) => switch (raw) {
    'discover' => AudienceMode.discover,
    'player' => AudienceMode.player,
    'both' => AudienceMode.both,
    _ => AudienceMode.discover,
  };

  String get wireValue => name;

  String get labelKo => switch (this) {
    AudienceMode.discover => '여자야구를 알아가는 중이에요',
    AudienceMode.player => '여자야구를 하고 있어요',
    AudienceMode.both => '둘 다 관심 있어요',
  };

  String get shortLabelKo => switch (this) {
    AudienceMode.discover => '알아가는 중',
    AudienceMode.player => '하고 있어요',
    AudienceMode.both => '둘 다',
  };

  /// Starting density for the mode. Only a default — the user can override it
  /// in 설정, and once they do, changing mode never overwrites their choice.
  WbDensity get defaultDensity => switch (this) {
    AudienceMode.discover => WbDensity.comfortable,
    AudienceMode.player => WbDensity.compact,
    AudienceMode.both => WbDensity.comfortable,
  };
}

/// How much of a result the user is willing to see before watching.
enum SpoilerLevel {
  /// Safe for anyone: no outcome revealed.
  none,

  /// Hints at drama without naming the result.
  mild,

  /// Reveals who won / what happened.
  result,

  /// Full detail including key plays.
  full;

  static SpoilerLevel parse(String? raw) => switch (raw) {
    'mild' => SpoilerLevel.mild,
    'result' => SpoilerLevel.result,
    'full' => SpoilerLevel.full,
    _ => SpoilerLevel.none,
  };

  String get wireValue => name;

  /// Ordering used to decide whether content must be masked.
  int get severity => switch (this) {
    SpoilerLevel.none => 0,
    SpoilerLevel.mild => 1,
    SpoilerLevel.result => 2,
    SpoilerLevel.full => 3,
  };
}

/// The user's spoiler tolerance, chosen in onboarding step 3.
enum SpoilerPolicy {
  /// "방송 결과를 바로 보기"
  reveal,

  /// "스포일러를 가리고 보기" — anything at `result` or above is masked
  /// behind a tap, in cards, detail screens, *and* notifications.
  hide;

  static SpoilerPolicy parse(String? raw) =>
      raw == 'reveal' ? SpoilerPolicy.reveal : SpoilerPolicy.hide;

  String get wireValue => name;

  String get labelKo => switch (this) {
    SpoilerPolicy.reveal => '방송 결과를 바로 보기',
    SpoilerPolicy.hide => '스포일러를 가리고 보기',
  };

  /// Single decision point used by every card, detail view and notification.
  bool shouldMask(SpoilerLevel level) =>
      this == SpoilerPolicy.hide &&
      level.severity >= SpoilerLevel.result.severity;
}

/// What the user can follow. Follows are local-only; there is no account.
enum FollowKind {
  team,
  competition,
  person,
  program,
  topic;

  static FollowKind parse(String? raw) => switch (raw) {
    'competition' => FollowKind.competition,
    'person' => FollowKind.person,
    'program' => FollowKind.program,
    'topic' => FollowKind.topic,
    _ => FollowKind.team,
  };

  String get wireValue => name;

  String get labelKo => switch (this) {
    FollowKind.team => '팀',
    FollowKind.competition => '대회',
    FollowKind.person => '선수',
    FollowKind.program => '프로그램',
    FollowKind.topic => '주제',
  };
}

/// A follow stored on the device.
@immutable
class LocalFollow {
  const LocalFollow({
    required this.kind,
    required this.entityId,
    required this.followedAt,
    this.label,
    this.muted = false,
  });

  final FollowKind kind;
  final String entityId;
  final DateTime followedAt;

  /// Cached display name so a follow still renders if the entity has not been
  /// synced yet (e.g. followed from a story cluster before teams arrived).
  final String? label;

  /// Still followed, but excluded from notifications.
  final bool muted;

  String get key => '${kind.wireValue}:$entityId';
}

/// Something the user saved to come back to.
enum SavedItemKind {
  game,
  storyCluster,
  episode,
  guide;

  static SavedItemKind parse(String? raw) => switch (raw) {
    'storyCluster' => SavedItemKind.storyCluster,
    'episode' => SavedItemKind.episode,
    'guide' => SavedItemKind.guide,
    _ => SavedItemKind.game,
  };

  String get wireValue => name;
}

@immutable
class SavedItem {
  const SavedItem({
    required this.kind,
    required this.entityId,
    required this.savedAt,
    this.note,
  });

  final SavedItemKind kind;
  final String entityId;
  final DateTime savedAt;
  final String? note;

  String get key => '${kind.wireValue}:$entityId';
}

/// Everything the onboarding collects, plus later adjustments. Stored locally;
/// never uploaded, never tied to an identity.
@immutable
class AudiencePreference {
  const AudiencePreference({
    this.mode = AudienceMode.discover,
    this.spoilerPolicy = SpoilerPolicy.hide,
    this.regionCode,
    this.regionLabel,
    this.showBeginnerExplanations = true,
    this.onboardingCompleted = false,
    this.onboardingSkipped = false,
    this.homeModuleOrder = const <String>[],
    this.collapsedModules = const <String>{},
    this.searchRadiusKm = 40,
    this.useDeviceLocation = false,
    this.densityOverride,
    this.modeNudgeDismissed = false,
    this.gameLogNudgeDismissed = false,
  });

  final AudienceMode mode;
  final SpoilerPolicy spoilerPolicy;

  /// Chosen 시·도 (e.g. `11` 서울). Optional — the user may skip it.
  final String? regionCode;
  final String? regionLabel;

  /// Beginner-level inline explanations ("이 기록은 무엇인가요?"). Someone who
  /// already knows baseball can turn these off.
  final bool showBeginnerExplanations;

  final bool onboardingCompleted;
  final bool onboardingSkipped;

  /// User-adjusted module order for the home screen. Empty means "use the
  /// default order for [mode]".
  final List<String> homeModuleOrder;

  final Set<String> collapsedModules;

  final int searchRadiusKm;

  /// Only ever true after an explicit in-context grant. Coordinates are used
  /// on-device for distance maths and are never persisted or transmitted.
  final bool useDeviceLocation;

  /// Null means "follow the mode". Set only when the user picks a density
  /// explicitly, so switching mode later does not silently undo their choice.
  final WbDensity? densityOverride;

  /// The user closed the home "모드 바꾸기" nudge once. Only meaningful while
  /// [isConfigured] is false — see [showsModeNudge].
  final bool modeNudgeDismissed;

  /// The user closed the "경기 하고 오셨나요?" 출전 일지 card without logging
  /// anything. Only meaningful before the first entry exists — once an entry
  /// exists the card is replaced by the log itself, so there is nothing left
  /// to dismiss. See `GameLogModule` in `my_baseball_screen.dart`.
  final bool gameLogNudgeDismissed;

  /// The density the UI should actually use.
  WbDensity get density => densityOverride ?? mode.defaultDensity;

  bool get hasRegion => regionCode != null && regionCode!.isNotEmpty;

  /// True when the user has told us anything at all through onboarding.
  bool get isConfigured => onboardingCompleted && !onboardingSkipped;

  /// Drives whether the home screen shows the "모드 바꾸기" nudge.
  ///
  /// A user who finished onboarding already chose a mode, so the nudge would
  /// only ever be telling them something they already know — that reading
  /// never changes, so it must not be a permanent fixture of the number-one
  /// position on home. Someone who *skipped* onboarding never chose, so they
  /// still need a way in; they get the nudge, but only until they dismiss it
  /// once, since 시작 화면 설정 (더보기 → 시작 화면과 지역) reaches the same
  /// picker for anyone who wants it back later.
  bool get showsModeNudge => !isConfigured && !modeNudgeDismissed;

  AudiencePreference copyWith({
    AudienceMode? mode,
    SpoilerPolicy? spoilerPolicy,
    String? regionCode,
    String? regionLabel,
    bool? showBeginnerExplanations,
    bool? onboardingCompleted,
    bool? onboardingSkipped,
    List<String>? homeModuleOrder,
    Set<String>? collapsedModules,
    int? searchRadiusKm,
    bool? useDeviceLocation,
    WbDensity? densityOverride,
    bool? modeNudgeDismissed,
    bool? gameLogNudgeDismissed,
    bool clearRegion = false,
    bool clearDensityOverride = false,
  }) {
    return AudiencePreference(
      mode: mode ?? this.mode,
      spoilerPolicy: spoilerPolicy ?? this.spoilerPolicy,
      regionCode: clearRegion ? null : (regionCode ?? this.regionCode),
      regionLabel: clearRegion ? null : (regionLabel ?? this.regionLabel),
      showBeginnerExplanations:
          showBeginnerExplanations ?? this.showBeginnerExplanations,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      onboardingSkipped: onboardingSkipped ?? this.onboardingSkipped,
      homeModuleOrder: homeModuleOrder ?? this.homeModuleOrder,
      collapsedModules: collapsedModules ?? this.collapsedModules,
      searchRadiusKm: searchRadiusKm ?? this.searchRadiusKm,
      useDeviceLocation: useDeviceLocation ?? this.useDeviceLocation,
      densityOverride: clearDensityOverride
          ? null
          : (densityOverride ?? this.densityOverride),
      modeNudgeDismissed: modeNudgeDismissed ?? this.modeNudgeDismissed,
      gameLogNudgeDismissed:
          gameLogNudgeDismissed ?? this.gameLogNudgeDismissed,
    );
  }
}

/// Korean administrative regions used for the region picker and nearby search.
///
/// Codes follow the 행정표준코드 시·도 prefix so they can later be joined to
/// public datasets without a translation table.
@immutable
class KoreanRegion {
  const KoreanRegion({
    required this.code,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String code;
  final String name;

  /// Representative centre point, used only for on-device distance sorting
  /// when the user has not granted (or has declined) location access.
  final double latitude;
  final double longitude;

  static const List<KoreanRegion> all = <KoreanRegion>[
    KoreanRegion(
      code: '11',
      name: '서울',
      latitude: 37.5665,
      longitude: 126.9780,
    ),
    KoreanRegion(
      code: '26',
      name: '부산',
      latitude: 35.1796,
      longitude: 129.0756,
    ),
    KoreanRegion(
      code: '27',
      name: '대구',
      latitude: 35.8714,
      longitude: 128.6014,
    ),
    KoreanRegion(
      code: '28',
      name: '인천',
      latitude: 37.4563,
      longitude: 126.7052,
    ),
    KoreanRegion(
      code: '29',
      name: '광주',
      latitude: 35.1595,
      longitude: 126.8526,
    ),
    KoreanRegion(
      code: '30',
      name: '대전',
      latitude: 36.3504,
      longitude: 127.3845,
    ),
    KoreanRegion(
      code: '31',
      name: '울산',
      latitude: 35.5384,
      longitude: 129.3114,
    ),
    KoreanRegion(
      code: '36',
      name: '세종',
      latitude: 36.4800,
      longitude: 127.2890,
    ),
    KoreanRegion(
      code: '41',
      name: '경기',
      latitude: 37.4138,
      longitude: 127.5183,
    ),
    KoreanRegion(
      code: '51',
      name: '강원',
      latitude: 37.8228,
      longitude: 128.1555,
    ),
    KoreanRegion(
      code: '43',
      name: '충북',
      latitude: 36.6357,
      longitude: 127.4917,
    ),
    KoreanRegion(
      code: '44',
      name: '충남',
      latitude: 36.5184,
      longitude: 126.8000,
    ),
    KoreanRegion(
      code: '52',
      name: '전북',
      latitude: 35.7175,
      longitude: 127.1530,
    ),
    KoreanRegion(
      code: '46',
      name: '전남',
      latitude: 34.8679,
      longitude: 126.9910,
    ),
    KoreanRegion(
      code: '47',
      name: '경북',
      latitude: 36.4919,
      longitude: 128.8889,
    ),
    KoreanRegion(
      code: '48',
      name: '경남',
      latitude: 35.4606,
      longitude: 128.2132,
    ),
    KoreanRegion(
      code: '50',
      name: '제주',
      latitude: 33.4996,
      longitude: 126.5312,
    ),
  ];

  static KoreanRegion? byCode(String? code) {
    if (code == null) return null;
    for (final r in all) {
      if (r.code == code) return r;
    }
    return null;
  }
}

/// Notification categories the user can switch on individually.
///
/// Deliberately fine-grained: the single biggest complaint about the KBO app
/// in public reviews is that notifications can only be toggled all at once.
enum NotificationCategory {
  // Player-oriented
  myTeamGameWeek,
  myTeamGameDay,
  myTeamGameHour,
  weatherRisk,
  scheduleChange,
  standingsUpdate,
  leaderboardUpdate,
  // Discover-oriented
  programEpisodeRecap,
  followedPersonNews,
  weekendNearbyGames,
  savedGameChange,
  weeklyBriefing;

  static NotificationCategory? parse(String? raw) {
    for (final c in NotificationCategory.values) {
      if (c.name == raw) return c;
    }
    return null;
  }

  String get wireValue => name;

  String get labelKo => switch (this) {
    NotificationCategory.myTeamGameWeek => '내 팀 경기 7일 전',
    NotificationCategory.myTeamGameDay => '내 팀 경기 24시간 전',
    NotificationCategory.myTeamGameHour => '내 팀 경기 1시간 전',
    NotificationCategory.weatherRisk => '날씨 위험 변화',
    NotificationCategory.scheduleChange => '경기 연기·취소·구장 변경',
    NotificationCategory.standingsUpdate => '순위표 갱신',
    NotificationCategory.leaderboardUpdate => '개인 기록 집계 완료',
    NotificationCategory.programEpisodeRecap => '팔로우한 프로그램 새 회차 요약',
    NotificationCategory.followedPersonNews => '팔로우한 인물·팀 소식',
    NotificationCategory.weekendNearbyGames => '이번 주말 우리 지역 경기',
    NotificationCategory.savedGameChange => '저장한 경기 일정 변경',
    NotificationCategory.weeklyBriefing => '주 1회 여자야구 브리핑',
  };

  /// Shown in the notification itself so the user always knows why they got it
  /// and can unfollow straight from there.
  String get reasonKo => switch (this) {
    NotificationCategory.myTeamGameWeek ||
    NotificationCategory.myTeamGameDay ||
    NotificationCategory.myTeamGameHour => '팔로우한 팀의 경기 알림을 켜 두셨습니다.',
    NotificationCategory.weatherRisk => '경기일 날씨 알림을 켜 두셨습니다.',
    NotificationCategory.scheduleChange => '일정 변경 알림을 켜 두셨습니다.',
    NotificationCategory.standingsUpdate => '순위 알림을 켜 두셨습니다.',
    NotificationCategory.leaderboardUpdate => '기록 알림을 켜 두셨습니다.',
    NotificationCategory.programEpisodeRecap => '이 프로그램을 팔로우하셨습니다.',
    NotificationCategory.followedPersonNews => '이 인물 또는 팀을 팔로우하셨습니다.',
    NotificationCategory.weekendNearbyGames => '지역 경기 알림을 켜 두셨습니다.',
    NotificationCategory.savedGameChange => '이 경기를 저장하셨습니다.',
    NotificationCategory.weeklyBriefing => '주간 브리핑을 켜 두셨습니다.',
  };

  /// What this category *does*, for the settings list.
  ///
  /// Distinct from [reasonKo], which explains why an alert already in the
  /// notification shade was sent. Reusing the reason here made every switched
  /// *off* row read "…켜 두셨습니다" — a description that contradicted the
  /// toggle sitting next to it.
  String get descriptionKo => switch (this) {
    NotificationCategory.myTeamGameWeek => '팔로우한 팀의 경기 일주일 전에 알려드립니다.',
    NotificationCategory.myTeamGameDay => '팔로우한 팀의 경기 하루 전에 알려드립니다.',
    NotificationCategory.myTeamGameHour => '팔로우한 팀의 경기 한 시간 전에 알려드립니다.',
    NotificationCategory.weatherRisk => '경기일 비·바람·더위 위험이 바뀌면 알려드립니다.',
    NotificationCategory.scheduleChange => '경기가 연기·취소되거나 구장이 바뀌면 알려드립니다.',
    NotificationCategory.standingsUpdate => '순위표가 갱신되면 알려드립니다.',
    NotificationCategory.leaderboardUpdate => '개인 기록 집계가 끝나면 알려드립니다.',
    NotificationCategory.programEpisodeRecap => '팔로우한 프로그램의 새 회차 요약을 알려드립니다.',
    NotificationCategory.followedPersonNews => '팔로우한 인물·팀의 새 소식을 알려드립니다.',
    NotificationCategory.weekendNearbyGames => '주말에 우리 지역 경기가 있으면 알려드립니다.',
    NotificationCategory.savedGameChange => '저장한 경기의 일정이 바뀌면 알려드립니다.',
    NotificationCategory.weeklyBriefing => '한 주에 한 번 여자야구 소식을 모아 보내드립니다.',
  };

  bool get isPlayerOriented => switch (this) {
    NotificationCategory.programEpisodeRecap ||
    NotificationCategory.followedPersonNews ||
    NotificationCategory.weekendNearbyGames ||
    NotificationCategory.savedGameChange ||
    NotificationCategory.weeklyBriefing => false,
    _ => true,
  };

  /// A category that can carry a broadcast outcome, so it must respect the
  /// spoiler policy.
  bool get canContainSpoiler =>
      this == NotificationCategory.programEpisodeRecap;
}

/// Quiet hours plus per-category switches.
@immutable
class NotificationPreference {
  const NotificationPreference({
    this.enabled = const <NotificationCategory>{},
    this.quietHoursStartMinute,
    this.quietHoursEndMinute,
    this.allowSpoilersInNotifications = false,
    this.permissionRequested = false,
  });

  final Set<NotificationCategory> enabled;

  /// Minutes from midnight, local time. Null disables quiet hours.
  final int? quietHoursStartMinute;
  final int? quietHoursEndMinute;

  final bool allowSpoilersInNotifications;

  /// We ask for the OS permission once, in context. If refused we do not ask
  /// again — the settings screen explains how to enable it manually.
  final bool permissionRequested;

  bool isEnabled(NotificationCategory category) => enabled.contains(category);

  bool get hasQuietHours =>
      quietHoursStartMinute != null && quietHoursEndMinute != null;

  /// Handles windows that wrap past midnight (e.g. 22:00 → 07:00).
  bool isWithinQuietHours(DateTime localTime) {
    final start = quietHoursStartMinute;
    final end = quietHoursEndMinute;
    if (start == null || end == null) return false;
    final minute = localTime.hour * 60 + localTime.minute;
    if (start == end) return false;
    return start < end
        ? minute >= start && minute < end
        : minute >= start || minute < end;
  }

  /// Sensible starting point per audience mode. Nothing is switched on without
  /// the user first following something.
  static Set<NotificationCategory> defaultsFor(AudienceMode mode) {
    return switch (mode) {
      AudienceMode.player => <NotificationCategory>{
        NotificationCategory.myTeamGameDay,
        NotificationCategory.scheduleChange,
        NotificationCategory.weatherRisk,
      },
      AudienceMode.discover => <NotificationCategory>{
        NotificationCategory.programEpisodeRecap,
        NotificationCategory.savedGameChange,
      },
      AudienceMode.both => <NotificationCategory>{
        NotificationCategory.myTeamGameDay,
        NotificationCategory.scheduleChange,
        NotificationCategory.programEpisodeRecap,
        NotificationCategory.savedGameChange,
      },
    };
  }

  NotificationPreference copyWith({
    Set<NotificationCategory>? enabled,
    int? quietHoursStartMinute,
    int? quietHoursEndMinute,
    bool? allowSpoilersInNotifications,
    bool? permissionRequested,
    bool clearQuietHours = false,
  }) {
    return NotificationPreference(
      enabled: enabled ?? this.enabled,
      quietHoursStartMinute: clearQuietHours
          ? null
          : (quietHoursStartMinute ?? this.quietHoursStartMinute),
      quietHoursEndMinute: clearQuietHours
          ? null
          : (quietHoursEndMinute ?? this.quietHoursEndMinute),
      allowSpoilersInNotifications:
          allowSpoilersInNotifications ?? this.allowSpoilersInNotifications,
      permissionRequested: permissionRequested ?? this.permissionRequested,
    );
  }
}
