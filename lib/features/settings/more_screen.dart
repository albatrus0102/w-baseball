import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/shell.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../core/utils/kst.dart';

/// The "더보기" hub.
///
/// Nothing here is a dead end and nothing is a placeholder — an entry whose
/// underlying configuration is missing says so plainly instead of opening an
/// empty screen.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final sync = ref.watch(syncControllerProvider);
    final audience = ref.watch(audienceProvider);
    final now = ref.watch(clockProvider)();
    final config = ref.watch(appConfigProvider);

    return Scaffold(
      appBar: const WbPrimaryAppBar(title: '더보기', showSearch: false),
      body: ListView(
        padding: const EdgeInsets.only(bottom: WbSpace.xxl),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(WbSpace.screen),
            child: WbCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.sync_rounded, size: 17, color: c.brand),
                      const SizedBox(width: WbSpace.sm),
                      Expanded(
                        child: Text(
                          sync.lastSuccessAt == null
                              ? '아직 갱신되지 않았습니다'
                              : '${KoDate.relative(sync.lastSuccessAt!, now)} 갱신됨',
                          style: WbType.body.copyWith(color: c.ink),
                        ),
                      ),
                      if (sync.isSyncing)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        TextButton(
                          onPressed: () => ref
                              .read(syncControllerProvider.notifier)
                              .refresh(force: true),
                          child: const Text('지금 갱신'),
                        ),
                    ],
                  ),
                  // A partial refresh is reported honestly rather than as
                  // a clean success.
                  if (sync.isPartial) ...<Widget>[
                    const SizedBox(height: WbSpace.sm),
                    const WbBadge(
                      label: '일부 데이터만 갱신됨',
                      tone: WbBadgeTone.warning,
                      icon: Icons.warning_amber_rounded,
                      dense: true,
                    ),
                  ],
                  if (!config.manifest.isConfigured) ...<Widget>[
                    const SizedBox(height: WbSpace.sm),
                    Text(
                      '원격 데이터 주소가 설정되지 않아 앱에 포함된 기본 데이터로 동작 중입니다.',
                      style: WbType.micro.copyWith(
                        color: c.inkMuted,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          _Group(
            title: '내 설정',
            items: <_Item>[
              _Item(
                icon: Icons.tune_rounded,
                title: '시작 화면과 지역',
                subtitle:
                    '${audience.mode.shortLabelKo}'
                    '${audience.regionLabel == null ? '' : ' · ${audience.regionLabel}'}',
                onTap: () => context.push(WbRoutes.settings),
              ),
              _Item(
                icon: Icons.notifications_none_rounded,
                title: '알림과 팔로우',
                subtitle: '카테고리별로 켜고 끌 수 있습니다',
                onTap: () => context.push(WbRoutes.notifications),
              ),
            ],
          ),

          _Group(
            title: '탐색',
            items: <_Item>[
              _Item(
                icon: Icons.place_outlined,
                title: '근처 경기',
                onTap: () => context.push(WbRoutes.nearby),
              ),
              _Item(
                icon: Icons.groups_outlined,
                title: '팀 찾기 · 여자야구 시작하기',
                onTap: () => context.push(WbRoutes.teams),
              ),
              _Item(
                icon: Icons.explore_outlined,
                title: '뉴스와 영상',
                onTap: () => context.go(WbRoutes.discover),
              ),
            ],
          ),

          _Group(
            title: '데이터',
            items: <_Item>[
              _Item(
                icon: Icons.fact_check_outlined,
                title: '데이터 출처와 이용정책',
                subtitle: '어떤 출처를 쓰고 무엇이 데모인지',
                onTap: () => context.push(WbRoutes.dataSources),
              ),
              _Item(
                icon: Icons.edit_note_rounded,
                title: '정보 등록 · 오류 제보',
                onTap: () => context.push(WbRoutes.submissions),
              ),
            ],
          ),

          _Group(
            title: '앱',
            items: <_Item>[
              _Item(
                icon: Icons.info_outline_rounded,
                title: '앱 정보와 개인정보처리방침',
                onTap: () => context.push(WbRoutes.about),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.items});

  final String title;
  final List<_Item> items;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WbSpace.screen,
            WbSpace.lg,
            WbSpace.screen,
            WbSpace.sm,
          ),
          child: Text(
            title,
            style: WbType.captionStrong.copyWith(color: c.inkMuted),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: WbSpace.screen),
          child: WbCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                for (var i = 0; i < items.length; i++) ...<Widget>[
                  items[i],
                  if (i < items.length - 1)
                    Divider(height: 1, color: c.divider, indent: WbSpace.xxl),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WbSpace.lg,
          vertical: WbSpace.md,
        ),
        child: Row(
          children: <Widget>[
            SizedBox(width: 28, child: Icon(icon, size: 19, color: c.brand)),
            const SizedBox(width: WbSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: WbType.body.copyWith(color: c.ink)),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: WbSpace.xxs),
                    Text(
                      subtitle!,
                      style: WbType.micro.copyWith(color: c.inkMuted),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.inkMuted),
          ],
        ),
      ),
    );
  }
}
