# 데이터 계약 (Data contract)

이 디렉터리는 앱과 데이터 배포본 사이의 **계약**입니다.

앱은 이 형식만 읽습니다. 원천 사이트의 필드명이나 특정 API의 응답 구조는
`lib/data/sources/adapters/`의 어댑터가 이 형식으로 바꿔서 넘깁니다. 그래서
나중에 공식 API가 생겨도 **어댑터 하나만 추가**하면 되고, 화면·리포지터리·DB는
그대로입니다.

## 파일

| 파일 | 대상 |
|---|---|
| `version.schema.json` | `version.json` 배포 매니페스트 |
| `envelope.schema.json` | 모든 데이터 파일의 공통 봉투 |
| `game.schema.json` | 경기 |
| `team.schema.json` | 팀 |
| `venue.schema.json` | 경기장 |
| `competition.schema.json` | 대회·시즌·단계 |
| `standing.schema.json` | 순위 스냅샷 |
| `person.schema.json` | 선수(최소 정보) |
| `content.schema.json` | 발견 번들(화제 콘텐츠·프로그램·이야기 묶음·가이드·날씨) |
| `provenance.schema.json` | 모든 레코드가 공유하는 출처 블록 |

## 세 계층의 분리

```text
원천 응답            →  DTO                    →  도메인 모델        →  DB 행
(WBAK/KBSA/API)        lib/data/dto/              lib/data/models/     lib/core/database/
                       이 스키마와 1:1
```

세 계층 사이의 변환은 명시적인 mapper가 담당합니다
(`lib/data/mappers/`). 어느 한 계층이 바뀌어도 나머지가 따라 바뀌지 않습니다.

## 검증

스키마는 문서이자 실행 가능한 규칙입니다. 두 곳에서 강제됩니다.

1. **게시 전** — `python scripts/validate/validate_data.py public-data`
   구조, 출처, 이닝 합계, 중복, 개인정보, 날씨 예보 구간, 데모 분리를 검사합니다.
2. **앱 안에서** — `lib/data/dto/*.dart`
   모르는 필드는 무시하고, 필수 필드가 없는 레코드만 격리합니다.

같은 규칙을 양쪽에서 검사하는 것은 중복이 아니라 의도입니다. 배포본이 잘못돼도
앱이 잘못된 데이터를 사실처럼 그리지 않습니다.

## 버전 정책

- `schemaVersion`은 정수입니다. 현재 앱이 읽는 범위는
  `DataContractConfig.minSupportedSchemaVersion` ~ `maxSupportedSchemaVersion`
  (지금은 1~1)입니다.
- **필드 추가는 버전을 올리지 않습니다.** 앱은 모르는 필드를 무시합니다.
- **필수 필드 제거나 의미 변경은 버전을 올립니다.**
- 앱이 읽을 수 없는 상위 버전을 받으면 **기존 캐시를 지우지 않고 갱신만 중단**하고
  사용자에게 앱 업데이트를 안내합니다. (`SyncFailureKind.schemaUnsupported`)

## 시각과 시간대

- 저장·전송은 **항상 UTC ISO-8601**이며 시간대 표기가 **필수**입니다.
  (`2026-08-30T05:00:00Z` 또는 `2026-08-30T14:00:00+09:00`)
- 시간대가 없는 시각은 거부합니다. 시간대 없는 경기 시각은 쓸 수 없는 값입니다.
- 표시만 Asia/Seoul로 변환합니다. 국제 경기는 `localTimeZone`을 함께 보냅니다.

## 절대 규칙

이 계약이 지키는 것은 형식이 아니라 신뢰입니다.

1. 출처(`sourceName`, `sourceUrl`, `fetchedAt`) 없이는 게시하지 않습니다.
2. `sourceUrl`은 사이트 홈이 아니라 **그 레코드의 상세 페이지**여야 합니다.
3. 확인되지 않은 데이터는 `isDemo: true`를 달고, 앱은 모든 화면에 데모 라벨을 붙입니다.
4. 기사 본문과 언론사 이미지는 저장하지 않습니다. API가 제공한 설명과 링크만 씁니다.
5. `licenseStatus`가 `permitted`가 아닌 사진은 게시하지 않습니다.
6. 미성년 선수의 사진과 개인 프로필은 게시하지 않습니다.
7. 개인 연락처(전화·이메일·주소·생년월일)는 스키마에 자리 자체가 없습니다.
8. `horizon: beyondForecast`인 날씨 레코드에는 기온·강수확률을 넣을 수 없습니다.
   기상청 상세 예보는 10일까지이며, 그 이후 일별 날씨는 만들어내지 않습니다.
9. `relation: isEntity` 연결(“이 인물은 실제로 이 선수다”)에는 근거 URL이 필요합니다.
10. `summaryMethod: aiAssisted` 요약은 생성 시각과 검수 상태를 반드시 함께 보냅니다.
