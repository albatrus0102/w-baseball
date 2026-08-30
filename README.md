# 여자야구 (w_baseball)

한국 여자야구의 일정·결과·팀·대회를 한곳에서 보는 Android 우선 Flutter 앱입니다.

방송(`야구여왕 시즌 2`)을 보고 처음 찾아온 사람과, 이미 팀에서 뛰고 있는
선수·운영진이 **같은 앱**을 쓰되 **다른 첫 화면**을 보도록 설계했습니다.

---

## 1. 목적과 범위

### 하는 것

| 영역 | 내용 |
| --- | --- |
| 일정·결과 | 월/일 단위 경기 일정, 결과, 상태(예정·진행·종료·연기·취소), 대회별 필터 |
| 발견 | 화제 주제(FeaturedTopic), 프로그램·회차, 뉴스 이야기 묶음, 입문 가이드, 근처 경기 |
| 마이야구 | 팔로우한 팀의 30일 일정판, 날씨 위험, 참석 상태, 순위, 개인 기록 순위표 |
| 경기 상세 | 스코어보드, 경기장, 길찾기·캘린더 연동, 출처 표시 |
| 알림 | 카테고리별 기기 로컬 알림, 방해 금지 시간, 스포일러 인지 |
| 제보 | Google Forms 기반 팀 등록·일정 변경·결과 제출·정정 요청 |

### 하지 않는 것 (의도적)

- **종합 평점·AI 랭킹을 만들지 않습니다.** 표본이 적은 리그에서 합성 지표는
  사실처럼 보이는 오해를 만듭니다. 원지표와 규정 이닝·타석 충족 여부만 보여줍니다.
- **기사 본문과 언론사 이미지를 복제하지 않습니다.** 제목·매체·시각·원문 링크와
  API가 제공한 설명까지만 저장합니다.
- **선수 개인 연락처·주소·정확한 생년월일을 수집하지 않습니다.** (8절 참고)
- **상시 서버를 두지 않습니다.** 정적 파일과 예약 작업만으로 동작합니다.
- **백그라운드 위치를 쓰지 않습니다.** 위치 권한 없이도 모든 기능이 동작합니다.

---

## 2. 실제 데이터와 데모 데이터 구분

**이 저장소에 담긴 경기 기록·순위·선수는 전부 데모입니다.** 실제 경기 결과처럼
보이게 만든 것이 하나도 없습니다.

배포본(`public-data/`) 기준 현재 상태:

| 구분 | 건수 | 내용 |
| --- | ---: | --- |
| 실제 (`isDemo: false`) | 5 + 발견 콘텐츠 | 단체 3곳(WBAK·KBSA·WBSC), WBSC 2026 여자야구 월드컵, 프로그램/시즌 메타데이터, 화제 주제 3건, 뉴스 묶음 1건, 입문 가이드 3건 |
| 데모 (`isDemo: true`) | 192 | 팀 8, 경기장 4, 경기 27, 선수 72, 로스터 72, 순위 8, 대회 1, 회차 1, 날씨 예보 12 |

구분 방법은 세 겹입니다.

1. **데이터 레벨** — 모든 레코드에 `source.isDemo` 가 있습니다. 데모는
   `sourceName: "demo-fixture"`, `sourceUrl: "app://demo/fixture"` 입니다.
2. **UI 레벨** — 데모 레코드는 목록 행과 상세 화면 양쪽에 `데모` 배지가 붙습니다.
   목록에도 붙이는 이유는, 목록 스크린샷 한 장이 공식 기록으로 오해되지 않게
   하기 위해서입니다.
3. **검증 레벨** — 아래 명령은 데모 레코드가 하나라도 있으면 **실패**합니다.
   실제 운영 배포는 이 게이트를 통과해야 합니다.

```bash
python scripts/validate/validate_data.py public-data --production
```

현재 이 명령은 데모 레코드 192건 때문에 의도적으로 실패합니다. 그것이 정상입니다.

