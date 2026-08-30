# 수정 백로그

감사일 2026-08-30. 근거는 `docs/post-build-audit.md`, 측정값은
`docs/audit-evidence/probe-output.txt`.

**현재 상태 (2026-08-30 수정 후)**

| | 완료 | 남음 |
| --- | --- | --- |
| P0 | 2 / 2 | — |
| P1 | 6 / 7 | P1-4 (콘텐츠 확보 — API 키 필요) |
| P2 | 6 / 7 | P2-6 (`whatToWatchNext` — 스키마 v3 필요) |
| P3 | 0 / 6 | 전부 (기기·키·비교 앱 필요) |

각 항목 제목 옆의 `[완료]` / `[남음]` 표시를 보세요.

**2026-08-30 추가 개선** (`docs/improvement-prompt.md`): 내용 없는 섹션 헤더,
알림 원인 오지목, 경기 탭 착지, 팀 구장 노출, 런치 배경 — 모두 완료.

---

## P0 — 출시 차단

### [P0-1] [완료] 사람이 검수하지 않은 레코드에 `humanVerified` / `reviewed` 라벨이 붙는다

- **영향을 받는 사용자**: 전원. 특히 출처 표시를 근거로 앱을 신뢰하는 사용자.
- **실제 증거**:
  - `scripts/publish/build_seed.py:82-83` — `"qualityStatus": "humanVerified"`,
    `"verifiedAt": generated_at` 을 **조건 없이** 기록.
  - 같은 파일 `:523, :540, :558, :573, :600, :649, :667, :681, :696, :711, :727`
    — `"reviewStatus": "reviewed"` 하드코딩.
  - 결과: `public-data/content/discover.json` 의 14개 콘텐츠 레코드 전부가
    `reviewed` + `humanVerified`.
- **재현 절차**:
  ```bash
  python -c "import json;d=json.load(open('public-data/content/discover.json',encoding='utf-8'));print(d['items'][0]['programs'][0]['source'])"
  ```
- **사용자에게 미치는 영향**: 이 앱이 파는 것은 "출처를 정직하게 밝힌다"입니다.
  그 라벨이 거짓이면 나머지 모든 출처 표시의 신뢰도가 함께 무너집니다.
  `normalize.py` 는 같은 상황에서 절대 `reviewed` 를 찍지 않으므로, 규율이
  있는데 한쪽에만 적용된 상태입니다.
- **추정 근본 원인**: seed 생성기를 "사람이 손으로 쓴 데이터니까 검수된 것"
  으로 취급. 손으로 썼다는 것과 검수됐다는 것은 다릅니다.
- **정확한 수정 방향**: 생성기 기본값을 `reviewStatus: "pending"`,
  `qualityStatus: "autoVerified"` 로 바꾸고, 사람이 실제로 확인한 레코드만
  명시적 인자로 승격. `verifiedAt` 은 승격된 레코드에만 기록.
- **관련 파일**: `scripts/publish/build_seed.py`, `assets/seed/**`,
  `public-data/**`
- **수정 후 검증**: `validate_data.py` 에 "생성기 출력에 `humanVerified` 가
  없을 것" 규칙 추가 → 회귀 시 CI 실패.
- **의존성**: 없음.
- **작업 규모**: **S**

### [P0-2] [완료] 뉴스 발행일이 실제와 다르고, 모든 발행 시각이 왜곡되어 있다

- **영향을 받는 사용자**: 발견 탭을 보는 전원.
- **실제 증거** (실제 URL을 열어 대조):

  | 저장값 | 실제 | 파일 |
  | --- | --- | --- |
  | `2026-06-20T00:00:00Z` | **2026-06-07 23:31 KST** | `build_seed.py:619` |
  | `2026-02-27T00:00:00Z` | 2026-02-27 **12:21** KST | `build_seed.py` 동일 블록 |
  | `2026-07-01T00:00:00Z` | 2026-07-01 **12:10** KST | 동일 |

  URL 자체는 3건 모두 정상 문서이며 제목도 일치합니다. 틀린 것은 **시각**이고,
  iMBC 건은 **날짜가 13일 틀립니다.**
- **재현 절차**: `public-data/content/discover.json` 의
  `storyClusters[0].sources[*].publishedAt` 과 각 `url` 의 기사 헤더 비교.
- **사용자에게 미치는 영향**: `00:00:00Z` = KST 오전 9시이므로 앱은 모든 기사에
  대해 실제와 다른 발행 시각을 표시합니다. 뉴스 묶음은 시간순 정렬·"최신" 판단의
  근거이기도 합니다. 게다가 이 레코드들은 `isDemo: false`, `reviewed` 입니다.
