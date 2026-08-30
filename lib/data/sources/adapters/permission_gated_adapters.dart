import '../../../core/config/app_config.dart';
import '../../dto/dtos.dart';
import '../../sync/sync_contracts.dart';
import '../sports_data_source.dart';

/// Adapters for sources that need a permission grant before they may run.
///
/// All four are compiled in and all four are **off by default**. That is a
/// deliberate product decision, not an oversight:
///
///  * **WBAK / KBSA** — no public, documented external API was found. Their
///    sites are built on an internal request layer that is not an API contract
///    offered to third parties. Calling it because it happens to respond would
///    be scraping something we have not been given permission to use, so the
///    app links to the official pages instead and the adapter stays disabled
///    until an explicit grant, a CSV export, or a real API exists.
///
///  * **WBSC / WPBL** — these do expose publicly reachable endpoints, but a
///    reachable endpoint is not a supported contract. They are gated behind a
///    flag so that enabling them is a conscious decision accompanied by schema
///    validation and failure isolation, rather than a silent dependency.
///
/// Each class below documents exactly what to implement when the grant
/// arrives. Until then `isEnabled` is false and `SyncEngine` skips them
/// without recording an error.
abstract base class PermissionGatedAdapter extends BaseSportsDataSource {
  const PermissionGatedAdapter({required this.enabled});

  /// Driven by a feature flag in [FeatureFlags]; never hard-coded to true.
  final bool enabled;

  @override
  bool get isEnabled => enabled;

  /// Human-readable reason shown on the data-sources screen.
  String get disabledReasonKo;

  /// Guard used by every fetch method, so an accidentally-enabled adapter with
  /// no implementation fails loudly rather than silently returning nothing.
  ///
  /// Only reachable when [enabled] is true, which is the "someone turned the
  /// flag on and the code is not written" case — not the licensing case. It
  /// therefore reports [SyncFailureKind.notImplemented] and says so, rather
  /// than repeating [disabledReasonKo]; telling a user who just enabled a
  /// source that we are waiting for permission sends them looking for a
  /// problem that is on our side.
  Never notImplemented() => throw SyncException(
    SyncFailureKind.notImplemented,
    sourceName: sourceName,
    message: '$displayName 어댑터가 활성화되었지만 아직 구현되지 않았습니다.',
  );
}

/// 한국여자야구연맹 (WBAK).
final class WbakAdapter extends PermissionGatedAdapter {
  const WbakAdapter({required super.enabled});

  @override
  String get sourceName => 'wbak';

  @override
  String get displayName => 'WBAK 한국여자야구연맹';

  @override
  String get disabledReasonKo =>
      'WBAK의 외부 공개 API가 확인되지 않았습니다. 이용허락을 받기 전까지 자동 수집을 하지 않습니다.';

  /// Entity types this source would provide once permitted. Empty while
  /// disabled so the engine has nothing to call.
  @override
  Set<SyncEntityType> get supportedEntities => enabled
      ? const <SyncEntityType>{
          SyncEntityType.team,
          SyncEntityType.competition,
          SyncEntityType.game,
          SyncEntityType.article,
        }
      : const <SyncEntityType>{};

  /// When a grant arrives, implement these four and nothing else:
  ///
  /// 1. `fetchTeams`      — map the club list to [TeamDto].
  /// 2. `fetchCompetitions` — map 대회 + 시즌 to [CompetitionDto].
  /// 3. `fetchGames`      — map 일정/결과 to [GameDto], scoped by month.
  /// 4. `fetchArticles`   — map 공지 to [ArticleDto] (metadata + link only).
  ///
  /// Every mapper must set `source.sourceUrl` to the exact public detail page,
  /// never a site root, so "공식 기록 보기" lands where the user expects.
  @override
  Future<SyncPage<TeamDto>> fetchTeams(SyncRequest request) async =>
      enabled ? notImplemented() : SyncPage.empty<TeamDto>(sourceName);

  @override
  Future<SyncPage<GameDto>> fetchGames(GameSyncRequest request) async =>
      enabled ? notImplemented() : SyncPage.empty<GameDto>(sourceName);

  @override
  Future<SyncPage<CompetitionDto>> fetchCompetitions(
    SyncRequest request,
  ) async =>
      enabled ? notImplemented() : SyncPage.empty<CompetitionDto>(sourceName);

