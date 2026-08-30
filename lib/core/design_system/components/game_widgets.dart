import 'package:flutter/material.dart';

import '../../../data/models/domain.dart';
import '../../../data/models/weather.dart';
import '../../utils/kst.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';
import 'primitives.dart';
import 'provenance_widgets.dart';

/// Status badge with an icon and a word — never colour alone.
class WbGameStatusBadge extends StatelessWidget {
  const WbGameStatusBadge({
    super.key,
    required this.status,
    this.note,
    this.dense = false,
  });

  final GameStatus status;
  final String? note;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (WbBadgeTone tone, IconData icon) = switch (status) {
      GameStatus.live => (WbBadgeTone.live, Icons.sensors_rounded),
      GameStatus.finalized => (WbBadgeTone.muted, Icons.flag_outlined),
      GameStatus.forfeit => (WbBadgeTone.warning, Icons.gavel_rounded),
      GameStatus.postponed => (WbBadgeTone.warning, Icons.event_repeat_rounded),
      GameStatus.cancelled => (WbBadgeTone.danger, Icons.event_busy_rounded),
      GameStatus.delayed => (
        WbBadgeTone.warning,
        Icons.hourglass_bottom_rounded,
      ),
      GameStatus.scheduled => (
        WbBadgeTone.neutral,
        Icons.event_available_rounded,
      ),
      GameStatus.unknown => (WbBadgeTone.muted, Icons.help_outline_rounded),
    };

    final label = note == null || note!.isEmpty
        ? status.labelKo
        : '${status.labelKo} · $note';

    return WbBadge(label: label, tone: tone, icon: icon, dense: dense);
  }
}

/// Weather risk badge.
///
/// Beyond D+10 this renders "예보 전" rather than any condition — the honesty
/// rule is enforced by [WeatherRisk] and simply surfaced here.
class WbWeatherRiskBadge extends StatelessWidget {
  const WbWeatherRiskBadge({super.key, required this.risk, this.dense = true});

  final WeatherRisk risk;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (risk.level == WeatherRiskLevel.clear) return const SizedBox.shrink();

    // "Unknown" has two very different causes. Past the forecast horizon we
    // say so, because that is a fact about meteorology. Inside the horizon it
    // just means we hold no forecast yet — which is a gap in our data, not a
    // statement about the weather, so the card stays quiet and the detail
    // screen explains it.
    if (risk.level == WeatherRiskLevel.unknown &&
        risk.horizon != ForecastHorizon.beyondForecast) {
      return const SizedBox.shrink();
    }

    final tone = switch (risk.level) {
      WeatherRiskLevel.severe => WbBadgeTone.danger,
      WeatherRiskLevel.caution => WbBadgeTone.warning,
      WeatherRiskLevel.watch => WbBadgeTone.highlight,
      WeatherRiskLevel.unknown => WbBadgeTone.muted,
      WeatherRiskLevel.clear => WbBadgeTone.positive,
    };

    final icon = switch (risk.kind) {
      WeatherRiskKind.rain => Icons.water_drop_outlined,
      WeatherRiskKind.wind => Icons.air_rounded,
      WeatherRiskKind.heat => Icons.thermostat_rounded,
      WeatherRiskKind.cold => Icons.ac_unit_rounded,
      WeatherRiskKind.none => Icons.schedule_rounded,
    };

    // "예보 전" for anything past the forecast horizon; otherwise the risk
    // wording plus the specific figure that triggered it.
    final label = risk.level == WeatherRiskLevel.unknown
        ? ForecastHorizon.beyondForecast.labelKo
        : '${risk.kind.labelKo} ${risk.level.labelKo}';

    return WbBadge(label: label, tone: tone, icon: icon, dense: dense);
  }
}

/// The home hero card: the single most relevant fixture.
///
/// One tap from here reaches the detail screen. Everything a user needs to
/// decide whether to care — competition, status, KST time, both clubs, score
/// or kick-off, venue — is on the card itself.
class WbHeroGameCard extends StatelessWidget {
  const WbHeroGameCard({
    super.key,
    required this.card,
    required this.now,
    required this.onTap,
    this.weatherRisk,
    this.onToggleFollow,
    this.isFavoriteDriven = false,
  });

  final GameCard card;
  final DateTime now;
  final VoidCallback onTap;
  final WeatherRisk? weatherRisk;
  final VoidCallback? onToggleFollow;