데모 선수 72명은 **전부 생성된 픽스처**입니다. 이름은 `데모선수 1-1` 형식이고,
레코드가 가진 필드는 `id`·`name`·`isMinor`·`source` 넷뿐입니다 — 생년월일,
연락처, 사진을 담을 자리가 스키마에 없습니다. 타격·투구 기록도 경기 id로 시드를
고정한 난수이며, 팀 점수와 합이 맞도록 제약만 걸려 있습니다. 실제 선수의 성적을
옮긴 것이 아닙니다.

실제 데이터로 바꾸는 방법은 [docs/data-sources.md](docs/data-sources.md) 와
[docs/connecting-an-official-api.md](docs/connecting-an-official-api.md) 를 보세요.

---

## 3. 실행 방법

전제: Flutter 3.47.2 이상, JDK 17, Android SDK.

```bash
flutter pub get
```

```bash
dart run build_runner build --delete-conflicting-outputs
```

```bash
flutter run
```

환경 변수를 하나도 주지 않아도 **번들된 seed 데이터로 완전히 동작합니다.**
네트워크도, API 키도 필요 없습니다.

릴리스 APK 빌드:

```bash
flutter build apk --release
```

자세한 절차와 문제 해결은 [docs/build-and-run.md](docs/build-and-run.md).

### 테스트

```bash
flutter test --exclude-tags screenshots
```

현재 **325개 테스트 통과**. 스크린샷은 리뷰용 산출물이라 CI에서 제외합니다
(호스트 폰트에 따라 픽셀이 달라지므로, 픽셀 차이로 빌드를 막지 않습니다).

```bash
flutter test --tags screenshots --update-goldens
```

21장이 `docs/screenshots/` 에 생성됩니다.

파이썬 파이프라인 테스트는 따로 돌립니다.

```bash
python -m unittest discover -s scripts/tests
```

---

## 4. 환경 변수 목록

전체 목록과 설명은 [.env.example](.env.example) 에 있습니다. **실제 비밀값은 이
저장소에 없고, 앱 바이너리에도 들어가지 않습니다.**

### 앱 빌드 시점 (`--dart-define`)

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `WB_MANIFEST_BASE_URL` | (빈 값) | 정적 데이터 배포 주소. 비우면 동기화 없이 seed만 사용 |
| `WB_MANIFEST_VERSION_PATH` | `version.json` | 매니페스트 경로 |
| `WB_API_TRANSPORT` | `none` | `none` / `rest` / `graphql` |
| `WB_API_BASE_URL` | (빈 값) | 미래 공식 API 주소 |
| `WB_API_PAGE_SIZE` | `100` | 페이지 크기 |
| `WB_FLAG_SPONSOR_COMMERCE` | `false` | 켜기 전에는 라우트 자체가 등록되지 않음 |
| `WB_FLAG_PLAYER_PROFILES` | `false` | 선수 개인 프로필 |
| `WB_FLAG_PUSH_MESSAGING` | `false` | 서버 푸시 (현재 미사용) |
| `WB_FLAG_TASK_METRICS` | `false` | 과업 계측 |
| `WB_FLAG_ADAPTER_WBAK` | `false` | 10절 참고 |
| `WB_FLAG_ADAPTER_KBSA` | `false` | 10절 참고 |
| `WB_FLAG_ADAPTER_WBSC` | `false` | 이용허락 확인 후에만 |
| `WB_FLAG_ADAPTER_WPBL` | `false` | 이용허락 확인 후에만 |
| `WB_FORM_*` | (빈 값) | Google Forms 진입점 5종. **비우면 "준비 중"으로 표시되고 눌리지 않습니다.** 가짜 URL을 넣지 마세요 |

### 자동화 전용 (GitHub Secrets / Variables — 앱에는 들어가지 않음)

`NAVER_CLIENT_ID`, `NAVER_CLIENT_SECRET`, `YOUTUBE_API_KEY`, `KMA_SERVICE_KEY`,
`WB_YOUTUBE_CHANNEL_IDS`, `WB_KMA_ZONES`, `WB_INGEST_*`.

> API 키가 필요한 원천은 GitHub Actions 안에서만 호출됩니다. 앱은 그 결과로
> 만들어진 정적 JSON만 내려받습니다. **그래서 앱에 키가 하나도 없어도 됩니다.**

