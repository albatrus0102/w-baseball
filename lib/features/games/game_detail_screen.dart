import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/analytics/analytics.dart';
import '../../core/design_system/components/game_widgets.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/components/provenance_widgets.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../core/platform/platform_services.dart';
import '../../core/utils/kst.dart';
import '../../data/models/audience.dart';
import '../../data/models/domain.dart';
import '../../data/models/reminder_status.dart';
import '../../data/models/weather.dart';
import 'widgets/attendance_section.dart';
import 'widgets/box_score.dart';

/// Full game detail.
///
/// Order follows what a reader needs, most-decisive first: competition and
/// status, the score, then progressively deeper records, then the "watch it in
/// person" block, and provenance at the end.
///
/// When there is no box score we do *not* draw an empty table — we say so and
/// link to the exact official page for this fixture.
class GameDetailScreen extends ConsumerWidget {
  const GameDetailScreen({super.key, required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(gameDetailProvider(gameId));
    final now = ref.watch(clockProvider)();

    return Scaffold(
      body: detail.when(
        loading: () => const _DetailSkeleton(),
        error: (error, _) => Scaffold(
          appBar: AppBar(title: const Text('경기')),
          body: WbEmptyState(
            icon: Icons.error_outline_rounded,
            tone: WbBadgeTone.danger,
            title: '경기 정보를 불러오지 못했습니다',
            primaryLabel: '뒤로',
            onPrimary: () => context.pop(),
          ),
        ),
        data: (value) {
          if (value == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('경기')),
              body: WbEmptyState(
                icon: Icons.search_off_rounded,
                title: '경기를 찾을 수 없습니다',
                message: '삭제되었거나 아직 동기화되지 않은 경기입니다.',
                primaryLabel: '뒤로',
                onPrimary: () => context.pop(),
              ),
            );
          }
          return _GameDetailBody(detail: value, now: now);
        },
      ),
    );
  }
}

class _GameDetailBody extends ConsumerWidget {
  const _GameDetailBody({required this.detail, required this.now});

