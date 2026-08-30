# 요구사항 추적표

기준 문서: (1) 마스터 프롬프트, (2) 사용자 세분화·콘텐츠·리텐션 보강 프롬프트.
검증일: 2026-08-30.

상태 정의
- **PASS** — 구현되어 있고 직접 확인함
- **PARTIAL** — 구현되어 있으나 불완전하거나 찾기 어렵거나 오류 상태가 없음
- **FAIL** — 구현되지 않았거나 요구를 어김
- **UNVERIFIED** — 문서·코드에는 있으나 이번 감사에서 직접 확인하지 못함

> 이 환경에는 Android 에뮬레이터·기기가 없습니다. 런타임 동작은 원칙적으로
> UNVERIFIED이며, 위젯 테스트로 대체 확인한 것은 그렇게 표기했습니다.

---

## A. 아키텍처와 API 독립성

| 요구사항 | 구현 위치 | 검증 방법 | 상태 | 근거 | 수정 필요 |
|---|---|---|---|---|---|
| DTO → Adapter/Validator → Domain → Sync → Drift → Repository → UI | `lib/data/**` | 코드 검토 | PASS | UI에서 Dio·JSON 경로·SQL 참조 없음 | — |
| UI가 Dio/JSON/URL/SQL 미참조 | `lib/features/**` | grep | PASS | 참조 0건 | — |
| 정적 adapter ↔ fake API 동등성 | `test/contract/adapter_equivalence_test.dart` | 테스트 실행 | PASS | 동일 도메인 지문 | — |
| canonicalId ↔ sourceRecordId 분리 | `external_identities` 테이블 | 테스트 | PASS | `sync_engine_test.dart` | — |
| pagination / cursor | `sync_engine.dart` | 테스트 | PASS | 3페이지 순회, 무한루프 방지 | — |
| updatedSince / ETag / snapshot·delta 구분 | `payload_envelope.dart` | 테스트 | PASS | `payloadKind` 없으면 delta | — |
| 멱등 upsert | 동일 | 테스트 | PASS | 중복 없음 | — |
| tombstone (즉시 hard delete 금지) | 동일 | 테스트 | PASS | 삭제 표시만 | — |
| 결과 정정 이력 | `_recordGameChanges()` | 테스트 | PASS | 점수·일정 변경 이력 | — |
| 상위 schema version 시 캐시 보존 | 동일 | 테스트 | PASS | 갱신만 중단 | — |
| malformed 1건이 전체를 막지 않음 | 동일 | 테스트 | PASS | 레코드 격리 | — |
| 401/403/404/429/500/timeout 처리 | `http_client.dart` | 테스트 | PASS | 실패 격리 + 404 특수 처리 | — |
| **checksum 불일치 처리** | 매니페스트 경로 | — | **UNVERIFIED** | 해당 테스트 없음 | 테스트 추가 |
| **DB 트랜잭션 중 실패** | — | — | **UNVERIFIED** | 테스트 없음 | 테스트 추가 |
| migration 후 즐겨찾기·알림·모드 보존 | `migration_test.dart` | 테스트 | PASS | 10개 테스트 | — |
| adapter feature flag 롤백 | `app_config.dart` | 코드 검토 | PASS | 플래그 off → 다음 원천 | — |

## B. 데이터 신뢰성과 출처

| 요구사항 | 구현 위치 | 검증 방법 | 상태 | 근거 | 수정 필요 |
|---|---|---|---|---|---|
| 모든 엔터티에 provenance | `ProvenanceColumns` | 스키마 검토 | PASS | 컬럼으로 강제 | — |
| **qualityStatus가 실제 검수 상태를 반영** | `build_seed.py:82` | 코드+데이터 검토 | **FAIL** | 생성기가 무조건 `humanVerified` | P0-1 |
| **reviewStatus가 실제 검수 상태를 반영** | `build_seed.py:523+` | 동일 | **FAIL** | 전부 `reviewed` 하드코딩 | P0-1 |
| 자동 요약은 `pending` | `normalize.py:196` | 코드 검토 | PASS | 원칙이 명시·구현됨 | — |
| **출처 발행시각 정확성** | `build_seed.py:619` | **실제 URL 열람** | **FAIL** | iMBC 저장 2026-06-20 vs 실제 2026-06-07 23:31 | P0-2 |
| 출처 URL 유효성 | 동일 | 실제 URL 열람 | PASS | 4/4 정상 |
| 기사 본문·이미지 미복제 | 데이터 검토 | 전수 확인 | PASS | 제목·링크·시각만 | — |
| 데모/실제 분리 | `isDemo` + 검증기 | 명령 실행 | PASS | `--production` exit 1 (116건) | — |
| 데모 UI 라벨 | 목록·상세 배지 | 골든 확인 | PASS | 스크린샷 | — |
| 야구여왕2 회차 결과 임의 작성 금지 | 데이터 검토 | 전수 확인 | PASS | 회차는 `데모 회차` 1건, `isDemo:true` | — |
| 이닝 합계·중복·시간대 검증 | `validate_data.py` | 명령 실행 | PASS | 오류 0 | — |
| **알 수 없는 별칭 자동 게시 금지** | `normalize.py` | 코드 검토 | PASS | review 큐로 분리 | — |
| **뉴스 군집화 테스트** | `normalize.py` | — | **FAIL** | 파이썬 테스트 0건 | P2 |

