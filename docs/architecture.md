# 아키텍처

## 1. 한 줄 요약

**로컬 SQLite가 유일한 원본**이고, 네트워크는 그 DB를 갱신하는 여러 수단 중
하나일 뿐입니다. 화면은 네트워크의 존재를 모릅니다.

```
원천 DTO
   ↓  Adapter — 원천마다 다른 필드 이름을 계약 형태로 맞춤
   ↓  Validator — 못 쓸 레코드를 여기서 걸러 격리
   ↓  Mapper — 도메인 모델로 변환
도메인 모델
   ↓  Sync Engine — 멱등 upsert, tombstone, 정정 기록
Drift · SQLite   ← 유일한 로컬 원본
   ↓  Repository — Stream<T> 만 노출
UI (Riverpod)
```

**UI는 Dio, JSON, URL, SQL을 직접 만지지 않습니다.** 이건 취향이 아니라
제약입니다. 이 선이 지켜지는 한 원천을 바꿔도 화면은 그대로입니다.
`docs/connecting-an-official-api.md` 의 전환 절차가 성립하는 이유가 이것입니다.

---

## 2. 계층별 위치

| 계층 | 위치 | 책임 |
| --- | --- | --- |
| 설정 | `lib/core/config/app_config.dart` | 모든 엔드포인트·플래그를 `--dart-define` 에서 읽음. 하드코딩된 주소 없음 |
| 원천 | `lib/data/sources/` | `SportsDataSource` 구현체들 |
| 어댑터 | `lib/data/sources/adapters/` | 허가 게이트가 걸린 원천 (WBAK·KBSA·WBSC·WPBL) |
| 봉투 | `lib/data/sources/payload_envelope.dart` | 모든 원천이 공유하는 정규화 형태 |
| 동기화 | `lib/data/sync/` | `SyncEngine`, `ContentSync`, 계약 타입 |
| DB | `lib/core/database/` | Drift 테이블 46개, 마이그레이션 |
| 저장소 | `lib/data/repositories/` | 쿼리 → `Stream<도메인 모델>` |
| 모델 | `lib/data/models/` | 도메인 타입, 출처, 관객 설정, 콘텐츠, 날씨, 기록 |
| 상태 | `lib/app/providers.dart` | Riverpod 의존성 그래프 전체 |
| 화면 | `lib/features/<영역>/` | 화면 24개 |
| 디자인 | `lib/core/design_system/` | 토큰, 타이포, 테마, 컴포넌트 |

---

## 3. 원천 인터페이스

```dart
abstract class SportsDataSource {
  String get sourceName;
  String get displayName;
  bool get isEnabled;

  Future<SyncPage<OrganizationDto>> fetchOrganizations(SyncRequest request);
  Future<SyncPage<TeamDto>>         fetchTeams(SyncRequest request);
  Future<SyncPage<CompetitionDto>>  fetchCompetitions(SyncRequest request);
  Future<SyncPage<VenueDto>>        fetchVenues(SyncRequest request);
  Future<SyncPage<GameDto>>         fetchGames(GameSyncRequest request);
  Future<SyncPage<StandingDto>>     fetchStandings(SyncRequest request);
  Future<SyncPage<ArticleDto>>      fetchArticles(SyncRequest request);
  Future<SyncPage<VideoDto>>        fetchVideos(SyncRequest request);
  Future<SyncPage<PersonDto>>       fetchPeople(SyncRequest request);
  Future<SyncPage<RosterEntryDto>>  fetchRoster(SyncRequest request);
}
```

구현체는 다섯 종류입니다.

| 구현체 | 상태 | 용도 |
| --- | --- | --- |
| `BundledSeedDataSource` | 항상 켜짐 | 앱에 번들된 seed. 마지막 안전망 |
| `StaticManifestDataSource` | URL이 있을 때 | `version.json` 기반 정적 배포본 |
| `FutureRestApiDataSource` | `WB_API_TRANSPORT=rest` | 미래 공식 REST API |
| `FutureGraphqlDataSource` | `WB_API_TRANSPORT=graphql` | 미래 공식 GraphQL API |
| 허가 게이트 어댑터 4종 | **기본 꺼짐** | WBAK·KBSA·WBSC·WPBL |

