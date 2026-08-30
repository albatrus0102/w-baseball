import 'package:meta/meta.dart';

/// Central, build-time-replaceable configuration.
///
/// Nothing in the app may hard-code a base URL, endpoint path, contract
/// version, or form link. Everything routes through here so that switching
/// from bundled seed data to a static manifest to a real REST/GraphQL API is a
/// configuration change plus one new adapter, not a code sweep.
///
/// Values are supplied with `--dart-define` (see `.env.example` and
/// `docs/configuration.md`); the defaults below are safe for a developer build
/// and never point at a fabricated URL.
@immutable
class AppConfig {
  const AppConfig({
    required this.dataContract,
    required this.manifest,
    required this.futureApi,
    required this.forms,
    required this.officialLinks,
    required this.flags,
    required this.sync,
    required this.webView,
  });

  final DataContractConfig dataContract;
  final ManifestConfig manifest;
  final FutureApiConfig futureApi;
  final FormsConfig forms;
  final OfficialLinksConfig officialLinks;
  final FeatureFlags flags;
  final SyncConfig sync;
  final WebViewConfig webView;

  /// Reads every value from the compile-time environment.
  factory AppConfig.fromEnvironment() {
    return AppConfig(
      dataContract: const DataContractConfig(),
      manifest: ManifestConfig.fromEnvironment(),
      futureApi: FutureApiConfig.fromEnvironment(),
      forms: FormsConfig.fromEnvironment(),
      officialLinks: const OfficialLinksConfig(),
      flags: FeatureFlags.fromEnvironment(),
      sync: const SyncConfig(),
      webView: const WebViewConfig(),
    );
  }

  AppConfig copyWith({
    DataContractConfig? dataContract,
    ManifestConfig? manifest,
    FutureApiConfig? futureApi,
    FormsConfig? forms,
    OfficialLinksConfig? officialLinks,
    FeatureFlags? flags,
    SyncConfig? sync,
    WebViewConfig? webView,
  }) {
    return AppConfig(
      dataContract: dataContract ?? this.dataContract,
      manifest: manifest ?? this.manifest,
      futureApi: futureApi ?? this.futureApi,
      forms: forms ?? this.forms,
      officialLinks: officialLinks ?? this.officialLinks,
      flags: flags ?? this.flags,
      sync: sync ?? this.sync,
      webView: webView ?? this.webView,
    );
  }
}

/// Data contract negotiation.
///
/// The app declares which payload schema versions it can consume. Receiving a
/// `schemaVersion` above [maxSupportedSchemaVersion] must *stop the refresh
/// and keep the existing cache* — never wipe local data the user can still read.
@immutable
class DataContractConfig {
  const DataContractConfig({
    this.minSupportedSchemaVersion = 1,
    this.maxSupportedSchemaVersion = 1,
  });

  final int minSupportedSchemaVersion;
  final int maxSupportedSchemaVersion;

  bool supports(int schemaVersion) =>
      schemaVersion >= minSupportedSchemaVersion &&
      schemaVersion <= maxSupportedSchemaVersion;
}

/// Static JSON manifest hosting (GitHub Pages / any object store / CDN).
///
/// When [baseUrl] is empty the app runs purely on bundled seed data and simply
/// reports "네트워크 동기화가 설정되지 않았습니다" rather than failing.
@immutable
class ManifestConfig {
  const ManifestConfig({
    required this.baseUrl,
    this.versionPath = 'version.json',
  });

  final String baseUrl;
  final String versionPath;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Uri get versionUri => Uri.parse(_join(baseUrl, versionPath));

  Uri fileUri(String relativePath) => Uri.parse(_join(baseUrl, relativePath));

  factory ManifestConfig.fromEnvironment() {
    return const ManifestConfig(
      baseUrl: String.fromEnvironment('WB_MANIFEST_BASE_URL'),
      versionPath: String.fromEnvironment(
        'WB_MANIFEST_VERSION_PATH',
        defaultValue: 'version.json',
      ),
    );
  }
}

/// Placeholder wiring for a future official API.
///
/// [transport] selects which adapter the sync engine builds. Neither REST nor
/// GraphQL is committed to in code; both sit behind `SportsDataSource`.
enum ApiTransport { none, rest, graphql }

@immutable
class FutureApiConfig {
  const FutureApiConfig({
    required this.transport,
    required this.baseUrl,
    this.organizationsPath = '/v1/organizations',
    this.teamsPath = '/v1/teams',
    this.competitionsPath = '/v1/competitions',
    this.gamesPath = '/v1/games',
    this.venuesPath = '/v1/venues',
    this.standingsPath = '/v1/standings',
    this.graphqlPath = '/graphql',
    this.pageSize = 100,
  });

