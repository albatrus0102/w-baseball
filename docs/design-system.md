# 디자인 시스템

## 1. 컨셉

**"현대 스포츠 에디토리얼 + 야구 기록지의 정확함"**

의도적으로 피한 것 두 가지:

- **여성 스포츠의 분홍·리본 관용구.** 여자야구 앱이라는 이유로 색을 바꾸는 것은
  경기를 덜 진지하게 다루는 신호가 됩니다.
- **베팅 앱의 네온 그라데이션.** 자극적인 색은 숫자의 신뢰도를 깎습니다.

권위는 타이포그래피, 넉넉한 여백, 절제된 잉크·네이비·미색 바탕과 소수의 기능색에서
나옵니다.

---

## 2. 토큰

`lib/core/design_system/tokens.dart`

### 색

| 토큰 | 값 | 용도 |
| --- | --- | --- |
| `ink` | `#111827` | 본문 |
| `navy` | `#14213D` | 강조 헤더, 선택 상태 |
| `canvas` | `#F7F5F0` | 배경 (순백이 아닌 미색) |
| `surface` | `#FFFFFF` | 카드 |
| `coral` | `#F05D5E` | 행동, 주의 |
| `teal` | `#168A86` | 검증됨, 성공 |
| `gold` | `#D7A83E` | 하이라이트 |

색은 `WbColors` 를 직접 쓰지 않고 **`WbSemanticColors` ThemeExtension**을 거칩니다
(`WbTheme.of(context)`). 그래서 다크 테마가 단순 반전이 아니라 표면 계층을
재구성할 수 있습니다.

### 간격

4dp 배수: `xxs 2 · xs 4 · sm 8 · md 12 · lg 16 · screen 20 · xl 24 · section 32 · xxl 40`.
화면 좌우 여백은 `screen`(20).

### 크기·모서리·시간

- `WbSize.minTap = 48` — **어떤 밀도에서도 줄어들지 않습니다.**
- `WbRadius` — 카드/칩/배지
- `WbDuration` — `instant 90 · quick 180 · standard 220 · slow 240` (ms)
  `WbTheme.duration()` 은 `MediaQuery.disableAnimationsOf` 를 존중합니다.
  애니메이션을 끈 사용자에게는 0이 됩니다.

### 타이포그래피

`Pretendard` + 한국어 폴백. **점수와 기록은 tabular figures** — 숫자 폭이
고정되지 않으면 표에서 자릿수가 흔들립니다. `WbClamp` 이 줄 수 상한을 담당합니다.

---

## 3. 하나의 시스템, 두 가지 정보 밀도

이 앱은 두 사람을 동시에 상대합니다. 처음 보는 사람에게는 카드 하나에 여백과
설명이 필요하고, 훈련 전에 여섯 경기를 확인하는 선수에게는 그 여섯이 한 화면에
들어와야 합니다. 한쪽을 잘 하려고 다른 쪽을 해치는 것이 이 열거형이 막으려는
실패입니다.

```dart
enum WbDensity { comfortable, compact }
```

| 속성 | `comfortable` | `compact` |
| --- | --- | --- |
| `cardPadding` | 16 전방향 | 12 / 12 |
| `rowPadding` | 16 / 12 | 12 / 8 |
| `sectionGap` | 32 | 20 |
| `blockGap` | 16 | 12 |
| `rowGap` | 8 | 4 |
| `listRowMinHeight` | 72 | 56 |
| `showsSecondaryLine` | true | false |

### 밀도가 바꿔도 되는 것 / 안 되는 것

**되는 것**: 패딩, 간격, 행 높이, *설명* 줄의 표시 여부.

**안 되는 것**: 어떤 컴포넌트를 쓰는지, 색 체계, 라벨 문구,
**어떤 정보에 닿을 수 있는지**.

`showsSecondaryLine` 은 *설명*(출처 문장을 풀어 쓴 형태, 초보용 부연)만
담당합니다. 경기장 이름이나 경기 상태 같은 **사실 정보는 두 밀도 모두에서
보입니다.** 표시 설정 뒤에 데이터를 숨기면 그건 표시 설정이 아니라 기능 차단입니다.

최소 탭 크기는 두 밀도가 동일합니다. **조밀 모드는 여백에서 공간을 벌지,
누를 수 있는 크기에서 벌지 않습니다.**

이 규약은 문장이 아니라 테스트입니다 (`test/widget/density_test.dart`):

- `listRowMinHeight >= WbSize.minTap` — 두 밀도 모두
- 조밀 모드가 실제로 더 조밀한지 (모든 간격 값 비교)
- **같은 화면을 두 밀도로 렌더링해 보이는 텍스트를 비교** — 조밀 모드에서
  사라진 문자열이 있으면 실패

