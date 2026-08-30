#!/usr/bin/env python3
"""Emit the JSON Schema contract files into `schemas/`.

The schemas are generated rather than hand-maintained so they cannot drift from
the shared vocabulary (provenance block, envelope, enum values) that the Dart
DTOs and the validator both rely on. Run after changing the contract:

    python scripts/publish/build_schemas.py
"""

from __future__ import annotations

import io
import json
import os

DRAFT = "https://json-schema.org/draft/2020-12/schema"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "schemas")

LICENSE_ENUM = ["permitted", "linkOnly", "unknown"]

PROVENANCE = {
    "$schema": DRAFT,
    "$id": "provenance.schema.json",
    "title": "Provenance",
    "description": "모든 게시 가능한 레코드가 공유하는 출처 블록. 이 블록 없이는 게시할 수 없습니다.",
    "type": "object",
    "required": ["sourceName", "sourceUrl", "fetchedAt"],
    "properties": {
        "sourceName": {
            "type": "string",
            "minLength": 1,
            "description": "출처 키. 예: wbak, kbsa, wbsc, wpbl, demo-fixture, app-editorial",
        },
        "sourceUrl": {
            "type": "string",
            "pattern": "^(https?://|app:)",
            "description": "사람이 확인할 수 있는 그 레코드의 상세 페이지. 사이트 홈이 아닙니다. "
            "앱이 직접 작성한 내용만 app: URI를 씁니다.",
        },
        "sourceRecordId": {
            "type": "string",
            "description": "원천이 쓰는 자체 id. 앱의 canonical id와 분리해 보관합니다.",
        },
        "fetchedAt": {"type": "string", "format": "date-time"},
        "verifiedAt": {
            "type": "string",
            "format": "date-time",
            "description": "사람이 공식 기록과 대조한 시각.",
        },
        "contentHash": {"type": "string"},
        "qualityStatus": {"enum": ["autoVerified", "humanVerified", "disputed"]},
        "licenseStatus": {
            "enum": LICENSE_ENUM,
            "description": "permitted 일 때만 본문·이미지를 복제할 수 있습니다.",
        },
        "visibility": {"enum": ["public", "private", "hidden"]},
        "isDemo": {
            "type": "boolean",
            "default": False,
            "description": "true 면 앱이 모든 화면에 데모 라벨을 붙이고, "
            "production 배포에서는 거부됩니다.",
        },
    },
    "additionalProperties": False,
}

ENVELOPE = {
    "$schema": DRAFT,
    "$id": "envelope.schema.json",
    "title": "Payload envelope",
    "description": "모든 데이터 파일의 공통 봉투. 정적 파일과 미래 API 응답이 같은 형태로 "
    "정규화되므로, 두 경로가 같은 도메인 결과를 만듭니다.",
    "type": "object",
    "required": ["items"],
    "properties": {
        "schemaVersion": {"type": "integer", "minimum": 1, "default": 1},
        "dataVersion": {"type": "string", "description": "게시자의 빌드 id. 예: 2026.08.30.1"},
        "generatedAt": {"type": "string", "format": "date-time"},
        "payloadKind": {
            "enum": ["snapshot", "delta"],
            "default": "delta",
            "description": "snapshot 이어야만 누락 레코드를 tombstone 처리합니다. "
            "delta 의 누락은 '변경 없음'을 뜻합니다.",
        },
        "hasMore": {"type": "boolean", "default": False},
        "nextCursor": {"type": ["string", "null"]},
        "tombstones": {
            "type": "array",
            "items": {"type": "string"},
            "description": "원천이 명시적으로 삭제를 선언한 sourceRecordId 목록.",
        },
        "items": {"type": "array"},
    },
}