---

## 5. 데이터 동기화 방식

```
원천 DTO → Adapter / Mapper / Validator → 도메인 모델 → Sync Engine
        → Drift · SQLite (유일한 로컬 원본) → Repository Stream → UI
```

UI는 Dio·JSON·URL·SQL을 직접 만지지 않습니다. 화면은 항상 DB 스트림만 봅니다.

- **매니페스트 우선** — `version.json` 의 파일별 `sha256` 을 비교해, 바뀌지 않은
  파일은 내려받지 않습니다. `ETag` / `If-Modified-Since` 도 함께 씁니다.
- **스냅샷과 델타** — 페이로드가 `payloadKind` 로 자신이 전체인지 증분인지
  선언합니다. 스냅샷일 때만 목록에서 빠진 레코드를 삭제 처리합니다.
- **하드 삭제 없음, tombstone만** — 되돌릴 수 있어야 합니다.
- **멱등 upsert** — 같은 페이로드를 두 번 넣어도 결과가 같습니다.
- **레코드 단위 격리(quarantine)** — 잘못된 레코드 하나가 배치 전체를 막지
  않습니다. 격리된 레코드는 사유와 함께 남고, 나머지는 정상 반영됩니다.
- **회로 차단기 + 지터 백오프** — 서버가 `Retry-After` 를 주면 그 값을 지킵니다.
- **스키마 버전 거부** — 앱이 아는 범위(현재 1..1) 밖의 `schemaVersion` 은
  받아들이지 않습니다. 구버전 앱이 새 데이터를 잘못 해석하는 사고를 막습니다.

원천 우선순위는 `FutureRestApi → FutureGraphql → (허가된 어댑터) → 정적 매니페스트
→ 번들 seed` 입니다. 앞이 실패하면 뒤로 내려갑니다.

---

## 6. 오프라인 동작

로컬 SQLite가 유일한 원본이므로 **오프라인은 예외가 아니라 기본 동작**입니다.

| 상황 | 동작 |
| --- | --- |
| 기내 모드로 최초 실행 | 번들 seed로 전 화면 동작. 빈 화면 없음 |
| 동기화 실패 | 마지막으로 성공한 데이터를 계속 보여주고, 마지막 갱신 시각을 표시 |
| 일부 파일만 실패 | 성공한 파일은 반영하고 실패한 원천만 기록. 전체 롤백하지 않음 |
| 검색 | 전부 로컬 쿼리. 네트워크와 무관 |
| 팔로우·저장·참석 상태 | 전부 로컬. `clearSyncedData()` 는 사용자 소유 행을 남깁니다 |
| 알림 예약 | 기기 로컬 알림. 서버 없이 동작 |
| 외부 링크 | 허용 목록(allowlist)에 있는 도메인만 WebView로 엽니다 |

---

## 7. 출처 표시 정책

- 모든 레코드에 `Provenance`(원천 이름·URL·수집 시각·라이선스 상태·데모 여부)가
  붙고, 화면에 **출처 줄**로 나옵니다.
- 요약문에는 `summaryMethod` 가 붙습니다: `apiDescription`(원천 API가 준 설명),
  `template`(구조화된 값으로 만든 문장), `human`(사람이 쓴 글).
  **제목을 근거로 무슨 일이 있었는지 추측해 쓰지 않습니다.**
- 자동 파이프라인이 만든 것은 전부 `reviewStatus: "pending"` 입니다. 자동화는
  후보만 만들고, 사람이 검수해야 `reviewed` 가 됩니다.
- 뉴스는 **이야기 묶음(StoryCluster)** 단위입니다. 같은 사안을 다룬 여러 매체를
  한 카드로 묶고 각 매체 원문으로 링크합니다. 본문은 저장하지 않습니다.
- 데이터가 없으면 **없다고 씁니다.** 커버리지(`DataCoverage`)를 화면에 밝히고,
  빈칸을 그럴듯한 값으로 채우지 않습니다.

---

## 8. 개인정보 최소화 정책

- **수집하지 않는 것**: 전화번호, 주소, 개인 이메일, 정확한 생년월일.
  검증 스크립트가 이 필드들의 존재 자체를 차단합니다.
