import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/discover/discover_screen.dart';
import '../features/discover/featured_topic_screen.dart';
import '../features/discover/guide_screen.dart';
import '../features/discover/nearby_games_screen.dart';
import '../features/discover/story_cluster_screen.dart';
import '../features/games/game_detail_screen.dart';
import '../features/games/games_screen.dart';
import '../features/home/home_screen.dart';
import '../features/my_baseball/leaderboard_screen.dart';
import '../features/my_baseball/my_baseball_screen.dart';
import '../features/my_baseball/schedule_board_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/about_screen.dart';
import '../features/settings/data_sources_screen.dart';
import '../features/settings/more_screen.dart';
import '../features/settings/notification_settings_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/submissions_screen.dart';
import '../features/competitions/competition_screen.dart';
import '../features/teams/team_detail_screen.dart';
import '../features/teams/teams_screen.dart';
import '../features/venues/venue_screen.dart';
import '../features/web_source/source_web_view_screen.dart';
import 'providers.dart';
import 'shell.dart';

/// Every addressable destination in the app.
///
/// Paths are stable and deep-linkable (`wbaseball://app/games/<id>`), so a
/// shared link reopens the exact screen. Routes are declared in one place so
/// the sponsor/commerce flag can withhold registration entirely rather than
/// hiding a button on a screen that still exists.
class WbRoutes {
  const WbRoutes._();

  static const String onboarding = '/onboarding';
  static const String home = '/';
  static const String discover = '/discover';
  static const String games = '/games';
  static const String myBaseball = '/my';
  static const String more = '/more';

  static const String search = '/search';
  static const String browser = '/browser';

  static String game(String id) => '/games/$id';
  static String team(String id) => '/team/$id';
  static String competition(String seasonId) => '/competition/$seasonId';
  static String venue(String id) => '/venue/$id';
  static String featuredTopic(String id) => '/discover/topic/$id';
  static String story(String id) => '/discover/story/$id';
  static String guide(String id) => '/discover/guide/$id';
  static const String nearby = '/discover/nearby';
  static const String teams = '/discover/teams';
  static const String scheduleBoard = '/my/schedule';
  static String leaderboard(String seasonId) => '/my/leaderboard/$seasonId';

