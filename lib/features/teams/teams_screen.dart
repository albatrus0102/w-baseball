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
import '../../data/models/domain.dart';
import '../../data/repositories/team_repository.dart';

/// Team finder.
///
/// Built for the "I want to start playing" journey: region chips first,
/// recruiting teams surfaced, and Korean-aware search (`ㅅㅇ` finds 서울).
/// If a region has no teams, the screen routes to registration rather than
/// leaving the user at a dead end.
class TeamsScreen extends ConsumerStatefulWidget {
  const TeamsScreen({super.key});

  @override
  ConsumerState<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends ConsumerState<TeamsScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  final Set<String> _regions = <String>{};
  bool _recruitingOnly = false;
  bool _followedOnly = false;

  @override
  void initState() {
    super.initState();
    // Teams store the 시·도 code, not its name — seeding this with the label
    // would filter everything out.
    final code = ref.read(audienceProvider).regionCode;
    if (code != null) _regions.add(code);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final regions = ref.watch(teamRegionsProvider).value ?? const <String>[];
    final query = TeamQuery(
      text: _query,
      regions: _regions.toList(),
      recruitingOnly: _recruitingOnly,
      followedOnly: _followedOnly,
    );
    final teams = ref.watch(teamsProvider(query));
    final followed =
        ref.watch(followedTeamIdsProvider).value ?? const <String>{};

    return Scaffold(
      appBar: AppBar(title: const Text('팀 찾기')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WbSpace.screen,
              WbSpace.md,
              WbSpace.screen,
              WbSpace.sm,
            ),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '팀 이름 검색 (초성도 가능해요)',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: c.surface,
                border: const OutlineInputBorder(
                  borderRadius: WbRadius.chipAll,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: WbSpace.screen,
                vertical: WbSpace.sm,
              ),
              children: <Widget>[
                WbFilterChip(
                  label: '모집 중',
                  icon: Icons.campaign_outlined,
                  selected: _recruitingOnly,
                  onTap: () =>
                      setState(() => _recruitingOnly = !_recruitingOnly),
                ),
                const SizedBox(width: WbSpace.sm),
                if (followed.isNotEmpty) ...<Widget>[
                  WbFilterChip(
                    label: '팔로우',
                    icon: Icons.star_rounded,
                    selected: _followedOnly,
                    onTap: () => setState(() => _followedOnly = !_followedOnly),
                  ),
                  const SizedBox(width: WbSpace.sm),
                ],
                for (final code in regions) ...<Widget>[
                  WbFilterChip(
                    // Codes are storage; people read names.
                    label: KoreanRegion.byCode(code)?.name ?? code,
                    selected: _regions.contains(code),
                    onTap: () => setState(() {
                      _regions.contains(code)
                          ? _regions.remove(code)
                          : _regions.add(code);
                    }),
                    onRemove: _regions.contains(code)
                        ? () => setState(() => _regions.remove(code))
                        : null,
                  ),
                  const SizedBox(width: WbSpace.sm),
                ],
              ],
            ),
          ),
          Expanded(
            child: teams.when(
              loading: () => ListView.builder(
                padding: const EdgeInsets.all(WbSpace.screen),
                itemCount: 5,
                itemBuilder: (context, _) => const Padding(
                  padding: EdgeInsets.only(bottom: WbSpace.sm),
                  child: WbCard(
                    child: Row(
                      children: <Widget>[
                        WbSkeleton(
                          width: 36,
                          height: 36,
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                        ),
                        SizedBox(width: WbSpace.md),
                        Expanded(child: WbSkeleton(height: 16)),
                      ],
                    ),
                  ),
                ),
              ),
              error: (_, _) => WbEmptyState(
                icon: Icons.error_outline_rounded,
                tone: WbBadgeTone.danger,
                title: '팀 목록을 불러오지 못했습니다',
              ),
              data: (list) {
                if (list.isEmpty) {
                  return WbEmptyState(
                    icon: Icons.groups_outlined,
                    title: _query.isEmpty
                        ? '조건에 맞는 팀이 없습니다'
                        : '"$_query" 검색 결과가 없습니다',
                    message: '조건을 지우거나, 우리 팀 정보를 직접 등록해 주세요.',
                    primaryLabel: '팀 정보 등록하기',
                    onPrimary: () => context.push(WbRoutes.submissions),
                    secondaryLabel: '조건 초기화',
                    onSecondary: () => setState(() {
                      _query = '';
                      _search.clear();
                      _regions.clear();
                      _recruitingOnly = false;
                      _followedOnly = false;
                    }),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    WbSpace.screen,
                    0,
                    WbSpace.screen,
                    WbSpace.xxl,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: WbSpace.sm),
                    child: _TeamRow(
                      team: list[i],
                      isFollowed: followed.contains(list[i].id),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamRow extends ConsumerWidget {
  const _TeamRow({required this.team, required this.isFollowed});

  final Team team;
  final bool isFollowed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    return WbCard(
      onTap: () => context.push(WbRoutes.team(team.id)),
      accentColor: WbTeamMark.parseHex(team.colorHex),
      child: Row(
        children: <Widget>[
          WbTeamMark(name: team.displayName, colorHex: team.colorHex),
          const SizedBox(width: WbSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  team.displayName,
                  style: WbType.headline.copyWith(color: c.ink),
                  maxLines: WbClamp.teamName,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: WbSpace.xxs),
                Text(
                  <String?>[
                    KoreanRegion.byCode(team.region)?.name ?? team.region,
                    team.city,
                  ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                  style: WbType.caption.copyWith(color: c.inkMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (team.isRecruiting) ...<Widget>[
                  const SizedBox(height: WbSpace.sm),
                  WbBadge(
                    label: team.recruitmentTarget == null
                        ? '모집 중'
                        : '모집 중 · ${team.recruitmentTarget}',
                    tone: WbBadgeTone.positive,
                    icon: Icons.campaign_outlined,
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
          WbTapTarget(
            onTap: () async {
              await ref
                  .read(followRepositoryProvider)
                  .toggleFollow(
                    FollowKind.team,
                    team.id,
                    label: team.displayName,
                  );
              await ref.read(platformServicesProvider).haptics.selection();
            },
            semanticLabel: isFollowed
                ? '${team.displayName} 팔로우 해제'
                : '${team.displayName} 팔로우',
            child: Icon(
              isFollowed ? Icons.star_rounded : Icons.star_border_rounded,
              size: 21,
              color: isFollowed ? c.highlight : c.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
