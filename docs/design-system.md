# 디자인 시스템

## 1. 컨셉

**"현대 스포츠 에디토리얼 + 야구 기록지의 정확함"**

의도적으로 피한 것 두 가지:

- **여성 스포츠의 분홍·리본 관용구.** 여자야구 앱이라는 이유로 색을 바꾸는 것은
  경기를 덜 진지하게 다루는 신호가 됩니다.
- **베팅 앱의 네온 그라데이션.** 자극적인 색은 숫자의 신뢰도를 깎습니다.

권위는 타이포그래피, 넉넉한 여백, 절제된 잉크·네이비·바탕과 소수의 기능색에서
나옵니다. (바탕의 색 온도는 2026-09-02 개정 — 아래 `canvas` 항목 참고.)

---

## 2. 토큰

`lib/core/design_system/tokens.dart`

### 색

| 토큰 | 값 | 용도 |
| --- | --- | --- |
| `ink` | `#111827` | 본문 |
| `navy` | `#14213D` | 강조 헤더, 선택 상태 |
| `canvas` | `#F6F7F8` | 배경 (순백이 아닌 차가운 중립 회백) |
| `surface` | `#FFFFFF` | 카드 |
| `coral` | `#F05D5E` | 행동, 주의 |
| `teal` | `#168A86` | 검증됨, 성공 |
| `gold` | `#D7A83E` | 하이라이트 |

**`canvas` 개정 이력 (2026-09-02).** 원래 값은 `#F7F5F0` — 순백을 피하되 종이
느낌의 **따뜻한 미색(파치먼트)** 을 의도적으로 골랐던 결정이었다 (당시엔 옳은
선택이었다). 리멤버(직장인 명함 앱)를 참고로 한 3단계 재작업의 마지막 단계에서,
참고 화면과 우리 앱의 남은 차이가 바탕의 **색 온도** 하나뿐임을 확인하고
`#F6F7F8`(차가운 중립 회백)로 바꿨다. 1·2단계에서 넣은 타이포 굵기 차이와 숫자
스트립은 차가운 바탕 위에서 완성되는 문법이라, 이 3단계까지 와야 인상이 실제로
바뀐다. 함께 움직인 값: `canvasRaised` `#FFFDF9→#FBFCFD` (따뜻한 흰색을 차가운
새 바탕 위에 두면 누렇게 떠 보이므로 같이 이동), `WbSemanticColors.light.skeleton`
(`theme.dart`) `#ECE9E2→#EBEDEF`. **`ink`·`navy`·`coral`·`teal`·`gold`·`muted`·
`divider`, 그리고 다크 테마 전 항목은 이 개정에서 변경하지 않았다.** "순백이
아닌 바탕" 이라는 원칙 자체는 유지된다 — 바뀐 것은 그 바탕이 따뜻한지 차가운지
뿐이다.

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

`Pretendard`(v1.3.9, SIL OFL 1.1) 다섯 굵기(400/500/600/700/800)를
`assets/fonts/` 에 번들합니다 — 릴리스 APK가 +6,420,430바이트(약 6.12MiB)
늘어나는 대가로, 기기마다 다른 안드로이드 한국어 시스템 폰트(또는 그 부재)에
기대지 않고 모든 기기에서 같은 얼굴로 렌더링됩니다. `Noto Sans KR` / `Apple SD
Gothic Neo` / `Malgun Gothic` / `sans-serif` 폴백은 번들 후에도 남겨 두는데,
이는 Pretendard 로딩 실패 대비가 아니라 **글자 단위** 폴백입니다 — Pretendard의
한글·라틴 범위 밖의 한자(漢字)나 동기화된 기사 제목에 섞여 들어올 수 있는
기호·이모지가 그 대상입니다. **점수와 기록은 tabular figures** — 숫자 폭이
고정되지 않으면 표에서 자릿수가 흔들립니다. `WbClamp` 이 줄 수 상한을 담당합니다.
자세한 근거는 `lib/core/design_system/typography.dart` 머리 주석 참고.

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
- **글자 확대**는 0.85~2.0배로 제한합니다 (Android 접근성 글자 설정이 닿는
  상한). 예전에는 1.4배에서 막았지만, 그 상한은 필요한 사람에게 필요한
  크기를 감추는 것이었지 넘침을 없애는 게 아니었다 — 지금은 `Row` 를
  `Wrap` 으로 바꾸는 식으로 레이아웃 쪽에서 해결합니다.