  final GameDetail detail;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final card = detail.card;
    final game = detail.game;
    final showBeginner = ref.watch(showBeginnerExplanationsProvider);
    final saved = ref.watch(savedGameIdsProvider).value ?? const <String>{};
    final isSaved = saved.contains(game.id);

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          title: Text(card.competition?.displayName ?? '경기'),
          actions: <Widget>[
            IconButton(
              tooltip: isSaved ? '저장 해제' : '저장',
              onPressed: () async {
                final nowSaved = await ref
                    .read(followRepositoryProvider)
                    .toggleSaved(SavedItemKind.game, game.id);
                await ref.read(platformServicesProvider).haptics.selection();
                if (nowSaved) {
                  await ref
                      .read(analyticsProvider)
                      .log(AnalyticsEvent.gameSaved);
                }
              },
              icon: Icon(
                isSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
              ),
            ),
            IconButton(
              tooltip: '공유',
              onPressed: () => _share(context, ref),
              icon: const Icon(Icons.ios_share_rounded),
            ),
          ],
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(WbSpace.screen),
            child: WbHeroGameCard(
              card: card,
              now: now,
              // No whole-card destination here — we are already on this
              // game's own page. The two team blocks are the live targets;
              // see the design note on `WbHeroGameCard.onTeamTap`.
              onTeamTap: (id) => context.push(WbRoutes.team(id)),
            ),
          ),
        ),

        // Quick actions sit high and are two steps at most: calendar, map,
        // official record.
        SliverToBoxAdapter(child: _QuickActions(detail: detail)),

        if (game.status.isDisrupted)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
              child: WbCard(
                accentColor: c.highlight,
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: c.highlight,
                    ),
                    const SizedBox(width: WbSpace.md),
                    Expanded(
                      child: Text(
                        // Disrupted fixtures are never collapsed into a result.
                        '${game.status.labelKo} 경기입니다.'
                        '${game.statusNote == null ? '' : ' ${game.statusNote}'}\n'
                        '변경된 일정은 공식 발표를 확인해 주세요.',
                        style: WbType.caption.copyWith(
                          color: c.ink,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Box score, or an honest pointer to the official record.
        SliverToBoxAdapter(
          child: detail.hasBoxScore
              ? BoxScoreSection(detail: detail, showBeginner: showBeginner)
              : _NoBoxScoreSection(detail: detail),
        ),

        SliverToBoxAdapter(
          child: AttendanceSection(detail: detail, now: now),
        ),

        if (detail.articles.isNotEmpty || detail.videos.isNotEmpty)
          SliverToBoxAdapter(
            child: _RelatedSection(detail: detail, now: now),
          ),

        SliverToBoxAdapter(
          child: _ProvenanceSection(detail: detail, now: now),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: WbSpace.xxl)),
      ],
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final card = detail.card;
    final game = detail.game;
    // Prefer the official page; fall back to a deep link into the app.
    final url = game.officialDetailUrl ?? 'wbaseball://app/games/${game.id}';
    final text =
        '${card.awayTeam.displayName} vs ${card.homeTeam.displayName}\n'
        '${KoDate.dateTime(game.startTimeUtc)}'
        '${card.venue == null ? '' : ' · ${card.venue!.name}'}\n$url';
    await ref
        .read(platformServicesProvider)
        .sharing
        .shareText(text: text, subject: '여자야구 경기');
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.detail});

  final GameDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(platformServicesProvider);
    final game = detail.game;
    final venue = detail.card.venue;

    // The reminder's state is read *here* rather than inside its own widget
    // because its label changes length with that state ('알림' / '알림 켜짐'),
    // and `_QuickActionBar` measures the labels to decide the layout. A
    // subscription living one level down would swap the label without the
    // bar remeasuring, leaving the grid sized for the label it no longer
    // shows.
    final saved = ref.watch(savedGameIdsProvider).value ?? const <String>{};
    final isOn = saved.contains(game.id);
    final categories = ref.watch(notificationPreferenceProvider).value;
    // A finished or called-off fixture has nothing left to announce.
    final canRemind =
        game.startTimeUtc.isAfter(ref.watch(clockProvider)()) &&
        game.status != GameStatus.cancelled &&
        game.status != GameStatus.postponed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        0,
        WbSpace.screen,
        WbSpace.md,
      ),
      child: _QuickActionBar(
        actions: <_QuickAction>[
          _QuickAction(
            label: '캘린더',
            icon: Icons.event_available_outlined,
            onPressed: services.calendar.isSupported
                ? () => _addToCalendar(context, ref)
                : null,
          ),
          _QuickAction(
            label: isOn ? '알림 켜짐' : '알림',
            icon: isOn
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            onPressed: canRemind
                ? () => _toggleReminder(context, ref, isOn, categories)
                : null,
          ),
          _QuickAction(
            label: '길찾기',
            icon: Icons.directions_outlined,
            onPressed: (venue?.isRoutable ?? false)
                ? () => _openDirections(context, ref)
                : null,
          ),
          if (game.officialDetailUrl != null)
            _QuickAction(
              label: '공식 기록',
              icon: Icons.description_outlined,
              emphasized: true,
              onPressed: () {
                ref
                    .read(analyticsProvider)
                    .log(
                      AnalyticsEvent.sourceOpened,
                      properties: <String, Object?>{'screen': 'game_detail'},
                    );
                openSource(
                  context,
                  url: game.officialDetailUrl!,
                  title:
                      '${detail.card.awayTeam.displayName} vs '
                      '${detail.card.homeTeam.displayName}',
                  sourceLabel: game.provenance.sourceName,
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _addToCalendar(BuildContext context, WidgetRef ref) async {
    final card = detail.card;
    final game = detail.game;
    final services = ref.read(platformServicesProvider);

    final ok = await services.calendar.addEvent(
      CalendarEvent(
        title: '${card.awayTeam.displayName} vs ${card.homeTeam.displayName}',
        startUtc: game.startTimeUtc,
        // Amateur baseball games have no fixed length; two hours is a
        // reasonable placeholder the user can adjust in their calendar app.
        endUtc: game.startTimeUtc.add(const Duration(hours: 2)),
        location: card.venue?.name,
        description: <String?>[
          card.competition?.displayName,
          game.officialDetailUrl,
        ].whereType<String>().join('\n'),
      ),
    );

    if (ok) {
      await ref.read(analyticsProvider).log(AnalyticsEvent.calendarAdded);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사용할 수 있는 캘린더 앱을 찾지 못했습니다.')),
      );
    }
  }

  Future<void> _openDirections(BuildContext context, WidgetRef ref) async {
    final venue = detail.card.venue;
    if (venue == null) return;
    final services = ref.read(platformServicesProvider);
    final ok = await services.maps.openDirections(
      latitude: venue.latitude,
      longitude: venue.longitude,
      address: venue.address,
      label: venue.name,
    );
    if (ok) {
      await ref.read(analyticsProvider).log(AnalyticsEvent.directionsOpened);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('지도 앱을 열지 못했습니다.')));
    }
  }

  Future<void> _toggleReminder(
    BuildContext context,
    WidgetRef ref,
    bool isOn,
    NotificationPreference? preference,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final follows = ref.read(followRepositoryProvider);
    final prefs = ref.read(preferencesProvider);

    if (isOn) {
      await follows.toggleSaved(SavedItemKind.game, detail.game.id);
      await ref.read(platformServicesProvider).haptics.selection();
      messenger?.showSnackBar(const SnackBar(content: Text('이 경기 알림을 껐습니다.')));
      return;
    }

    // Ask for permission at the moment of intent, not before.
    var current = preference ?? prefs.notifications;
    if (!current.permissionRequested) {
      await ref.read(notificationServiceProvider).requestPermission();
      current = current.copyWith(permissionRequested: true);
      await prefs.saveNotifications(current);
    }

    await follows.toggleSaved(SavedItemKind.game, detail.game.id);
    await ref.read(platformServicesProvider).haptics.selection();
    await ref.read(analyticsProvider).log(AnalyticsEvent.gameSaved);

    if (!context.mounted) return;

    // Ask the shared judgement why an alert would not arrive, rather than
    // guessing from the categories alone. Blaming the wrong cause sends the
    // user to a screen that cannot fix their problem.
    final status = await ref.read(reminderStatusProvider.future);
    if (!context.mounted) return;

    final blocker = status.blocker;
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          blocker.blocks
              ? '경기를 저장했습니다. ${blocker.messageKo}'
              : blocker.messageKo,
        ),
        action: switch (blocker) {
          ReminderBlocker.permissionDenied => SnackBarAction(
            label: blocker.actionLabelKo!,
            onPressed: () => ref
                .read(platformServicesProvider)
                .systemSettings
                .openNotificationSettings(),
          ),
          ReminderBlocker.categoriesOff => SnackBarAction(
            label: blocker.actionLabelKo!,
            onPressed: () => context.push(WbRoutes.notifications),
          ),
          _ => null,
        },
      ),
    );
  }
}

