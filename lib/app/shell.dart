import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/design_system/theme.dart';
import '../core/platform/notification_route.dart';
import '../core/design_system/tokens.dart';
import 'providers.dart';
import 'router.dart';

/// The five-tab shell.
///
/// Tab order follows the two audiences the app serves rather than a generic
/// sports-app template:
///   홈       — today, ordered by the user's mode
///   발견     — the entry point for people new to women's baseball
///   경기     — schedule, results, competitions, standings
///   마이야구 — the entry point for players and team staff
///   더보기   — sources, settings, submissions, legal
///
/// `발견` and `마이야구` are the two required entry points from the brief; teams,
/// players and competitions are not removed but reached contextually and
/// through unified search, which is one tap from every tab.
class WbAppShell extends ConsumerWidget {
  const WbAppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<WbTabSpec> tabs = <WbTabSpec>[
    WbTabSpec(
      label: '홈',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      semantic: '홈 탭',
    ),
    WbTabSpec(
      label: '발견',
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore_rounded,
      semantic: '발견 탭. 화제 콘텐츠와 근처 경기',
    ),
    WbTabSpec(
      label: '경기',
      icon: Icons.sports_baseball_outlined,
      activeIcon: Icons.sports_baseball_rounded,
      semantic: '경기 탭. 일정·결과·순위',
    ),
    WbTabSpec(
      label: '마이야구',
      icon: Icons.calendar_month_outlined,
      activeIcon: Icons.calendar_month_rounded,
      semantic: '마이야구 탭. 내 팀 일정과 기록',
    ),
    WbTabSpec(
      label: '더보기',
      icon: Icons.more_horiz_rounded,
      activeIcon: Icons.more_horiz_rounded,
      semantic: '더보기 탭',
    ),
  ];

  void _onTap(BuildContext context, int index) {
    // Tapping the active tab pops that branch back to its root, which is the
    // Android convention and gives a reliable way out of a deep stack.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);

    // Keeps the notification schedule alive for the whole session. `listen`
    // rather than `watch`: the shell has no use for the count, and rebuilding
    // it every time the schedule changes would be pure waste.
    ref.listen(scheduledNotificationCountProvider, (_, _) {});

    return Scaffold(
      backgroundColor: c.canvas,
      body: _NotificationRouteListener(child: navigationShell),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.divider)),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) => _onTap(context, index),
            destinations: <Widget>[
              for (final tab in tabs)
                NavigationDestination(
                  icon: Icon(tab.icon),
                  selectedIcon: Icon(tab.activeIcon),
                  label: tab.label,
                  tooltip: tab.label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class WbTabSpec {
  const WbTabSpec({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.semantic,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String semantic;
}

/// The app bar used by every primary screen.
///
/// Carries three things consistently: where you are, the freshness of what you
/// are looking at, and one-tap search. Search living here is what makes
/// "unified search is 1 tap from any main screen" true by construction.
class WbPrimaryAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const WbPrimaryAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.showSearch = true,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showSearch;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(
    (subtitle == null ? kToolbarHeight : kToolbarHeight + 14) +
        (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final sync = ref.watch(syncControllerProvider);

    return AppBar(
      titleSpacing: WbSpace.screen,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title),
          if (subtitle != null)
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: c.inkMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      actions: <Widget>[
        // A quiet, non-blocking indicator. Syncing never gates the UI — the
        // cached content is already on screen.
        if (sync.isSyncing)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WbSpace.md),
            child: Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.inkMuted,
                ),
              ),
            ),
          ),
        ...actions,
        if (showSearch)
          IconButton(
            onPressed: () => context.push(WbRoutes.search),
            icon: const Icon(Icons.search_rounded),
            tooltip: '검색',
          ),
        const SizedBox(width: WbSpace.sm),
      ],
      bottom: bottom,
    );
  }
}

/// Navigates when a notification tap hands over a destination.
///
/// Listening rather than reading during `build` is the whole point: a tap that
/// arrives while the app is in the background rebuilds nothing, so a value read
/// in `build` is never seen. This also drains anything already waiting, which
/// covers the cold start where the payload arrived before this widget existed.
class _NotificationRouteListener extends ConsumerStatefulWidget {
  const _NotificationRouteListener({required this.child});

  final Widget child;

  @override
  ConsumerState<_NotificationRouteListener> createState() =>
      _NotificationRouteListenerState();
}

class _NotificationRouteListenerState
    extends ConsumerState<_NotificationRouteListener> {
  @override
  void initState() {
    super.initState();
    PendingNotificationRoute.instance.route.addListener(_go);
    // Cold start: the destination may already be waiting.
    WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }

  @override
  void dispose() {
    PendingNotificationRoute.instance.route.removeListener(_go);
    super.dispose();
  }

  void _go() {
    final destination = PendingNotificationRoute.instance.take();
    if (destination == null || !mounted) return;
    // Deferred: the notifier can fire mid-frame, and pushing a route during a
    // build is not allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(routerProvider).push(destination);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
