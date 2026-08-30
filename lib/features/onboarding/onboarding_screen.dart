import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../data/models/audience.dart';
import '../../data/repositories/team_repository.dart';

/// Three short questions, all skippable, over live content.
///
/// Deliberately not a carousel of marketing slides and never a sign-up wall:
///  * every step can be skipped, and the whole flow can be skipped at once,
///  * answers only reorder home modules — nothing is gated behind them,
///  * notification permission is *not* requested here. It is asked for later,
///    at the moment the user first turns on an alert, where the value is
///    obvious.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pages = PageController();
  int _index = 0;

  AudienceMode? _mode;
  KoreanRegion? _region;
  SpoilerPolicy _spoiler = SpoilerPolicy.hide;
  String? _teamId;

  static const int _stepCount = 3;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool skipped}) async {
    final controller = ref.read(audienceControllerProvider);
    if (!skipped) {
      if (_mode != null) await controller.setMode(_mode!);
      await controller.setRegion(_region?.code, _region?.name);
      await controller.setSpoilerPolicy(_spoiler);
      if (_teamId != null) {
        await ref
            .read(followRepositoryProvider)
            .follow(FollowKind.team, _teamId!);
      }
      await controller.completeOnboarding();
    } else {
      await controller.skipOnboarding();
    }
    if (!mounted) return;
    // Go where they were headed before the redirect intervened, if anywhere.
    // Skipping counts too: someone who skipped still wants the game they tapped.
    context.go(PendingDestination.instance.take() ?? WbRoutes.home);
  }

  void _next() {
    if (_index >= _stepCount - 1) {
      _finish(skipped: false);
      return;
    }
    setState(() => _index++);
    _pages.animateToPage(
      _index,
      duration: WbTheme.duration(context, WbDuration.standard),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);

    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WbSpace.screen,
                WbSpace.md,
                WbSpace.sm,
                0,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        for (var i = 0; i < _stepCount; i++) ...<Widget>[
                          Expanded(
                            child: AnimatedContainer(
                              duration: WbTheme.duration(
                                context,
                                WbDuration.quick,
                              ),
                              height: 3,
                              decoration: BoxDecoration(
                                color: i <= _index ? c.brand : c.divider,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          if (i < _stepCount - 1)
                            const SizedBox(width: WbSpace.xs),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: WbSpace.md),
                  TextButton(
                    onPressed: () => _finish(skipped: true),
                    child: const Text('건너뛰기'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _index = i),
                children: <Widget>[
                  _ModeStep(
                    selected: _mode,
                    onSelect: (mode) => setState(() => _mode = mode),
                  ),
                  _RegionStep(
                    selected: _region,
                    mode: _mode,
                    selectedTeamId: _teamId,
                    onSelectRegion: (r) => setState(() => _region = r),
                    onSelectTeam: (id) => setState(() => _teamId = id),
                  ),
                  _SpoilerStep(
                    selected: _spoiler,
                    onSelect: (p) => setState(() => _spoiler = p),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WbSpace.screen,
                WbSpace.md,
                WbSpace.screen,
                WbSpace.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_index >= _stepCount - 1 ? '시작하기' : '다음'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        WbSpace.xl,
        WbSpace.screen,
        WbSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: WbType.display.copyWith(color: c.ink)),
          const SizedBox(height: WbSpace.sm),
          Text(description, style: WbType.body.copyWith(color: c.inkMuted)),
          const SizedBox(height: WbSpace.xl),
          child,
        ],
      ),
    );
  }
}

class _ModeStep extends StatelessWidget {
  const _ModeStep({required this.selected, required this.onSelect});

  final AudienceMode? selected;
  final ValueChanged<AudienceMode> onSelect;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: '어떤 화면으로\n시작할까요?',
      description: '홈에 보이는 순서만 달라집니다. 모든 기능은 언제든 사용할 수 있고, 나중에 바꿀 수 있어요.',
      child: Column(
        children: <Widget>[
          for (final mode in AudienceMode.values) ...<Widget>[
            _ChoiceCard(
              title: mode.labelKo,
              description: switch (mode) {
                AudienceMode.discover =>
                  '화제 콘텐츠, 근처에서 볼 수 있는 경기, 입문 가이드를 먼저 보여드려요.',
                AudienceMode.player => '내 팀 일정과 구장, 날씨 위험, 순위와 기록을 먼저 보여드려요.',
                AudienceMode.both => '오늘 급한 것부터 섞어서 보여드려요.',
              },
              selected: selected == mode,
              onTap: () => onSelect(mode),
            ),
            const SizedBox(height: WbSpace.md),
          ],
        ],
      ),
    );
  }
}

class _RegionStep extends ConsumerWidget {
  const _RegionStep({
    required this.selected,
    required this.mode,
    required this.selectedTeamId,
    required this.onSelectRegion,
    required this.onSelectTeam,
  });

  final KoreanRegion? selected;
  final AudienceMode? mode;
  final String? selectedTeamId;
  final ValueChanged<KoreanRegion?> onSelectRegion;
  final ValueChanged<String?> onSelectTeam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final wantsTeam = mode == AudienceMode.player || mode == AudienceMode.both;