/// One button in [_QuickActionBar]: the label the bar measures, plus what to
/// draw and run.
class _QuickAction {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
  });

  final String label;
  final IconData icon;

  /// Null renders the button disabled — it still occupies a column, because a
  /// 캘린더 button that vanishes on a device without a calendar app would
  /// reflow the whole bar rather than explain itself.
  final VoidCallback? onPressed;

  /// Draws as a `FilledButton.icon` rather than an `OutlinedButton.icon`, and
  /// is measured with that button's wider padding.
  final bool emphasized;
}

/// The action buttons under the fixture card, in as many equal columns as
/// their labels actually fit in — four, two, or one.
///
/// Laying these out as a `Row` of `Expanded` buttons, which is what this
/// replaced, hands every button an equal 1/N of the width no matter what its
/// label needs. Like the `Expanded(Text)` shape that
/// `scripts/validate/find_squeezed_rows.py` enumerates (this row was entry
/// one on that list), it never overflows — `Expanded` absorbs the squeeze —
/// so no overflow probe can see it. What it does instead is break each label
/// into one Hangul syllable per line. Measured on a 360dp screen, that was
/// not an accessibility-only defect: with four buttons, '캘린더' already drew
/// as 캘/린/더 at **1.0x**, and '공식 기록' got a label column 0.0dp wide.
///
/// The column count is measured per build with [TextPainter] rather than
/// switched on a text-scale threshold, following [WbNoticeWithAction] in
/// `notice_widgets.dart` — the same reason applies here: the deciding
/// variable is how wide these particular labels are, and '알림' vs '알림 켜짐'
/// changes that at a fixed scale. Labels are never shrunk, ellipsised, or
/// dropped for their icons: a larger text scale is an accessibility setting
/// someone turned on deliberately, and answering it by hiding the words
/// defeats it. The bar gets taller instead, which a scrolling screen can
/// afford.
class _QuickActionBar extends StatelessWidget {
  const _QuickActionBar({required this.actions});

  final List<_QuickAction> actions;

  /// Column counts tried, widest first; counts above [actions] length are
  /// skipped, so a three-button bar starts at 3. Three is kept for the
  /// four-button bar too, even though it leaves a single button alone on the
  /// second run: dropping it would also forbid the three-button bar its own
  /// natural single row on a screen wide enough for one.
  static const List<int> _steps = <int>[4, 3, 2, 1];

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final needed = _widestButton(context);
        final columns = _columnsThatFit(constraints.maxWidth, needed);
        final width =
            (constraints.maxWidth - (columns - 1) * WbSpace.sm) / columns;

