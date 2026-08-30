# 감사 근거 자료

2026-08-30 감사에서 실제로 실행해 얻은 출력입니다. 개인정보·비밀값은 포함하지
않습니다.

| 파일 | 내용 | 재생성 명령 |
| --- | --- | --- |
| `probe-output.txt` | 딥링크·글자 배율 프로브와 과업 측정값 | 아래 참고 |

```bash
flutter test test/audit --reporter=expanded
```

```bash
flutter test test/widget/task_benchmark_test.dart --reporter=expanded
```

## 프로브 테스트에 대해

`test/audit/` 의 두 파일은 **단정하지 않고 현재 동작을 출력만 합니다.**
감사 근거를 재현 가능하게 남기려는 목적이며, 통과한다고 해서 앱이 옳다는 뜻이
아닙니다.

- `deeplink_probe_test.dart` — 신규 설치 사용자의 딥링크 목적지 (P1-1)
- `text_scale_probe_test.dart` — 글자 배율별 오버플로 (P1-7)

해당 결함을 고친 뒤에는 이 프로브들을 **단정하는 회귀 테스트로 승격**하세요.
그러지 않으면 같은 버그가 다시 들어와도 초록불이 켜집니다.

## 남기지 않은 것

- 실기기·에뮬레이터 실행 로그 — 이 환경에 Android 이미지가 없어 실행 자체를
  못 했습니다
- 성능 트레이스 — 같은 이유
- 경쟁 앱 스크린샷 — 저작권 및 실행 수단 부재
