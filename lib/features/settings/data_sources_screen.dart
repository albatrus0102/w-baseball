import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/database/database.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';
import '../../core/utils/kst.dart';

final _syncRunsProvider = StreamProvider.autoDispose<List<SyncRunRow>>((ref) {
  final db = ref.watch(databaseProvider);
  final select = db.select(db.syncRuns)
    ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
    ..limit(12);
  return select.watch();
});

final _demoCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await (db.select(
    db.games,
  )..where((t) => t.isDemo.equals(true))).get();
  return rows.length;
});

/// Where the data comes from, what is demo, and which adapters are switched
/// off and why.
///
/// This screen exists so a user can always answer "can I trust this number?"
/// without leaving the app.
class DataSourcesScreen extends ConsumerWidget {
  const DataSourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final config = ref.watch(appConfigProvider);
    final runs = ref.watch(_syncRunsProvider);
    final demoCount = ref.watch(_demoCountProvider).value ?? 0;
    final now = DateTime.now().toUtc();

    return Scaffold(
      appBar: AppBar(title: const Text('데이터 출처')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          WbSpace.screen,
          WbSpace.md,
          WbSpace.screen,
          WbSpace.xxl,
        ),
        children: <Widget>[
          if (demoCount > 0)
            WbCard(
              accentColor: c.highlight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const WbBadge(
                    label: '데모 데이터 포함',
                    tone: WbBadgeTone.warning,
                    icon: Icons.science_outlined,
                  ),
                  const SizedBox(height: WbSpace.sm),
                  Text(
                    '현재 $demoCount개의 경기가 데모 데이터입니다. '
                    '앱 동작을 확인하기 위한 예시이며 실제 경기 기록이 아닙니다. '
                    '모든 화면에서 "데모 데이터" 표시가 함께 나타납니다.',
                    style: WbType.body.copyWith(color: c.ink, height: 1.6),
                  ),
                ],
              ),
            ),

          const SizedBox(height: WbSpace.lg),
          Text('공식 출처', style: WbType.section.copyWith(color: c.ink)),
          const SizedBox(height: WbSpace.md),
          _SourceCard(
            name: 'WBAK 한국여자야구연맹',
            url: config.officialLinks.wbakHome,
            enabled: config.flags.wbakAdapterEnabled,
            // Stated plainly: this is a licence question, not a technical one.
            note:
                '외부 공개 API가 확인되지 않았습니다. 이용허락을 받기 전까지 '
                '앱에서 직접 수집하지 않고, 공식 페이지로 연결만 합니다.',
          ),
          const SizedBox(height: WbSpace.sm),
          _SourceCard(
            name: 'KBSA 대한야구소프트볼협회',
            url: config.officialLinks.kbsaHome,
            enabled: config.flags.kbsaAdapterEnabled,
            note:
                '통합경기정보의 공개 API가 확인되지 않았습니다. '
                '이용허락 또는 CSV 제공 시 어댑터를 활성화합니다.',
          ),
          const SizedBox(height: WbSpace.sm),
          _SourceCard(
            name: 'WBSC 여자야구 월드컵',
            url: config.officialLinks.wbscWomensWorldCup,
            enabled: config.flags.wbscAdapterEnabled,
            note: '공개 페이지가 있으나 응답 구조 검증과 실패 격리를 마친 뒤 활성화합니다.',
          ),
          const SizedBox(height: WbSpace.sm),
          _SourceCard(
            name: 'WPBL 미국 여자프로야구리그',
            url: config.officialLinks.wpblStats,
            enabled: config.flags.wpblAdapterEnabled,
            note:
                '공개 GET 주소가 있으나 장기 제공이 보장되지 않아 '
                '스키마 검증과 함께 별도 활성화합니다.',
          ),