  final ApiTransport transport;
  final String baseUrl;
  final String organizationsPath;
  final String teamsPath;
  final String competitionsPath;
  final String gamesPath;
  final String venuesPath;
  final String standingsPath;
  final String graphqlPath;
  final int pageSize;

  bool get isConfigured =>
      transport != ApiTransport.none && baseUrl.trim().isNotEmpty;

  Uri uri(String path) => Uri.parse(_join(baseUrl, path));

  factory FutureApiConfig.fromEnvironment() {
    const raw = String.fromEnvironment(
      'WB_API_TRANSPORT',
      defaultValue: 'none',
    );
    final transport = switch (raw.toLowerCase()) {
      'rest' => ApiTransport.rest,
      'graphql' => ApiTransport.graphql,
      _ => ApiTransport.none,
    };
    return FutureApiConfig(
      transport: transport,
      baseUrl: const String.fromEnvironment('WB_API_BASE_URL'),
      pageSize: const int.fromEnvironment(
        'WB_API_PAGE_SIZE',
        defaultValue: 100,
      ),
    );
  }
}

/// Google Form entry points for submissions and corrections.
///
/// Empty by default — we do not ship invented URLs. Any entry point whose URL
/// is blank is hidden from the UI (see `SubmissionLinks.availableEntries`).
@immutable
class FormsConfig {
  const FormsConfig({
    this.teamRegistration = '',
    this.scheduleChange = '',
    this.resultSubmission = '',
    this.dataCorrection = '',
    this.privacyRemoval = '',

    /// Query parameter used to pre-fill the "which record?" field, e.g.
    /// `entry.123456789`. Without it we still open the form, just unfilled.
    this.entityIdField = '',
    this.sourceUrlField = '',
  });

  final String teamRegistration;
  final String scheduleChange;
  final String resultSubmission;
  final String dataCorrection;
  final String privacyRemoval;
  final String entityIdField;
  final String sourceUrlField;

  factory FormsConfig.fromEnvironment() {
    return const FormsConfig(
      teamRegistration: String.fromEnvironment('WB_FORM_TEAM_REGISTRATION'),
      scheduleChange: String.fromEnvironment('WB_FORM_SCHEDULE_CHANGE'),
      resultSubmission: String.fromEnvironment('WB_FORM_RESULT_SUBMISSION'),
      dataCorrection: String.fromEnvironment('WB_FORM_DATA_CORRECTION'),
      privacyRemoval: String.fromEnvironment('WB_FORM_PRIVACY_REMOVAL'),
      entityIdField: String.fromEnvironment('WB_FORM_FIELD_ENTITY_ID'),
      sourceUrlField: String.fromEnvironment('WB_FORM_FIELD_SOURCE_URL'),
    );
  }
}

/// Verified public landing pages, used only as a fallback when a record has no
/// specific `sourceUrl`. Deep source URLs always win — we open the exact
/// detail page, never a site home page, when the record carries one.
@immutable
class OfficialLinksConfig {
  const OfficialLinksConfig({
    this.wbakHome = 'https://www.wbak.net/home',
    this.kbsaHome = 'https://kbsa.or.kr/',
    this.wbscWomensWorldCup = 'https://www.wbsc.org/en/events/2026-x-womens-baseball-world-cup-group-stage-rockford/home',
    this.wpblStats = 'https://stats.womensprobaseballleague.com/',
  });

  final String wbakHome;
  final String kbsaHome;
  final String wbscWomensWorldCup;
  final String wpblStats;
}

/// Feature flags. Anything experimental, licence-blocked, or commercial is
/// off by default and its routes are not even registered when off.
@immutable
class FeatureFlags {
  const FeatureFlags({
    this.sponsorCommerceEnabled = false,
    this.playerProfilesEnabled = false,
    this.pushMessagingEnabled = false,
    this.wbakAdapterEnabled = false,
    this.kbsaAdapterEnabled = false,
    this.wbscAdapterEnabled = false,
    this.wpblAdapterEnabled = false,
    this.debugTaskMetricsEnabled = false,
  });

  /// Sponsor / commerce. Hard off: no routes, no tabs, no "coming soon"
  /// placeholders, and no sponsor payload in the public JSON.
  final bool sponsorCommerceEnabled;

  /// Individual player profiles. Off until the data-use scope is settled;
  /// roster names still render where a team has published them.
  final bool playerProfilesEnabled;

  /// FCM receive path. Client structure only — no sending key ever ships.
  final bool pushMessagingEnabled;

  /// Source adapters that require an explicit permission grant before use.
  final bool wbakAdapterEnabled;
  final bool kbsaAdapterEnabled;

