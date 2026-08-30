import '../../data/models/audience.dart';

/// The home screen is a list of modules, not a fixed layout.
///
/// Order is data, keyed by [AudienceMode], and the user can collapse or
/// reorder them. That is what lets one screen serve both a newcomer and a
/// player without becoming two apps or one very long page.
enum HomeModule {
  /// Small banner offering to switch mode, for users who skipped onboarding.
  modeNudge,

  // --- discover-leaning ---
  featuredTopic,
  programRecap,
  weekendNearby,
  topStories,
  storiesForYou,
  beginnerGuide,
  officialVideos,

  // --- player-leaning ---
  myNextGame,
  weatherOutlook,
  scheduleSummary,
  myStanding,
  leaguePulse,
  leaderboardHighlights,
  myTeamNews,

  // --- shared tail ---
  officialNotices,
  recentResults,
  upcomingGames,
  startPlaying;

  String get key => name;

  String get titleKo => switch (this) {
    HomeModule.modeNudge => '',
    HomeModule.featuredTopic => '지금 화제',
    HomeModule.programRecap => '방송 다시 보기',
    HomeModule.weekendNearby => '이번 주말 가까운 경기',
    HomeModule.topStories => '모두가 알아둘 주요 소식',
    HomeModule.storiesForYou => '내 관심 소식',
    HomeModule.beginnerGuide => '여자야구 1분 이해',
    HomeModule.officialVideos => '공식 영상',
    HomeModule.myNextGame => '내 팀 다음 경기',
    HomeModule.weatherOutlook => '경기일 날씨',
    HomeModule.scheduleSummary => '앞으로 30일',
    HomeModule.myStanding => '내 팀 순위',
    HomeModule.leaguePulse => '리그 현황',
    HomeModule.leaderboardHighlights => '기록 부문 선두',
    HomeModule.myTeamNews => '내 팀 소식',
    HomeModule.officialNotices => '공지',
    HomeModule.recentResults => '최근 결과',
    HomeModule.upcomingGames => '다가오는 경기',
    HomeModule.startPlaying => '여자야구 시작하기',
  };

  /// What an empty module should do.
  ///
  /// Two different situations were being rendered the same way. "공식 영상이
  /// 아직 없음" is housekeeping the reader does not need; "이번 주말 우리 지역
  /// 경기 없음" is the answer they came for. Treating both as "draw nothing"
  /// left a heading with a blank space under it, which reads as a broken app.
  ///
  /// Kept as data on the module rather than decided in the widget, because a
  /// judgement made per-widget is one each new module gets to make again.
  bool get statesItsAbsence => switch (this) {
    HomeModule.weekendNearby ||
    HomeModule.myNextGame ||
    HomeModule.scheduleSummary ||
    HomeModule.myStanding => true,
    _ => false,
  };

  /// Shown, with the heading, when [statesItsAbsence] and there is nothing.
  /// Never invents a reason — it says what is missing, not why.
  String get emptyMessageKo => switch (this) {
    HomeModule.weekendNearby => '이번 주말 등록된 경기가 없습니다',
    HomeModule.myNextGame => '예정된 다음 경기가 없습니다',
    HomeModule.scheduleSummary => '앞으로 30일 안에 예정된 경기가 없습니다',
    HomeModule.myStanding => '아직 순위를 보여줄 대회가 없습니다',
    _ => '',
  };

  /// Modules a user can collapse. The lead module of each mode is pinned so
  /// the screen always answers its primary question.
  bool get isCollapsible => switch (this) {
    HomeModule.modeNudge ||
    HomeModule.featuredTopic ||
    HomeModule.myNextGame => false,
    _ => true,
  };

  /// Default order for a newcomer.
  ///
  /// Scores are not removed — they move below content that gives someone with
  /// no team allegiance a reason to care.
  static const List<HomeModule> discoverOrder = <HomeModule>[
    HomeModule.modeNudge,
    HomeModule.featuredTopic,
    HomeModule.programRecap,
    HomeModule.weekendNearby,
    HomeModule.topStories,
    HomeModule.storiesForYou,
    HomeModule.beginnerGuide,
    HomeModule.officialVideos,
    HomeModule.upcomingGames,
    HomeModule.recentResults,
    HomeModule.startPlaying,
  ];

  /// Default order for someone who plays.
  static const List<HomeModule> playerOrder = <HomeModule>[
    HomeModule.modeNudge,
    HomeModule.myNextGame,
    HomeModule.weatherOutlook,
    HomeModule.scheduleSummary,
    HomeModule.myStanding,
    HomeModule.leaguePulse,
    HomeModule.leaderboardHighlights,
    HomeModule.myTeamNews,
    HomeModule.officialNotices,
    HomeModule.featuredTopic,
  ];

  /// Both. Deliberately *not* the two lists concatenated: the urgent
  /// player-facing items lead, then the strongest discovery item, then the
  /// rest. Roughly the length of one list, not two.
  static const List<HomeModule> bothOrder = <HomeModule>[
    HomeModule.modeNudge,
    HomeModule.myNextGame,
    HomeModule.weatherOutlook,
    HomeModule.featuredTopic,
    HomeModule.weekendNearby,
    HomeModule.myStanding,
    HomeModule.topStories,
    HomeModule.leaguePulse,
    HomeModule.programRecap,
    HomeModule.upcomingGames,
  ];

  static List<HomeModule> defaultOrderFor(AudienceMode mode) => switch (mode) {
    AudienceMode.discover => discoverOrder,
    AudienceMode.player => playerOrder,
    AudienceMode.both => bothOrder,
  };

  static HomeModule? fromKey(String key) {
    for (final m in HomeModule.values) {
      if (m.key == key) return m;
    }
    return null;
  }

  /// Resolves the order to render: the user's saved arrangement if they have
  /// one, otherwise the default for their mode.
  ///
  /// A saved order is filtered against the current mode's module set, so
  /// switching modes never leaves an orphaned module behind, and newly added
  /// modules appear rather than being silently dropped.
  static List<HomeModule> resolveOrder(AudiencePreference preference) {
    final defaults = defaultOrderFor(preference.mode);
    if (preference.homeModuleOrder.isEmpty) return defaults;

    final allowed = defaults.toSet();
    final saved = preference.homeModuleOrder
        .map(HomeModule.fromKey)
        .whereType<HomeModule>()
        .where(allowed.contains)
        .toList();

    // Append anything the saved order does not mention (e.g. a module added
    // in a later release) so the screen never loses content on upgrade.
    for (final module in defaults) {
      if (!saved.contains(module)) saved.add(module);
    }
    return saved;
  }
}