  @override
  Future<SyncPage<ArticleDto>> fetchArticles(SyncRequest request) async =>
      enabled ? notImplemented() : SyncPage.empty<ArticleDto>(sourceName);
}

/// 대한야구소프트볼협회 (KBSA) 통합경기정보.
final class KbsaAdapter extends PermissionGatedAdapter {
  const KbsaAdapter({required super.enabled});

  @override
  String get sourceName => 'kbsa';

  @override
  String get displayName => 'KBSA 대한야구소프트볼협회';

  @override
  String get disabledReasonKo =>
      'KBSA 통합경기정보의 공개 API가 확인되지 않았습니다. 이용허락 또는 CSV 제공 시 활성화합니다.';

  @override
  Set<SyncEntityType> get supportedEntities => enabled
      ? const <SyncEntityType>{
          SyncEntityType.competition,
          SyncEntityType.game,
          SyncEntityType.standing,
        }
      : const <SyncEntityType>{};

  @override
  Future<SyncPage<GameDto>> fetchGames(GameSyncRequest request) async =>
      enabled ? notImplemented() : SyncPage.empty<GameDto>(sourceName);

  @override
  Future<SyncPage<StandingDto>> fetchStandings(SyncRequest request) async =>
      enabled ? notImplemented() : SyncPage.empty<StandingDto>(sourceName);

  @override
  Future<SyncPage<CompetitionDto>> fetchCompetitions(
    SyncRequest request,
  ) async =>
      enabled ? notImplemented() : SyncPage.empty<CompetitionDto>(sourceName);
}

/// WBSC — international events.
final class WbscAdapter extends PermissionGatedAdapter {
  const WbscAdapter({required super.enabled});

  @override
  String get sourceName => 'wbsc';

  @override
  String get displayName => 'WBSC 국제대회';

  @override
  String get disabledReasonKo => '공개 페이지는 있으나 응답 구조 검증과 실패 격리를 마친 뒤 활성화합니다.';

  @override
  Set<SyncEntityType> get supportedEntities => enabled
      ? const <SyncEntityType>{SyncEntityType.game, SyncEntityType.standing}
      : const <SyncEntityType>{};

  @override
  Future<SyncPage<GameDto>> fetchGames(GameSyncRequest request) async =>
      enabled ? notImplemented() : SyncPage.empty<GameDto>(sourceName);

  @override
  Future<SyncPage<StandingDto>> fetchStandings(SyncRequest request) async =>
      enabled ? notImplemented() : SyncPage.empty<StandingDto>(sourceName);
}

/// WPBL — the US women's professional league.
///
/// Its `wp-json` endpoints are publicly reachable, but a WordPress REST route
/// is an implementation detail of someone else's site, not a contract offered
/// to us. Gated for the same reason as the others.
final class WpblAdapter extends PermissionGatedAdapter {
  const WpblAdapter({required super.enabled});

  @override
  String get sourceName => 'wpbl';

  @override
  String get displayName => 'WPBL';

  @override
  String get disabledReasonKo =>
      '공개 GET 주소가 있으나 장기 제공이 보장되지 않아 스키마 검증과 함께 별도 활성화합니다.';

  @override
  Set<SyncEntityType> get supportedEntities => enabled
      ? const <SyncEntityType>{SyncEntityType.game, SyncEntityType.article}
      : const <SyncEntityType>{};

  @override
  Future<SyncPage<GameDto>> fetchGames(GameSyncRequest request) async =>
      enabled ? notImplemented() : SyncPage.empty<GameDto>(sourceName);

  @override
  Future<SyncPage<ArticleDto>> fetchArticles(SyncRequest request) async =>
      enabled ? notImplemented() : SyncPage.empty<ArticleDto>(sourceName);
}

/// Builds the gated adapters from the current flag set.
///
/// Called by the provider graph so that "which sources exist" is answered in
/// one place and every one of them defaults to off.
List<SportsDataSource> buildGatedAdapters(FeatureFlags flags) =>
    <SportsDataSource>[
      WbakAdapter(enabled: flags.wbakAdapterEnabled),
      KbsaAdapter(enabled: flags.kbsaAdapterEnabled),
      WbscAdapter(enabled: flags.wbscAdapterEnabled),
      WpblAdapter(enabled: flags.wpblAdapterEnabled),
    ];