- **추정 근본 원인**: 날짜를 기억에 의존해 기입하고 시각은 자정으로 채움.
- **정확한 수정 방향**: 세 건의 `publishedAt` 을 실제 값(UTC)으로 정정하고,
  시각을 모르면 **날짜만 저장하고 시각 미상임을 UI에 표시**하는 필드를 쓰거나
  해당 출처를 내림. 자정으로 채우지 말 것.
- **관련 파일**: `scripts/publish/build_seed.py:600-640`
- **수정 후 검증**: 각 URL 재확인 + `validate_data.py` 에
  "`publishedAt` 이 정확히 00:00:00Z인 실제 뉴스 레코드 금지" 규칙 추가.
- **의존성**: 없음.
- **작업 규모**: **S**

---

## P1 — 사용자 이탈

### [P1-1] [완료] 신규 설치 사용자의 딥링크가 유실된다

- **영향을 받는 사용자**: 공유 링크로 유입되는 **모든 신규 사용자** — 방송
  유입이 주 채널이므로 가장 중요한 경로.
- **실제 증거**: `docs/audit-evidence/probe-output.txt`
  ```
  PROBE|configured|detail=1      ← 설정 완료 사용자: 경기 상세 열림
  PROBE|fresh|onboarding=1|detail=0  ← 신규 설치: 온보딩만, 경기 유실
  ```
- **재현 절차**: `flutter test test/audit/deeplink_probe_test.dart`
- **사용자에게 미치는 영향**: 친구가 보낸 경기 링크를 눌러 설치했는데 그 경기가
  열리지 않습니다. 온보딩을 마치면 홈으로 갑니다. 원래 보려던 것을 다시 찾아야
  합니다.
- **추정 근본 원인**: `lib/app/router.dart:82` 의 redirect가 목적지를 저장하지
  않고 온보딩으로 보냄. 온보딩 완료 후에도 `WbRoutes.home` 으로 고정 이동.
- **정확한 수정 방향**: redirect 시 `state.matchedLocation` 을 보류 목적지로
  저장하고, 온보딩 완료 시 보류 목적지가 있으면 그곳으로, 없으면 홈으로.
  온보딩 화면 자체는 그대로.
- **관련 파일**: `lib/app/router.dart`,
  `lib/features/onboarding/onboarding_screen.dart`
- **수정 후 검증**: `test/audit/deeplink_probe_test.dart` 의 `fresh` 케이스를
  `detail=1` 을 단정하는 회귀 테스트로 승격.
- **의존성**: 없음.
- **작업 규모**: **S**

### [P1-2] [완료] 알림을 눌러도 해당 화면으로 가지 않는다

- **영향을 받는 사용자**: 알림을 켠 현역 사용자 전원.
- **실제 증거**: `lib/core/platform/notification_service.dart` 의
  `initialize()` 가 `_plugin.initialize(InitializationSettings(...))` 를
  호출하면서 `onDidReceiveNotificationResponse` 를 넘기지 않음.
  `getNotificationAppLaunchDetails` 호출도 없음. payload는 `:253` 에서
  `'${entityKind}:${entityId}'` 로 채워지지만 읽는 곳이 없음.
- **재현 절차**: 코드 검토. (실기기 확인은 에뮬레이터 부재로 불가)
- **사용자에게 미치는 영향**: "1시간 전" 알림을 눌러 앱이 열렸는데 홈입니다.
  경기를 다시 찾아야 하므로 알림의 가치가 절반으로 줄어듭니다.
- **추정 근본 원인**: 스케줄링만 구현하고 수신 경로를 연결하지 않음.
- **정확한 수정 방향**: `initialize()` 에 응답 콜백을 등록해 payload를 파싱하고
  `router.go(WbRoutes.game(id))` 로 이동. 콜드 스타트는
  `getNotificationAppLaunchDetails()` 로 처리. 라우터가 준비되기 전 도착한
  payload를 보류할 큐가 필요.
- **관련 파일**: `lib/core/platform/notification_service.dart`,
  `lib/app/router.dart`, `lib/app/bootstrap.dart`
- **수정 후 검증**: payload 파싱 단위 테스트 + 보류 큐 테스트. 실기기 확인은
  에뮬레이터 확보 후.
- **의존성**: 실기기 또는 에뮬레이터(최종 확인용).
- **작업 규모**: **M**

### [P1-3] [완료] 공식 원문을 확인할 수 있는 경기가 하나도 없다

- **영향을 받는 사용자**: 근거를 확인하려는 전원. 마스터 명세 과업 4가 완료
  불가.
