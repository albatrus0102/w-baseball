import '../../data/models/audience.dart';
import '../../data/models/domain.dart';
import '../../data/repositories/follow_repository.dart';
import '../../data/repositories/game_repository.dart';
import '../utils/kst.dart';
import 'notification_service.dart';

/// Connects the pure [NotificationPlanner] to real data.
///
/// The planner decides *what* should be scheduled and the service decides *how*
/// to schedule it; neither knows where the fixture list comes from. This class
/// is the only place that answers "which games does this user care about", so
/// the rule lives once instead of at every call site that might want to
/// reschedule.
///
/// Rescheduling is always a full reconcile, never an incremental edit. The
/// service diffs the desired schedule against what is already registered and
/// cancels what no longer belongs. That makes calling this too often harmless
/// and calling it too rarely the only real failure mode — which is the safer
/// direction for something the user notices only when it does not happen.
class NotificationScheduler {
  const NotificationScheduler({
    required this.games,
    required this.follows,
    required this.notifications,
    this.planner = const NotificationPlanner(),
    this.horizon = const Duration(days: 30),
  });

  final GameRepository games;
  final FollowRepository follows;
  final NotificationService notifications;
  final NotificationPlanner planner;

  /// How far ahead to schedule. Long enough for the week-ahead alert, short
  /// enough to stay well inside the platform's registered-alarm limits.
  final Duration horizon;

  /// Recomputes the whole schedule and hands it to the platform.
  ///
  /// Returns the number of alerts the plan contains, which is what the caller
  /// shows the user ("알림 3건 예약됨"). Returns 0 when the user has every
  /// category off — that is a valid outcome, not a failure.
  Future<int> reschedule(NotificationPreference preference) async {
    final now = DateTime.now().toUtc();

    final followedTeams = await follows.watchFollowedIds(FollowKind.team).first;
    final savedGames = await follows.watchSavedIds(SavedItemKind.game).first;

    // Two sources of interest, unioned: teams the user follows, and individual
    // games they saved. Someone can want an alert for one fixture without
    // adopting the whole team's schedule.
    if (followedTeams.isEmpty && savedGames.isEmpty) {
      // Nothing is followed or saved. An empty `teamIds` means "every team" to
      // the query, so skipping is not an optimisation here — it is the
      // difference between no alerts and an alert for every fixture in the
      // league.
      await notifications.reconcile(const <PlannedNotification>[]);
      return 0;
    }

    // Quantised so an identical call a second later produces an identical
    // query rather than a new one.
    final from = Kst.hourBucket(now);
    final to = now.add(horizon);

    final cards = <String, GameCard>{};

    if (followedTeams.isNotEmpty) {
      final upcoming = await games
          .watchGames(
            GameQuery(
              fromUtc: from,
              toUtc: to,
              teamIds: followedTeams.toList()..sort(),
              ascending: true,
            ),
          )
          .first;
      for (final card in upcoming) {
        cards[card.game.id] = card;
      }
    }

    if (savedGames.isNotEmpty) {
      // Saved games are individual fixtures, which the query cannot express
      // directly, so the window is fetched once and filtered here. The window
      // is bounded by [horizon], so this stays small.
      final window = await games
          .watchGames(GameQuery(fromUtc: from, toUtc: to, ascending: true))
          .first;
      for (final card in window) {
        if (savedGames.contains(card.game.id)) {
          cards[card.game.id] = card;
        }
      }
    }

    final planned = planner.plan(
      games: cards.values.toList(),
      preference: preference,
      nowUtc: now,
    );

    await notifications.reconcile(planned);
    return planned.length;
  }
}