`dataSourcesProvider` 가 이 순서대로 배열을 만듭니다. 앞이 실패하면 뒤가 답합니다.
seed가 마지막인 이유는, 앞의 어떤 것도 없을 때 **빈 화면 대신 무언가**를
보여주기 위해서입니다.

### 공유 봉투

원천이 무엇이든 결국 `PayloadEnvelope` 한 형태로 정규화됩니다.

```dart
class PayloadEnvelope {
  final List<Object?> items;
  final int schemaVersion;
  final SyncPayloadKind payloadKind;   // snapshot | delta
  final String? dataVersion;
  final DateTime? generatedAt;
  final bool hasMore;
  final SyncCursor? nextCursor;
  final List<String> tombstones;
}
```

`payloadKind` 가 핵심입니다. **스냅샷일 때만** 목록에 없는 레코드를 삭제로
간주합니다. 델타를 스냅샷으로 오해하면 매번 DB가 비워집니다 — 계약 동등성
테스트(`test/contract/adapter_equivalence_test.dart`)가 이걸 막습니다.

---

## 4. 동기화 엔진

`SyncEngine.refreshAll()` → 원천별 `refreshSource()` → 엔티티별 `_syncPaged()`.

지키는 규칙:

1. **멱등** — 같은 페이로드를 두 번 적용해도 결과가 같습니다.
2. **하드 삭제 없음** — 사라진 레코드는 tombstone으로 표시만 합니다.
   되돌릴 수 없는 동작을 자동화에 맡기지 않습니다.
3. **레코드 단위 격리** — 검증에 실패한 레코드는 사유와 함께 quarantine으로
   가고, 같은 배치의 나머지는 정상 반영됩니다. 하나 때문에 전부 막히지 않습니다.
4. **원천 단위 실패 격리** — 한 원천이 죽어도 다른 원천은 계속 갱신됩니다.
5. **정정 기록** — 경기 결과가 바뀌면 `_recordGameChanges()` 가 무엇이 어떻게
   바뀌었는지 남깁니다. "어제 본 점수와 다른데?"에 답할 수 있어야 합니다.
6. **스키마 버전 거부** — 계약 범위(현재 1..1) 밖이면 아예 받지 않습니다.
7. **재개 가능** — 커서를 저장하므로 중간에 끊겨도 이어서 받습니다.
8. **충돌 해결** — `SourcePolicy.challengerWins` 등 원천 우선순위 규칙으로
   같은 레코드의 서로 다른 값 중 무엇을 채택할지 결정합니다.

네트워크 계층(`lib/core/network/`)은 회로 차단기와 지터 백오프를 갖고 있고,
서버가 `Retry-After` 를 주면 그 값을 따릅니다. 무한 재시도로 남의 서버를
때리지 않습니다.

---

## 5. 데이터베이스

Drift, 테이블 46개. 스키마 버전 **2**.

- **v1** — 스포츠 코어(단체·팀·경기장·대회·경기·순위·선수·로스터),
  뉴스·영상, 동기화 기록, 사용자 소유 데이터(팔로우·저장·예약 알림)
- **v2** — 발견 계층(화제 주제·프로그램·시즌·회차·리캡·이야기 묶음·가이드·
  예보), `articles.story_cluster_id`, `standings.previous_rank`

모든 동기화 테이블은 두 mixin을 씁니다.

- `ProvenanceColumns` — 원천 이름·URL·수집 시각·라이선스 상태·`is_demo`
- `ContentMetaColumns` — `summary_method`, `review_status`, `spoiler_level`

**출처를 컬럼으로 강제한 것이 핵심 설계 결정입니다.** 출처 없는 레코드를 넣는
경로 자체가 없습니다.