        return Wrap(
          spacing: WbSpace.sm,
          runSpacing: WbSpace.sm,
          children: <Widget>[
            for (final action in actions)
              SizedBox(width: width, child: _button(action)),
          ],
        );
      },
    );
  }

  Widget _button(_QuickAction action) {
    // Keyed the way `game_log_widgets.dart` keys its fields: '길찾기' and
    // '공식 기록' each appear a second time further down this screen (the
    // 관람 준비 venue row, the 상세 기록 card), so a test that reaches for a
    // quick action by its text alone finds two widgets and cannot say which
    // one it measured.
    final key = ValueKey<String>('quickAction_${action.label}');
    final icon = Icon(action.icon, size: 18);
    // Deliberately not `maxLines: 1`: if [_widestButton] ever measures
    // short, a wrapped label is visible on screen and fails the
    // line-count assertion in `game_detail_quick_actions_test.dart`,
    // whereas a clipped or ellipsised one would hide the same mistake.
    final label = Text(action.label);
    return action.emphasized
        ? FilledButton.icon(
            key: key,
            onPressed: action.onPressed,
            icon: icon,
            label: label,
          )
        : OutlinedButton.icon(
            key: key,
            onPressed: action.onPressed,
            icon: icon,
            label: label,
          );
  }

  /// The largest count in [_steps] whose columns are each at least [needed]
  /// wide. Falls through to 1 — a single full-width column is the last shape
  /// that can still show a label whole.
  int _columnsThatFit(double maxWidth, double needed) {
    for (final columns in _steps) {
      if (columns > actions.length) continue;
      if ((maxWidth - (columns - 1) * WbSpace.sm) / columns >= needed) {
        return columns;
      }
    }
    return 1;
  }

  /// Width the widest button needs to keep its label on one line: the label
  /// text measured at its real style and the live text scale, plus
  /// [_chromeWidth].
  ///
  /// Deliberately generous, for the same reason [WbNoticeWithAction] is: the
  /// only failure this measurement must not produce is claiming a label fits
  /// when it does not. Folding to fewer columns a little early costs vertical
  /// space on a screen that scrolls; folding too late puts a syllable on its
  /// own line, which is the defect.
  double _widestButton(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final action in actions) {
      // Both `outlinedButtonTheme` and `filledButtonTheme` in `theme.dart`
      // set `textStyle: WbType.bodyStrong` — the style Material renders these
      // labels in.
      final painter = TextPainter(
        text: TextSpan(text: action.label, style: WbType.bodyStrong),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      final width = painter.width + _chromeWidth(textScaler, action.emphasized);
      if (width > widest) widest = width;
    }
    return widest;
  }

  /// Width a button adds beyond its own label: its horizontal padding from
  /// `theme.dart` (`WbSpace.lg` a side for outlined, `WbSpace.xl` for filled),
  /// plus the 18dp icon and the gap Material puts beside it.
  ///
  /// Material also grows a button's padding as the text scale rises, inside
  /// its own private implementation. That is not modelled exactly here —
  /// instead the whole allowance scales with [textScaler], a generous
  /// stand-in that cannot fall behind Material's growth. Same approach, and
  /// same reasoning, as `_actionChromeWidth` in `notice_widgets.dart`.
  double _chromeWidth(TextScaler textScaler, bool emphasized) {
    final padding = (emphasized ? WbSpace.xl : WbSpace.lg) * 2;
    const iconAllowance = 18 + WbSpace.sm;
    final growth = textScaler.scale(1).clamp(1.0, 2.0);
    return (padding + iconAllowance) * growth;
  }
}

/// Shown instead of an empty table.
class _NoBoxScoreSection extends StatelessWidget {
  const _NoBoxScoreSection({required this.detail});