- **실제 증거**: 23개 경기 전부 `officialDetailUrl` 없음.
  ```bash
  python -c "import json,glob;print(sum(1 for p in glob.glob('public-data/games/*.json') for g in json.load(open(p,encoding='utf-8'))['items'] if g.get('officialDetailUrl')))"
  # → 0
  ```
  따라서 `game_detail_screen.dart` 의 "공식 기록" 버튼과 "공식 기록 페이지 열기"
  버튼이 **한 번도 렌더링되지 않습니다.**
- **사용자에게 미치는 영향**: 화면은 "아직 수집되지 않았습니다"라고 정직하게
  말하지만, 앱의 핵심 약속인 "공식 근거 확인"이 전 화면에서 불가능합니다.
  덤으로 공유 링크가 `wbaseball://app/games/<id>` 로 폴백되어, 앱이 없는
  사람에게는 **열리지 않는 링크**가 전달됩니다.
- **추정 근본 원인**: 데모 데이터에 공식 URL이 없고, 공유 폴백이 웹 대체 주소를
  갖고 있지 않음.
- **정확한 수정 방향**: (a) 실제 데이터가 들어오기 전까지 공유 텍스트에서
  `wbaseball://` 단독 폴백을 빼고 앱 이름·경기 정보만 공유하거나, 게시된
  `public-data` 웹 주소를 폴백으로 사용. (b) 데모 경기에는 대회 공식 페이지를
  `officialDetailUrl` 로 넣지 **말 것** — 데모를 실제 기록에 연결하면 P0-1과
  같은 종류의 거짓말이 됩니다.
- **관련 파일**: `lib/features/games/game_detail_screen.dart:194`,
  `scripts/publish/build_seed.py`
- **수정 후 검증**: 공유 텍스트 생성 단위 테스트.
- **의존성**: 실데이터 확보 또는 웹 fallback 주소 결정.
- **작업 규모**: **S** (공유 폴백) / **L** (실데이터 확보)

### [P1-4] [남음] 발견 탭 콘텐츠가 14건뿐이고, 방송에서 실제 야구로 이어지지 않는다

- **영향을 받는 사용자**: 방송 유입 입문자.
- **실제 증거**: 전수 조사 — 화제 주제 3, 프로그램·시즌 2, 회차·리캡 2(**데모**),
  이야기 묶음 1, 뉴스 출처 3, 가이드 3.
- **사용자에게 미치는 영향**: 첫 방문에서 볼 것이 5분 안에 소진되고, 재방문
  이유가 없습니다. 방송 → 실제 팀·경기로 넘어가는 링크가 실제 데이터로 존재하지
  않습니다(회차가 데모).
- **추정 근본 원인**: 콘텐츠 수집 파이프라인이 API 키 부재로 비어 있고, seed는
  구조 시연용 최소 세트.
- **정확한 수정 방향**: 네이버·YouTube 키를 확보해 수집을 켜고, 검수 흐름을 한
  번 실제로 돌려 `pending → reviewed` 승격 절차를 검증. 그 전까지는 발견 탭
  상단에 "콘텐츠 준비 중" 상태를 명시.
- **관련 파일**: `scripts/ingest/fetch_sources.py`,
  `scripts/normalize/normalize.py`, `.github/workflows/publish-data.yml`
- **수정 후 검증**: 수집 1회 실행 후 `review/unknown-aliases.json` 과
  후보 건수 확인.
- **의존성**: **네이버 검색 API 키, YouTube API 키** (사용자 제공 필요)
- **작업 규모**: **M**

### [P1-5] [완료] 팀 순위를 앱이 계산하지 않는다

- **영향을 받는 사용자**: 순위를 보는 전원. 실제 데이터 연결 시 즉시 문제화.
- **실제 증거**: `lib/data/repositories/competition_repository.dart:197`
  ```dart
  out.sort((a, b) => (a.snapshot.rank ?? 9999).compareTo(b.snapshot.rank ?? 9999));
  ```
  순위 산식·대회별 규정·동률 규칙이 코드에 없습니다. 개인 기록에는
  `Leaderboard.rank()` 와 동률 테스트가 있는 반면, 팀 순위에는 계산도 테스트도
  없습니다.
- **사용자에게 미치는 영향**: 원천이 `rank` 를 주지 않으면(수기 제보·CSV에서는
  흔함) 모든 팀이 9999가 되어 **임의 순서로 나열되고 순위는 `-` 로 표시**됩니다.
  동률 처리도 원천에 위임됩니다.
- **추정 근본 원인**: "순위를 만들어내지 않는다"는 원칙을 "순위를 계산하지
  않는다"로 확대 적용. 원칙은 *근거 없는 추정 금지*이지 *결정론적 계산 금지*가
  아닙니다.
