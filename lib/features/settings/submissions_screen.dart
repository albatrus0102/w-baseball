import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';

/// One submission entry point per purpose.
///
/// URLs come from configuration; **no placeholder or invented URL is ever
/// shipped**. An entry whose URL is unset is shown as "준비 중" and cannot be
/// tapped, rather than opening a dead link.
///
/// Submitting is explicitly not publishing — the status ladder is stated on
/// the screen so nobody expects an instant change.
class SubmissionsScreen extends ConsumerWidget {
  const SubmissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final forms = ref.watch(appConfigProvider).forms;

    final entries = <_Entry>[
      _Entry(
        icon: Icons.add_business_outlined,
        title: '팀 정보 등록 · 수정',
        description: '팀 이름, 지역, 모집 여부, 공식 채널을 등록하거나 고칩니다.',
        url: forms.teamRegistration,
      ),
      _Entry(
        icon: Icons.event_repeat_outlined,
        title: '경기 일정 변경 제보',
        description: '연기, 취소, 구장 변경을 알려주세요.',
        url: forms.scheduleChange,
      ),
      _Entry(
        icon: Icons.assignment_turned_in_outlined,
        title: '경기 결과 · 기록지 제출',
        description: '공식 기록지나 결과를 보내주시면 검토 후 반영합니다.',
        url: forms.resultSubmission,
      ),
      _Entry(
        icon: Icons.flag_outlined,
        title: '잘못된 정보 신고',
        description: '틀린 점수, 이름, 날짜를 신고합니다.',
        url: forms.dataCorrection,
      ),
      _Entry(
        icon: Icons.privacy_tip_outlined,
        title: '개인정보 숨김 · 삭제 요청',
        description: '본인 또는 미성년자 정보의 비공개를 요청합니다.',
        url: forms.privacyRemoval,
      ),
    ];

    final available = entries.where((e) => e.isAvailable).length;

    return Scaffold(
      appBar: AppBar(title: const Text('정보 등록 · 제보')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          WbSpace.screen,
          WbSpace.md,
          WbSpace.screen,
          WbSpace.xxl,
        ),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(WbSpace.md),
            decoration: BoxDecoration(
              color: c.brandSoft,
              borderRadius: WbRadius.chipAll,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '제출이 곧 게시는 아닙니다',
                  style: WbType.captionStrong.copyWith(color: c.ink),
                ),
                const SizedBox(height: WbSpace.xs),
                Text(
                  '접수됨 → 검토 중 → 반영됨 / 반영 안 됨 순서로 처리됩니다. '
                  '출처를 확인할 수 있는 자료를 함께 보내주시면 빠르게 검토할 수 있습니다.',
                  style: WbType.caption.copyWith(color: c.ink, height: 1.6),
                ),
              ],
            ),
          ),

          if (available == 0) ...<Widget>[
            const SizedBox(height: WbSpace.lg),
            WbEmptyState(
              icon: Icons.hourglass_empty_rounded,
              title: '제보 창구를 준비하고 있습니다',
              message:
                  '접수 양식이 연결되면 이 화면에서 바로 열 수 있습니다.\n'
                  '설정 파일에 양식 주소를 넣으면 즉시 활성화됩니다.',
            ),
          ],

          const SizedBox(height: WbSpace.lg),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: WbSpace.sm),
              child: _EntryCard(entry: entry),
            ),

          const SizedBox(height: WbSpace.lg),
          Text(
            '전화번호, 주소, 이메일 같은 개인 연락처는 앱에 저장하지 않습니다. '
            '양식에도 꼭 필요한 정보만 적어 주세요.',
            style: WbType.micro.copyWith(color: c.inkMuted, height: 1.7),
          ),
        ],
      ),
    );
  }
}

class _Entry {
  const _Entry({
    required this.icon,
    required this.title,
    required this.description,
    required this.url,
  });

  final IconData icon;
  final String title;
  final String description;
  final String url;

  bool get isAvailable => url.trim().isNotEmpty;
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return WbCard(
      onTap: entry.isAvailable
          ? () => openSource(
              context,
              url: entry.url,
              title: entry.title,
              sourceLabel: 'Google Forms',
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            entry.icon,
            size: 20,
            color: entry.isAvailable ? c.brand : c.inkMuted,
          ),
          const SizedBox(width: WbSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        entry.title,
                        style: WbType.headline.copyWith(
                          color: entry.isAvailable ? c.ink : c.inkMuted,
                        ),
                      ),
                    ),
                    if (!entry.isAvailable) ...<Widget>[
                      const SizedBox(width: WbSpace.sm),
                      const WbBadge(
                        label: '준비 중',
                        tone: WbBadgeTone.muted,
                        dense: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: WbSpace.xs),
                Text(
                  entry.description,
                  style: WbType.caption.copyWith(
                    color: c.inkMuted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          if (entry.isAvailable)
            Icon(Icons.open_in_new_rounded, size: 16, color: c.inkMuted),
        ],
      ),
    );
  }
}