VERSION = {
    "$schema": DRAFT,
    "$id": "version.schema.json",
    "title": "Data manifest",
    "description": "앱이 무엇이 바뀌었는지 판단하는 파일. 해시가 같으면 요청 자체를 생략합니다.",
    "type": "object",
    "required": ["schemaVersion", "dataVersion", "generatedAt", "files"],
    "properties": {
        "schemaVersion": {"type": "integer", "minimum": 1},
        "dataVersion": {"type": "string"},
        "generatedAt": {"type": "string", "format": "date-time"},
        "files": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["path"],
                "properties": {
                    "path": {"type": "string"},
                    "sha256": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
                    "size": {"type": "integer", "minimum": 0},
                    "etag": {"type": "string"},
                    "updatedAt": {"type": "string", "format": "date-time"},
                },
            },
        },
    },
}

TEAM = {
    "$schema": DRAFT,
    "$id": "team.schema.json",
    "title": "Team",
    "type": "object",
    "required": ["id", "name", "source"],
    "properties": {
        "id": {
            "type": "string",
            "description": "앱의 canonical id. 팀 이름을 키로 쓰지 않습니다 — 이름은 바뀝니다.",
        },
        "name": {"type": "string", "minLength": 1},
        "shortName": {"type": "string"},
        "region": {
            "type": "string",
            "description": "행정표준코드 시·도 코드(예: 11). 이름이 아닙니다.",
        },
        "city": {"type": "string"},
        "foundedYear": {"type": "integer", "minimum": 1900},
        "introduction": {"type": "string"},
        "recruitment": {"enum": ["open", "closed", "unknown"], "default": "unknown"},
        "recruitmentTarget": {
            "type": "string",
            "description": "팀이 직접 밝힌 모집 대상. 추정하지 않습니다.",
        },
        "homeVenueId": {"type": "string"},
        "practiceArea": {"type": "string"},
        "officialUrl": {"type": "string", "format": "uri"},
        "contactUrl": {
            "type": "string",
            "format": "uri",
            "description": "공식 문의 채널. 개인 연락처는 넣지 않습니다.",
        },
        "logoUrl": {"type": "string", "format": "uri"},
        "logoLicense": {"enum": LICENSE_ENUM, "default": "unknown"},
        "colorHex": {"type": "string", "pattern": "^#?[0-9a-fA-F]{6}$"},
        "aliases": {
            "type": "array",
            "items": {"type": "string"},
            "description": "띄어쓰기·지역명 표기 차이를 흡수합니다.",
        },
        "deletedAt": {"type": ["string", "null"], "format": "date-time"},
        "source": {"$ref": "provenance.schema.json"},
    },
    "additionalProperties": False,
}

VENUE = {
    "$schema": DRAFT,
    "$id": "venue.schema.json",
    "title": "Venue",
    "type": "object",
    "required": ["id", "name", "source"],
    "properties": {
        "id": {"type": "string"},
        "name": {"type": "string", "minLength": 1},
        "address": {
            "type": "string",
            "description": "공개 시설 주소. 길찾기에 필요하며 개인정보가 아닙니다.",
        },
        "region": {"type": "string"},
        "latitude": {"type": "number", "minimum": -90, "maximum": 90},
        "longitude": {"type": "number", "minimum": -180, "maximum": 180},
        "capacity": {"type": "integer", "minimum": 0},
        "surface": {"type": "string"},
        "notes": {"type": "string"},
        "deletedAt": {"type": ["string", "null"], "format": "date-time"},
        "source": {"$ref": "provenance.schema.json"},
    },
    "additionalProperties": False,
}