  final GameDetail detail;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final url = detail.game.officialDetailUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
      child: WbCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.table_chart_outlined, size: 18, color: c.inkMuted),
                const SizedBox(width: WbSpace.sm),
                Text('상세 기록', style: WbType.section.copyWith(color: c.ink)),
              ],
            ),
            const SizedBox(height: WbSpace.sm),
            Text(
              url == null
                  ? '이 경기의 상세 기록은 아직 수집되지 않았습니다.'
                  : '이 경기의 상세 기록은 공식 사이트에서 확인할 수 있습니다.',
              style: WbType.body.copyWith(color: c.inkMuted, height: 1.55),
            ),
            if (url != null) ...<Widget>[
              const SizedBox(height: WbSpace.md),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => openSource(
                    context,
                    url: url,
                    title: '공식 기록',
                    sourceLabel: detail.game.provenance.sourceName,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('공식 기록 페이지 열기'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RelatedSection extends StatelessWidget {
  const _RelatedSection({required this.detail, required this.now});

  final GameDetail detail;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const WbSectionHeader(title: '관련 소식'),
        for (final article in detail.articles)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WbSpace.screen,
              0,
              WbSpace.screen,
              WbSpace.sm,
            ),
            child: WbCard(
              onTap: () => openSource(
                context,
                url: article.url,
                title: article.title,
                sourceLabel: article.outlet ?? '뉴스',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    article.title,
                    style: WbType.bodyStrong.copyWith(color: c.ink),
                    maxLines: WbClamp.articleTitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: WbSpace.sm),
                  WbSourceLine(provenance: article.provenance, now: now),
                ],
              ),
            ),
          ),
        for (final video in detail.videos)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WbSpace.screen,
              0,
              WbSpace.screen,
              WbSpace.sm,
            ),
            child: WbCard(
              onTap: () => openSource(
                context,
                url: video.url,
                title: video.title,
                sourceLabel: video.channelName ?? '영상',
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.play_circle_outline_rounded,
                    size: 20,
                    color: c.action,
                  ),
                  const SizedBox(width: WbSpace.md),
                  Expanded(
                    child: Text(
                      video.title,
                      style: WbType.body.copyWith(color: c.ink),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ProvenanceSection extends ConsumerWidget {
  const _ProvenanceSection({required this.detail, required this.now});

  final GameDetail detail;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final config = ref.watch(appConfigProvider);
    final game = detail.game;
    final correctionUrl = config.forms.dataCorrection;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        WbSpace.lg,
        WbSpace.screen,
        0,
      ),
      child: WbCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('데이터 출처', style: WbType.captionStrong.copyWith(color: c.ink)),
            const SizedBox(height: WbSpace.sm),
            WbSourceLine(provenance: game.provenance, now: now),
            const SizedBox(height: WbSpace.xs),
            Text(
              '마지막 확인 ${KoDate.dateTime(game.provenance.lastConfirmedAt)}',
              style: WbType.micro.copyWith(color: c.inkMuted),
            ),
            if (game.provenance.isDemo) ...<Widget>[
              const SizedBox(height: WbSpace.md),
              Container(
                padding: const EdgeInsets.all(WbSpace.md),
                decoration: BoxDecoration(
                  color: c.highlightSoft,
                  borderRadius: WbRadius.chipAll,
                ),
                child: Text(
                  // Demo data is labelled everywhere it appears, never dressed
                  // up as an official record.
                  '이 경기는 앱 동작 확인을 위한 데모 데이터입니다. '
                  '실제 경기 기록이 아닙니다.',
                  style: WbType.caption.copyWith(color: c.ink, height: 1.5),
                ),
              ),
            ],
            const WbInsetDivider(),
            if (correctionUrl.isEmpty)
              Text(
                '정보 정정 제보 창구는 준비 중입니다.',
                style: WbType.caption.copyWith(color: c.inkMuted),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // The correction form opens with the entity id and source
                    // URL pre-filled, so the reporter does not have to copy
                    // anything by hand.
                    final uri = Uri.parse(correctionUrl).replace(
                      queryParameters: <String, String>{
                        ...Uri.parse(correctionUrl).queryParameters,
                        if (config.forms.entityIdField.isNotEmpty)
                          config.forms.entityIdField: 'game:${game.id}',
                        if (config.forms.sourceUrlField.isNotEmpty)
                          config.forms.sourceUrlField:
                              game.provenance.sourceUrl,
                      },
                    );
                    ref
                        .read(analyticsProvider)
                        .log(AnalyticsEvent.correctionSubmitted);
                    openSource(
                      context,
                      url: uri.toString(),
                      title: '잘못된 정보 제보',
                      sourceLabel: 'Google Forms',
                    );
                  },
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: const Text('잘못된 정보 제보하기'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('경기')),
      body: ListView(
        padding: const EdgeInsets.all(WbSpace.screen),
        children: const <Widget>[
          WbSkeleton(height: 170, borderRadius: WbRadius.heroAll),
          SizedBox(height: WbSpace.lg),
          WbSkeleton(height: 48, borderRadius: WbRadius.chipAll),
          SizedBox(height: WbSpace.lg),
          WbSkeleton(height: 140, borderRadius: WbRadius.cardAll),
        ],
      ),
    );
  }
}

