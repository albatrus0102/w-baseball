import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:w_baseball/core/config/app_config.dart';
import 'package:w_baseball/data/models/audience.dart';
import 'package:w_baseball/features/home/home_screen.dart';

import 'harness.dart';

/// `공식 영상` (officialVideos) has no adapter filling it yet — see
/// `OfficialLinksConfig.officialVideosChannel`. Its empty state offers the
/// real 야구여왕 YouTube channel instead of just apologising; once the module
/// actually has video records, that offer must get out of the way.
void main() {
  const audience = AudiencePreference(
    mode: AudienceMode.discover,
    onboardingCompleted: true,
    regionCode: '11',
    regionLabel: '서울',
  );

  /// One `content/videos.json` item, following the same envelope + `source`
  /// block shape every other seed document uses (see `assets/seed/teams.json`
  /// for a worked example). `visibility: public` is required — `SyncEngine`
  /// silently drops anything else.
  const populatedVideosJson = '''
{
  "schemaVersion": 1,
  "dataVersion": "2026.08.30",
  "generatedAt": "2026-08-30T00:00:00Z",
  "payloadKind": "snapshot",
  "hasMore": false,
  "items": [
    {
      "id": "video-test-official-1",
      "title": "테스트 공식 영상",
      "url": "https://www.youtube.com/watch?v=abc123",
      "publishedAt": "2026-08-25T00:00:00Z",
      "channelName": "테스트 채널",
      "source": {
        "sourceName": "demo-fixture",
        "sourceUrl": "https://www.youtube.com/watch?v=abc123",
        "fetchedAt": "2026-08-25T00:00:00Z",
        "qualityStatus": "autoVerified",
        "licenseStatus": "permitted",
        "visibility": "public",
        "isDemo": true,
        "sourceRecordId": "video-test-official-1"
      }
    }
  ]
}
''';

  test('설정된 채널 URL은 실제로 검증된 야구여왕 채널을 가리킨다', () {
    // Guards against a typo or placeholder silently replacing the verified
    // channel id — this project has a standing rule against invented URLs.
    const links = OfficialLinksConfig();
    expect(
      links.officialVideosChannel,
      'https://www.youtube.com/channel/UCbHZ_ylnH0zdbRZjfRxrBjg',
    );
  });

  /// `officialVideos` sits eighth in `discoverOrder`, below the viewport at
  /// the harness's default phone size, so — exactly like the `mustRender`
  /// scroll loop in `home_modules_test.dart` — every text on screen has to be
  /// accumulated across a scroll, or a real result reads as "not found".
  Future<Set<String>> scrollAndCollectText(
    WidgetTester tester,
    TestApp app,
  ) async {
    await pumpScreen(tester, app, const HomeScreen(), phone: TestPhone.large);
    await settle(tester);

    final seen = <String>{};
    void collect() => seen.addAll(
      tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? ''),
    );
    collect();
    for (var i = 0; i < 10; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await settle(tester);
      collect();
    }
    return seen;
  }

  testWidgets('영상이 하나도 없으면 공식 영상 모듈이 채널 링크를 제안한다', (tester) async {
    // The real bundled seed already ships `content/videos.json` with zero
    // items — this is the actual gap the task describes, not a fixture.
    final app = await buildTestApp(audience: audience);
    addTearDown(app.dispose);

    final seen = await scrollAndCollectText(tester, app);

    expect(seen, contains('공식 영상'));
    expect(seen, contains('공식 영상이 아직 없습니다'));
    expect(seen, contains('야구여왕 채널 열기'));
    expectNoOverflow(tester);
  });

  testWidgets('영상이 있으면 채널 링크를 더 이상 제안하지 않는다', (tester) async {
    final documents = Map<String, String>.from(loadSeedFromDisk())
      ..['content/videos.json'] = populatedVideosJson;

    final app = await buildTestApp(audience: audience, documents: documents);
    addTearDown(app.dispose);

    final seen = await scrollAndCollectText(tester, app);

    // The real video card renders instead of the empty-state offer.
    expect(seen, contains('테스트 공식 영상'));
    expect(seen, isNot(contains('공식 영상이 아직 없습니다')));
    expect(
      seen,
      isNot(contains('야구여왕 채널 열기')),
      reason: '모듈에 실제 영상이 있으면 채널 링크는 사라져야 합니다',
    );
    expectNoOverflow(tester);
  });
}