- **미성년 선수**: 명시적 사용 근거가 없으면 사진과 개인 프로필을 표시하지
  않습니다. `WB_FLAG_PLAYER_PROFILES` 는 기본 `false` 입니다.
- **위치**: 온보딩에서 요구하지 않습니다. 지역(시·도) 선택만으로 근처 경기가
  동작합니다. 사용자가 위치를 허용해도 좌표는 **기기 안에서 거리 계산에만**
  쓰이고 서버·로그·정적 데이터에 저장되지 않습니다. 백그라운드 위치는 없습니다.
- **알림 권한**: 온보딩에서 요청하지 않습니다. 사용자가 알림을 실제로 켜는
  시점에만 요청합니다.
- **분석**: 인터페이스만 있고 기본 구현은 `LocalAnalyticsService` — 기기 안에만
  남습니다. 외부 분석 SDK는 기본 비활성이며, 동의와 개인정보처리방침 없이 켜지
  않습니다.
- 경기장 주소는 개인정보가 아니라 시설 정보이므로 표시합니다. 검증 스크립트는
  연락처 필드와 사람 필드를 분리해서 판정합니다.

---

## 9. 대표 과업 측정 결과

감상이 아니라 **위젯 테스트에서 실제로 센 값**입니다
(`test/widget/task_benchmark_test.dart`). 테스트가 측정값을 `BENCHMARK|...` 로
출력하므로 아래 표와 코드가 조용히 어긋날 수 없습니다.

| # | 과업 | 시작 화면 | 탭 수 | 스크롤 | 네트워크 실패 시 |
| --- | --- | --- | ---: | ---: | --- |
| T1 | 내 팀 다음 경기 상세 보기 | 홈 (현역 모드) | **1** | 0 | 로컬 DB의 마지막 일정 + 마지막 갱신 시각 표시 |
| T1′ | 다음 경기 상세 보기 | 홈 (입문자 모드) | **3** | 0 | 위와 같음. 경기 없는 날이면 "다음 경기일" 1탭이 포함된 값 |
| T2 | 통합 검색 시작 | 홈 / 발견 / 경기 / 마이야구 | **1** | 0 | 전부 로컬 검색. 영향 없음 |
| T3 | 근처 경기 찾기 | 발견 | **2** | 0 | 지역 기준 로컬 필터. 위치 권한·네트워크 모두 불필요 |
| T4 | 내 팀 설정 | 마이야구 | **2** | 0 | 팀 목록은 로컬. 영향 없음 |
| T5 | 마이야구 진입 | 아무 탭 | **1** | 0 | 영향 없음 |
| M1 | 오늘 경기 결과 확인 | 경기 | **2** | 0 | 로컬 결과 표시 + 마지막 갱신 시각 |
| M2 | 특정 팀의 다음 경기와 구장 | 검색 | **2** | 2 | 팀 상세 전체가 로컬. 영향 없음 |
| M3 | 특정 대회의 현재 순위 | 검색 | **2** | 0 | 순위는 로컬. 갱신 시각만 오래됨 |
| M4 | 공식 원문 확인 후 목록 복귀 | 경기 | **2** | 0 | 원문은 네트워크 필요. 실패 시 목록 위치·필터는 그대로 유지 |
| M5 | 캘린더 추가 + 알림 설정 | 홈(현역) | **1** | 0 | 둘 다 기기 로컬. 영향 없음 |

T1~T5는 개정 명세의 두 사용자군 기준 과업이고, M1~M5는 최초 명세가 이름으로
지목한 과업입니다. 겹치지 않으므로 둘 다 측정합니다.

`스크롤 0` 은 **첫 화면 안에서 다음 탭 지점에 닿는다**는 뜻입니다. 테스트가
직접 확인하며, 닿지 못하면 실패합니다.

추가로 검증한 것:

- 경기 탭의 필터는 다른 탭을 다녀와도 유지됩니다 (`StatefulShellRoute`).
- **공식 원문을 보고 돌아와도** 보던 날짜와 필터가 그대로입니다 (M4).
- 근처 경기 화면은 `useDeviceLocation == false` 상태에서 정상 동작합니다.
- 경기 상세에서 알림을 켜면 그 경기가 실제 예약 대상이 됩니다 (M5).