GAME = {
    "$schema": DRAFT,
    "$id": "game.schema.json",
    "title": "Game",
    "type": "object",
    "required": ["id", "status", "startTime", "homeTeamId", "awayTeamId", "source"],
    "properties": {
        "id": {"type": "string"},
        "status": {
            "enum": [
                "scheduled",
                "delayed",
                "postponed",
                "cancelled",
                "live",
                "final",
                "forfeit",
                "unknown",
            ],
            "description": "연기·취소·몰수는 승패로 뭉개지 않습니다. "
            "모르는 값은 unknown 으로 보존하고 scheduled 로 오해하지 않습니다.",
        },
        "startTime": {
            "type": "string",
            "format": "date-time",
            "description": "시간대 표기 필수. 시간대 없는 시각은 거부됩니다.",
        },
        "localTimeZone": {"type": "string", "default": "Asia/Seoul"},
        "homeTeamId": {"type": "string"},
        "awayTeamId": {"type": "string"},
        "seasonId": {"type": "string"},
        "stageId": {"type": "string"},
        "competitionId": {"type": "string"},
        "venueId": {"type": "string"},
        "homeScore": {"type": ["integer", "null"], "minimum": 0},
        "awayScore": {"type": ["integer", "null"], "minimum": 0},
        "round": {"type": "string"},
        "summary": {"type": "string", "description": "licenseStatus 가 permitted 일 때만."},
        "officialDetailUrl": {
            "type": "string",
            "format": "uri",
            "description": "이 경기의 공식 기록 페이지. 사이트 홈이 아닙니다.",
        },
        "statusNote": {"type": "string", "description": "예: 우천 순연"},
        "lineScore": {
            "type": "object",
            "properties": {
                "homeInnings": {
                    "type": "array",
                    "items": {"type": ["integer", "null"]},
                    "description": "null 은 '공격하지 않음'이며 0점과 다릅니다.",
                },
                "awayInnings": {"type": "array", "items": {"type": ["integer", "null"]}},
                "homeRuns": {"type": "integer"},
                "awayRuns": {"type": "integer"},
                "homeHits": {"type": "integer"},
                "awayHits": {"type": "integer"},
                "homeErrors": {"type": "integer"},
                "awayErrors": {"type": "integer"},
            },
            "description": "이닝 합계는 최종 득점과 정확히 일치해야 합니다.",
        },
        "batting": {"type": "array", "items": {"type": "object"}},
        "pitching": {"type": "array", "items": {"type": "object"}},
        "deletedAt": {"type": ["string", "null"], "format": "date-time"},
        "source": {"$ref": "provenance.schema.json"},
    },
    "allOf": [
        {
            "if": {"properties": {"status": {"const": "final"}}, "required": ["status"]},
            "then": {
                "required": ["homeScore", "awayScore"],
                "description": "종료된 경기는 점수가 있어야 합니다.",
            },
        }
    ],
    "additionalProperties": False,
}

COMPETITION = {
    "$schema": DRAFT,
    "$id": "competition.schema.json",
    "title": "Competition",
    "type": "object",
    "required": ["id", "name", "source"],
    "properties": {
        "id": {"type": "string"},
        "name": {"type": "string"},
        "shortName": {"type": "string"},
        "level": {"enum": ["domestic", "international", "unknown"]},
        "organizationId": {"type": "string"},
        "description": {"type": "string"},
        "regulationsUrl": {"type": "string", "format": "uri"},
        "bracketUrl": {"type": "string", "format": "uri"},
        "resultsUrl": {"type": "string", "format": "uri"},
        "seasons": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["id", "year", "name"],
                "properties": {
                    "id": {"type": "string"},
                    "competitionId": {"type": "string"},
                    "year": {"type": "integer"},
                    "name": {"type": "string"},
                    "phase": {"enum": ["upcoming", "ongoing", "completed", "unknown"]},
                    "startDate": {"type": "string"},
                    "endDate": {"type": "string"},
                    "stages": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "required": ["id", "name"],
                            "properties": {
                                "id": {"type": "string"},
                                "seasonId": {"type": "string"},
                                "name": {"type": "string"},
                                "format": {
                                    "enum": [
                                        "league",
                                        "groupStage",
                                        "knockout",
                                        "friendly",
                                        "unknown",
                                    ]
                                },
                                "groupLabel": {"type": "string"},
                                "ordering": {"type": "integer"},
                                "deletedAt": {"type": ["string", "null"]},
                            },
                        },
                    },
                    "deletedAt": {"type": ["string", "null"]},
                },
            },
        },
        "deletedAt": {"type": ["string", "null"], "format": "date-time"},
        "source": {"$ref": "provenance.schema.json"},
    },
    "additionalProperties": False,
}