  /// True when this fixture leads because the user follows one of the clubs.
  final bool isFavoriteDriven;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final game = card.game;
    final hasScore = game.hasScore && game.status.hasResult;

    return WbCard(
      emphasized: true,
      onTap: onTap,
      semanticLabel: _semanticLabel(),
      padding: const EdgeInsets.fromLTRB(
        WbSpace.lg,
        WbSpace.lg,
        WbSpace.lg,
        WbSpace.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (isFavoriteDriven) ...<Widget>[
                const WbBadge(
                  label: '내 팀',
                  tone: WbBadgeTone.positive,
                  icon: Icons.star_rounded,
                  dense: true,
                ),
                const SizedBox(width: WbSpace.xs),
              ],
              Flexible(
                child: Text(
                  card.competition?.displayName ?? '경기',
                  style: WbType.captionStrong.copyWith(color: c.brand),
                  maxLines: WbClamp.competitionName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              WbGameStatusBadge(
                status: game.status,
                note: game.statusNote,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: WbSpace.md),

          // Teams and the number. The score (or kick-off time) is the largest
          // element on the card by a clear margin.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: _TeamBlock(
                  team: card.awayTeam,
                  isFavorite: card.isAwayFavorite,
                  alignment: CrossAxisAlignment.start,
                  suffix: '원정',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: WbSpace.sm),
                child: hasScore
                    ? _ScoreBlock(
                        home: game.homeScore!,
                        away: game.awayScore!,
                        winnerIsHome: game.winnerTeamId == card.homeTeam.id,
                        isDraw: game.isDraw,
                      )
                    : _TimeBlock(startUtc: game.startTimeUtc, now: now),
              ),
              Expanded(
                child: _TeamBlock(
                  team: card.homeTeam,
                  isFavorite: card.isHomeFavorite,
                  alignment: CrossAxisAlignment.end,
                  suffix: '홈',
                ),
              ),
            ],
          ),

          const SizedBox(height: WbSpace.md),
          Row(
            children: <Widget>[
              Icon(Icons.place_outlined, size: 14, color: c.inkMuted),
              const SizedBox(width: WbSpace.xs),
              Expanded(
                child: Text(
                  card.venue?.name ?? '구장 미정',
                  style: WbType.caption.copyWith(color: c.inkMuted),
                  maxLines: WbClamp.venueName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (weatherRisk != null &&
                  weatherRisk!.level != WeatherRiskLevel.clear)
                WbWeatherRiskBadge(risk: weatherRisk!),
              if (onToggleFollow != null)
                WbTapTarget(
                  onTap: onToggleFollow,
                  semanticLabel: card.involvesFavorite ? '팔로우 해제' : '팀 팔로우',
                  child: Icon(
                    card.involvesFavorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 20,
                    color: card.involvesFavorite ? c.highlight : c.inkMuted,
                  ),
                ),
            ],
          ),
          const WbInsetDivider(vertical: WbSpace.sm),
          WbSourceLine(provenance: game.provenance, now: now),
        ],
      ),
    );
  }

  /// Screen readers get the score as "5 대 4", not "5 - 4".
  String _semanticLabel() {
    final game = card.game;
    final parts = <String>[
      card.competition?.displayName ?? '경기',
      game.status.labelKo,
      KoDate.dateTime(game.startTimeUtc),
      '원정 ${card.awayTeam.displayName}',
      '홈 ${card.homeTeam.displayName}',
    ];
    if (game.hasScore && game.status.hasResult) {
      parts.add(KoDate.scoreForScreenReader(game.homeScore!, game.awayScore!));
    }
    final venue = card.venue?.name;
    if (venue != null) parts.add(venue);
    // The demo marker is a badge on screen, so it has to be spoken too. It is
    // the app's core safety label; a screen-reader user who cannot tell demo
    // data from a real result is exactly the person it exists to protect.
    if (game.provenance.isDemo) parts.add('데모 데이터');
    return parts.join(', ');
  }
}

class _TeamBlock extends StatelessWidget {
  const _TeamBlock({
    required this.team,
    required this.isFavorite,
    required this.alignment,
    required this.suffix,
  });