/// Weather block reused by the attendance section.
class GameWeatherPanel extends ConsumerWidget {
  const GameWeatherPanel({
    super.key,
    required this.gameId,
    required this.startTimeUtc,
  });

  final String gameId;
  final DateTime startTimeUtc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final now = ref.watch(clockProvider)();
    final horizon = ForecastHorizon.between(now, startTimeUtc);
    final forecast = ref.watch(gameWeatherProvider(gameId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('날씨', style: WbType.captionStrong.copyWith(color: c.ink)),
            const SizedBox(width: WbSpace.sm),
            WbBadge(
              label: horizon.labelKo,
              tone: horizon == ForecastHorizon.beyondForecast
                  ? WbBadgeTone.muted
                  : WbBadgeTone.neutral,
              dense: true,
            ),
          ],
        ),
        const SizedBox(height: WbSpace.sm),
        // Beyond D+10 we state the limit rather than showing a fabricated
        // daily forecast.
        if (horizon == ForecastHorizon.beyondForecast)
          Text(
            horizon.explanationKo,
            style: WbType.caption.copyWith(color: c.inkMuted, height: 1.55),
          )
        else
          forecast.when(
            loading: () => const WbSkeleton(width: 200, height: 16),
            error: (_, _) => Text(
              '날씨 정보를 불러오지 못했습니다.',
              style: WbType.caption.copyWith(color: c.inkMuted),
            ),
            data: (value) {
              if (value == null) {
                return Text(
                  '이 경기의 예보가 아직 저장되지 않았습니다.',
                  style: WbType.caption.copyWith(color: c.inkMuted),
                );
              }
              final risk = WeatherRisk.evaluate(value);
              final range = value.displayTemperatureRange;
              final exact = value.displayTemperature;
              final pop = value.displayPrecipitationProbability;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Wrap, not Row: the risk badge, temperature and
                  // precipitation chance are three independent facts with no
                  // slack to give up, so at large text scale — or a long risk
                  // label — a piece that doesn't fit the line drops to a line
                  // of its own instead of pushing past the screen edge. Same
                  // technique as `WbSourceLine`.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: WbSpace.sm,
                    runSpacing: WbSpace.xs,
                    children: <Widget>[
                      if (risk.level != WeatherRiskLevel.clear)
                        WbWeatherRiskBadge(risk: risk, dense: false),
                      if (exact != null)
                        Text(
                          '${exact.toStringAsFixed(0)}℃',
                          style: WbType.tabular.copyWith(color: c.ink),
                        )
                      else if (range != null)
                        Text(
                          '${range.min.toStringAsFixed(0)}~'
                          '${range.max.toStringAsFixed(0)}℃',
                          style: WbType.tabular.copyWith(color: c.ink),
                        ),
                      if (pop != null)
                        Text(
                          '강수 $pop%',
                          style: WbType.tabular.copyWith(color: c.ink),
                        ),
                    ],
                  ),
                  if (risk.detail != null) ...<Widget>[
                    const SizedBox(height: WbSpace.xs),
                    Text(
                      risk.detail!,
                      style: WbType.caption.copyWith(color: c.inkMuted),
                    ),
                  ],
                  const SizedBox(height: WbSpace.sm),
                  Text(
                    '${value.forecastZone ?? '예보구역 미상'} · '
                    '${KoDate.dateTime(value.issuedAt)} 발표 · '
                    '${value.confidence.labelKo}',
                    style: WbType.micro.copyWith(color: c.inkMuted),
                  ),
                  const SizedBox(height: WbSpace.xs),
                  Text(
                    // We never state that a game will be cancelled — that is
                    // the organiser's decision, not a forecast's.
                    '날씨 위험은 참고용입니다. 경기 진행 여부는 주최 측 공지를 확인해 주세요.',
                    style: WbType.micro.copyWith(color: c.inkMuted),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// Per-game reminder toggle.
///
/// Saving a game is what makes it eligible for alerts, so this button and the
/// bookmark in the app bar act on the same state rather than on two competing
/// notions of "I care about this fixture". The wording differs because the
/// intent differs: one is "keep this", the other is "tell me before it starts".
///
/// Permission is requested here and nowhere earlier — this is the first moment
/// the user has actually asked to be interrupted. On iOS especially, asking at
/// launch and being refused is unrecoverable.
