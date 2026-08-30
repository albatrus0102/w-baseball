# Android 실행·빌드 가이드

## 1. 준비물

| 항목 | 버전 | 확인 |
| --- | --- | --- |
| Flutter | 3.47.2 이상 | `flutter --version` |
| Dart | 3.13.2 이상 | Flutter에 포함 |
| JDK | **17** | `java -version` |
| Android SDK | compileSdk는 Flutter 기본값 사용 | `flutter doctor` |

```bash
flutter doctor
```

`[!]` 가 Android toolchain에 있으면 먼저 해결하세요. JDK가 17이 아니면
Gradle이 이상한 오류를 냅니다.

---

## 2. 처음 실행

```bash
flutter pub get
```

```bash
dart run build_runner build --delete-conflicting-outputs
```

Drift 코드 생성입니다. **생성 결과는 저장소에 커밋되어 있으므로** 보통은 이
단계 없이도 빌드됩니다. 테이블을 고쳤을 때만 필요합니다. (CI는 재생성 결과가
커밋과 같은지 확인하고, 다르면 빌드를 실패시킵니다.)

```bash
flutter run
```

**환경 변수 없이 그대로 실행됩니다.** 번들 seed로 모든 화면이 동작합니다.
네트워크도 API 키도 필요 없습니다.

### 정적 데이터 배포본에 연결해서 실행

```bash
flutter run --dart-define=WB_MANIFEST_BASE_URL=https://<사용자>.github.io/w-baseball/
```

여러 개를 줄 때는 `--dart-define` 을 반복하거나
`--dart-define-from-file=env.json` 을 쓰세요.

---

## 3. 빌드

### 디버그 APK

```bash
flutter build apk --debug
```

→ `build/app/outputs/flutter-apk/app-debug.apk` (약 200MB — 디버그 심볼 포함)

### 릴리스 APK

```bash
flutter build apk --release
```

→ `build/app/outputs/flutter-apk/app-release.apk` (약 69MB)

**69MB는 범용(universal) 빌드이기 때문입니다.** 모든 ABI(arm64, armeabi-v7a,
x86_64)의 네이티브 코드가 한 파일에 들어 있습니다.

### ABI 분할 (권장)

```bash
flutter build apk --split-per-abi
```

기기별 APK가 따로 나오고 각각 훨씬 작습니다. 사이드로드로 배포한다면 이쪽입니다.

### Play Store 배포용

```bash
flutter build appbundle --release
```

Play가 기기별로 쪼개주므로 실제 다운로드 크기가 가장 작습니다.

---

## 4. 서명

릴리스 빌드는 현재 **디버그 키로 서명**됩니다. 실제 배포 전에:

1. 키스토어 생성

```bash
keytool -genkey -v -keystore ~/wbaseball-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias wbaseball
```

2. `android/key.properties` 생성 — **저장소에 커밋하지 마세요.**

```
storePassword=...
keyPassword=...
keyAlias=wbaseball
storeFile=C:/경로/wbaseball-release.jks
```

3. `android/app/build.gradle.kts` 의 `signingConfigs` 에서 이 파일을 읽도록 설정.

**키스토어와 `key.properties` 는 `.gitignore` 에 있어야 합니다.**
잃어버리면 같은 앱으로 업데이트를 낼 수 없습니다. 안전한 곳에 백업하세요.

---

## 5. 테스트

```bash
flutter test --exclude-tags screenshots
```

217개 통과 (약 12초).

```bash
flutter test --tags screenshots --update-goldens
```

`docs/screenshots/` 에 21장 생성. **CI에서는 제외**합니다 — 호스트 폰트에 따라
픽셀이 달라지므로 픽셀 차이로 빌드를 막지 않습니다.

```bash
flutter analyze
```

```bash
dart format --set-exit-if-changed .
```

### 데이터 검증

```bash
python scripts/validate/validate_data.py public-data
```

```bash
python scripts/validate/validate_data.py public-data --production
```

두 번째는 **현재 의도적으로 실패합니다** (데모 레코드 116건). 정상입니다.

---

## 6. 자주 겪는 문제

### `flutter_local_notifications` 관련 빌드 실패

이미 해결돼 있습니다. `android/app/build.gradle.kts` 에:

```kotlin
compileOptions {
    isCoreLibraryDesugaringEnabled = true
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
```

이 플러그인은 옛 API 레벨에서 `java.time` 을 쓰므로 desugaring이 필수입니다.
**이 설정을 지우면 릴리스 빌드가 실패합니다.**

### Gradle이 JDK를 못 찾음 / 이상한 버전 사용

```bash
flutter config --jdk-dir "<JDK 17 경로>"
```

### 빌드 캐시 문제

```bash
flutter clean
```

```bash
flutter pub get
```

### Drift 생성 코드와 테이블 불일치

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 앱은 뜨는데 데이터가 안 보임

`WB_MANIFEST_BASE_URL` 을 지정했는데 주소가 잘못됐을 가능성이 큽니다.
비워두면 seed로 동작하므로, 먼저 비워서 실행해보세요.
더보기 → **데이터 출처** 화면에서 원천별 상태와 마지막 동기화 시각을 볼 수 있습니다.

### 에뮬레이터에서 한글이 네모로 보임

에뮬레이터 시스템 이미지에 한국어 폰트가 없는 경우입니다. Google APIs 포함
이미지를 쓰거나 실기기로 확인하세요.

---

## 7. 출시 체크리스트

- [ ] 릴리스 서명 키 구성, 키스토어 백업
- [ ] `flutter build appbundle --release` 성공
- [ ] `WB_MANIFEST_BASE_URL` 을 실제 배포 주소로 지정
- [ ] 개인정보처리방침 URL 준비 (README 8절 근거)
- [ ] Play Console 데이터 보안 섹션 작성 — 수집 항목 없음, 위치는 선택·기기 내 처리
- [ ] **스토어 설명에 데모 데이터임을 명시**
- [ ] `python scripts/validate/validate_data.py public-data` 통과
- [ ] 기내 모드 최초 실행 확인
- [ ] 알림 권한 거부 상태에서 앱이 정상 동작하는지 확인
- [ ] 위치 권한 거부 상태에서 근처 경기가 동작하는지 확인
- [ ] 큰 글자(130%) 설정에서 주요 화면 확인
