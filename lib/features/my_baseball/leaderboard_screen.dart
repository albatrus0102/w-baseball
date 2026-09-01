import 'package:flutter/material.dart';

import '../competitions/leaderboard_boards.dart';

/// Per-category individual leaderboards.
///
/// Rules this screen enforces visibly (via `WbLeaderboardBoards` /
/// `WbLeaderboardCard`, shared with the games tab's 순위 → 개인 순위 view):
///  * every stat shows its definition and formula on demand,
///  * qualified and unqualified players are separated, with the threshold and
///    how it was derived stated,
///  * ties share a rank and are marked,
///  * data coverage is shown, so a partial tally is never read as official,
///  * records from different competitions are never summed — one season only,
///  * there is no composite rating and no AI grade.
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key, required this.seasonId});

  final String seasonId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('개인 기록 순위')),
      body: WbLeaderboardBoards(seasonId: seasonId),
    );
  }
}