## C. 사용자 세분화와 정보 구조

| 요구사항 | 구현 위치 | 검증 방법 | 상태 | 근거 | 수정 필요 |
|---|---|---|---|---|---|
| 3단계 건너뛰기 가능 온보딩 | `onboarding_screen.dart` | 위젯 테스트 | PASS | 건너뛰면 discover | — |
| 온보딩에서 알림 권한 미요청 | 동일 | 코드 검토 | PASS | 요청 지점이 알림 설정·경기 상세 | — |
| 온보딩에서 위치 권한 미요청 | 동일 | 코드+매니페스트 | PASS | 위치 권한 자체가 매니페스트에 없음 | — |
| 5탭 IA (홈/발견/경기/마이야구/더보기) | `shell.dart` | 위젯 테스트 | PASS | 탭 구조 테스트 | — |
| IA 대안 비교 문서화 | `information-architecture.md` | 문서 검토 | **PARTIAL** | 대안 2개는 구현 없이 경로 추정 비교. 문서가 그렇게 명시함 | — |
| 모드별 홈 모듈 순서 | `home_modules.dart` | 위젯 테스트 | PASS | 모드별 첫 모듈 다름 | — |
| 모드가 기능을 숨기지 않음 | 동일 | 코드 검토 | PASS | 순서만 변경 | — |
| `둘 다` 모드 과다 길이 방지 | `bothOrder` | 코드 검토 | PASS | 10개, 이어붙이기 아님 | — |
| 두 정보 밀도 | `WbDensity`/`WbDensityScope` | 테스트 | PASS | 정보 손실 없음을 테스트가 강제 | — |
| 통합 검색 1탭 | 앱바 | **측정** | PASS | 4개 탭 각각 1탭 | — |
| 문맥(탭·필터·날짜) 복원 | `StatefulShellRoute` | **측정** | PASS | M4 | — |
| **딥링크로 상세 진입** | `AndroidManifest` + `router.dart` | **프로브 테스트** | **PARTIAL** | 설정 완료=성공, 신규 설치=온보딩으로 유실 | P1-1 |
| 딥링크 오류 fallback | `errorBuilder` | 코드 검토 | PASS | 전용 화면 + 홈 복귀 | — |
| **Android 뒤로가기·제스처** | — | — | **UNVERIFIED** | 기기 없음 | — |

## D. 콘텐츠와 리텐션

| 요구사항 | 구현 위치 | 검증 방법 | 상태 | 근거 | 수정 필요 |
|---|---|---|---|---|---|
| FeaturedTopic/Program/Season/Episode 일반화 | `content.dart` | 데이터 검토 | PASS | WBSC가 같은 형태로 공존 | — |
| 설정으로 교체 가능 | 동일 | 코드 검토 | PASS | 프로그램 종속 없음 | — |
| 뉴스 이야기 묶음 | `StoryCluster` | 데이터 검토 | PASS | 3개 매체 1묶음 | — |
| **30초 요약 3단 구조(무슨 일/왜 중요/다음)** | `shortSummary` | 데이터 검토 | **PARTIAL** | 1줄 요약만 존재 | P2 |
| 3분 이해 가이드 | `guides` | 데이터 검토 | PASS | 3건 | — |
| **방송 → 실제 야구 이동** | 링크 모델 | 데이터 검토 | **FAIL** | 실제 데이터 연결 0건 (회차가 데모) | P1-4 |
| 스포일러 정책 (카드·상세·알림) | `SpoilerPolicy` | 테스트 | PASS | 3면 모두 적용 | — |
| **spoilerLevel 기본값 안전성** | `audience.dart:64` | 코드 검토 | **FAIL** | 미지정 시 `none`(공개)로 fail-open | P1-6 |
| 카테고리별 알림 + 조용한 시간 | `NotificationPreference` | 테스트 | PASS | 개별 on/off, 자정 넘김 처리 | — |
| 알림 예약이 실제로 일어남 | `NotificationScheduler` | 테스트 | PASS | 6개 테스트 | — |
| **알림 탭 → 해당 상세 이동** | `notification_service.dart` | 코드 검토 | **FAIL** | 응답 핸들러 미등록 | P1-2 |
| 재부팅·시간대 변경 복구 | `AndroidManifest` 리시버 | — | **UNVERIFIED** | 선언은 있음, 실행 확인 불가 | — |
| 분석 인터페이스 + 로컬 전용 | `analytics.dart` | 코드 검토 | PASS | 허용 키 화이트리스트, 검색어 미저장 | — |

## E. 근처 경기 · 날씨 · 기록