    return _StepScaffold(
      title: '어느 지역이\n궁금하세요?',
      // Location permission is never required for this. The user picks a
      // region; we only ever ask for GPS later, and only to sort by distance.
      description: '선택하지 않아도 괜찮아요. 위치 권한 없이 지역만 골라도 근처 경기를 찾을 수 있습니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: WbSpace.sm,
            runSpacing: WbSpace.sm,
            children: <Widget>[
              for (final region in KoreanRegion.all)
                WbFilterChip(
                  label: region.name,
                  selected: selected?.code == region.code,
                  onTap: () => onSelectRegion(
                    selected?.code == region.code ? null : region,
                  ),
                ),
            ],
          ),
          if (wantsTeam) ...<Widget>[
            const SizedBox(height: WbSpace.section),
            Text('활동하는 팀이 있나요?', style: WbType.section.copyWith(color: c.ink)),
            const SizedBox(height: WbSpace.xs),
            Text(
              '선택 사항입니다. 팀을 고르면 일정과 날씨를 마이야구에서 바로 볼 수 있어요.',
              style: WbType.caption.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: WbSpace.md),
            _TeamPicker(
              regionCode: selected?.code,
              selectedTeamId: selectedTeamId,
              onSelect: onSelectTeam,
            ),
          ],
        ],
      ),
    );
  }
}

class _TeamPicker extends ConsumerWidget {
  const _TeamPicker({
    required this.regionCode,
    required this.selectedTeamId,
    required this.onSelect,
  });

  final String? regionCode;
  final String? selectedTeamId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final query = TeamQuery(
      regions: regionCode == null ? const <String>[] : <String>[regionCode!],
      limit: 12,
    );
    final teams = ref.watch(teamsProvider(query));

    return teams.when(
      loading: () => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          WbSkeleton(width: 180, height: 18),
          SizedBox(height: WbSpace.sm),
          WbSkeleton(width: 140, height: 18),
        ],
      ),
      error: (_, _) => Text(
        '팀 목록을 불러오지 못했습니다.',
        style: WbType.caption.copyWith(color: c.inkMuted),
      ),
      data: (list) {
        if (list.isEmpty) {
          // Never a dead end: no teams here means an invitation to add one.
          return WbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '이 지역에 등록된 팀 정보가 아직 없습니다.',
                  style: WbType.bodyStrong.copyWith(color: c.ink),
                ),
                const SizedBox(height: WbSpace.xs),
                Text(
                  '우리 팀 정보를 등록해 주시면 다른 사람도 찾을 수 있어요.',
                  style: WbType.caption.copyWith(color: c.inkMuted),
                ),
                const SizedBox(height: WbSpace.md),
                OutlinedButton(
                  onPressed: () => context.push(WbRoutes.submissions),
                  child: const Text('팀 정보 등록하기'),
                ),
              ],
            ),
          );
        }
        return Wrap(
          spacing: WbSpace.sm,
          runSpacing: WbSpace.sm,
          children: <Widget>[
            for (final team in list)
              WbFilterChip(
                label: team.displayName,
                selected: selectedTeamId == team.id,
                onTap: () =>
                    onSelect(selectedTeamId == team.id ? null : team.id),
              ),
          ],
        );
      },
    );
  }
}

class _SpoilerStep extends StatelessWidget {
  const _SpoilerStep({required this.selected, required this.onSelect});

  final SpoilerPolicy selected;
  final ValueChanged<SpoilerPolicy> onSelect;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: '결과를 바로\n볼까요?',
      description: '방송이나 경기를 나중에 볼 계획이라면 가려둘 수 있어요. 카드, 상세 화면, 알림에 모두 적용됩니다.',
      child: Column(
        children: <Widget>[
          for (final policy in SpoilerPolicy.values) ...<Widget>[
            _ChoiceCard(
              title: policy.labelKo,
              description: switch (policy) {
                SpoilerPolicy.reveal => '요약과 점수를 그대로 보여드려요.',
                SpoilerPolicy.hide =>
                  '결과가 포함된 내용은 한 번 더 눌러야 보입니다. 알림에도 결과를 넣지 않아요.',
              },
              selected: selected == policy,
              onTap: () => onSelect(policy),
            ),
            const SizedBox(height: WbSpace.md),
          ],
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.brandSoft : c.surface,
        borderRadius: WbRadius.cardAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: WbRadius.cardAll,
          child: Container(
            padding: const EdgeInsets.all(WbSpace.lg),
            decoration: BoxDecoration(
              borderRadius: WbRadius.cardAll,
              border: Border.all(
                color: selected ? c.brand : c.divider,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: WbType.headline.copyWith(color: c.ink),
                      ),
                      const SizedBox(height: WbSpace.xs),
                      Text(
                        description,
                        style: WbType.caption.copyWith(
                          color: c.inkMuted,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: WbSpace.md),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? c.brand : c.divider,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
