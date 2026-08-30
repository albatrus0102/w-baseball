import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/analytics/analytics.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../data/models/domain.dart';

/// Unified search across teams, competitions, venues and (when enabled)
/// players.
///
/// Reachable in one tap from every primary screen via the app-bar icon.
/// Matching is Korean-aware: `ㅅㅇ`, `서울`, and `서울다이아몬드` all hit the same
/// team. Recent terms stay on the device and can be cleared.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  final FocusNode _focus = FocusNode();

  String _query = '';
  List<SearchHit> _results = const <SearchHit>[];
  List<SearchHit> _suggestions = const <SearchHit>[];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _loadSuggestions();
      if (_query.isNotEmpty) _run(_query);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    final suggestions = await ref.read(searchRepositoryProvider).suggestions();
    if (!mounted) return;
    setState(() => _suggestions = suggestions);
  }

  Future<void> _run(String value) async {
    setState(() {
      _query = value;
      _searching = value.trim().isNotEmpty;
    });
    if (value.trim().isEmpty) {
      setState(() => _results = const <SearchHit>[]);
      return;
    }
    final hits = await ref.read(searchRepositoryProvider).search(value);
    if (!mounted) return;
    setState(() {
      _results = hits;
      _searching = false;
    });
    await ref
        .read(analyticsProvider)
        .log(
          AnalyticsEvent.searchPerformed,
          properties: <String, Object?>{'result_count': hits.length},
        );
  }

  Future<void> _submit(String value) async {
    if (value.trim().isEmpty) return;
    await ref.read(preferencesProvider).addRecentSearch(value.trim());
    await _run(value);
    if (mounted) setState(() {});
  }

  void _open(SearchHit hit) {
    switch (hit.type) {
      case SearchEntityType.team:
        context.push(WbRoutes.team(hit.id));
      case SearchEntityType.competition:
        context.push(WbRoutes.competition(hit.id));
      case SearchEntityType.venue:
        context.push(WbRoutes.venue(hit.id));
      case SearchEntityType.person:
        // Player detail is flag-gated; fall back to the team finder rather
        // than pushing a route that may not exist.
        context.push(WbRoutes.teams);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final recent = ref.watch(preferencesProvider).recentSearches;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          onChanged: _run,
          onSubmitted: _submit,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '팀, 대회, 경기장 검색',
            border: InputBorder.none,
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _controller.clear();
                      _run('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
      ),
      // resizeToAvoidBottomInset keeps results above the keyboard rather than
      // letting it cover them.
      resizeToAvoidBottomInset: true,
      body: _query.trim().isEmpty
          ? _IdleState(
              recent: recent,
              suggestions: _suggestions,
              onPick: (term) {
                _controller.text = term;
                _submit(term);
              },
              onOpen: _open,
              onClearRecent: () async {
                await ref.read(preferencesProvider).clearRecentSearches();
                if (mounted) setState(() {});
              },
            )
          : _searching
          ? ListView.builder(
              padding: const EdgeInsets.all(WbSpace.screen),
              itemCount: 4,
              itemBuilder: (context, _) => const Padding(
                padding: EdgeInsets.only(bottom: WbSpace.sm),
                child: WbSkeleton(height: 52, borderRadius: WbRadius.cardAll),
              ),
            )
          : _results.isEmpty
          ? WbEmptyState(
              icon: Icons.search_off_rounded,
              title: '"$_query" 검색 결과가 없습니다',
              message:
                  '초성 검색도 가능합니다. 예: ㅅㅇ → 서울\n'
                  '찾는 팀이 없다면 등록해 주세요.',
              primaryLabel: '팀 정보 등록',
              onPrimary: () => context.push(WbRoutes.submissions),
              secondaryLabel: '추천 검색어 보기',
              onSecondary: () {
                _controller.clear();
                _run('');
              },
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                WbSpace.screen,
                WbSpace.md,
                WbSpace.screen,
                WbSpace.xxl,
              ),
              itemCount: _results.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: WbSpace.sm),
                child: _HitTile(
                  hit: _results[i],
                  onTap: () => _open(_results[i]),
                ),
              ),
            ),
      bottomNavigationBar: _query.trim().isEmpty
          ? null
          : Container(
              color: c.canvas,
              padding: const EdgeInsets.fromLTRB(
                WbSpace.screen,
                WbSpace.sm,
                WbSpace.screen,
                WbSpace.sm,
              ),
              child: SafeArea(
                top: false,
                child: Text(
                  '${_results.length}개 결과',
                  style: WbType.micro.copyWith(color: c.inkMuted),
                ),
              ),
            ),
    );
  }
}

class _IdleState extends StatelessWidget {
  const _IdleState({
    required this.recent,
    required this.suggestions,
    required this.onPick,
    required this.onOpen,
    required this.onClearRecent,
  });

  final List<String> recent;
  final List<SearchHit> suggestions;
  final ValueChanged<String> onPick;
  final ValueChanged<SearchHit> onOpen;
  final VoidCallback onClearRecent;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        WbSpace.screen,
        WbSpace.md,
        WbSpace.screen,
        WbSpace.xxl,
      ),
      children: <Widget>[
        if (recent.isNotEmpty) ...<Widget>[
          Row(
            children: <Widget>[
              Text('최근 검색', style: WbType.captionStrong.copyWith(color: c.ink)),
              const Spacer(),
              TextButton(onPressed: onClearRecent, child: const Text('지우기')),
            ],
          ),
          const SizedBox(height: WbSpace.sm),
          Wrap(
            spacing: WbSpace.sm,
            runSpacing: WbSpace.sm,
            children: <Widget>[
              for (final term in recent)
                WbFilterChip(
                  label: term,
                  selected: false,
                  onTap: () => onPick(term),
                ),
            ],
          ),
          const SizedBox(height: WbSpace.xl),
        ],
        if (suggestions.isNotEmpty) ...<Widget>[
          Text('추천', style: WbType.captionStrong.copyWith(color: c.ink)),
          const SizedBox(height: WbSpace.sm),
          for (final hit in suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: WbSpace.sm),
              child: _HitTile(hit: hit, onTap: () => onOpen(hit)),
            ),
        ],
        const SizedBox(height: WbSpace.lg),
        Text(
          '팁 · 초성으로도 찾을 수 있어요. 예: ㅅㅇ → 서울\n'
          '최근 검색어는 이 기기에만 저장되며 언제든 지울 수 있습니다.',
          style: WbType.micro.copyWith(color: c.inkMuted, height: 1.7),
        ),
      ],
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit, required this.onTap});

  final SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    final (IconData icon, String label) = switch (hit.type) {
      SearchEntityType.team => (Icons.groups_outlined, '팀'),
      SearchEntityType.competition => (Icons.emoji_events_outlined, '대회'),
      SearchEntityType.venue => (Icons.place_outlined, '경기장'),
      SearchEntityType.person => (Icons.person_outline_rounded, '선수'),
    };

    return WbCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: WbSpace.lg,
        vertical: WbSpace.md,
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 19, color: c.brand),
          const SizedBox(width: WbSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  hit.title,
                  style: WbType.body.copyWith(color: c.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hit.subtitle != null && hit.subtitle!.isNotEmpty)
                  Text(
                    hit.subtitle!,
                    style: WbType.micro.copyWith(color: c.inkMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          WbBadge(label: label, tone: WbBadgeTone.muted, dense: true),
        ],
      ),
    );
  }
}