STANDING = {
    "$schema": DRAFT,
    "$id": "standing.schema.json",
    "title": "Standing snapshot",
    "type": "object",
    "required": ["id", "seasonId", "teamId", "capturedAt", "source"],
    "properties": {
        "id": {"type": "string"},
        "seasonId": {"type": "string"},
        "stageId": {"type": "string"},
        "teamId": {"type": "string"},
        "capturedAt": {"type": "string", "format": "date-time"},
        "rank": {"type": "integer", "minimum": 1},
        "played": {"type": "integer", "minimum": 0},
        "wins": {"type": "integer", "minimum": 0},
        "losses": {"type": "integer", "minimum": 0},
        "draws": {"type": "integer", "minimum": 0},
        "runsScored": {"type": "integer", "minimum": 0},
        "runsAllowed": {"type": "integer", "minimum": 0},
        "gamesBehind": {"type": "number"},
        "deletedAt": {"type": ["string", "null"], "format": "date-time"},
        "source": {"$ref": "provenance.schema.json"},
    },
    "additionalProperties": False,
}

PERSON = {
    "$schema": DRAFT,
    "$id": "person.schema.json",
    "title": "Person",
    "description": "의도적으로 최소한입니다. 전화·이메일·주소·생년월일을 담을 자리가 "
    "스키마에 아예 없으므로 실수로도 저장될 수 없습니다.",
    "type": "object",
    "required": ["id", "name", "source"],
    "properties": {
        "id": {"type": "string"},
        "name": {"type": "string"},
        "isMinor": {
            "type": "boolean",
            "default": False,
            "description": "true 면 사진과 개인 프로필을 표시하지 않습니다.",
        },
        "photoUrl": {"type": "string", "format": "uri"},
        "photoLicense": {"enum": LICENSE_ENUM, "default": "unknown"},
        "aliases": {"type": "array", "items": {"type": "string"}},
        "deletedAt": {"type": ["string", "null"], "format": "date-time"},
        "source": {"$ref": "provenance.schema.json"},
    },
    "additionalProperties": False,
}