  /// Public endpoints that still need schema validation + failure isolation.
  final bool wbscAdapterEnabled;
  final bool wpblAdapterEnabled;

  /// Records tap counts for the five benchmark tasks in debug builds.
  final bool debugTaskMetricsEnabled;

  factory FeatureFlags.fromEnvironment() {
    return const FeatureFlags(
      sponsorCommerceEnabled: bool.fromEnvironment(
        'WB_FLAG_SPONSOR_COMMERCE',
        defaultValue: false,
      ),
      playerProfilesEnabled: bool.fromEnvironment(
        'WB_FLAG_PLAYER_PROFILES',
        defaultValue: false,
      ),
      pushMessagingEnabled: bool.fromEnvironment(
        'WB_FLAG_PUSH_MESSAGING',
        defaultValue: false,
      ),
      wbakAdapterEnabled: bool.fromEnvironment(
        'WB_FLAG_ADAPTER_WBAK',
        defaultValue: false,
      ),
      kbsaAdapterEnabled: bool.fromEnvironment(
        'WB_FLAG_ADAPTER_KBSA',
        defaultValue: false,
      ),
      wbscAdapterEnabled: bool.fromEnvironment(
        'WB_FLAG_ADAPTER_WBSC',
        defaultValue: false,
      ),
      wpblAdapterEnabled: bool.fromEnvironment(
        'WB_FLAG_ADAPTER_WPBL',
        defaultValue: false,
      ),
      debugTaskMetricsEnabled: bool.fromEnvironment(
        'WB_FLAG_TASK_METRICS',
        defaultValue: false,
      ),
    );
  }

  FeatureFlags copyWith({
    bool? sponsorCommerceEnabled,
    bool? playerProfilesEnabled,
    bool? pushMessagingEnabled,
    bool? wbakAdapterEnabled,
    bool? kbsaAdapterEnabled,
    bool? wbscAdapterEnabled,
    bool? wpblAdapterEnabled,
    bool? debugTaskMetricsEnabled,
  }) {
    return FeatureFlags(
      sponsorCommerceEnabled:
          sponsorCommerceEnabled ?? this.sponsorCommerceEnabled,
      playerProfilesEnabled:
          playerProfilesEnabled ?? this.playerProfilesEnabled,
      pushMessagingEnabled: pushMessagingEnabled ?? this.pushMessagingEnabled,
      wbakAdapterEnabled: wbakAdapterEnabled ?? this.wbakAdapterEnabled,
      kbsaAdapterEnabled: kbsaAdapterEnabled ?? this.kbsaAdapterEnabled,
      wbscAdapterEnabled: wbscAdapterEnabled ?? this.wbscAdapterEnabled,
      wpblAdapterEnabled: wpblAdapterEnabled ?? this.wpblAdapterEnabled,
      debugTaskMetricsEnabled:
          debugTaskMetricsEnabled ?? this.debugTaskMetricsEnabled,
    );
  }
}

@immutable
class SyncConfig {
  const SyncConfig({
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 20),
    this.maxAttempts = 3,
    this.initialBackoff = const Duration(milliseconds: 600),
    this.maxBackoff = const Duration(seconds: 20),

    /// Data older than this is surfaced with a "오래된 데이터" marker.
    this.staleAfter = const Duration(hours: 12),

    /// Minimum gap between automatic foreground refreshes.
    this.minAutoRefreshInterval = const Duration(minutes: 30),

    /// Consecutive failures before a source's circuit opens.
    this.circuitFailureThreshold = 4,
    this.circuitResetTimeout = const Duration(minutes: 5),
  });

  final Duration connectTimeout;
  final Duration receiveTimeout;
  final int maxAttempts;
  final Duration initialBackoff;
  final Duration maxBackoff;
  final Duration staleAfter;
  final Duration minAutoRefreshInterval;
  final int circuitFailureThreshold;
  final Duration circuitResetTimeout;
}

@immutable
class WebViewConfig {
  const WebViewConfig({
    this.allowedHosts = const <String>[
      'wbak.net',
      'kbsa.or.kr',
      'wbsc.org',
      'womensprobaseballleague.com',
      'stats.womensprobaseballleague.com',
      'youtube.com',
      'youtu.be',
      'docs.google.com',
      'forms.gle',
      'naver.com',
      'news.naver.com',
    ],
    this.loadTimeout = const Duration(seconds: 20),
  });

  /// Registrable-domain allowlist for the shared in-app browser. Anything else
  /// is handed to the external browser after telling the user where it goes.
  final List<String> allowedHosts;
  final Duration loadTimeout;
}

String _join(String base, String path) {
  final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final p = path.startsWith('/') ? path.substring(1) : path;
  return '$b/$p';
}
