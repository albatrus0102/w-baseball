import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/providers.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';

final _packageInfoProvider = FutureProvider.autoDispose<PackageInfo?>((
  ref,
) async {
  try {
    return await PackageInfo.fromPlatform();
  } on Object {
    // Not available on a test host; the screen degrades gracefully.
    return null;
  }
});

/// App information and the privacy policy, stated in full rather than linked
/// to a page that may not exist yet.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    final info = ref.watch(_packageInfoProvider).value;
    final flags = ref.watch(appConfigProvider).flags;

    return Scaffold(
      appBar: AppBar(title: const Text('앱 정보')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          WbSpace.screen,
          WbSpace.md,
          WbSpace.screen,
          WbSpace.xxl,
        ),
        children: <Widget>[
          WbCard(
            emphasized: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('여자야구', style: WbType.display.copyWith(color: c.ink)),
                const SizedBox(height: WbSpace.xs),
                Text(
                  info == null
                      ? '버전 정보를 불러올 수 없습니다'
                      : '버전 ${info.version} (${info.buildNumber})',
                  style: WbType.caption.copyWith(color: c.inkMuted),
                ),
                const SizedBox(height: WbSpace.md),
                Text(
                  '한국 여자야구의 일정, 결과, 대회, 팀 정보를 한곳에서 찾도록 만든 앱입니다. '
                  '로그인 없이 사용할 수 있고, 네트워크가 없어도 마지막으로 받은 데이터로 동작합니다.',
                  style: WbType.body.copyWith(color: c.inkMuted, height: 1.65),
                ),
              ],
            ),
          ),

          const SizedBox(height: WbSpace.section),
          Text('개인정보처리방침', style: WbType.section.copyWith(color: c.ink)),
          const SizedBox(height: WbSpace.md),
          WbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final entry in const <List<String>>[
                  <String>[
                    '수집하지 않는 정보',
                    '계정, 이름, 전화번호, 이메일, 주소, 생년월일을 수집하지 않습니다. '
                        '회원가입 자체가 없습니다.',
                  ],
                  <String>[
                    '기기에만 저장되는 정보',
                    '팔로우한 팀, 저장한 경기, 시작 화면 설정, 지역, 알림 설정, 최근 검색어. '
                        '모두 이 기기에만 저장되며 외부로 전송되지 않습니다.',
                  ],
                  <String>[
                    '위치',
                    '기본적으로 사용하지 않습니다. 사용자가 허용한 경우에도 좌표는 기기 안에서 '
                        '거리 계산에만 쓰고 저장하거나 전송하지 않습니다. 백그라운드 위치는 쓰지 않습니다.',
                  ],
                  <String>[
                    '네트워크 요청',
                    '공개된 정적 데이터 파일을 내려받는 요청만 보냅니다. '
                        '사용자를 식별하는 값이나 광고 식별자를 함께 보내지 않습니다.',
                  ],
                  <String>[
                    '분석',
                    '외부 분석 도구를 연결하지 않았습니다. 앱 사용 이벤트는 기기 안의 '
                        '개발용 로그로만 남고 외부로 나가지 않습니다.',
                  ],
                  <String>['알림', '기기에서 직접 예약하는 로컬 알림만 사용합니다. 푸시 서버를 쓰지 않습니다.'],
                  <String>['미성년자', '미성년 선수의 사진과 개인 프로필은 표시하지 않습니다.'],
                  <String>[
                    '삭제',
                    '앱을 삭제하면 저장된 모든 정보가 함께 삭제됩니다. '
                        '앱 안에서도 팔로우와 최근 검색어를 지울 수 있습니다.',
                  ],
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: WbSpace.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          entry[0],
                          style: WbType.captionStrong.copyWith(color: c.ink),
                        ),
                        const SizedBox(height: WbSpace.xs),
                        Text(
                          entry[1],
                          style: WbType.caption.copyWith(
                            color: c.inkMuted,
                            height: 1.65,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: WbSpace.section),
          Text('알려진 제한', style: WbType.section.copyWith(color: c.ink)),
          const SizedBox(height: WbSpace.md),
          WbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final line in const <String>[
                  '실시간 투구 단위 중계는 제공하지 않습니다.',
                  '기상청 상세 예보는 10일까지만 제공되므로 그 이후 날짜의 일별 날씨는 표시하지 않습니다.',
                  '공식 이용허락을 받기 전까지 WBAK·KBSA 자동 수집은 꺼져 있습니다.',
                  '개인 기록은 공식적으로 공개된 기록지가 있는 경기만 집계합니다.',
                  '팀 채팅, 출석, 회비 같은 팀 운영 기능은 포함되어 있지 않습니다.',
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

          // Debug-only. Never shown in a release build.
          if (flags.debugTaskMetricsEnabled) ...<Widget>[
            const SizedBox(height: WbSpace.section),
            const _DebugEvents(),
          ],
        ],
      ),
    );
  }
}

class _DebugEvents extends ConsumerWidget {
  const _DebugEvents();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = WbTheme.of(context);
    return FutureBuilder(
      future: ref.read(analyticsProvider).recent(limit: 40),
      builder: (context, snapshot) {
        final events = snapshot.data ?? const [];
        return WbCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '개발용 이벤트 로그',
                style: WbType.captionStrong.copyWith(color: c.ink),
              ),
              const SizedBox(height: WbSpace.sm),
              if (events.isEmpty)
                Text(
                  '기록된 이벤트가 없습니다.',
                  style: WbType.caption.copyWith(color: c.inkMuted),
                )
              else
                for (final event in events)
                  Text(
                    '${event.name} ${event.properties}',
                    style: WbType.micro.copyWith(color: c.inkMuted),
                  ),
            ],
          ),
        );
      },
    );
  }
}