CONTENT = {
    "$schema": DRAFT,
    "$id": "content.schema.json",
    "title": "Discovery bundle",
    "description": "화제 콘텐츠·프로그램·이야기 묶음·가이드·관람 정보·날씨를 한 문서에 담습니다.",
    "type": "object",
    "properties": {
        "featuredTopics": {"type": "array", "items": {"$ref": "#/$defs/featuredTopic"}},
        "programs": {"type": "array", "items": {"$ref": "#/$defs/program"}},
        "clips": {"type": "array", "items": {"type": "object"}},
        "storyClusters": {"type": "array", "items": {"$ref": "#/$defs/storyCluster"}},
        "guides": {"type": "array", "items": {"type": "object"}},
        "attendance": {"type": "array", "items": {"$ref": "#/$defs/attendance"}},
        "forecasts": {"type": "array", "items": {"$ref": "#/$defs/forecast"}},
    },
    "$defs": {
        "contentMeta": {
            "type": "object",
            "required": ["publishedAt", "source"],
            "properties": {
                "publishedAt": {"type": "string", "format": "date-time"},
                "summaryMethod": {
                    "enum": ["manual", "template", "aiAssisted"],
                    "default": "manual",
                },
                "reviewStatus": {
                    "enum": ["pending", "reviewed", "rejected"],
                    "default": "reviewed",
                },
                "spoilerLevel": {
                    "enum": ["none", "mild", "result", "full"],
                    "default": "none",
                },
                "generatedAt": {
                    "type": "string",
                    "format": "date-time",
                    "description": "summaryMethod 가 aiAssisted 이면 필수입니다.",
                },
                "coverageObserved": {"type": "integer"},
                "coverageExpected": {"type": "integer"},
                "coverageNote": {"type": "string"},
                "source": {"$ref": "provenance.schema.json"},
            },
        },
        "featuredTopic": {
            "type": "object",
            "required": ["id", "kind", "title"],
            "properties": {
                "id": {"type": "string"},
                "kind": {
                    "enum": [
                        "broadcast",
                        "international",
                        "domesticCompetition",
                        "story",
                        "nearbyGames",
                        "gettingStarted",
                    ],
                    "description": "활성 주제가 없으면 다음 우선순위로 자동 대체됩니다. "
                    "프로그램 이름이 코드에 박히지 않는 이유입니다.",
                },
                "title": {"type": "string"},
                "subtitle": {"type": "string"},
                "priority": {"type": "integer"},
                "programId": {"type": "string"},
                "competitionId": {"type": "string"},
                "storyClusterId": {"type": "string"},
                "guideId": {"type": "string"},
                "heroImageUrl": {"type": "string", "format": "uri"},
                "heroImageLicense": {"enum": LICENSE_ENUM},
                "activeFrom": {"type": "string", "format": "date-time"},
                "activeUntil": {"type": "string", "format": "date-time"},
            },
        },
        "program": {
            "type": "object",
            "required": ["id", "title"],
            "properties": {
                "id": {"type": "string"},
                "title": {"type": "string"},
                "broadcaster": {"type": "string"},
                "officialUrl": {"type": "string", "format": "uri"},
                "streamingUrl": {"type": "string", "format": "uri"},
                "description": {"type": "string"},
                "seasons": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "required": ["id", "seasonNumber", "title"],
                        "properties": {
                            "id": {"type": "string"},
                            "seasonNumber": {"type": "integer"},
                            "title": {"type": "string"},
                            "airDayOfWeek": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 7,
                                "description": "ISO 요일. 주간 편성에서 '다음 방송'만 계산하며, "
                                "발표되지 않은 회차를 만들어내지 않습니다.",
                            },
                            "airTimeMinuteOfDay": {
                                "type": "integer",
                                "minimum": 0,
                                "maximum": 1439,
                            },
                            "premiereDate": {"type": "string"},
                            "finaleDate": {"type": "string"},
                            "isActive": {"type": "boolean", "default": True},
                            "episodes": {"type": "array", "items": {"type": "object"}},
                        },
                    },
                },
            },
        },
        "storyCluster": {
            "type": "object",
            "required": ["id", "title", "firstPublishedAt", "lastUpdatedAt", "sources"],
            "properties": {
                "id": {"type": "string"},
                "title": {"type": "string"},
                "shortSummary": {"type": "string"},
                "whyItMatters": {"type": "string"},
                "beginnerContext": {"type": "string"},
                "isTopStory": {
                    "type": "boolean",
                    "default": False,
                    "description": "true 면 개인화와 무관한 '모두가 알아둘 주요 소식'에 들어갑니다.",
                },
                "firstPublishedAt": {"type": "string", "format": "date-time"},
                "lastUpdatedAt": {"type": "string", "format": "date-time"},
                "sources": {
                    "type": "array",
                    "minItems": 1,
                    "items": {
                        "type": "object",
                        "required": ["id", "title", "url", "publishedAt"],
                        "properties": {
                            "id": {"type": "string"},
                            "title": {"type": "string"},
                            "url": {"type": "string", "format": "uri"},
                            "publishedAt": {"type": "string", "format": "date-time"},
                            "outlet": {"type": "string"},
                            "apiDescription": {
                                "type": "string",
                                "description": "뉴스 API가 제공한 설명만. "
                                "기사 본문과 언론사 이미지는 저장하지 않습니다.",
                            },
                        },
                        "additionalProperties": False,
                    },
                },
                "links": {"type": "array", "items": {"$ref": "#/$defs/contentLink"}},
            },
        },
        "contentLink": {
            "type": "object",
            "required": ["id", "toKind", "toId"],
            "properties": {
                "id": {"type": "string"},
                "fromKind": {"type": "string"},
                "fromId": {"type": "string"},
                "toKind": {"type": "string"},
                "toId": {"type": "string"},
                "relation": {
                    "enum": ["isEntity", "mentions", "relatedContext", "opponent"]
                },
                "label": {"type": "string"},
                "confirmedSourceUrl": {
                    "type": "string",
                    "format": "uri",
                    "description": "relation 이 isEntity 이면 필수입니다. "
                    "'이 인물은 실제로 이 선수다'라는 주장에는 근거가 필요합니다.",
                },
            },
            "allOf": [
                {
                    "if": {
                        "properties": {"relation": {"const": "isEntity"}},
                        "required": ["relation"],
                    },
                    "then": {"required": ["confirmedSourceUrl"]},
                }
            ],
        },
        "attendance": {
            "type": "object",
            "required": ["gameId", "source"],
            "properties": {
                "gameId": {"type": "string"},
                "status": {
                    "enum": ["open", "closed", "needsConfirmation"],
                    "default": "needsConfirmation",
                    "description": "기본값은 '확인 필요'입니다. "
                    "정보가 없다고 무료 개방으로 추정하지 않습니다.",
                },
                "admissionNote": {"type": "string"},
                "entryProcedure": {"type": "string"},
                "seatingNote": {"type": "string"},
                "parkingUrl": {"type": "string", "format": "uri"},
                "transitUrl": {"type": "string", "format": "uri"},
                "restroomAvailable": {"type": "boolean"},
                "concessionAvailable": {"type": "boolean"},
                "familyFriendlyConfirmed": {"type": "boolean", "default": False},
                "confirmedAt": {"type": "string", "format": "date-time"},
                "source": {"$ref": "provenance.schema.json"},
            },
        },
        "forecast": {
            "type": "object",
            "required": ["id", "venueId", "targetTime", "issuedAt", "source"],
            "description": "기상청 상세 예보는 10일까지입니다. "
            "horizon 이 beyondForecast 이면 일별 값을 넣을 수 없습니다.",
            "properties": {
                "id": {"type": "string"},
                "venueId": {"type": "string"},
                "gameId": {"type": "string"},
                "targetTime": {"type": "string", "format": "date-time"},
                "issuedAt": {
                    "type": "string",
                    "format": "date-time",
                    "description": "예보 발표 시각. 화면에 항상 함께 표시합니다.",
                },
                "horizon": {
                    "enum": ["shortTerm", "midTerm", "beyondForecast"],
                    "description": "shortTerm=D+0~2(상세), midTerm=D+3~10(범위), "
                    "beyondForecast=D+11 이후(일정만)",
                },
                "forecastZone": {
                    "type": "string",
                    "description": "기상청 예보구역. 구장으로 축약하지 않습니다.",
                },
                "temperatureC": {"type": "number"},
                "temperatureMinC": {"type": "number"},
                "temperatureMaxC": {"type": "number"},
                "precipitationProbability": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 100,
                },
                "precipitationMm": {"type": "number", "minimum": 0},
                "windSpeedMs": {"type": "number", "minimum": 0},
                "humidityPercent": {"type": "integer", "minimum": 0, "maximum": 100},
                "skyCondition": {"type": "string"},
                "confidence": {"enum": ["high", "medium", "low", "unknown"]},
                "seasonalTendency": {
                    "type": "string",
                    "description": "예보 구간 밖에서 허용되는 유일한 표현. "
                    "예: '평년보다 기온이 높을 가능성'",
                },
                "source": {"$ref": "provenance.schema.json"},
            },
            "allOf": [
                {
                    "if": {
                        "properties": {"horizon": {"const": "beyondForecast"}},
                        "required": ["horizon"],
                    },
                    "then": {
                        "not": {
                            "anyOf": [
                                {"required": ["temperatureC"]},
                                {"required": ["temperatureMinC"]},
                                {"required": ["temperatureMaxC"]},
                                {"required": ["precipitationProbability"]},
                                {"required": ["skyCondition"]},
                            ]
                        }
                    },
                }
            ],
        },
    },
}

SCHEMAS = {
    "provenance.schema.json": PROVENANCE,
    "envelope.schema.json": ENVELOPE,
    "version.schema.json": VERSION,
    "team.schema.json": TEAM,
    "venue.schema.json": VENUE,
    "game.schema.json": GAME,
    "competition.schema.json": COMPETITION,
    "standing.schema.json": STANDING,
    "person.schema.json": PERSON,
    "content.schema.json": CONTENT,
}


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, document in SCHEMAS.items():
        path = os.path.join(OUT_DIR, name)
        with io.open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(document, f, ensure_ascii=False, indent=2)
            f.write("\n")
    print(f"wrote {len(SCHEMAS)} schema files to {OUT_DIR}")


if __name__ == "__main__":
    main()