### 전달 방식

밀도는 호출 지점마다 `bool` 을 넘기지 않고 **컨텍스트로 내려갑니다.**

```dart
WbDensityScope.of(context)   // 없으면 comfortable
```

`WbDensityHost` 가 라우터 위에 있어서, 전체 화면 라우트(검색·상세)도 자기가
출발한 탭과 같은 밀도를 갖고, 밀도를 바꾸면 모든 화면이 한 번에 다시 그려집니다.
손으로 넘기는 불리언은 새 위젯이 참여를 강제받지 않기 때문에 결국 두 밀도가
갈라집니다.

### 기본값과 사용자 선택

| 모드 | 기본 밀도 |
| --- | --- |
| `discover` (알아가는 중) | `comfortable` |
| `player` (하고 있어요) | `compact` |
| `both` (둘 다) | `comfortable` |

설정 → **보기 밀도** 에서 사용자가 직접 고를 수 있습니다.
**한 번 고르면 모드를 바꿔도 그 선택이 유지됩니다** (`densityOverride`).
모드 변경이 사용자의 명시적 선택을 조용히 덮으면, 각 동작은 "맞게" 작동해도
사용자에게는 버그로 읽힙니다. "모드 기본값으로 되돌리기" 버튼으로 언제든
되돌릴 수 있습니다.

비교 스크린샷: `docs/screenshots/home_density_comfortable_regular_412x915.png`,
`docs/screenshots/home_density_compact_regular_412x915.png` — 같은 데이터,
조밀 모드에서 한 모듈이 더 들어옵니다.

---

## 4. 컴포넌트

`lib/core/design_system/components/`

### 기본 (`primitives.dart`)

- **`WbCard`** — 액센트 레일이 `Positioned` 오버레이입니다.
  `Row(crossAxisAlignment: stretch)` 는 높이 제약을 요구해 무한 높이 오류를 내고,
  한 변만 색이 다른 `Border` 는 반지름을 가질 수 없습니다. 두 문제를 모두 피하려면
  단일 비배치 자식으로 크기가 정해지는 `Stack` 이어야 합니다. (둘 다 실제로
  밟은 뒤 도달한 형태입니다.)
- **`WbBadge`** — 라벨이 `Flexible` + 말줄임. 360dp에서 넘치지 않습니다.
- **`WbSkeleton`**, **`WbEmptyState`**, **`WbTapTarget`**, **`WbFilterChip`**,
  **`WbTeamMark`**

### 출처 (`provenance_widgets.dart`)

- **`WbSourceLine`** — 원천·수집 시각·링크. 밀도를 따릅니다.
- **`WbSummaryMethodBadge`** — 이 요약이 API 설명인지, 템플릿인지, 사람이 쓴
  것인지.
- **`WbCoverageNote`** — 이 데이터가 어디까지 덮는지. 없는 것을 없다고 말하는
  자리입니다.
- **`WbSpoilerVeil`** — 결과를 가립니다. 짧은 카드에서 넘치지 않도록
  `FittedBox(scaleDown)`.
- **`WbExplainer`** — 초보용 부연. `showBeginnerExplanations` 를 따릅니다.

### 경기 (`game_widgets.dart`)

- **`WbHeroGameCard`** — 홈 최상단. 현역 모드에서 1탭 목표 지점.
- **`WbGameRow`** — 목록 행. 밀도를 따릅니다.
- **`WbGameStatusBadge`**, **`WbWeatherRiskBadge`**, **`WbGameRowSkeleton`**

---

## 5. 접근성

- **최소 탭 48dp** — 밀도와 무관.
- **글자 확대**는 0.85~1.4배로 제한합니다. 1.4배를 넘으면 360dp 화면에서
  줄바꿈을 해도 점수표가 들어가지 않습니다. 핵심 정보가 잘리게 두느니 상한을
  둡니다.
- **4가지 화면 크기에서 넘침 검사**: 360×640, 412×915, 480×1040, 360×640 @130%.
- **스크린리더 라벨** — 점수는 "3 대 1"처럼 읽히도록 의미 라벨을 붙입니다.
  숫자만 나열하면 무엇 대 무엇인지 알 수 없습니다.
- **애니메이션 축소** 설정을 존중합니다.
- 다크 테마는 반전이 아니라 별도 표면 계층입니다.

---

## 6. 스크린샷

`flutter test --tags screenshots --update-goldens` → `docs/screenshots/` 21장.

CI에서는 제외합니다. 호스트 폰트에 따라 픽셀이 달라지므로 픽셀 차이로 빌드를
막는 것은 잘못된 신호입니다. **리뷰 자료이지 회귀 게이트가 아닙니다.**