마이그레이션 v1→v2는 순수 추가(additive)이며, 팔로우·저장·예약 알림이 보존되는
것을 `test/unit/migration_test.dart` 가 확인합니다.
`clearSyncedData()` 는 동기화된 행만 지우고 사용자 소유 행은 남깁니다.

### 한국어 검색

`search_key` 컬럼에 정규화형과 초성을 함께 저장합니다. 그래서 `ㅅㅇ` 로 `서울` 이
찾아집니다. 같은 규칙이 `lib/core/utils/` 의 Dart 구현과
`scripts/normalize/normalize.py` 의 Python 구현 양쪽에 있고, 두 구현이 같은
답을 내는지 `test/unit/korean_text_test.dart` 가 확인합니다.

### 시간

**저장은 UTC, 표시는 Asia/Seoul.** `lib/core/utils/kst.dart` 가 유일한 변환
지점입니다. 월별·일별 조회를 위해 `monthKey` / `dayKey` 를 비정규화해 저장합니다.

주의할 함정 하나: `Kst.toKst()` 는 한국 벽시계 시각을 담은 **UTC 플래그 인스턴트**를
돌려줍니다. 그 값으로 계산할 때 `DateTime()` 을 쓰면 기기 시간대가 섞여 결과가
어긋납니다. 반드시 `DateTime.utc(...)` 로 만들어야 합니다. 방해 금지 시간
계산에서 실제로 알림이 조용히 사라졌던 버그가 여기서 나왔습니다.

---

## 6. 상태 관리

Riverpod 3 (`Notifier` / `NotifierProvider`), 라우팅은 go_router 17의
`StatefulShellRoute.indexedStack` — 탭별 상태가 유지됩니다. 경기 탭에서 필터를
걸고 다른 탭에 갔다 와도 필터가 살아 있는 이유입니다
(`test/widget/task_benchmark_test.dart` 가 확인).

### family 키 규칙 (중요)

**family 키로 쓰는 타입은 반드시 값 동등성(`==`/`hashCode`)을 가져야 합니다.**
동일성만 있는 키는 리빌드마다 새 provider를 만들어, 캐시 낭비가 아니라
**무한 리빌드 루프**가 됩니다. 실제로 세 번 밟았습니다.

- `GameQuery`, `TeamQuery` — `ListEquality` 를 쓴 `==` 추가
- `weatherRisksProvider` — `Map` 키를 `WeatherRiskQuery` 값 타입으로 교체
- 키 안의 시각 — `Kst.quantize()` / `Kst.hourBucket()` 으로 양자화.
  날것의 `DateTime.now()` 를 키에 넣으면 매 프레임 새 키가 됩니다.

---

## 7. 화면 계층

5탭 셸: **홈 · 발견 · 경기 · 마이야구 · 더보기**.
근거와 대안 비교는 `docs/information-architecture.md`.

- 검색은 모든 주요 화면의 앱바에 있습니다 — 어디서든 1탭.
- 홈 모듈 순서는 `AudienceMode` 에 따라 달라지고, 사용자가 다시 정렬할 수 있으며
  접을 수 있습니다.
- 스포일러 정책은 카드·상세·알림에 **전부** 적용됩니다. 한 곳만 가리면 의미가
  없습니다.

---

## 8. 알림

세 조각으로 나뉘어 있고, 각 조각이 다른 이유로 존재합니다.

| 조각 | 위치 | 책임 |
| --- | --- | --- |
| `NotificationPlanner` | `core/platform/notification_service.dart` | **무엇을** 알릴지. 순수 함수 — 리드 타임, 방해 금지 시간, 취소·연기 억제, 스포일러 마스킹 |
| `NotificationScheduler` | `core/platform/notification_scheduler.dart` | **어떤 경기가** 대상인지. 팔로우한 팀 + 개별 저장한 경기 |
| `LocalNotificationService` | `core/platform/notification_service.dart` | **어떻게** 예약할지. 플랫폼 플러그인, 30일 창, 멱등 reconcile |

