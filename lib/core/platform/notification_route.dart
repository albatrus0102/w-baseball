import 'package:flutter/foundation.dart';

import '../../app/router.dart';

/// Turns a notification payload into an in-app route.
///
/// Payloads are written as `<entityKind>:<entityId>` when an alert is
/// scheduled. Parsing lives here, apart from the plugin, so the mapping is
/// testable without a platform channel — the tap path is otherwise only
/// exercisable on a real device.
class NotificationRoute {
  const NotificationRoute._();

  /// Returns the route for [payload], or null when it names nothing openable.
  ///
  /// Deliberately strict: an unrecognised kind returns null rather than
  /// guessing a route, because sending someone to the wrong screen is worse
  /// than leaving them on the home screen they already have.
  static String? resolve(String? payload) {
    if (payload == null) return null;
    final separator = payload.indexOf(':');
    if (separator <= 0 || separator == payload.length - 1) return null;

    final kind = payload.substring(0, separator);
    final id = payload.substring(separator + 1);
    if (id.isEmpty) return null;

    return switch (kind) {
      'game' => WbRoutes.game(id),
      'team' => WbRoutes.team(id),
      'competition' => WbRoutes.competition(id),
      'storyCluster' => WbRoutes.story(id),
      'featuredTopic' => WbRoutes.featuredTopic(id),
      _ => null,
    };
  }
}

/// Holds a notification destination until the router can serve it.
///
/// Two arrival times have to work. A tap can land *before the first frame* —
/// the cold-start case, where the OS launched the app because of the
/// notification — and it can land while the app sits in the background, where
/// nothing rebuilds on its own.
///
/// It is a [ValueNotifier] for the second case. An earlier version exposed only
/// `take()` and was drained inside a widget's `build`; resuming from the
/// background does not necessarily rebuild anything, so the tap silently did
/// nothing and the user landed on the home screen. A listener fires either way.
class PendingNotificationRoute {
  PendingNotificationRoute._();

  static final PendingNotificationRoute instance = PendingNotificationRoute._();

  /// Non-null while a destination is waiting to be consumed.
  final ValueNotifier<String?> route = ValueNotifier<String?>(null);

  /// Called from the plugin callback, which may run before `runApp`.
  void offer(String? payload) {
    final resolved = NotificationRoute.resolve(payload);
    if (resolved != null) route.value = resolved;
  }

  /// Returns the destination once, then forgets it. Clearing matters: a
  /// destination read twice would re-navigate on the next rebuild.
  String? take() {
    final value = route.value;
    route.value = null;
    return value;
  }
}