| 요구사항 | 구현 위치 | 검증 방법 | 상태 | 근거 | 수정 필요 |
|---|---|---|---|---|---|
| 위치 권한 없이 근처 경기 | `nearby_games_screen.dart` | **측정** | PASS | 2탭, `useDeviceLocation=false` | — |
| 정확 좌표 미저장·미전송 | 코드 검토 | grep | PASS | 위치 권한 자체가 없음 | — |
| 관람 가능 여부 추정 금지 | `AttendanceStatus` | 코드 검토 | PASS | 기본값 `needsConfirmation` | — |
| 길찾기·캘린더·공유 2단계 이내 | `game_detail_screen.dart` | **측정** | PASS | 같은 행에 나란히 | — |
| **공식 일정 원문 확인** | 동일 | 데이터 검토 | **FAIL** | `officialDetailUrl` 0/23 | P1-3 |
| 예보 구간 구분 (단기·중기·범위 밖) | `weather.dart` | 테스트 | PASS | 자동 테스트 | — |
| D+11 이후 일별 값 생성 금지 | 동일 | 테스트 | **PASS (강함)** | 경계 테스트 자동화됨 | — |
| 발표시각·불확실성 표시 | UI | 골든 확인 | PASS | "8월 30일 오전 9:00 발표 · 신뢰도 높음" | — |
| 날씨 위험 ≠ 경기 취소 | 테스트 | 테스트 | PASS | 단정 문구 금지 테스트 | — |
| 개인 기록 자격 기준·동률 | `stats.dart` | 테스트 | PASS | 비례 기준, 동률 공유 | — |
| 종합 평점·AI 등급 부재 | 동일 | 테스트 | PASS | 존재 부정 테스트 | — |
| **팀 순위 계산·대회별 규정·동률** | `competition_repository.dart:197` | 코드 검토 | **FAIL** | 계산 없음, 원천 rank 신뢰, null이면 임의 순서 | P1-5 |
| 리그 진행률·진출 확정 단정 금지 | 테스트 | 테스트 | PASS | — | — |
| 데이터 누락 비율 표시 | `DataCoverage` | 테스트 | PASS | 전체 모르면 비율 미계산 | — |

## F. 운영·보안·접근성

| 요구사항 | 구현 위치 | 검증 방법 | 상태 | 근거 | 수정 필요 |
|---|---|---|---|---|---|
| 앱·저장소에 키·토큰 없음 | 전체 | 정규식 스캔 | PASS | 0건 | — |
| WBAK/KBSA 기본 비활성 + 사유 노출 | `permission_gated_adapters.dart` | 코드 검토 | PASS | 이중 잠금 | — |
| 환경변수만으로 못 켬 | `fetch_sources.py` | 코드 검토 | PASS | `blocked_reason` 하드코딩 | — |
| 불필요 권한 미포함 | `AndroidManifest.xml` | 매니페스트 검토 | **PASS (모범)** | 위치·캘린더·저장소 없음 | — |
| 개인정보 필드 차단 | `validate_data.py` | 명령 실행 | PASS | 연락처/사람 필드 분리 | — |
| 미성년 사진 정책 | `dto_validation_test.dart` | 테스트 | PASS | 표시 차단 테스트 | — |
| 로컬 설정 삭제 기능 | 설정 | 코드 검토 | PASS | 최근 검색 삭제 등 | — |
| 터치 영역 48dp | `WbSize.minTap` | 테스트 | **PARTIAL** | 밀도 토큰만 강제, 칩·날짜 스트립 미검증 | P2 |
| **큰 글자 200%** | `app.dart:41-42` | **프로브 테스트** | **FAIL** | 1.4로 클램프, 1.4에서 홈 넘침 | P1-7 |
| TalkBack 순서·라벨 | — | — | **UNVERIFIED** | 기기 없음 | — |
| 다크 모드 대비비 | — | 렌더링만 확인 | **UNVERIFIED** | 수치 측정 없음 | — |
| CI가 codegen·format·analyze·test·data 검사 | `.github/workflows/ci.yml` | 파일 검토 | PASS | — | — |
| 게시 실패 시 롤백 | `publish-data.yml` | 파일 검토 | PASS | 백업 후 복원 | — |

## G. 측정과 문서

| 요구사항 | 구현 위치 | 검증 방법 | 상태 | 근거 | 수정 필요 |
|---|---|---|---|---|---|
| 대표 과업 5개 이상 탭 수 측정 | `task_benchmark_test.dart` | 테스트 실행 | PASS | T1~T5 + M1~M5 실측 | — |
| README에 시작화면·탭·스크롤·실패 대체 표 | `README.md` 9절 | 문서 검토 | PASS | — | — |
| **M4가 실제로 "공식 원문 확인"을 측정** | 동일 | 테스트 코드 검토 | **PARTIAL** | 출처 줄 존재만 확인, 원문 미개봉 (데이터에 URL 없음) | 라벨 정정 |
| README 실행 방법 정확성 | `README.md` 3절 | 명령 실행 | **PARTIAL** | 디버그 APK 169MB → 실제 199MB | P2 |
| 실사용자 테스트 미수행 명시 | `user-testing-plan.md` | 문서 검토 | PASS | 상단 경고 유지 | — |
| **경쟁 앱 정량 비교** | — | — | **UNVERIFIED** | 비교 앱 실행 수단 없음 | — |
| 성능 측정 | — | — | **UNVERIFIED** | 기기 없음 | — |