  final Team team;
  final bool isFavorite;
  final CrossAxisAlignment alignment;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final isEnd = alignment == CrossAxisAlignment.end;
    return Column(
      crossAxisAlignment: alignment,
      children: <Widget>[
        WbTeamMark(name: team.displayName, colorHex: team.colorHex, size: 34),
        const SizedBox(height: WbSpace.sm),
        Text(
          team.displayName,
          textAlign: isEnd ? TextAlign.right : TextAlign.left,
          style: WbType.headline.copyWith(
            color: c.ink,
            fontWeight: isFavorite ? FontWeight.w800 : FontWeight.w600,
          ),
          maxLines: WbClamp.teamName,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: WbSpace.xxs),
        Text(suffix, style: WbType.micro.copyWith(color: c.inkMuted)),
      ],
    );
  }
}

class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock({
    required this.home,
    required this.away,
    required this.winnerIsHome,
    required this.isDraw,
  });

  final int home;
  final int away;
  final bool winnerIsHome;
  final bool isDraw;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    // The winning number is heavier; the losing one is muted. Weight and
    // colour together, so the distinction survives greyscale.
    Color colorFor(bool isWinner) =>
        isDraw ? c.ink : (isWinner ? c.ink : c.inkMuted);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          '$away',
          style: WbType.scoreHero.copyWith(color: colorFor(!winnerIsHome)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: WbSpace.sm),
          child: Text(':', style: WbType.scoreRow.copyWith(color: c.divider)),
        ),
        Text(
          '$home',
          style: WbType.scoreHero.copyWith(color: colorFor(winnerIsHome)),
        ),
      ],
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({required this.startUtc, required this.now});

  final DateTime startUtc;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final relative = KoDate.relativeDayLabel(startUtc, now);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          relative ?? KoDate.monthDay(startUtc),
          style: WbType.micro.copyWith(color: c.inkMuted),
        ),
        const SizedBox(height: WbSpace.xxs),
        Text(
          KoDate.time24(startUtc),
          style: WbType.timeLarge.copyWith(color: c.ink),
        ),
        const SizedBox(height: WbSpace.xxs),
        Text('KST', style: WbType.micro.copyWith(color: c.inkMuted)),
      ],
    );
  }
}

/// Compact list row used in the games list, team detail, and league pulse.
class WbGameRow extends StatelessWidget {
  const WbGameRow({
    super.key,
    required this.card,
    required this.now,
    required this.onTap,
    this.weatherRisk,
    this.showCompetition = true,
    this.showDate = false,
  });

  final GameCard card;
  final DateTime now;
  final VoidCallback onTap;
  final WeatherRisk? weatherRisk;
  final bool showCompetition;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final density = WbDensityScope.of(context);
    final game = card.game;
    final hasScore = game.hasScore && game.status.hasResult;
    final winnerId = game.winnerTeamId;

