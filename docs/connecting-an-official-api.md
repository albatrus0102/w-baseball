# 공식 API가 생겼을 때 전환하는 방법

WBAK·KBSA가 공식 API나 정기 CSV를 제공하기 시작하면, **화면 코드를 한 줄도
고치지 않고** 그 원천으로 갈아탈 수 있어야 합니다. 이 문서는 그 절차입니다.

전제: UI는 `Stream<도메인 모델>` 만 봅니다. Dio·JSON·URL·SQL을 모릅니다.
그래서 갈아끼우는 지점이 원천 계층 하나입니다.

---

## 0. 먼저 확인할 것 (코드 이전)

- [ ] 서면 이용허락 또는 공개 이용약관이 있는가?
- [ ] 요청 한도와 간격 제한이 문서화돼 있는가?
- [ ] 스키마가 문서화돼 있는가, 아니면 관찰로 추측해야 하는가?
- [ ] 개인정보가 섞여 오는가? (선수 연락처·생년월일 등)
- [ ] 그 근거를 `docs/data-sources.md` 에 기록했는가?

마지막 항목을 건너뛰지 마세요. 반년 뒤에 "이거 왜 켜져 있지?"를 답할 수 있어야
합니다.

---

## 1. 어댑터 구현

**파일**: `lib/data/sources/adapters/permission_gated_adapters.dart`

이미 `WbakAdapter` 골격이 있습니다. `PermissionGatedAdapter` 를 상속하고
`enabled` 가 `false` 인 상태로 존재합니다. 할 일은 세 가지입니다.

```dart
final class WbakAdapter extends PermissionGatedAdapter {
  @override
  String get sourceName => 'wbak';

  @override
  Set<SyncEntityType> get supportedEntities => enabled
      ? const <SyncEntityType>{SyncEntityType.game, SyncEntityType.team, ...}
      : const <SyncEntityType>{};   // 꺼져 있으면 엔진이 부를 것이 없음

  @override
  Future<SyncPage<GameDto>> fetchGames(GameSyncRequest request) async {
    // 1. HTTP 호출 (lib/core/network/ 의 클라이언트 사용 — 회로 차단기 포함)
    // 2. 원천 필드를 GameDto 로 매핑
    // 3. PayloadEnvelope 로 감싸기 — payloadKind 를 정확히 선언할 것
  }
}
```

### 반드시 지킬 것

| 항목 | 이유 |
| --- | --- |
| `payloadKind` 를 정확히 | 델타를 스냅샷으로 선언하면 매 동기화마다 DB가 비워집니다 |
| 모든 DTO에 `Provenance` | 출처 없는 레코드는 저장 경로가 없습니다 |
| `isDemo: false` | 실제 데이터임을 명시 |
| 시각은 UTC로 | 저장은 UTC, 표시만 KST |
| 페이지네이션은 커서로 | 중간에 끊겨도 재개할 수 있어야 합니다 |
| 못 쓸 레코드는 **던지지 말고 격리** | 하나 때문에 배치 전체가 막히면 안 됩니다 |
| 직접 네트워크 클라이언트를 만들지 말 것 | `lib/core/network/` 를 쓰면 회로 차단기·백오프·`Retry-After` 를 공짜로 얻습니다 |

---

## 2. 플래그와 순서 조정

**파일**: `lib/core/config/app_config.dart`

```
WB_FLAG_ADAPTER_WBAK=true
```

**파일**: `lib/app/providers.dart` → `dataSourcesProvider`

현재 순서:

```
FutureRestApi → FutureGraphql → (허가된 어댑터) → 정적 매니페스트 → 번들 seed
```

공식 API를 **정적 매니페스트보다 앞에** 두면, API가 살아 있을 때는 API를 쓰고
죽으면 정적 배포본으로 내려갑니다. seed는 계속 마지막입니다 — 어떤 경우에도
빈 화면을 보여주지 않기 위해서입니다.

---

## 3. 테스트 — 이 순서로

**순서가 중요합니다.** 앞 단계가 실패하면 뒤 단계는 의미가 없습니다.

### 3-1. DTO 검증

```bash
flutter test test/unit/dto_validation_test.dart
```