- **정확한 수정 방향**: 대회별 순위 규정을 설정값(승률 / 승점 / 동률 기준
  순서)으로 두고, 확정 경기 결과에서 순위를 계산. 원천 `rank` 가 있으면 대조해
  불일치를 표시. 계산 불가한 경우에만 `-`.
- **관련 파일**: `lib/data/repositories/competition_repository.dart`,
  `lib/data/models/domain.dart`, 새 `test/unit/standings_test.dart`
- **수정 후 검증**: 손으로 계산한 소형 fixture(동률·몰수·경기 수 불균형·연기
  포함)와 결과 대조.
- **의존성**: 대회별 규정 확인(연맹 문의).
- **작업 규모**: **M**

### [P1-6] [완료] `spoilerLevel` 이 없으면 "공개"로 처리된다

- **영향을 받는 사용자**: 스포일러 가리기를 켠 방송 시청자.
- **실제 증거**: `lib/data/models/audience.dart:64-69` — `parse()` 의 기본값이
  `SpoilerLevel.none`. 실제 데이터에서도 WBSC 화제 주제·가이드의
  `spoilerLevel` 이 `null` 입니다.
- **사용자에게 미치는 영향**: 향후 수집기가 회차·리캡에 `spoilerLevel` 을 빠뜨리면
  결과가 그대로 노출됩니다. 안전 기능이 fail-open입니다.
- **정확한 수정 방향**: 콘텐츠 종류별로 기본값을 나눠, 회차·리캡·경기 결과처럼
  결과를 담을 수 있는 종류는 미지정 시 `result` 로 보수적으로 처리.
  가이드·정적 문서만 `none`.
- **관련 파일**: `lib/data/models/audience.dart`, `lib/data/models/content.dart`
- **수정 후 검증**: "spoilerLevel 미지정 회차는 가려진다" 테스트 추가.
- **작업 규모**: **S**

### [P1-7] [완료] 앱이 허용하는 최대 글자 배율에서 홈이 넘친다 (그리고 200%를 지원하지 않는다)

- **영향을 받는 사용자**: 시스템 글자 크기를 키운 사용자 — 저시력 사용자 포함.
- **실제 증거**: `docs/audit-evidence/probe-output.txt`
  ```
  PROBE|홈|scale=1.3|OK
  PROBE|홈|scale=1.4|A RenderFlex overflowed by 1.4 pixels on the right.
  PROBE|홈|scale=1.7|... 60 pixels ...
  PROBE|홈|scale=2.0|... 118 pixels ...
  PROBE|홈-입문자|scale=1.4|OK      ← 현역 모드 전용 문제
  PROBE|경기|scale=1.7|... bottom 오버플로 5건 ...
  ```
- **재현 절차**: `flutter test test/audit/text_scale_probe_test.dart`
- **사용자에게 미치는 영향**: 두 겹입니다. (a) `lib/app/app.dart:41-42` 가
  배율을 1.4로 잘라, 안드로이드에서 200%를 설정한 사용자가 140%만 받습니다.
  (b) 그 1.4에서조차 현역 홈이 넘칩니다. 기존 테스트는 1.3까지만 봐서 놓쳤습니다.
- **정확한 수정 방향**: 먼저 1.4에서 넘치는 현역 홈 모듈의 가로 `Row` 를
  `Wrap`/`Flexible` 로 교체(입문자 홈은 정상이므로 현역 전용 모듈로 범위가
  좁혀집니다). 그 다음 상한을 2.0까지 올리면서 홈·경기의 세로 오버플로를 해결.
  상한을 먼저 올리면 더 크게 깨집니다.
- **관련 파일**: `lib/features/home/home_screen.dart` (현역 모듈),
  `lib/core/design_system/components/game_widgets.dart`, `lib/app/app.dart`
- **수정 후 검증**: `TestPhone` 에 1.4 케이스를 추가해 기존 넘침 검사에 포함.
  프로브를 단정 테스트로 승격.
- **작업 규모**: **M**

---

## P2 — 완성도

### [P2-1] [완료] 출처 줄에 `demo-fixture` 가 영문 그대로 노출된다
- 증거: `provenance_widgets.dart` `_sourceLabel()` 매핑에 `demo-fixture` 없음 →
  "출처 demo-fixture · … 확인" 으로 표시. 옆에 "데모 데이터" 배지가 따로 있어
  중복이면서 의미 불명.
- 수정: 매핑 추가("앱 데모 데이터") 또는 데모일 때 출처 줄에서 이름 생략.
- 규모: **S**