- **넘침 검사**: `expectNoOverflow` (`test/widget/harness.dart`) 로 홈·경기
  목록을 360×640/412×915/480×1040/360×640@130% 에서, 경기 상세를 360×640 @
  1.0/1.4/2.0배에서 검사합니다. `text_scale_probe_test.dart` 는 홈·경기·
  마이야구·경기 상세를 360dp 에서 1.3/1.4/1.7/2.0배로 검사합니다. 둘 다
  `scrollToEnd` 로 끝까지 스크롤한 뒤 잽니다 — `CustomScrollView` 는 뷰포트
  밖 sliver 를 build 하지 않으므로, 스크롤 없이는 화면 아래쪽이 사각지대로
  남습니다. 하네스로 띄울 수 있는 화면만 포함되어 있고, 그 밖의 화면은 아직
  없습니다.
- **스크린리더 라벨** — 점수는 "3 대 1"처럼 읽히도록 의미 라벨을 붙입니다.
  숫자만 나열하면 무엇 대 무엇인지 알 수 없습니다.
- **애니메이션 축소** 설정을 존중합니다.
- 다크 테마는 반전이 아니라 별도 표면 계층입니다.

---

## 6. 스크린샷

`flutter test --tags screenshots --update-goldens` → `docs/screenshots/` 31장.

CI에서는 제외합니다. **리뷰 자료이지 회귀 게이트가 아닙니다** — 이는 정책
결정이며, 픽셀이 재현 가능한지와는 별개입니다.

**2026-09-02 개정.** 예전엔 이 절이 "호스트 폰트에 따라 픽셀이 달라진다" 고
적혀 있었다. 그 근거였던 결함(`test/screenshots/capture_test.dart` 의
`_loadKoreanFont`)을 재현해 보니, 원인으로 지목됐던 "`malgun.ttf`/
`malgunbd.ttf` 를 같은 family 에 등록하는 순서가 매 실행 흔든다" 는 가설은
틀렸다 — Flutter `FontLoader.load()` 는 `addFont` 호출 순서대로 순차적으로
`await` 하지 등록 완료 순서로 하지 않는다(`packages/flutter/lib/src/
services/font_loader.dart` 확인). 같은 커밋(HEAD)을 20회 이상 다시 캡처해도
흔들리지 않았다 — 다만 **그 결과가 저장소에 커밋된 골든과는 항상 달랐다**,
왜 다른지는 끝내 특정하지 못했다(코드는 골든이 마지막으로 갱신된 시점 이후
바뀌지 않았음을 확인함).

원인은 못 밝혔지만 재발은 막았다: `_loadKoreanFont` 가 이제 **번들된
Pretendard**(`assets/fonts/`, 저장소에 커밋되어 모든 호스트·CI에 동일하게
존재)를 `Pretendard` family 로 먼저 등록하고, 시스템 한국어 폰트(Windows의
Malgun Gothic 등)는 `Pretendard` 가 커버 못 하는 글자(한자·일부 기호/이모지)
전용 폴백 family 에만 등록한다 — 절대 `Pretendard` 에 같이 넣지 않는다. 지금
캡처되는 화면은 전부 한글·라틴·숫자뿐이라 실제로 시스템 폰트에 기대는 글자가
없고, 그래서 **이 31장은 이제 호스트 독립적**이다(10회 연속 재캡처, 픽셀
동일 확인). 화면에 한자·이모지가 들어가는 날이 오면 그 글자만 다시 호스트
의존적이 된다 — 리눅스 CI 에는 `malgun.ttf` 가 없으므로. **CI 제외는 정책으로
남아 있다** — 게이트로 승격할지는 별도 결정 사항.
