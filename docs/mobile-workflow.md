# 폰에서 작업하기

이 저장소는 **로컬에 Flutter가 없어도 굴러가도록** 구성돼 있습니다. 빌드·테스트·
데이터 수집이 전부 GitHub Actions에서 돌기 때문에, 폰에서 할 수 있는 일은
"코드를 고치고 결과를 확인하는 것" 전부입니다.

빌드는 못 합니다. 대신 **빌드를 시키고 결과물을 받을 수** 있습니다.

---

## 1. 한 번만 하는 준비

### 저장소 만들기

GitHub 앱이나 모바일 브라우저에서:

1. **New repository**
2. 이름 `w-baseball`
3. **README·.gitignore·라이선스를 추가하지 마세요** — 이미 커밋이 있어서
   충돌합니다
4. Private / Public 은 아래 「공개 여부」를 보고 정하세요

만든 뒤 PC에서 한 번만:

```bash
git remote add origin https://github.com/<사용자>/w-baseball.git
```

```bash
git push -u origin main
```

### 공개 여부

| | Public | Private |
| --- | --- | --- |
| GitHub Actions | 무제한 | 월 2,000분 (이 저장소는 월 ~180분 사용) |
| GitHub Pages | 사용 가능 | 유료 플랜 필요 |
| 데이터 배포 | 가능 | 불가 — `WB_MANIFEST_BASE_URL` 을 쓸 수 없음 |

정적 데이터를 배포할 계획이면 **Public** 이어야 합니다. 저장소에 비밀값이 없다는
것은 확인돼 있습니다 — 키는 전부 GitHub Secrets에만 들어갑니다.

### Pages 켜기 (데이터 배포용, 선택)

Settings → Pages → Source: `Deploy from a branch` → `main` / `/ (root)`.
그러면 `https://<사용자>.github.io/w-baseball/public-data/` 가 데이터 주소가
됩니다.

---

## 2. 폰에서 코드 고치기

### 작은 수정 — GitHub 웹 편집기

파일을 열고 연필 아이콘. 문구 수정, 상수 변경, 문서 편집에 충분합니다.

**바로 `main` 에 커밋하지 말고 브랜치를 만드세요.** PR로 올리면 CI가 돌고,
초록불을 보고 머지할 수 있습니다. `main` 에 직접 커밋하면 깨진 걸 폰에서
되돌리기가 번거롭습니다.

### 여러 파일 수정 — github.dev

주소창에서 `github.com` 을 `github.dev` 로 바꾸면 브라우저 안에서 VS Code가
열립니다. 폰에서는 좁지만 파일 이동·검색·다중 편집이 됩니다.

### 고치면 안 되는 것

폰에서는 검증할 수 없으니 손대지 마세요. CI가 잡아주긴 하지만 왕복이 깁니다.

- `lib/core/database/tables.dart` — 스키마를 바꾸면 코드 재생성과 마이그레이션이
  필요합니다
- `lib/core/database/database.g.dart` — 생성 파일. 직접 고치면 CI가 막습니다
- `public-data/`, `assets/seed/` — 생성기가 만듭니다.
  `scripts/publish/build_seed.py` 를 고쳐야 합니다

---

## 3. CI가 알아서 하는 검사

푸시하거나 PR을 열면 자동으로 돕니다.

| 검사 | 무엇을 막는가 |
| --- | --- |
| 코드 생성 확인 | 커밋된 생성 코드와 재생성 결과가 다르면 실패 |
| 포맷 | `dart format` 결과와 다르면 실패 |
| 정적 분석 | 경고 하나라도 있으면 실패 |
| 테스트 | Dart 326개, 파이썬 22개 |
| 데이터 검증 | 출처 누락, 이닝 합계 불일치, 박스스코어 불일치, 개인정보 필드, 예보 범위 위반 |
| 스키마 재생성 확인 | 스키마 파일이 생성 결과와 다르면 실패 |
| Android 빌드 | 디버그 APK 빌드 |

**초록불이 아니면 머지하지 마세요.** 폰에서 되돌리는 것보다 안 넣는 게 쉽습니다.

---

## 4. 폰에 앱 설치하기

GitHub 모바일 앱은 workflow 실행 버튼이 없습니다. **모바일 브라우저**로
`github.com` 에 접속하세요.

1. Actions → **APK 빌드·배포** → `Run workflow`
2. `build_type`: 평소엔 `debug`, 실제 사용감을 볼 땐 `release`
3. `manifest_base_url`: 데이터 배포 주소. 비우면 번들 seed로 동작합니다
4. 10분쯤 뒤 Releases 탭에 APK가 올라옵니다
5. `arm64-v8a` 를 받으세요 — 요즘 기기는 대부분 이겁니다

설치하려면 "출처를 알 수 없는 앱" 허용이 필요합니다.

> 이 워크플로는 APK를 만들기 전에 분석·테스트·데이터 검증을 먼저 돌립니다.
> 폰에 도달하는 빌드가 리뷰를 통과하지 못했을 빌드면 안 되기 때문입니다.
>
> 디버그 키로 서명되므로 **스토어에 올릴 수 없습니다.** 배포용 서명은
> `docs/build-and-run.md` 4절을 보세요.

---

## 5. 데이터 갱신하기

Actions → **데이터 수집·게시** → `Run workflow`.

- `sources`: 비우면 활성화된 전체
- `publish`: **켜야 실제로 커밋됩니다.** 끄면 검수용 후보만 아티팩트로 남습니다

API 키가 없으면 해당 원천은 건너뛰고, 어떤 변수가 없어서 건너뛰었는지 말해줍니다.
키를 넣으려면 Settings → Secrets and variables → Actions.

WBAK·KBSA는 **여기서 켤 수 없습니다.** 코드에 차단 사유가 박혀 있고, 지우려면
리뷰가 필요합니다. 이유는 `docs/data-sources.md` 1절에 있습니다.

---

## 6. 폰에서 못 하는 것

정직하게 적습니다.

- **실기기 검증** — 알림 도착, 권한 대화상자, 지도·캘린더 연동은 앱을 설치해
  손으로 확인해야 합니다. APK를 받아 설치하면 됩니다
- **골든 스크린샷 재생성** — 호스트 폰트에 의존해서 CI에서 제외돼 있습니다.
  화면을 바꾸면 PC에서 `flutter test --tags screenshots --update-goldens` 를
  돌려야 합니다
- **성능 측정** — 실기기가 필요합니다
- **스키마 마이그레이션** — v3 같은 변경은 PC에서

---

## 7. 자주 쓰는 흐름

**문구 하나 고치기**
브랜치 만들기 → 웹 편집기로 수정 → PR → CI 초록불 → 머지

**고친 걸 폰에서 확인하기**
머지 → Actions에서 APK 빌드 실행 → Releases에서 받기 → 설치

**데이터만 갱신하기**
Actions에서 데이터 수집 실행 (`publish` 켜기) → 앱에서 당겨서 새로고침