자세한 경로와 설계 근거는 [docs/task-benchmarks.md](docs/task-benchmarks.md).

---

## 10. WBAK·KBSA 자동 수집이 기본 비활성인 이유

**기술적으로 가능하다는 것과 해도 된다는 것은 다릅니다.**

- 두 단체의 공개 웹사이트에는 **공개 API 이용약관이 없습니다.** 브라우저 개발자
  도구에 보이는 내부 통신 주소는 공식 API가 아니며, 그렇게 가정하지 않습니다.
- 그래서 `WbakAdapter` 와 `KbsaAdapter` 는 `enabled: false` 로 만들어져 있고,
  앱에서는 비활성 사유(`disabledReasonKo`)가 그대로 화면에 표시됩니다.
- 수집 스크립트에서도 **환경 변수만으로는 켤 수 없습니다.**
  `scripts/ingest/fetch_sources.py` 에 `blocked_reason` 이 하드코딩되어 있고,
  이를 지우려면 코드 변경과 리뷰가 필요합니다. 실수로 켜지는 경로를 없앤 것입니다.

켜는 순서: 서면 이용허락 → `docs/data-sources.md` 에 근거 기록 →
`blocked_reason` 제거(리뷰 필수) → 플래그 활성화. 순서를 바꾸지 마세요.

그동안의 대안은 **사람이 넣는 데이터**입니다. Google Forms 제보 → 검수 → 게시.
자세한 내용은 [docs/google-forms.md](docs/google-forms.md).

---

## 11. 무료 인프라 한도

상시 서버가 없으므로 비용은 사실상 0이지만, 무료 한도는 유한합니다.

| 자원 | 무료 한도 | 현재 사용 | 여유 |
| --- | --- | --- | --- |
| GitHub Actions (public) | 무제한 | 하루 2회 × 약 3분 | 충분 |
| GitHub Actions (private) | 월 2,000분 | 하루 2회 × 약 3분 ≒ 월 180분 | 충분 |
| GitHub Pages | 저장소 1GB, 월 100GB 전송 | 배포본 약 60KB | 전송량이 먼저 한계에 닿습니다 |
| 네이버 검색 API | 일 25,000회 | 하루 2회 | 충분 |
| YouTube Data API | 일 10,000 유닛 | 채널당 약 100 유닛 × 2회 | 충분 |
| 기상청 단기·중기예보 | 일 10,000회 (활용신청 기준) | 예보구역 수 × 2회 | 예보구역을 늘릴 때만 주의 |

전송량이 한계에 닿으면: 매니페스트 `sha256` 스킵이 이미 대부분을 막고 있으므로,
다음 수단은 파일 분할 폭을 좁히는 것입니다 (경기 데이터는 이미 월별입니다).

---

## 12. 알려진 제한

정직하게 적습니다.

1. **경기 기록·순위·선수는 전부 데모입니다.** 실제 리그 데이터가 아닙니다.
2. **실사용자 테스트를 하지 않았습니다.** 탭 수는 측정했지만 사람에게 써보게 한
   적은 없습니다. [docs/user-testing-plan.md](docs/user-testing-plan.md) 는
   *계획*이며 수행 결과가 아닙니다.
3. **날씨는 기상청 예보 가능 범위까지만** 보여줍니다. D+0~2 상세, D+3~10 범위,
   11일 이후는 일정만. 30일 일별 날씨를 만들어내지 않습니다.
4. **뉴스 자동 요약은 후보 상태**입니다. 전부 `reviewStatus: pending` 이며,
   사람 검수 없이 운영 배포에 넣으면 안 됩니다.
5. **팀 별칭 해석은 보수적**입니다. 모르는 표기는 추측하지 않고
   `review/unknown-aliases.json` 으로 보냅니다. 그만큼 미해결이 쌓입니다.
6. **iOS는 빌드해보지 않았습니다.** 코드는 플랫폼 중립이지만 실제 검증은
   Android에서만 했습니다.