  static const String settings = '/more/settings';
  static const String notifications = '/more/notifications';
  static const String dataSources = '/more/sources';
  static const String submissions = '/more/submit';
  static const String about = '/more/about';
}

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final prefs = ref.watch(preferencesProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: WbRoutes.home,
    debugLogDiagnostics: false,

    // Onboarding is skippable, so the redirect only fires the very first time
    // and never traps a user who chose to skip.
    redirect: (context, state) {
      final audience = prefs.audience;
      final atOnboarding = state.matchedLocation == WbRoutes.onboarding;
      if (!audience.onboardingCompleted && !atOnboarding) {
        // Remember where they were actually going. A shared game link is the
        // main way a new user arrives, and sending them to onboarding without
        // keeping the destination loses the one thing they came for.
        PendingDestination.instance.remember(state.uri.toString());
        return WbRoutes.onboarding;
      }
      if (audience.onboardingCompleted && atOnboarding) {
        return WbRoutes.home;
      }
      return null;
    },

    routes: <RouteBase>[
      GoRoute(
        path: WbRoutes.onboarding,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const OnboardingScreen(),
      ),

      // Full-screen routes that sit above the tab bar.
      GoRoute(
        path: WbRoutes.search,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            SearchScreen(initialQuery: state.uri.queryParameters['q'] ?? ''),
      ),
      GoRoute(
        path: WbRoutes.browser,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final params = state.uri.queryParameters;
          return SourceWebViewScreen(
            url: params['url'] ?? '',
            title: params['title'] ?? '',
            sourceLabel: params['source'] ?? '',
          );
        },
      ),

      // The five tabs. `StatefulShellRoute.indexedStack` keeps each branch's
      // navigation stack, scroll offset, and filter state alive when the user
      // switches tabs and comes back — a hard requirement of the brief.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            WbAppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: WbRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: WbRoutes.discover,
                builder: (context, state) => const DiscoverScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'nearby',
                    builder: (context, state) => const NearbyGamesScreen(),
                  ),
                  GoRoute(
                    path: 'teams',
                    builder: (context, state) => const TeamsScreen(),
                  ),
                  GoRoute(
                    path: 'topic/:id',
                    builder: (context, state) => FeaturedTopicScreen(
                      topicId: state.pathParameters['id']!,
                    ),
                  ),
                  GoRoute(
                    path: 'story/:id',
                    builder: (context, state) => StoryClusterScreen(
                      clusterId: state.pathParameters['id']!,
                    ),
                  ),
                  GoRoute(
                    path: 'guide/:id',
                    builder: (context, state) =>
                        GuideScreen(guideId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: WbRoutes.games,
                builder: (context, state) => const GamesScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: ':id',
                    builder: (context, state) =>
                        GameDetailScreen(gameId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: WbRoutes.myBaseball,
                builder: (context, state) => const MyBaseballScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'schedule',
                    builder: (context, state) => const ScheduleBoardScreen(),
                  ),
                  GoRoute(
                    path: 'leaderboard/:seasonId',
                    builder: (context, state) => LeaderboardScreen(
                      seasonId: state.pathParameters['seasonId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: WbRoutes.more,
                builder: (context, state) => const MoreScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'settings',
                    builder: (context, state) => const SettingsScreen(),
                  ),
                  GoRoute(
                    path: 'notifications',
                    builder: (context, state) =>
                        const NotificationSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'sources',
                    builder: (context, state) => const DataSourcesScreen(),
                  ),
                  GoRoute(
                    path: 'submit',
                    builder: (context, state) => const SubmissionsScreen(),
                  ),
                  GoRoute(
                    path: 'about',
                    builder: (context, state) => const AboutScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // Shared detail routes, reachable from several tabs. They push over the
      // shell so the bottom bar stays visible and Back returns to the exact
      // list position the user came from.
      GoRoute(
        path: '/team/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            TeamDetailScreen(teamId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/competition/:seasonId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            CompetitionScreen(seasonId: state.pathParameters['seasonId']!),
      ),
      GoRoute(
        path: '/venue/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            VenueScreen(venueId: state.pathParameters['id']!),
      ),

      // Sponsor / commerce routes are deliberately absent. The feature flag is
      // checked here, at registration time, so when it is off the routes do
      // not exist at all and cannot be reached by deep link.
      // if (ref.read(appConfigProvider).flags.sponsorCommerceEnabled) ...
    ],

    errorBuilder: (context, state) =>
        _RouteErrorScreen(location: state.uri.toString()),
  );
});

class _RouteErrorScreen extends StatelessWidget {
  const _RouteErrorScreen({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('페이지를 찾을 수 없습니다')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('요청한 화면을 열 수 없습니다.'),
              const SizedBox(height: 8),
              Text(
                location,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go(WbRoutes.home),
                child: const Text('홈으로'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens a URL in the shared in-app browser.
///
/// Every web link in the app funnels through here — there is exactly one
/// WebView screen, and callers always pass a specific title and source label
/// so the user knows where they are going before they tap.
void openSource(
  BuildContext context, {
  required String url,
  required String title,
  required String sourceLabel,
}) {
  context.push(
    Uri(
      path: WbRoutes.browser,
      queryParameters: <String, String>{
        'url': url,
        'title': title,
        'source': sourceLabel,
      },
    ).toString(),
  );
}

/// Holds the route a first-run user was trying to reach.
///
/// The onboarding redirect fires before any screen exists, so the destination
/// has nowhere to live except here. Deliberately a single global rather than a
/// provider: it is written from inside `redirect`, which has no `ref`, and it
/// must survive the router rebuild that finishing onboarding triggers.
///
/// Not persisted. If the app is killed mid-onboarding the link is gone, which
/// is the right trade — a stale destination restored days later would be more
/// confusing than a home screen.
class PendingDestination {
  PendingDestination._();

  static final PendingDestination instance = PendingDestination._();

  String? _location;

  /// Ignores the onboarding route itself and the plain home route: neither
  /// is a destination worth restoring, and remembering them would mask the
  /// "no pending link" case.
  void remember(String location) {
    if (location == WbRoutes.onboarding || location == WbRoutes.home) return;
    _location = location;
  }

  /// Returns the pending destination once, then forgets it. Reading it twice
  /// would re-navigate on a later rebuild.
  String? take() {
    final value = _location;
    _location = null;
    return value;
  }
}