    return WbCard(
      onTap: onTap,
      padding: density.rowPadding,
      semanticLabel: _semanticLabel(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: density.listRowMinHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                SizedBox(
                  width: 52,
                  child: Text(
                    showDate
                        ? KoDate.monthDay(game.startTimeUtc)
                        : KoDate.time24(game.startTimeUtc),
                    style: WbType.tabularSmall.copyWith(color: c.inkMuted),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _RowTeamLine(
                        team: card.awayTeam,
                        score: hasScore ? game.awayScore : null,
                        isWinner: winnerId == card.awayTeam.id,
                        isFavorite: card.isAwayFavorite,
                        dimmed:
                            hasScore &&
                            winnerId != null &&
                            winnerId != card.awayTeam.id,
                      ),
                      SizedBox(height: density.rowGap),
                      _RowTeamLine(
                        team: card.homeTeam,
                        score: hasScore ? game.homeScore : null,
                        isWinner: winnerId == card.homeTeam.id,
                        isFavorite: card.isHomeFavorite,
                        dimmed:
                            hasScore &&
                            winnerId != null &&
                            winnerId != card.homeTeam.id,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: WbSpace.sm),
                // Capped and flexible: status text plus a demo marker can be
                // wide, and a 360dp screen has no room to spare.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 116),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      WbGameStatusBadge(
                        status: game.status,
                        note: game.statusNote,
                        dense: true,
                      ),
                      // Demo rows are labelled in the list too, not only on the
                      // detail screen — a screenshot of this list must never be
                      // mistakable for an official record.
                      if (game.provenance.isDemo) ...<Widget>[
                        const SizedBox(height: WbSpace.xs),
                        const WbBadge(
                          label: '데모',
                          tone: WbBadgeTone.muted,
                          icon: Icons.science_outlined,
                          dense: true,
                        ),
                      ],
                      if (weatherRisk != null &&
                          weatherRisk!.level != WeatherRiskLevel.clear &&
                          weatherRisk!.level !=
                              WeatherRiskLevel.unknown) ...<Widget>[
                        const SizedBox(height: WbSpace.xs),
                        WbWeatherRiskBadge(risk: weatherRisk!),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            // Shown in both densities. Compact tightens the gap above it; it
            // does not remove the venue, which is the line players scan for.
            if (showCompetition || card.venue != null) ...<Widget>[
              SizedBox(height: density.rowGap),
              Row(
                children: <Widget>[
                  const SizedBox(width: 52),
                  Expanded(
                    child: Text(
                      <String?>[
                        if (showCompetition) card.competition?.displayName,
                        card.venue?.name,
                      ].whereType<String>().join(' · '),
                      style: WbType.micro.copyWith(color: c.inkMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _semanticLabel() {
    final game = card.game;
    final parts = <String>[
      KoDate.dateTime(game.startTimeUtc),
      '${card.awayTeam.displayName} 대 ${card.homeTeam.displayName}',
      game.status.labelKo,
    ];
    if (game.hasScore && game.status.hasResult) {
      parts.add(KoDate.scoreForScreenReader(game.homeScore!, game.awayScore!));
    }
    if (game.provenance.isDemo) parts.add('데모 데이터');
    return parts.join(', ');
  }
}

class _RowTeamLine extends StatelessWidget {
  const _RowTeamLine({
    required this.team,
    required this.score,
    required this.isWinner,
    required this.isFavorite,
    required this.dimmed,
  });

  final Team team;
  final int? score;
  final bool isWinner;
  final bool isFavorite;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Row(
      children: <Widget>[
        if (isFavorite) ...<Widget>[
          Icon(Icons.star_rounded, size: 13, color: c.highlight),
          const SizedBox(width: WbSpace.xs),
        ],
        Expanded(
          child: Text(
            team.displayName,
            style: WbType.bodyStrong.copyWith(
              color: dimmed ? c.inkMuted : c.ink,
              fontWeight: isWinner ? FontWeight.w800 : FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (score != null) ...<Widget>[
          const SizedBox(width: WbSpace.sm),
          // Fixed width keeps the score column aligned across rows even when
          // one team scores double digits.
          SizedBox(
            width: 26,
            child: Text(
              '$score',
              textAlign: TextAlign.right,
              style: WbType.scoreRow.copyWith(
                fontSize: 17,
                color: dimmed ? c.inkMuted : c.ink,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Sticky day heading in the games list ("오늘 · 8월 30일 (토)").
class WbDayHeader extends StatelessWidget {
  const WbDayHeader({
    super.key,
    required this.dayUtc,
    required this.now,
    this.count,
  });

  final DateTime dayUtc;
  final DateTime now;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Container(
      color: c.canvas,
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        WbSpace.lg,
        WbSpace.screen,
        WbSpace.sm,
      ),
      child: Row(
        children: <Widget>[
          Text(
            KoDate.dayHeading(dayUtc, now),
            style: WbType.captionStrong.copyWith(color: c.ink),
          ),
          if (count != null) ...<Widget>[
            const SizedBox(width: WbSpace.sm),
            Text('$count경기', style: WbType.micro.copyWith(color: c.inkMuted)),
          ],
        ],
      ),
    );
  }
}

/// Skeleton shaped like [WbGameRow], so the list does not re-flow on load.
class WbGameRowSkeleton extends StatelessWidget {
  const WbGameRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return WbCard(
      padding: const EdgeInsets.symmetric(
        horizontal: WbSpace.lg,
        vertical: WbSpace.md,
      ),
      child: Row(
        children: const <Widget>[
          WbSkeleton(width: 40, height: 12),
          SizedBox(width: WbSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                WbSkeleton(width: 130, height: 15),
                SizedBox(height: WbSpace.sm),
                WbSkeleton(width: 104, height: 15),
              ],
            ),
          ),
          SizedBox(width: WbSpace.md),
          WbSkeleton(width: 44, height: 20),
        ],
      ),
    );
  }
}