### [P2-2] [완료] `dart_test.yaml` 이 없어 `screenshots` 태그가 미선언 경고를 낸다
- 증거: `flutter test` 출력 —
  `Warning: A tag was used that wasn't specified in dart_test.yaml.`
- 영향: 오타 난 태그가 조용히 무시될 수 있음. CI의 `--exclude-tags` 가 의도대로
  동작하는지 보장되지 않음.
- 수정: `dart_test.yaml` 에 `tags: {screenshots: {}}` 선언.
- 규모: **S**

### [P2-3] [완료] README의 디버그 APK 크기가 실제와 다르다
- 증거: README 13절 "169MB" vs 실제 측정 **199.0MB**.
- 수정: 값 정정. 크기를 문서에 박아두는 대신 "빌드 시점에 따라 변동" 명시.
- 규모: **S**

### [P2-4] [완료] 파이썬 파이프라인에 테스트가 0건이다
- 증거: `find . -name "test_*.py"` → 없음. 뉴스 군집화(`story_key`), 별칭 해석,
  초성 추출이 전부 미검증. Dart 쪽 초성 구현과의 일치는 Dart 테스트가 주장만 함.
- 수정: `story_key` 군집화, `resolve_team` 미확인 별칭 분리, `initials`/
  `normalize_name` 의 Dart 대조 테스트.
- 규모: **M**

### [P2-5] [완료] 경기 상태 fixture가 부족하다
- 증거: seed의 status 값이 `scheduled`/`final`/`postponed` 뿐.
  `live`·`cancelled`·`delayed`·`forfeit`·`unknown` 화면 상태는 골든·위젯
  테스트에서 한 번도 렌더링되지 않음.
- 수정: 데모 fixture에 각 상태 1건씩 추가하고 골든에 포함.
- 규모: **S**

### [P2-6] [오탐 정정] 30초 요약 3단 구조
- **이 항목은 감사자의 오판이었습니다.** JSON 덤프에서 `shortSummary` 만 보고
  판단했는데, 모델과 UI를 확인하니 리캡에는 `whatHappened` / `whyItMatters` /
  `whatToWatchNext` 가 이미 있고 화면에도 "왜 중요한가" 로 렌더링됩니다
  (`featured_card.dart:297`, `story_cluster_screen.dart:98`).
- 실제로 빠진 것은 **`StoryCluster` 의 `whatToWatchNext`** 하나뿐입니다. 뉴스에서
  실제 경기로 넘어가는 다리라 값어치는 있지만, DB 컬럼 추가 → 스키마 v3
  마이그레이션이 필요해 이번 범위에서 제외했습니다.
- 규모: **M** (마이그레이션 포함)

### [P2-7] [완료] 터치 영역 48dp가 칩·날짜 스트립에서 미검증
- 증거: 밀도 테스트가 `listRowMinHeight >= WbSize.minTap` 만 강제.
- 수정: 주요 화면의 모든 `InkWell`/`GestureDetector` 크기를 순회 검사하는
  위젯 테스트 추가.
- 규모: **S**

---

## P3 — 향후

- **[P3-1] 실기기·에뮬레이터 검증 체계** — 현재 런타임 검증 0회. 최소 1대의
  저사양 기기 또는 AVD 확보. 이것이 없으면 P1-2를 끝까지 확인할 수 없습니다.
- **[P3-2] 성능 측정** — cold start, 첫 콘텐츠 표시, 스크롤 frame drop, DB
  쿼리 시간. 전부 미측정.
- **[P3-3] checksum 불일치·DB 트랜잭션 실패 테스트**
- **[P3-4] 경쟁 앱 정량 비교** — 과업별 시간·탭 수 실측.
- **[P3-5] 지도 화면, 홈 위젯, FCM 서버 푸시**
- **[P3-6] 골든에 없는 화면 추가** — `둘 다` 모드 홈, 비시즌 화제 콘텐츠,
  WebView 로딩·실패.

---

## 세 묶음 요약

### 1. 배포 전에 반드시 수정할 것
P0-1, P0-2 (데이터 정직성) — 둘 다 규모 **S**.
P1-1 (딥링크 유실), P1-6 (스포일러 fail-open), P1-7 (1.4x 넘침).

### 2. 첫 사용자 테스트 전에 수정할 것
P1-2 (알림 탭 이동), P1-3 (공유 링크 폴백), P1-4 (콘텐츠 확보),
P2-1, P2-3, P2-5.

### 3. 실제 사용 데이터를 본 뒤 결정할 것
P1-5 (순위 계산 — 실제 원천이 `rank` 를 주는지 보고 설계),
P2-6 (30초 요약 구조), P3 전체.
