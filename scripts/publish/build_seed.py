#!/usr/bin/env python3
"""Build the bundled seed data set and the public static data set.

Two outputs from one definition:

  assets/seed/    shipped inside the APK, so a first launch with no network is
                  still a working app.
  public-data/    what a static host serves; identical shape, plus checksums.

Honesty rules enforced here, not left to reviewers:

  * Every record that is not independently verifiable is marked isDemo=true and
    carries a `demo-fixture` source name. The app badges those everywhere.
  * Records that ARE verifiable (governing bodies, the WBSC 2026 event, the
    Channel A programme metadata, the three real news articles) are marked
    isDemo=false and carry their real source URL.
  * No episode outcome, player record, or daily weather beyond D+10 is invented.
  * `scripts/validate/validate_data.py` re-checks all of this independently.

Usage:
    python scripts/publish/build_seed.py [--generated-at 2026-08-30T00:00:00Z]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import shutil
from datetime import datetime, timedelta, timezone

KST = timezone(timedelta(hours=9))

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SEED_DIR = os.path.join(ROOT, "assets", "seed")
PUBLIC_DIR = os.path.join(ROOT, "public-data")

SCHEMA_VERSION = 1

# --- human review ledger -----------------------------------------------------
#
# `reviewStatus: reviewed` and `qualityStatus: humanVerified` are claims about a
# *person*, not about this script. A generator cannot certify its own output, so
# nothing here is promoted unless a named reviewer is recorded below.
#
# To sign off on a record, add its id with who checked it and when:
#
#     "story-src-imbc-s2": {
#         "reviewer": "홍길동",
#         "reviewedAt": "2026-09-01T00:00:00Z",
#     },
#
# The reviewer is expected to have opened `sourceUrl` and confirmed the facts.
# Deleting an entry demotes the record back to `pending` on the next build.
#
# Deliberately empty: at the time of writing no one has signed off on anything.
REVIEW_LEDGER: dict[str, dict[str, str]] = {}

REVIEW_DEFAULT = "pending"


def apply_review_ledger(node, generated_at: str) -> None:
    """Promotes only the records a named person signed off on.

    Walks the emitted structure and, for every dict carrying an `id`, upgrades
    `reviewStatus` / `qualityStatus` / `verifiedAt` when that id appears in
    [REVIEW_LEDGER]. Everything else is left at the honest default.

    Done as one pass over the finished tree rather than at each construction
    site: there are dozens of those, and a single missed one is exactly the bug
    this replaces.
    """
    if isinstance(node, list):
        for child in node:
            apply_review_ledger(child, generated_at)
        return
    if not isinstance(node, dict):
        return

    entry = REVIEW_LEDGER.get(node.get("id", ""))
    if entry is not None:
        if "reviewStatus" in node:
            node["reviewStatus"] = "reviewed"
        source = node.get("source")
        if isinstance(source, dict) and not source.get("isDemo"):
            source["qualityStatus"] = "humanVerified"
            source["verifiedAt"] = entry["reviewedAt"]
            source["reviewedBy"] = entry["reviewer"]

    for value in node.values():
        apply_review_ledger(value, generated_at)


# --- source blocks -----------------------------------------------------------


def demo_source(generated_at: str, record_id: str | None = None) -> dict:
    """Illustrative data. Always labelled, never presented as an official record."""
    block = {
        "sourceName": "demo-fixture",
        "sourceUrl": "app://demo/fixture",
        "fetchedAt": generated_at,
        "qualityStatus": "autoVerified",
        "licenseStatus": "permitted",
        "visibility": "public",
        "isDemo": True,
    }
    if record_id:
        block["sourceRecordId"] = record_id
    return block


def official_source(name: str, url: str, generated_at: str) -> dict:
    """A record whose facts come from a page anyone can open and check.

    Always `autoVerified`. Being *checkable* is not the same as having been
    *checked*, and only [REVIEW_LEDGER] can make that second claim.
    """
    return {
        "sourceName": name,
        "sourceUrl": url,
        "fetchedAt": generated_at,
        "qualityStatus": "autoVerified",
        "licenseStatus": "linkOnly",
        "visibility": "public",
        "isDemo": False,
    }


def editorial_source(generated_at: str) -> dict:
    """Written for this app. No external page, hence an `app:` URI."""
    return {
        "sourceName": "app-editorial",
        "sourceUrl": "app://editorial/guide",
        "fetchedAt": generated_at,
        # Written for this app, but writing is not reviewing.
        "qualityStatus": "autoVerified",
        "licenseStatus": "permitted",
        "visibility": "public",
        "isDemo": False,
    }


def envelope(items: list, generated_at: str, kind: str = "snapshot") -> dict:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "dataVersion": generated_at[:10].replace("-", "."),
        "generatedAt": generated_at,
        "payloadKind": kind,
        "hasMore": False,
        "items": items,
    }


# --- reference data ----------------------------------------------------------

REGIONS = ["11", "41", "28", "26", "27", "30"]

TEAMS = [
    ("team-demo-hangang", "한강 리버베어스", "11", "서울", "#1F4E79", "open", "초보 환영 · 20~40대"),
    ("team-demo-namsan", "남산 스카이라크스", "11", "서울", "#7A3E9D", "closed", None),
    ("team-demo-suwon", "수원 필드메이커스", "41", "수원", "#2E7D4F", "open", "경험 무관"),
    ("team-demo-goyang", "고양 윈드밀스", "41", "고양", "#B7791F", "unknown", None),
    ("team-demo-incheon", "인천 하버라이츠", "28", "인천", "#0F766E", "open", "주말 훈련 가능자"),
    ("team-demo-busan", "부산 씨걸스", "26", "부산", "#C2410C", "open", "초보 환영"),
    ("team-demo-daegu", "대구 애플블라썸", "27", "대구", "#9D174D", "closed", None),
    ("team-demo-daejeon", "대전 코멧츠", "30", "대전", "#3730A3", "unknown", None),
]

VENUES = [
    ("venue-demo-hangang", "한강 야구장 (데모)", "서울 광진구 강변북로", "11", 37.5300, 127.0700),
    ("venue-demo-suwon", "수원 스포츠파크 야구장 (데모)", "경기 수원시 팔달구", "41", 37.2800, 127.0100),
    ("venue-demo-incheon", "인천 문학 보조구장 (데모)", "인천 미추홀구", "28", 37.4350, 126.6900),
    ("venue-demo-busan", "부산 사직 보조구장 (데모)", "부산 동래구", "26", 35.1940, 129.0610),
]

# Deterministic fixture pattern so regenerating produces the same data set.
FIXTURES = [
    # (offset_days_from_generated, home_index, away_index, venue_index, played)
    (-52, 0, 2, 0, True),
    (-45, 4, 1, 2, True),
    (-38, 5, 7, 3, True),
    (-31, 2, 4, 1, True),
    (-24, 1, 6, 0, True),
    (-17, 3, 0, 1, True),
    (-10, 6, 5, 2, True),
    (-9, 7, 3, 3, True),
    (-3, 0, 4, 0, True),
    (-2, 2, 6, 1, True),
    (1, 0, 1, 0, False),
    (2, 4, 5, 2, False),
    (3, 2, 3, 1, False),
    (6, 6, 7, 3, False),
    (9, 1, 4, 0, False),
    (13, 5, 0, 3, False),
    (16, 3, 6, 1, False),
    (21, 7, 2, 2, False),
    (27, 4, 0, 0, False),
    (34, 1, 5, 3, False),
    (41, 6, 3, 1, False),
    (48, 2, 7, 2, False),
]

# Deterministic pseudo-scores. Fixed table rather than a RNG so the seed is
# reproducible and reviewable.
SCORES = [
    (5, 3), (2, 7), (4, 4), (8, 1), (3, 6),
    (1, 2), (9, 5), (0, 3), (6, 6), (7, 2),
]


def build(generated_at_dt: datetime) -> None:
    generated_at = generated_at_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    year = generated_at_dt.year

    files: dict[str, dict] = {}

    # --- organizations: real bodies, real URLs -------------------------------
    files["organizations.json"] = envelope(
        [
            {
                "id": "org-wbak",
                "name": "한국여자야구연맹",
                "shortName": "WBAK",
                "country": "KR",
                "websiteUrl": "https://www.wbak.net/home",
                "source": official_source("wbak", "https://www.wbak.net/home", generated_at),
            },
            {
                "id": "org-kbsa",
                "name": "대한야구소프트볼협회",
                "shortName": "KBSA",
                "country": "KR",
                "websiteUrl": "https://kbsa.or.kr/",
                "source": official_source("kbsa", "https://kbsa.or.kr/", generated_at),
            },
            {
                "id": "org-wbsc",
                "name": "World Baseball Softball Confederation",
                "shortName": "WBSC",
                "country": "INT",
                "websiteUrl": "https://www.wbsc.org/",
                "source": official_source("wbsc", "https://www.wbsc.org/", generated_at),
            },
        ],
        generated_at,
    )

    # --- venues (demo) -------------------------------------------------------
    files["venues.json"] = envelope(
        [
            {
                "id": vid,
                "name": name,
                "address": address,
                "region": region,
                "latitude": lat,
                "longitude": lon,
                "surface": "인조잔디",
                "source": demo_source(generated_at, vid),
            }
            for vid, name, address, region, lat, lon in VENUES
        ],
        generated_at,
    )

    # --- teams (demo) --------------------------------------------------------
    files["teams.json"] = envelope(
        [
            {
                "id": tid,
                "name": name,
                "region": region,
                "city": city,
                "foundedYear": 2015 + (i % 8),
                "introduction": "앱 동작 확인을 위한 데모 팀입니다. 실제 팀이 아닙니다.",
                "recruitment": recruitment,
                **({"recruitmentTarget": target} if target else {}),
                "homeVenueId": VENUES[i % len(VENUES)][0],
                "practiceArea": city,
                "colorHex": color,
                "aliases": [name.replace(" ", ""), name.split(" ")[0]],
                "source": demo_source(generated_at, tid),
            }
            for i, (tid, name, region, city, color, recruitment, target) in enumerate(TEAMS)
        ],
        generated_at,
    )

    # --- competitions --------------------------------------------------------
    season_id = f"season-demo-league-{year}"
    files[f"competitions/{year}.json"] = envelope(
        [
            {
                "id": "comp-demo-league",
                "name": f"{year} 데모 여자야구 리그",
                "shortName": "데모 리그",
                "level": "domestic",
                "organizationId": "org-wbak",
                "description": "앱의 일정·순위·기록 화면을 확인하기 위한 데모 대회입니다. "
                               "실제 대회가 아니며 모든 경기와 기록은 예시입니다.",
                "seasons": [
                    {
                        "id": season_id,
                        "year": year,
                        "name": f"{year} 정규 시즌",
                        "phase": "ongoing",
                        "startDate": f"{year}-04-05",
                        "endDate": f"{year}-11-15",
                        "stages": [
                            {
                                "id": f"stage-demo-{year}-regular",
                                "name": "정규 리그",
                                "format": "league",
                                "ordering": 1,
                            }
                        ],
                    }
                ],
                "source": demo_source(generated_at, "comp-demo-league"),
            },
            {
                # Real event. Metadata only — we hold no verified schedule, so
                # this competition intentionally has no games or standings.
                "id": "comp-wbsc-wbwc-2026",
                "name": "2026 WBSC 여자야구 월드컵",
                "shortName": "여자야구 월드컵",
                "level": "international",
                "organizationId": "org-wbsc",
                "description": "WBSC가 주관하는 국제 대회입니다. 일정과 결과는 공식 페이지에서 확인할 수 있습니다.",
                "resultsUrl": "https://www.wbsc.org/en/events/2026-x-womens-baseball-world-cup-group-stage-rockford/schedule-and-results",
                "bracketUrl": "https://www.wbsc.org/en/events/2026-x-womens-baseball-world-cup-group-stage-rockford/standings",
                "seasons": [
                    {
                        "id": "season-wbsc-wbwc-2026",
                        "year": 2026,
                        "name": "2026 그룹 스테이지 (Rockford)",
                        "phase": "upcoming",
                        "stages": [],
                    }
                ],
                "source": official_source(
                    "wbsc",
                    "https://www.wbsc.org/en/events/2026-x-womens-baseball-world-cup-group-stage-rockford/home",
                    generated_at,
                ),
            },
        ],
        generated_at,
    )

    # --- games ---------------------------------------------------------------
    games_by_month: dict[str, list] = {}
    standings_acc = {
        tid: {"w": 0, "l": 0, "d": 0, "rs": 0, "ra": 0} for tid, *_ in TEAMS
    }
    played_index = 0

    for offset, home_i, away_i, venue_i, played in FIXTURES:
        # 14:00 KST kick-off, expressed in UTC.
        kst_day = (generated_at_dt.astimezone(KST) + timedelta(days=offset)).date()
        start_kst = datetime(kst_day.year, kst_day.month, kst_day.day, 14, 0, tzinfo=KST)
        start_utc = start_kst.astimezone(timezone.utc)
        month_key = start_kst.strftime("%Y-%m")
        game_id = f"game-demo-{start_kst.strftime('%Y%m%d')}-{home_i}{away_i}"

        home_id = TEAMS[home_i][0]
        away_id = TEAMS[away_i][0]

        record: dict = {
            "id": game_id,
            "status": "final" if played else "scheduled",
            "startTime": start_utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "localTimeZone": "Asia/Seoul",
            "homeTeamId": home_id,
            "awayTeamId": away_id,
            "competitionId": "comp-demo-league",
            "seasonId": season_id,
            "stageId": f"stage-demo-{year}-regular",
            "venueId": VENUES[venue_i][0],
            "round": f"{(abs(offset) // 7) + 1}라운드",
            "source": demo_source(generated_at, game_id),
        }

        if played:
            home_score, away_score = SCORES[played_index % len(SCORES)]
            played_index += 1
            record["homeScore"] = home_score
            record["awayScore"] = away_score
            record["lineScore"] = _line_score(home_score, away_score)

            # Per-player lines, so the leaderboards have something to rank.
            # The schema, sync path, repository and UI for records all existed
            # already; only the data was missing, which left 개인 기록 순위
            # permanently empty.
            if True:
                home_bat, home_pit = _box_score(
                    game_id, home_id, home_i, home_score, away_score
                )
                away_bat, away_pit = _box_score(
                    game_id, away_id, away_i, away_score, home_score
                )
                record["batting"] = home_bat + away_bat
                record["pitching"] = home_pit + away_pit

            standings_acc[home_id]["rs"] += home_score
            standings_acc[home_id]["ra"] += away_score
            standings_acc[away_id]["rs"] += away_score
            standings_acc[away_id]["ra"] += home_score
            if home_score > away_score:
                standings_acc[home_id]["w"] += 1
                standings_acc[away_id]["l"] += 1
            elif away_score > home_score:
                standings_acc[away_id]["w"] += 1
                standings_acc[home_id]["l"] += 1
            else:
                standings_acc[home_id]["d"] += 1
                standings_acc[away_id]["d"] += 1

        games_by_month.setdefault(month_key, []).append(record)

    # One disrupted fixture so the postponed/cancelled paths are exercised and
    # visibly not collapsed into a win or loss.
    postponed_day = (generated_at_dt.astimezone(KST) + timedelta(days=5)).date()
    postponed_kst = datetime(
        postponed_day.year, postponed_day.month, postponed_day.day, 17, 0, tzinfo=KST
    )
    postponed_id = f"game-demo-{postponed_kst.strftime('%Y%m%d')}-pp"
    games_by_month.setdefault(postponed_kst.strftime("%Y-%m"), []).append(
        {
            "id": postponed_id,
            "status": "postponed",
            "statusNote": "우천 순연",
            "startTime": postponed_kst.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "localTimeZone": "Asia/Seoul",
            "homeTeamId": TEAMS[1][0],
            "awayTeamId": TEAMS[3][0],
            "competitionId": "comp-demo-league",
            "seasonId": season_id,
            "venueId": VENUES[1][0],
            "source": demo_source(generated_at, postponed_id),
        }
    )

    # The remaining disrupted states. Without a fixture in each, the badges and
    # empty-result paths for cancelled / delayed / live / forfeit games are
    # never rendered by any test or screenshot, and a bug in them would ship
    # unseen. Deliberately spread across days so no single list is dominated by
    # odd states.
    for offset, (status, note, hours) in enumerate(
        [
            ("cancelled", "폭염 취소", 17),
            ("delayed", "우천 지연", 14),
            ("live", None, -2),
            ("forfeit", "몰수 (인원 미달)", 15),
        ],
        start=6,
    ):
        day = (generated_at_dt.astimezone(KST) + timedelta(days=offset)).date()
        start_kst = datetime(day.year, day.month, day.day, 12, 0, tzinfo=KST) + timedelta(
            hours=hours
        )
        gid = f"game-demo-{start_kst.strftime('%Y%m%d')}-{status[:2]}"
        record = {
            "id": gid,
            "status": status,
            "startTime": start_kst.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "localTimeZone": "Asia/Seoul",
            "homeTeamId": TEAMS[(offset + 1) % len(TEAMS)][0],
            "awayTeamId": TEAMS[(offset + 4) % len(TEAMS)][0],
            "competitionId": "comp-demo-league",
            "seasonId": season_id,
            "venueId": VENUES[offset % len(VENUES)][0],
            "source": demo_source(generated_at, gid),
        }
        if note:
            record["statusNote"] = note
        # A forfeit has a recorded result; the others deliberately do not, so
        # the "no score yet" rendering is exercised too.
        if status == "forfeit":
            record["homeScore"] = 9
            record["awayScore"] = 0
        games_by_month.setdefault(start_kst.strftime("%Y-%m"), []).append(record)

    for month_key, records in games_by_month.items():
        records.sort(key=lambda r: r["startTime"])
        files[f"games/{month_key}.json"] = envelope(records, generated_at)

    # --- standings -----------------------------------------------------------
    rows = []
    ordered = sorted(
        standings_acc.items(),
        key=lambda kv: (-kv[1]["w"], kv[1]["l"], -(kv[1]["rs"] - kv[1]["ra"])),
    )
    for rank, (team_id, acc) in enumerate(ordered, start=1):
        played = acc["w"] + acc["l"] + acc["d"]
        if played == 0:
            continue
        rows.append(
            {
                "id": f"standing-demo-{team_id}",
                "seasonId": season_id,
                "teamId": team_id,
                "capturedAt": generated_at,
                "rank": rank,
                "played": played,
                "wins": acc["w"],
                "losses": acc["l"],
                "draws": acc["d"],
                "runsScored": acc["rs"],
                "runsAllowed": acc["ra"],
                "source": demo_source(generated_at, f"standing-demo-{team_id}"),
            }
        )
    files[f"standings/{season_id}.json"] = envelope(rows, generated_at)

    # --- people & roster (demo) ---------------------------------------------
    people, roster = _people_and_roster(generated_at, season_id)
    files["people.json"] = envelope(people, generated_at)
    files["roster.json"] = envelope(roster, generated_at)

    # --- news / videos -------------------------------------------------------
    # Empty on purpose: we hold no licence-cleared feed yet, and inventing
    # headlines is exactly what this project must not do. The real articles we
    # *can* cite live in the story cluster below, with their own URLs.
    files["content/news.json"] = envelope([], generated_at)
    files["content/videos.json"] = envelope([], generated_at)

    # --- discovery bundle ----------------------------------------------------
    # Forecasts are attached to real upcoming fixtures so the weather feature
    # is demonstrable, and so the horizon rule can be seen working.
    upcoming = []
    for records in games_by_month.values():
        for record in records:
            if record["status"] != "scheduled":
                continue
            start = datetime.strptime(record["startTime"], "%Y-%m-%dT%H:%M:%SZ").replace(
                tzinfo=timezone.utc
            )
            lead_days = (start - generated_at_dt).days
            if lead_days >= 0:
                upcoming.append((lead_days, record["id"], record["venueId"], record["startTime"]))
    upcoming.sort()

    files["content/discover.json"] = _discover_bundle(
        generated_at, generated_at_dt, season_id, upcoming
    )

    _write(files, generated_at)



def _box_score(
    game_id: str,
    team_id: str,
    team_index: int,
    runs_for: int,
    runs_against: int,
) -> tuple[list[dict], list[dict]]:
    """Demo batting and pitching lines for one team in one game.

    Deterministic from `game_id`, so rebuilding the seed does not reshuffle
    every record. Everything is `isDemo` — these are not anyone's real numbers,
    and the leaderboards label them as demo wherever they appear.

    Two invariants are honoured because the app checks them and a reader can
    check them too:
      * the batters' runs add up to the team's score;
      * the pitchers concede exactly the opponent's score.
    A box score that does not reconcile with the scoreboard is worse than none.
    """
    rng = random.Random(f"{game_id}:{team_id}")
    positions = ["투수", "포수", "1루수", "2루수", "3루수", "유격수", "좌익수", "중견수", "우익수"]

    batting = []
    # Spread the team's runs across the order, then build a plausible line
    # around each batter's run total.
    scorers = [0] * 9
    for _ in range(runs_for):
        scorers[rng.randrange(9)] += 1

    for slot in range(9):
        person_id = f"person-demo-{team_index}-{slot}"
        at_bats = rng.randint(3, 5)
        # A batter who scored must have reached base at least that often.
        hits = min(at_bats, max(scorers[slot], rng.randint(0, 2)))
        doubles = 1 if hits >= 2 and rng.random() < 0.35 else 0
        home_runs = 1 if hits >= 1 and rng.random() < 0.12 else 0
        singles = hits - doubles - home_runs
        if singles < 0:
            home_runs = 0
            singles = hits - doubles
        batting.append(
            {
                "personId": person_id,
                "playerName": f"데모선수 {team_index + 1}-{slot + 1}",
                "teamId": team_id,
                "battingOrder": slot + 1,
                "position": positions[slot],
                "atBats": at_bats,
                "runs": scorers[slot],
                "hits": hits,
                "doubles": doubles,
                "triples": 0,
                "homeRuns": home_runs,
                "rbi": scorers[slot],
                "walks": rng.randint(0, 1),
                "strikeouts": rng.randint(0, 2),
                "stolenBases": 1 if rng.random() < 0.15 else 0,
            }
        )

    # One starter, occasionally a reliever. Outs add to a nine-inning game.
    starter_outs = rng.choice([18, 21, 27])
    pitching = [
        {
            "personId": f"person-demo-{team_index}-0",
            "playerName": f"데모선수 {team_index + 1}-1",
            "teamId": team_id,
            "outsRecorded": starter_outs,
            "hitsAllowed": max(runs_against, rng.randint(3, 8)),
            "runsAllowed": runs_against,
            "earnedRuns": max(0, runs_against - (1 if rng.random() < 0.3 else 0)),
            "walks": rng.randint(0, 3),
            "strikeouts": rng.randint(2, 9),
            "homeRunsAllowed": 1 if runs_against >= 4 and rng.random() < 0.4 else 0,
            "decision": "win" if runs_for > runs_against else "loss",
        }
    ]
    if starter_outs < 27:
        pitching.append(
            {
                "personId": f"person-demo-{team_index}-1",
                "playerName": f"데모선수 {team_index + 1}-2",
                "teamId": team_id,
                "outsRecorded": 27 - starter_outs,
                "hitsAllowed": rng.randint(0, 3),
                # The starter is already charged with every run, so the
                # reliever is charged with none. Splitting them would need a
                # play-by-play we do not have.
                "runsAllowed": 0,
                "earnedRuns": 0,
                "walks": rng.randint(0, 2),
                "strikeouts": rng.randint(0, 3),
                "homeRunsAllowed": 0,
                "decision": None,
            }
        )
    return batting, pitching


def _line_score(home: int, away: int) -> dict:
    """Distribute runs across nine innings so the innings always sum exactly."""

    def spread(total: int) -> list[int]:
        innings = [0] * 9
        i = 0
        remaining = total
        while remaining > 0:
            take = min(remaining, 1 if i % 2 else 2)
            innings[i % 9] += take
            remaining -= take
            i += 1
        return innings

    home_innings = spread(home)
    away_innings = spread(away)
    return {
        "homeInnings": home_innings,
        "awayInnings": away_innings,
        "homeRuns": home,
        "awayRuns": away,
        "homeHits": home + 3,
        "awayHits": away + 2,
        "homeErrors": 1 if home % 3 == 0 else 0,
        "awayErrors": 1 if away % 4 == 0 else 0,
    }


def _people_and_roster(generated_at: str, season_id: str):
    """Demo roster entries. Names are obviously placeholders and no personal
    data beyond a display name, number and position exists in the schema."""
    positions = ["투수", "포수", "1루수", "2루수", "3루수", "유격수", "좌익수", "중견수", "우익수"]
    people, roster = [], []
    # Every team, not just the first four. A league where half the clubs have
    # no players cannot demonstrate 개인 기록 순위 — most fixtures would have
    # nobody to rank.
    for t_index, (team_id, team_name, *_rest) in enumerate(TEAMS):
        for p in range(9):
            pid = f"person-demo-{t_index}-{p}"
            people.append(
                {
                    "id": pid,
                    "name": f"데모선수 {t_index + 1}-{p + 1}",
                    "isMinor": False,
                    "source": demo_source(generated_at, pid),
                }
            )
            roster.append(
                {
                    "id": f"roster-demo-{t_index}-{p}",
                    "teamId": team_id,
                    "seasonId": season_id,
                    "personId": pid,
                    "jerseyNumber": str(p + 1),
                    "position": positions[p],
                    "source": demo_source(generated_at, f"roster-demo-{t_index}-{p}"),
                }
            )
    return people, roster


def _discover_bundle(
    generated_at: str,
    now: datetime,
    season_id: str,
    upcoming: list | None = None,
) -> dict:
    """Featured topics, the programme, one demo recap, one real story cluster,
    guides, and a weather set that respects the forecast horizon."""

    kst_now = now.astimezone(KST)

    # Channel A programme metadata. Verified from public reporting and the
    # TVING listing; the *episode content* below is explicitly demo.
    program = {
        "id": "program-yaguyeowang",
        "title": "야구여왕",
        "broadcaster": "채널A",
        "streamingUrl": "https://www.tving.com/contents/E004589050",
        "description": "여러 종목 출신 여성 선수들로 구성된 팀의 야구 도전을 다루는 스포츠 버라이어티입니다.",
        "publishedAt": generated_at,
        "summaryMethod": "manual",
        "reviewStatus": REVIEW_DEFAULT,
        "spoilerLevel": "none",
        "source": official_source(
            "tving", "https://www.tving.com/contents/E004589050", generated_at
        ),
        "seasons": [
            {
                "id": "program-season-yaguyeowang-2",
                "seasonNumber": 2,
                "title": "야구여왕 시즌 2",
                # Thursday 22:00 KST, per public programme listings.
                "airDayOfWeek": 4,
                "airTimeMinuteOfDay": 22 * 60,
                "premiereDate": "2026-07-02",
                "isActive": True,
                "publishedAt": generated_at,
                "summaryMethod": "manual",
                "reviewStatus": REVIEW_DEFAULT,
                "spoilerLevel": "none",
                "source": official_source(
                    "tving", "https://www.tving.com/contents/E004589050", generated_at
                ),
                "episodes": [
                    {
                        # DEMO. We hold no verified episode content, so this
                        # exists only to exercise the recap UI and is labelled
                        # as demo everywhere it appears.
                        "id": "episode-demo-yaguyeowang-2-x",
                        "episodeNumber": 1,
                        "title": "데모 회차",
                        "airedAt": (kst_now - timedelta(days=4))
                        .astimezone(timezone.utc)
                        .strftime("%Y-%m-%dT%H:%M:%SZ"),
                        "publishedAt": generated_at,
                        "summaryMethod": "manual",
                        "reviewStatus": REVIEW_DEFAULT,
                        "spoilerLevel": "result",
                        "source": demo_source(generated_at, "episode-demo-yaguyeowang-2-x"),
                        "recap": {
                            "id": "recap-demo-yaguyeowang-2-x",
                            "teaser": "이번 회차는 수비 훈련과 팀 재정비를 다룹니다. (데모 콘텐츠)",
                            "whatHappened": "데모 콘텐츠입니다. 실제 방송 내용이 아닙니다.",
                            "whyItMatters": "회차 요약 화면의 동작을 확인하기 위한 예시입니다.",
                            "whatToWatchNext": "공식 회차 정보가 확인되면 이 자리에 실제 요약이 들어갑니다.",
                            "background": "이 앱은 확인되지 않은 방송 결과를 만들어내지 않습니다. "
                                          "공식 자료가 확보되기 전까지 이 회차는 데모로 표시됩니다.",
                            "realBaseballContext": "방송에 등장하는 인물과 실제 여자야구 팀·선수의 연결은 "
                                                   "공식적으로 확인된 경우에만 표시합니다.",
                            "publishedAt": generated_at,
                            "summaryMethod": "manual",
                            "reviewStatus": REVIEW_DEFAULT,
                            "spoilerLevel": "result",
                            "source": demo_source(generated_at, "recap-demo-yaguyeowang-2-x"),
                        },
                        "people": [],
                    }
                ],
            }
        ],
    }

    # A real story cluster: three genuine articles about the same event, with
    # a human-written summary that states only what those articles report.
    story_cluster = {
        "id": "story-yaguyeowang-s2-confirmed",
        "title": "채널A '야구여왕' 시즌 2 제작 확정과 편성",
        "shortSummary": "채널A의 스포츠 버라이어티 '야구여왕'이 시즌 2 제작을 확정하고 "
                        "2026년 7월 첫 방송으로 편성됐습니다.",
        "whyItMatters": "여자야구를 소재로 한 지상파·종편 예능이 시즌을 이어가면서 "
                        "종목에 대한 대중적 관심이 유지될 수 있는 창구가 생겼습니다.",
        "beginnerContext": "여자야구는 아직 리그 규모가 크지 않아, 방송 콘텐츠가 종목을 처음 접하는 "
                           "사람에게 중요한 입구 역할을 합니다.",
        "isTopStory": True,
        # Times below are UTC, taken from each article's own header. KST is
        # UTC+9, so 12:21 KST is 03:21Z. Midnight-Z was a placeholder that
        # displayed as 09:00 KST on every article — a wrong time on every card.
        "firstPublishedAt": "2026-02-27T03:21:00Z",
        "lastUpdatedAt": "2026-07-01T03:10:00Z",
        "publishedAt": "2026-07-01T03:10:00Z",
        "summaryMethod": "manual",
        "reviewStatus": REVIEW_DEFAULT,
        "spoilerLevel": "none",
        "source": official_source(
            "news-aggregate",
            "https://enews.imbc.com/News/RetrieveNewsInfo/507497",
            generated_at,
        ),
        "sources": [
            {
                "id": "story-src-mt-20260227",
                "title": "'시청률 1%' 채널A 예능 '야구여왕', 시즌2 제작 확정",
                "url": "https://www.mt.co.kr/entertainment/2026/02/27/2026022712217279530",
                # 2026-02-27 12:21 KST
                "publishedAt": "2026-02-27T03:21:00Z",
                "outlet": "머니투데이",
            },
            {
                "id": "story-src-imbc-s2",
                "title": "'야구여왕' 시즌2 제작 확정…오는 7월 첫 방송 \"308명 지원\"",
                "url": "https://enews.imbc.com/News/RetrieveNewsInfo/507497",
                # 2026-06-07 23:31 KST. The previous value said 2026-06-20,
                # which was wrong by 13 days.
                "publishedAt": "2026-06-07T14:31:00Z",
                "outlet": "iMBC 연예",
            },
            {
                "id": "story-src-daum-20260701",
                "title": "전열 가다듬은 채널A '야구여왕' 시즌2로 세계관 본격화",
                "url": "https://v.daum.net/v/20260701121002581",
                # 2026-07-01 12:10 KST
                "publishedAt": "2026-07-01T03:10:00Z",
                "outlet": "다음 뉴스",
            },
        ],
        "links": [],
    }

    guides = [
        {
            "id": "guide-one-minute",
            "kind": "oneMinuteIntro",
            "title": "여자야구 1분 이해",
            "body": "야구는 두 팀이 공격과 수비를 번갈아 하며 정해진 이닝 동안 더 많은 점수를 낸 팀이 "
                    "이기는 경기입니다. 공격 팀은 타자가 공을 치고 1루, 2루, 3루를 돌아 홈으로 "
                    "들어오면 1점을 얻습니다. 수비 팀이 아웃 3개를 잡으면 공수가 교대되고, 양 팀이 "
                    "한 번씩 공격을 마치면 1이닝이 끝납니다.\n\n"
                    "한국 여자야구는 동호인 리그를 중심으로 운영되며, 대회는 주로 주말에 열립니다. "
                    "프로 리그와 달리 경기 수가 적고 구장이 매번 달라질 수 있어, 일정과 장소를 "
                    "미리 확인하는 것이 중요합니다.",
            "anchorKey": "screen:home",
            "readSeconds": 60,
            "publishedAt": generated_at,
            "summaryMethod": "manual",
            "reviewStatus": REVIEW_DEFAULT,
            "source": editorial_source(generated_at),
        },
        {
            "id": "guide-first-visit",
            "kind": "firstVisit",
            "title": "처음 직관할 때 알아둘 것",
            "body": "대부분의 여자야구 경기는 소규모 구장에서 열립니다. 관람석이 따로 없을 수 있으니 "
                    "접이식 의자나 돗자리를 준비하면 편합니다. 그늘이 부족한 구장이 많아 모자와 "
                    "물을 챙기는 것이 좋습니다.\n\n"
                    "관람 가능 여부는 대회마다 다릅니다. 이 앱에서 '확인 필요'로 표시된 경기는 아직 "
                    "공개된 관람 안내가 없다는 뜻이므로, 주최 측 공지를 먼저 확인해 주세요.\n\n"
                    "경기 진행 여부는 날씨에 따라 당일 바뀔 수 있습니다. 출발 전에 일정이 변경되지 "
                    "않았는지 다시 한번 확인하는 것을 권합니다.",
            "anchorKey": "screen:nearby",
            "readSeconds": 70,
            "publishedAt": generated_at,
            "summaryMethod": "manual",
            "reviewStatus": REVIEW_DEFAULT,
            "source": editorial_source(generated_at),
        },
        {
            "id": "guide-stat-era",
            "kind": "statExplainer",
            "title": "평균자책점(ERA)이란?",
            "body": "투수가 9이닝을 던졌다고 가정했을 때 내줄 것으로 예상되는 자책점입니다. "
                    "자책점 × 9 ÷ 이닝으로 계산하며, 낮을수록 좋은 기록입니다. "
                    "수비 실책으로 들어온 점수는 자책점에서 제외됩니다.",
            "anchorKey": "stat:era",
            "readSeconds": 25,
            "publishedAt": generated_at,
            "summaryMethod": "manual",
            "reviewStatus": REVIEW_DEFAULT,
            "source": editorial_source(generated_at),
        },
    ]

    featured_topics = [
        {
            "id": "featured-program-yaguyeowang",
            "kind": "broadcast",
            "title": "야구여왕 시즌 2",
            "subtitle": "채널A · 매주 목요일 밤 10시. 방송에서 실제 여자야구로 이어지는 길을 안내합니다.",
            "priority": 0,
            "programId": "program-yaguyeowang",
            "publishedAt": generated_at,
            "summaryMethod": "manual",
            "reviewStatus": REVIEW_DEFAULT,
            "spoilerLevel": "none",
            "source": official_source(
                "tving", "https://www.tving.com/contents/E004589050", generated_at
            ),
        },
        {
            "id": "featured-wbsc-2026",
            "kind": "international",
            "title": "2026 WBSC 여자야구 월드컵",
            "subtitle": "국제 무대에서 여자야구가 어떻게 겨루는지 공식 일정과 순위를 확인해 보세요.",
            "priority": 1,
            "competitionId": "comp-wbsc-wbwc-2026",
            "publishedAt": generated_at,
            "summaryMethod": "manual",
            "reviewStatus": REVIEW_DEFAULT,
            "source": official_source(
                "wbsc",
                "https://www.wbsc.org/en/events/2026-x-womens-baseball-world-cup-group-stage-rockford/home",
                generated_at,
            ),
        },
        {
            "id": "featured-getting-started",
            "kind": "gettingStarted",
            "title": "여자야구, 어떻게 시작하나요?",
            "subtitle": "규칙부터 가까운 팀 찾기까지 1분이면 감이 옵니다.",
            "priority": 5,
            "guideId": "guide-one-minute",
            "publishedAt": generated_at,
            "summaryMethod": "manual",
            "reviewStatus": REVIEW_DEFAULT,
            "source": editorial_source(generated_at),
        },
    ]

    # Weather, attached to real upcoming fixtures.
    #
    # The horizon rule is expressed in the data itself:
    #   D+0..2  shortTerm       exact temperature allowed
    #   D+3..10 midTerm         range + probability, no exact value
    #   D+11+   beyondForecast  NO daily values at all, only a tendency
    # `WeatherForecastDto` rejects a beyondForecast record that carries a
    # temperature or a precipitation probability, so this cannot drift.
    forecasts = []
    for index, (lead_days, game_id, venue_id, start_time) in enumerate(upcoming or []):
        if lead_days <= 2:
            horizon = "shortTerm"
        elif lead_days <= 10:
            horizon = "midTerm"
        else:
            horizon = "beyondForecast"

        record = {
            "id": f"wx-demo-{game_id}",
            "venueId": venue_id,
            "gameId": game_id,
            "targetTime": start_time,
            "issuedAt": generated_at,
            "horizon": horizon,
            "forecastZone": "데모 예보구역",
            "source": demo_source(generated_at, f"wx-demo-{game_id}"),
        }

        if horizon == "beyondForecast":
            record["seasonalTendency"] = (
                "기상청 상세 예보는 10일까지 제공됩니다. 이 날짜의 일별 예보는 아직 없습니다."
            )
        else:
            record["precipitationProbability"] = [10, 30, 60, 85, 20, 45][index % 6]
            record["windSpeedMs"] = 3.0 + (index % 5) * 2.5
            record["confidence"] = (
                "high" if horizon == "shortTerm" else ("medium" if lead_days <= 6 else "low")
            )
            if horizon == "shortTerm":
                record["temperatureC"] = 26.0 + (index % 8)
            else:
                record["temperatureMinC"] = 20.0 + (index % 5)
                record["temperatureMaxC"] = 28.0 + (index % 6)

        forecasts.append(record)

    return {
        "schemaVersion": SCHEMA_VERSION,
        "dataVersion": generated_at[:10].replace("-", "."),
        "generatedAt": generated_at,
        "payloadKind": "snapshot",
        "items": [
            {
                "featuredTopics": featured_topics,
                "programs": [program],
                "clips": [],
                "storyClusters": [story_cluster],
                "guides": guides,
                "attendance": [],
                "forecasts": forecasts,
            }
        ],
    }


def _write(files: dict[str, dict], generated_at: str) -> None:
    for target in (SEED_DIR, PUBLIC_DIR):
        for sub in ("competitions", "games", "content", "standings"):
            os.makedirs(os.path.join(target, sub), exist_ok=True)

    manifest_files = []
    for rel_path, payload in sorted(files.items()):
        # The single promotion point. Everything reaches disk at the honest
        # default unless a named reviewer signed off in REVIEW_LEDGER.
        apply_review_ledger(payload, generated_at)
        body = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
        raw = body.encode("utf-8")
        digest = hashlib.sha256(raw).hexdigest()
        manifest_files.append(
            {"path": rel_path, "sha256": digest, "size": len(raw)}
        )
        for target in (SEED_DIR, PUBLIC_DIR):
            out = os.path.join(target, rel_path)
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out, "w", encoding="utf-8", newline="\n") as f:
                f.write(body)

    version = {
        "schemaVersion": SCHEMA_VERSION,
        "dataVersion": generated_at[:10].replace("-", ".") + ".1",
        "generatedAt": generated_at,
        "files": manifest_files,
    }
    body = json.dumps(version, ensure_ascii=False, indent=2) + "\n"
    for target in (SEED_DIR, PUBLIC_DIR):
        with open(os.path.join(target, "version.json"), "w", encoding="utf-8", newline="\n") as f:
            f.write(body)

    print(f"wrote {len(manifest_files)} files + version.json")
    print(f"  seed:   {SEED_DIR}")
    print(f"  public: {PUBLIC_DIR}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--generated-at",
        default=None,
        help="ISO-8601 UTC instant the data set is stamped with (default: now).",
    )
    parser.add_argument("--clean", action="store_true", help="Remove outputs first.")
    args = parser.parse_args()

    if args.clean:
        for target in (SEED_DIR, PUBLIC_DIR):
            if os.path.isdir(target):
                shutil.rmtree(target)

    if args.generated_at:
        stamp = datetime.fromisoformat(args.generated_at.replace("Z", "+00:00"))
    else:
        stamp = datetime.now(timezone.utc)
    build(stamp.astimezone(timezone.utc).replace(microsecond=0))


if __name__ == "__main__":
    main()