플래너가 순수한 덕분에 스케줄링 규칙 전체가 플러그인이나 DB 없이 단위 테스트
가능합니다. 스케줄러는 그 순수 함수와 실제 데이터 사이의 이음매이고,
`test/unit/notification_scheduler_test.dart` 가 그 이음매만 따로 검증합니다.

### 전체 reconcile, 부분 수정 아님

일정이 바뀔 때마다 **전체 스케줄을 다시 계산**해서 넘깁니다. 증분 수정은 매번
정확해야 맞지만, 전체 reconcile은 **실행되기만 하면** 맞습니다. 사용자가 부재를
알아채는 종류의 기능에서는 후자가 안전한 방향입니다.

### 무엇이 재계산을 유발하는가

`scheduledNotificationCountProvider` 를 **watch 하는 것이 곧 예약**입니다.
팔로우·저장·알림 설정 중 하나라도 바뀌면 provider가 무효화되고 다시 계산됩니다.
어떤 화면도 "팔로우를 바꿨으니 재예약을 호출해야지"를 기억할 필요가 없습니다 —
그건 모든 화면이 결국 잊어버리는 종류의 일입니다.

셸이 `ref.listen` 으로 이 provider를 세션 내내 살려둡니다.

### 함정 하나

아무것도 팔로우·저장하지 않았을 때 **조회를 아예 하지 않습니다.**
`GameQuery.teamIds` 가 비어 있으면 "모든 팀"을 뜻하므로, 그냥 조회하면
리그의 모든 경기에 알림이 걸립니다. 최적화가 아니라 정확성 문제입니다.

---

## 9. 분석

`AnalyticsService` 인터페이스와 이벤트 20종이 있고, 기본 구현은
`LocalAnalyticsService` — **기기 안에만 기록**합니다. 아무것도 전송하지 않습니다.
`NoopAnalyticsService` 도 있습니다.

외부 SDK를 붙이려면 동의 흐름과 개인정보처리방침이 먼저 있어야 합니다.
인터페이스를 미리 둔 것은, 나중에 급하게 SDK를 넣으면서 호출 지점을 코드 전체에
흩뿌리는 일을 막기 위해서입니다.

---

## 10. 테스트 구조

| 파일 | 검증 대상 |
| --- | --- |
| `test/unit/korean_text_test.dart` | 초성 추출, 정규화, Dart·Python 구현 일치 |
| `test/unit/dto_validation_test.dart` | 못 쓸 레코드가 격리되는지 |
| `test/unit/sync_engine_test.dart` | 페이지네이션, 증분, 멱등성, tombstone, 정정, 실패 격리, 스키마 거부, 재개 |
| `test/unit/migration_test.dart` | v1→v2에서 사용자 데이터 보존 |
| `test/unit/weather_horizon_test.dart` | 예보 가능 범위 밖을 만들어내지 않는지 |
| `test/unit/rules_test.dart` | 순위표 규정 충족, 알림 계획, 회로 차단기, WebView 허용 목록, 스포일러 |
| `test/unit/notification_scheduler_test.dart` | 어떤 경기가 예약 대상이 되는지 |
| `test/contract/adapter_equivalence_test.dart` | 정적 파일과 페이지네이션 REST가 **같은 도메인 지문**을 만드는지 |
| `test/widget/screens_test.dart` | 화면 렌더링, 4가지 화면 크기, 넘침 없음, 스폰서 비활성 |
| `test/widget/density_test.dart` | 두 정보 밀도의 규약 |
| `test/widget/task_benchmark_test.dart` | 대표 과업 10종의 탭 수·스크롤 수 측정 |
| `test/screenshots/capture_test.dart` | 리뷰용 스크린샷 21장 (CI 제외) |

계약 동등성 테스트가 특히 중요합니다. 원천을 바꿔도 화면이 그대로라는 주장을
**말이 아니라 테스트로** 뒷받침합니다.