          const SizedBox(height: WbSpace.section),
          Text('데이터 배포', style: WbType.section.copyWith(color: c.ink)),
          const SizedBox(height: WbSpace.md),
          WbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _KeyValue(
                  label: '배포 주소',
                  value: config.manifest.isConfigured
                      ? config.manifest.baseUrl
                      : '설정되지 않음 (앱 기본 데이터 사용 중)',
                ),
                _KeyValue(
                  label: '지원 스키마',
                  value:
                      'v${config.dataContract.minSupportedSchemaVersion}'
                      '~v${config.dataContract.maxSupportedSchemaVersion}',
                ),
                _KeyValue(
                  label: '오래된 기준',
                  value: '${config.sync.staleAfter.inHours}시간',
                ),
                const SizedBox(height: WbSpace.sm),
                Text(
                  '앱이 읽을 수 없는 상위 스키마 버전을 받으면 기존 데이터를 지우지 않고 '
                  '갱신만 중단합니다.',
                  style: WbType.micro.copyWith(color: c.inkMuted, height: 1.55),
                ),
              ],
            ),
          ),

          const SizedBox(height: WbSpace.section),
          Text('최근 동기화', style: WbType.section.copyWith(color: c.ink)),
          const SizedBox(height: WbSpace.md),
          runs.when(
            loading: () =>
                const WbSkeleton(height: 120, borderRadius: WbRadius.cardAll),
            error: (_, _) => const SizedBox.shrink(),
            data: (list) {
              if (list.isEmpty) {
                return WbEmptyState(
                  compact: true,
                  icon: Icons.sync_disabled_rounded,
                  title: '동기화 기록이 없습니다',
                );
              }
              return WbCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    for (var i = 0; i < list.length; i++) ...<Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: WbSpace.lg,
                          vertical: WbSpace.md,
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              list[i].failureKind == null
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.error_outline_rounded,
                              size: 16,
                              color: list[i].failureKind == null
                                  ? c.verified
                                  : c.danger,
                            ),
                            const SizedBox(width: WbSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    list[i].sourceName,
                                    style: WbType.body.copyWith(color: c.ink),
                                  ),
                                  Text(
                                    list[i].failureKind == null
                                        ? '신규 ${list[i].inserted} · '
                                              '수정 ${list[i].updated} · '
                                              '삭제표시 ${list[i].tombstoned}'
                                        : (list[i].failureMessage ?? '실패'),
                                    style: WbType.micro.copyWith(
                                      color: c.inkMuted,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              KoDate.relative(list[i].startedAt, now),
                              style: WbType.micro.copyWith(color: c.inkMuted),
                            ),
                          ],
                        ),
                      ),
                      if (i < list.length - 1)
                        Divider(height: 1, color: c.divider),
                    ],
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: WbSpace.section),
          WbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '저작권과 개인정보 원칙',
                  style: WbType.captionStrong.copyWith(color: c.ink),
                ),
                const SizedBox(height: WbSpace.sm),
                for (final line in const <String>[
                  '뉴스는 제목·언론사·발행시각·API가 제공한 설명·원문 링크만 저장합니다. 기사 본문과 언론사 이미지는 복제하지 않습니다.',
                  '팀 로고와 선수 사진은 이용허락이 확인된 경우에만 표시합니다.',
                  '미성년 선수의 사진과 개인 프로필은 표시하지 않습니다.',
                  '전화번호·주소·이메일·정확한 생년월일은 수집하지도, 저장하지도 않습니다.',
                  '위치 정보는 기기 안에서 거리 계산에만 쓰고 저장·전송하지 않습니다.',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: WbSpace.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '· ',
                          style: WbType.caption.copyWith(color: c.inkMuted),
                        ),
                        Expanded(
                          child: Text(
                            line,
                            style: WbType.caption.copyWith(
                              color: c.inkMuted,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.name,
    required this.url,
    required this.enabled,
    required this.note,
  });

  final String name;
  final String url;
  final bool enabled;
  final String note;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return WbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  style: WbType.headline.copyWith(color: c.ink),
                ),
              ),
              WbBadge(
                label: enabled ? '자동 수집 켜짐' : '자동 수집 꺼짐',
                tone: enabled ? WbBadgeTone.positive : WbBadgeTone.muted,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: WbSpace.sm),
          Text(
            note,
            style: WbType.caption.copyWith(color: c.inkMuted, height: 1.6),
          ),
          const SizedBox(height: WbSpace.md),
          OutlinedButton.icon(
            onPressed: () =>
                openSource(context, url: url, title: name, sourceLabel: name),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('공식 사이트 열기'),
          ),
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: WbSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: WbType.caption.copyWith(color: c.inkMuted),
            ),
          ),
          Expanded(
            child: Text(value, style: WbType.caption.copyWith(color: c.ink)),
          ),
        ],
      ),
    );
  }
}