새 원천이 보내는 이상한 값(빈 id, 음수 점수, 잘못된 시각)이 **격리되는지**
확인합니다. 통과하는지가 아니라 **제대로 걸러지는지**를 봅니다.

### 3-2. 동기화 엔진

```bash
flutter test test/unit/sync_engine_test.dart
```

멱등성, tombstone, 정정 기록, 실패 격리, 재개.
같은 페이로드를 두 번 넣어 결과가 같은지 반드시 확인하세요.

### 3-3. 계약 동등성 — **가장 중요**

```bash
flutter test test/contract/adapter_equivalence_test.dart
```

이 테스트는 정적 파일 원천과 페이지네이션 REST 원천이 **같은 도메인 지문**을
만드는지 봅니다. 새 어댑터를 이 테스트에 추가하세요. 통과하면 "원천을 바꿔도
화면이 같다"가 주장이 아니라 사실이 됩니다.

### 3-4. 화면

```bash
flutter test --exclude-tags screenshots
```

화면 코드를 안 고쳤으면 여기서 아무것도 깨지지 않아야 합니다.
**뭔가 깨졌다면 계층 경계가 새고 있다는 뜻입니다** — 어댑터를 고칠 게 아니라
경계를 고치세요.

### 3-5. 실기기

```bash
flutter run --dart-define=WB_FLAG_ADAPTER_WBAK=true
```

기내 모드로 껐다 켜보고, 동기화 도중 네트워크를 끊어보고, 같은 데이터를 두 번
받아보세요.

---

## 4. 점진 배포

한 번에 전부 바꾸지 마세요.

1. **읽기 전용 비교** — 새 원천을 켜되 기록만 하고 DB에는 쓰지 않게 해서,
   기존 데이터와 얼마나 다른지 봅니다.
2. **엔티티 하나씩** — 팀 → 경기장 → 대회 → 경기 → 순위 순.
   경기가 가장 복잡하므로 마지막에서 두 번째입니다.
3. **전체 전환.**

---

## 5. 롤백

**즉시 되돌리는 방법 (앱 재배포 없이):**

```bash
WB_FLAG_ADAPTER_WBAK=false
```

플래그를 끄면 다음 순위 원천(정적 매니페스트)이 답합니다. **DB는 그대로**입니다 —
하드 삭제를 하지 않기 때문에 잘못 들어온 데이터도 tombstone 상태로 남아 있고,
정적 배포본이 덮어씁니다.

**데이터가 오염됐을 때:**

```bash
python scripts/validate/validate_data.py public-data
```

`publish-data.yml` 은 게시 전에 `public-data` 를 백업하고, 검증이 실패하면
자동으로 이전 상태로 되돌립니다. 마지막 정상 데이터가 계속 서비스됩니다.

**앱 쪽에서 완전 초기화가 필요할 때:**

`clearSyncedData()` 는 동기화된 행만 지우고 팔로우·저장·예약 알림은 남깁니다.
사용자가 자기 손으로 넣은 것을 잃지 않습니다.

**스키마가 바뀌었을 때:**

`DataContractConfig` 의 최소·최대 스키마 버전(현재 1..1)을 올리기 전에,
구버전 앱이 새 페이로드를 거부하는지 확인하세요. 거부가 정상 동작입니다 —
구버전이 새 데이터를 잘못 해석하는 것보다 안 받는 편이 낫습니다.

---

## 6. 흔한 함정

| 증상 | 원인 |
| --- | --- |
| 동기화할 때마다 데이터가 사라짐 | 델타를 `snapshot` 으로 선언 |
| 같은 경기가 두 개 | `Game.dedupeKey()` 가 구분 못 하는 id 체계 |
| 화면이 무한 리빌드 | family 키에 값 동등성이 없거나, 키 안에 날것의 `DateTime.now()` |
| 알림이 조용히 안 옴 | KST 계산에 `DateTime()` 사용 — `DateTime.utc()` 여야 함 |
| 배치 전체 실패 | 어댑터가 예외를 던짐. 격리해야 함 |
| 시각이 9시간 어긋남 | 저장할 때 KST로 저장. 저장은 항상 UTC |