7. **릴리스 APK가 약 69MB** 입니다. 범용(universal) 빌드라 모든 ABI가 들어 있어서
   그렇습니다. AAB 또는 ABI 분할로 줄일 수 있습니다 (13절).
8. **서버 푸시 없음.** 기기 로컬 알림만 씁니다. 앱이 오래 꺼져 있으면 예약된
   알림 외에는 새 소식을 받지 못합니다.
9. **스크린샷 골든은 CI에서 제외**되어 있습니다. 폰트가 다른 머신에서 픽셀이
   달라지므로, 그만큼 회귀 검출력이 낮습니다.
10. **뉴스·영상 배포본이 비어 있습니다.** 수집에 API 키가 필요한데 이 저장소에
    키가 없기 때문입니다. 빈 상태가 정상이며, 앱은 빈 상태를 정상적으로 표시합니다.

---

## 13. Android 출시 준비

현재 상태:

- `flutter build apk --debug` 성공 (약 200MB — 디버그 심볼 포함, 배포용 아님)
- `flutter build apk --release` 성공 (약 69MB, universal)
- JDK 17
- `flutter_local_notifications` 가 `java.time` 을 쓰므로 **core library
  desugaring 활성화됨** (`isCoreLibraryDesugaringEnabled = true`,
  `desugar_jdk_libs:2.1.5`). 이게 없으면 빌드가 실패합니다.

출시 전에 해야 할 일:

1. **서명 키 생성**과 `key.properties` 구성. 키스토어는 저장소에 넣지 마세요.
2. **AAB로 전환** — `flutter build appbundle`. Play Store가 기기별로 쪼개주므로
   실제 다운로드 크기가 크게 줄어듭니다. APK로 배포해야 한다면
   `flutter build apk --split-per-abi` 를 쓰세요.
3. **개인정보처리방침 URL** 준비 (Play Console 필수). 8절 내용을 근거로.
4. **데이터 보안 섹션** 작성 — 수집 항목 없음, 위치는 선택이며 기기 내 처리.
5. **데모 데이터 표기** — 스토어 설명에 실제 기록이 아니라는 점을 명시.
6. `WB_MANIFEST_BASE_URL` 을 실제 배포 주소로 지정해 빌드.

자세한 절차는 [docs/build-and-run.md](docs/build-and-run.md).

---

## 14. iOS 출시 준비

코드는 iOS를 막고 있지 않지만 **아직 빌드·검증하지 않았습니다.**
필요한 작업(플러그인 확인, 권한 문구, 폰트 라이선스, 다크 모드 확인 등)은
[docs/ios-port.md](docs/ios-port.md) 에 정리했습니다.

---

## 문서

| 문서 | 내용 |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | 계층 구조, 동기화 엔진, DB 스키마, 상태 관리 |
| [docs/competitor-audit.md](docs/competitor-audit.md) | 경쟁 앱 감사와 차용·기각 근거 |
| [docs/information-architecture.md](docs/information-architecture.md) | 새 IA(홈·발견·경기·마이야구·더보기) 시안 비교 |
| [docs/design-system.md](docs/design-system.md) | 토큰, 컴포넌트, 두 가지 정보 밀도, 접근성 |
| [docs/data-sources.md](docs/data-sources.md) | 원천별 라이선스 상태와 이용 근거 |
| [docs/connecting-an-official-api.md](docs/connecting-an-official-api.md) | 공식 API가 생겼을 때 전환 절차 |
| [docs/google-forms.md](docs/google-forms.md) | 제보·정정 폼 구성과 운영 |
| [docs/task-benchmarks.md](docs/task-benchmarks.md) | 대표 과업 경로와 측정값 |
| [docs/user-testing-plan.md](docs/user-testing-plan.md) | 사용성 점검 계획 (미수행) |
| [docs/build-and-run.md](docs/build-and-run.md) | Android 실행·빌드·문제 해결 |
| [docs/mobile-workflow.md](docs/mobile-workflow.md) | **폰에서만** 고치고 빌드하고 설치하기 |
| [docs/ios-port.md](docs/ios-port.md) | iOS 확장 절차 |
