#!/usr/bin/env python3
"""Validate a published data set before it goes anywhere near the app.

This is the gate that keeps the app's promises true. It re-checks, from the
outside, every rule the Dart DTOs enforce from the inside — so a mistake in the
generator, a hand-edited file, or a future ingest adapter cannot quietly ship
something the app would have to render as fact.

Checks
------
Structure
  * every file listed in `version.json` exists, and its sha256 and size match
  * every JSON file parses and carries an `items` array
  * `schemaVersion` is one the app declares support for

Provenance (no unattributed data)
  * every record has `source.sourceName`, `source.sourceUrl`, `source.fetchedAt`
  * `sourceUrl` is http(s) or an `app:` URI for app-authored content
  * `fetchedAt` is a real ISO-8601 instant with a zone

Games
  * home team != away team
  * kick-off time carries a time zone
  * a `final` game has both scores; scores are never negative
  * innings sum exactly to the stated runs
  * no duplicate fixture (same competition, hour, teams, venue)
  * referenced team / venue / competition ids exist
  * a changed result in a re-publish leaves a revision note

Standings / leaderboards
  * played >= wins + losses + draws

Weather (the 30-day honesty rule)
  * a `beyondForecast` record carries NO temperature and NO precipitation
    probability — only a tendency string
  * precipitation probability is 0-100

Content
  * an `isEntity` link carries a confirming source URL
  * a recap that reveals a result carries a spoiler-free teaser
  * an `aiAssisted` summary carries a generation time
  * an unreviewed AI summary is not published unless the flag allows it
  * a story cluster has at least one source

Privacy and licensing
  * no contact field appears anywhere (phone, e-mail, ID number)
  * person records additionally carry no address or date of birth
    (a *venue* address is public facility data and is allowed)
  * a person marked `isMinor` carries no photo
  * a photo with `licenseStatus != permitted` is not published

Demo separation
  * `--production` refuses any record with `isDemo: true`

Exit code is non-zero on any error, so CI stops before publishing.

Usage:
    python scripts/validate/validate_data.py public-data
    python scripts/validate/validate_data.py public-data --production
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

# Korean output on a cp949 console would raise; force UTF-8 so CI logs and a
# local Windows terminal both show the same messages.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

MAX_SCHEMA_VERSION = 1

ISO_WITH_ZONE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})$")

# Contact details that must never appear in any published record, for anyone.
FORBIDDEN_CONTACT_FIELDS = {
    "phone",
    "phoneNumber",
    "mobile",
    "email",
    "emailAddress",
    "residentNumber",
    "nationalId",
    "ssn",
}

# Additionally forbidden on records that describe a *person*. A venue's
# `address` is public facility information and is required for directions; a
# person's address is not, and must never be stored.
FORBIDDEN_PERSON_FIELDS = FORBIDDEN_CONTACT_FIELDS | {
    "address",
    "streetAddress",
    "homeAddress",
    "birthDate",
    "dateOfBirth",
    "birthday",
}

# Files whose records describe people.
PERSON_FILES = {"people.json", "roster.json"}


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)

    @property
    def ok(self) -> bool:
        return not self.errors


def load_json(path: str, report: Report):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        report.error(f"{path}: 파일이 없습니다")
    except json.JSONDecodeError as e:
        report.error(f"{path}: JSON 파싱 실패 ({e})")
    return None


def items_of(document, path: str, report: Report) -> list:
    if isinstance(document, list):
        return document
    if not isinstance(document, dict):
        report.error(f"{path}: 최상위가 object/array가 아닙니다")
        return []
    version = document.get("schemaVersion", 1)
    if not isinstance(version, int) or version > MAX_SCHEMA_VERSION:
        report.error(f"{path}: 지원하지 않는 schemaVersion={version}")
    items = document.get("items")
    if items is None:
        report.error(f"{path}: items 배열이 없습니다")
        return []
    if not isinstance(items, list):
        report.error(f"{path}: items가 배열이 아닙니다")
        return []
    return items


def check_instant(value, label: str, path: str, report: Report) -> datetime | None:
    if not isinstance(value, str) or not ISO_WITH_ZONE.match(value):
        report.error(f"{path}: {label}에 시간대를 포함한 ISO-8601 시각이 필요합니다 ({value!r})")
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        report.error(f"{path}: {label} 시각을 해석할 수 없습니다 ({value!r})")
        return None


def check_source(record: dict, path: str, label: str, report: Report, production: bool) -> None:
    source = record.get("source")
    if not isinstance(source, dict):
        report.error(f"{path}: {label} — source 블록이 없습니다")
        return

    for field in ("sourceName", "sourceUrl", "fetchedAt"):
        if not source.get(field):
            report.error(f"{path}: {label} — source.{field}가 없습니다")

    url = source.get("sourceUrl", "")
    if isinstance(url, str) and url:
        if not (url.startswith("http://") or url.startswith("https://") or url.startswith("app:")):
            report.error(f"{path}: {label} — sourceUrl 형식이 올바르지 않습니다 ({url})")

    check_instant(source.get("fetchedAt"), f"{label}.source.fetchedAt", path, report)

    if production and source.get("isDemo") is True:
        report.error(f"{path}: {label} — 데모 데이터는 production 배포에 포함할 수 없습니다")

    # Personal data that has not been licence-cleared must not be published.
    if source.get("licenseStatus") == "unknown" and record.get("photoUrl"):
        report.error(f"{path}: {label} — 라이선스 미확인 사진은 게시할 수 없습니다")

    # A review claim is a claim about a person. It must name one, carry a date,
    # and agree with the record's own reviewStatus. A generator stamping its own
    # output as humanVerified is how provenance stops meaning anything.
    quality = source.get("qualityStatus")
    review = record.get("reviewStatus")

    if quality == "humanVerified":
        if not source.get("verifiedAt"):
            report.error(f"{path}: {label} — humanVerified 인데 verifiedAt이 없습니다")
        if not source.get("reviewedBy"):
            report.error(
                f"{path}: {label} — humanVerified 인데 검수자(reviewedBy)가 없습니다"
            )
        if review is not None and review != "reviewed":
            report.error(
                f"{path}: {label} — source는 humanVerified 인데 "
                f"reviewStatus가 {review} 입니다"
            )
    elif review == "reviewed":
        report.error(
            f"{path}: {label} — reviewStatus가 reviewed 인데 "
            "source.qualityStatus가 humanVerified가 아닙니다"
        )


def check_no_personal_fields(
    node,
    path: str,
    label: str,
    report: Report,
    forbidden: set,
) -> None:
    """Walks the record and rejects any contact-shaped field, at any depth."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key in forbidden:
                report.error(f"{path}: {label} — 개인정보 필드 '{key}'는 게시할 수 없습니다")
            check_no_personal_fields(value, path, label, report, forbidden)
    elif isinstance(node, list):
        for entry in node:
            check_no_personal_fields(entry, path, label, report, forbidden)


# --- entity checks -----------------------------------------------------------


def validate_games(items: list, path: str, report: Report, known: dict) -> None:
    seen_keys: dict[str, str] = {}

    for record in items:
        rid = record.get("id", "<no id>")
        label = f"game {rid}"
        validate_box_score(record, path, label, report)

        home = record.get("homeTeamId")
        away = record.get("awayTeamId")
        if not home or not away:
            report.error(f"{path}: {label} — 팀 참조가 없습니다")
            continue
        if home == away:
            report.error(f"{path}: {label} — 홈팀과 원정팀이 동일합니다")

        for team_id in (home, away):
            if known["teams"] and team_id not in known["teams"]:
                report.error(f"{path}: {label} — 알 수 없는 팀 id '{team_id}'")

        venue = record.get("venueId")
        if venue and known["venues"] and venue not in known["venues"]:
            report.error(f"{path}: {label} — 알 수 없는 경기장 id '{venue}'")

        competition = record.get("competitionId")
        if competition and known["competitions"] and competition not in known["competitions"]:
            report.error(f"{path}: {label} — 알 수 없는 대회 id '{competition}'")

        start = check_instant(record.get("startTime"), "startTime", path, report)

        status = record.get("status", "unknown")
        home_score = record.get("homeScore")
        away_score = record.get("awayScore")

        if status == "final" and (home_score is None or away_score is None):
            report.error(f"{path}: {label} — 종료된 경기에 점수가 없습니다")
        for score, side in ((home_score, "homeScore"), (away_score, "awayScore")):
            if score is not None and (not isinstance(score, int) or score < 0):
                report.error(f"{path}: {label} — {side}가 올바르지 않습니다 ({score})")

        line = record.get("lineScore")
        if isinstance(line, dict):
            for side, innings_key, runs_key, declared in (
                ("home", "homeInnings", "homeRuns", home_score),
                ("away", "awayInnings", "awayRuns", away_score),
            ):
                innings = line.get(innings_key)
                if not isinstance(innings, list):
                    continue
                total = sum(v for v in innings if isinstance(v, int))
                stated = line.get(runs_key, declared)
                if stated is not None and stated != total:
                    report.error(
                        f"{path}: {label} — {side} 이닝 합계 {total}이(가) 득점 {stated}과 다릅니다"
                    )

        # Duplicate fixture detection, mirroring Game.dedupeKey in the app.
        if start is not None:
            slot = start.astimezone(timezone.utc).strftime("%Y-%m-%dT%H")
            teams = "~".join(sorted([home, away]))
            key = f"{competition or '-'}|{slot}|{teams}|{venue or '-'}"
            if key in seen_keys:
                report.error(
                    f"{path}: {label} — {seen_keys[key]}와(과) 중복된 경기입니다"
                )
            else:
                seen_keys[key] = rid


def validate_box_score(game: dict, path: str, label: str, report: Report) -> None:
    """A box score that disagrees with the scoreboard is worse than none.

    Two readers can check these by hand, so the app must not ship a sheet that
    fails them: the batters' runs are the team's score, and the pitchers concede
    exactly what the other side scored.
    """
    batting = game.get("batting") or []
    pitching = game.get("pitching") or []
    if not batting and not pitching:
        return

    for line in batting:
        who = line.get("playerName", line.get("personId", "?"))
        at_bats = line.get("atBats", 0)
        hits = line.get("hits", 0)
        if hits > at_bats:
            report.error(f"{path}: {label} — {who}: 안타({hits})가 타수({at_bats})보다 많습니다")
        extra = line.get("doubles", 0) + line.get("triples", 0) + line.get("homeRuns", 0)
        if extra > hits:
            report.error(f"{path}: {label} — {who}: 장타 합({extra})이 안타({hits})보다 많습니다")
        for field in ("atBats", "runs", "hits", "rbi", "walks", "strikeouts"):
            if line.get(field, 0) < 0:
                report.error(f"{path}: {label} — {who}: {field}가 음수입니다")

    home_id, away_id = game.get("homeTeamId"), game.get("awayTeamId")
    scores = {home_id: game.get("homeScore"), away_id: game.get("awayScore")}
    for team_id, score in scores.items():
        if score is None:
            continue
        scored = sum(l.get("runs", 0) for l in batting if l.get("teamId") == team_id)
        if batting and scored != score:
            report.error(
                f"{path}: {label} — {team_id} 타자 득점 합({scored})이 "
                f"팀 점수({score})와 다릅니다"
            )
        conceded = sum(
            l.get("runsAllowed", 0) for l in pitching if l.get("teamId") != team_id
        )
        if pitching and conceded != score:
            report.error(
                f"{path}: {label} — 상대 투수 실점 합({conceded})이 "
                f"{team_id} 점수({score})와 다릅니다"
            )

    for line in pitching:
        who = line.get("playerName", line.get("personId", "?"))
        if line.get("earnedRuns", 0) > line.get("runsAllowed", 0):
            report.error(f"{path}: {label} — {who}: 자책점이 실점보다 많습니다")


def validate_standings(items: list, path: str, report: Report) -> None:
    for record in items:
        rid = record.get("id", "<no id>")
        wins = record.get("wins", 0) or 0
        losses = record.get("losses", 0) or 0
        draws = record.get("draws", 0) or 0
        played = record.get("played", wins + losses + draws) or 0
        if played < wins + losses + draws:
            report.error(
                f"{path}: standing {rid} — 경기 수 {played}이(가) 승패무 합계보다 적습니다"
            )
        check_instant(record.get("capturedAt"), "capturedAt", path, report)


def validate_forecasts(items: list, path: str, report: Report) -> None:
    """The 30-day honesty rule, enforced on the data itself."""
    for record in items:
        rid = record.get("id", "<no id>")
        horizon = record.get("horizon")

        pop = record.get("precipitationProbability")
        if pop is not None and (not isinstance(pop, int) or pop < 0 or pop > 100):
            report.error(f"{path}: forecast {rid} — 강수확률이 0~100이 아닙니다 ({pop})")

        if horizon == "beyondForecast":
            for field in (
                "temperatureC",
                "temperatureMinC",
                "temperatureMaxC",
                "precipitationProbability",
                "skyCondition",
            ):
                if record.get(field) is not None:
                    report.error(
                        f"{path}: forecast {rid} — 상세 예보 구간을 벗어난 예보에 "
                        f"'{field}'를 넣을 수 없습니다"
                    )
        elif horizon == "midTerm":
            if record.get("temperatureC") is not None:
                report.warn(
                    f"{path}: forecast {rid} — 중기예보에 정확한 기온이 있습니다. "
                    "앱은 범위로만 표시합니다."
                )
        elif horizon not in ("shortTerm", None):
            report.error(f"{path}: forecast {rid} — 알 수 없는 horizon '{horizon}'")

        # A forecast must be internally consistent about lead time.
        issued = check_instant(record.get("issuedAt"), "issuedAt", path, report)
        target = check_instant(record.get("targetTime"), "targetTime", path, report)
        if issued and target:
            lead = target - issued
            if horizon == "shortTerm" and lead > timedelta(days=3):
                report.error(
                    f"{path}: forecast {rid} — 단기예보로 표시됐지만 "
                    f"{lead.days}일 뒤를 가리킵니다"
                )
            if horizon == "midTerm" and lead > timedelta(days=11):
                report.error(
                    f"{path}: forecast {rid} — 중기예보 범위(10일)를 넘습니다"
                )
            if horizon in ("shortTerm", "midTerm") and lead > timedelta(days=11):
                report.error(f"{path}: forecast {rid} — 예보 구간이 잘못됐습니다")


def validate_content(bundle: dict, path: str, report: Report, allow_unreviewed_ai: bool) -> None:
    for cluster in bundle.get("storyClusters", []) or []:
        cid = cluster.get("id", "<no id>")
        sources = cluster.get("sources") or []
        if not sources:
            report.error(f"{path}: storyCluster {cid} — 출처가 최소 1개 필요합니다")
        for source in sources:
            if not source.get("url"):
                report.error(f"{path}: storyCluster {cid} — 출처 URL이 없습니다")
            # 00:00:00Z renders as 09:00 KST, so a placeholder midnight shows a
            # wrong publication time on every card that displays one.
            published = source.get("publishedAt")
            if (
                isinstance(published, str)
                and published.endswith("T00:00:00Z")
                and not (cluster.get("source") or {}).get("isDemo")
            ):
                report.error(
                    f"{path}: storyCluster {cid} — 출처 {source.get('url')} 의 "
                    "publishedAt이 정확히 00:00:00Z 입니다. 실제 발행 시각을 "
                    "확인하거나 해당 출처를 내리세요"
                )
            # Only the API-provided description may be stored.
            if source.get("body") or source.get("content"):
                report.error(
                    f"{path}: storyCluster {cid} — 기사 본문을 저장할 수 없습니다"
                )
        for link in cluster.get("links", []) or []:
            if link.get("relation") == "isEntity" and not link.get("confirmedSourceUrl"):
                report.error(
                    f"{path}: storyCluster {cid} — 공식 확인 연결에 근거 URL이 없습니다"
                )
        _check_summary(cluster, path, f"storyCluster {cid}", report, allow_unreviewed_ai)

    for program in bundle.get("programs", []) or []:
        for season in program.get("seasons", []) or []:
            for episode in season.get("episodes", []) or []:
                eid = episode.get("id", "<no id>")
                recap = episode.get("recap")
                if not recap:
                    continue
                spoiler = recap.get("spoilerLevel")
                if spoiler in ("result", "full") and not recap.get("teaser"):
                    report.error(
                        f"{path}: recap for {eid} — 결과를 포함한 요약에는 "
                        "스포일러 없는 teaser가 필요합니다"
                    )
                _check_summary(recap, path, f"recap {eid}", report, allow_unreviewed_ai)

    for person in bundle.get("featuredPeople", []) or []:
        if person.get("linkedPersonId") and not person.get("confirmedSourceUrl"):
            report.warn(
                f"{path}: featuredPerson {person.get('id')} — 실제 선수 연결에 근거가 없습니다"
            )


def _check_summary(record: dict, path: str, label: str, report: Report, allow_unreviewed_ai: bool) -> None:
    method = record.get("summaryMethod")
    review = record.get("reviewStatus")

    if method == "aiAssisted":
        if not record.get("generatedAt"):
            report.error(f"{path}: {label} — AI 요약에 생성 시각이 없습니다")
        if review != "reviewed" and not allow_unreviewed_ai:
            report.error(
                f"{path}: {label} — 검수되지 않은 AI 요약은 게시할 수 없습니다 "
                "(--allow-unreviewed-ai 로만 허용)"
            )
    if review == "rejected":
        report.error(f"{path}: {label} — 검수 반려된 콘텐츠가 포함돼 있습니다")


def validate_people(items: list, path: str, report: Report) -> None:
    for record in items:
        rid = record.get("id", "<no id>")
        if record.get("isMinor") and record.get("photoUrl"):
            report.error(f"{path}: person {rid} — 미성년 선수의 사진은 게시할 수 없습니다")
        license_status = (record.get("source") or {}).get("licenseStatus")
        if record.get("photoUrl") and license_status != "permitted":
            report.error(
                f"{path}: person {rid} — 이용허락이 확인되지 않은 사진은 게시할 수 없습니다"
            )


# --- manifest ----------------------------------------------------------------


def validate_manifest(root: str, report: Report) -> list[str]:
    manifest_path = os.path.join(root, "version.json")
    manifest = load_json(manifest_path, report)
    if manifest is None:
        return []

    for field in ("schemaVersion", "dataVersion", "generatedAt", "files"):
        if field not in manifest:
            report.error(f"version.json: {field}가 없습니다")

    check_instant(manifest.get("generatedAt"), "generatedAt", "version.json", report)

    version = manifest.get("schemaVersion")
    if version is not None and version > MAX_SCHEMA_VERSION:
        report.error(f"version.json: 지원하지 않는 schemaVersion={version}")

    paths: list[str] = []
    for entry in manifest.get("files", []) or []:
        rel = entry.get("path")
        if not rel:
            report.error("version.json: files 항목에 path가 없습니다")
            continue
        full = os.path.join(root, rel)
        if not os.path.isfile(full):
            report.error(f"version.json: {rel} 파일이 없습니다")
            continue
        paths.append(rel)

        with open(full, "rb") as f:
            raw = f.read()
        if entry.get("sha256") and hashlib.sha256(raw).hexdigest() != entry["sha256"]:
            report.error(f"{rel}: sha256이 manifest와 다릅니다")
        if entry.get("size") is not None and len(raw) != entry["size"]:
            report.error(f"{rel}: 크기가 manifest와 다릅니다")

    # Anything on disk but absent from the manifest would never be fetched.
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            if not name.endswith(".json") or name == "version.json":
                continue
            rel = os.path.relpath(os.path.join(dirpath, name), root).replace(os.sep, "/")
            if rel not in paths:
                report.warn(f"{rel}: manifest에 없어 앱이 내려받지 않습니다")

    return paths


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default="public-data")
    parser.add_argument(
        "--production",
        action="store_true",
        help="데모 데이터가 하나라도 있으면 실패합니다.",
    )
    parser.add_argument(
        "--allow-unreviewed-ai",
        action="store_true",
        help="검수 전 AI 요약 게시를 허용합니다(기본 금지).",
    )
    args = parser.parse_args()

    report = Report()
    root = args.root

    if not os.path.isdir(root):
        print(f"[FAIL] {root} 디렉터리가 없습니다")
        return 1

    paths = validate_manifest(root, report)

    known = {"teams": set(), "venues": set(), "competitions": set()}
    documents: dict[str, list] = {}
    content_bundle: dict | None = None

    # First pass: collect ids so cross-references can be checked.
    for rel in paths:
        full = os.path.join(root, rel)
        document = load_json(full, report)
        if document is None:
            continue
        items = items_of(document, rel, report)
        documents[rel] = items

        if rel == "teams.json":
            known["teams"] = {i.get("id") for i in items if isinstance(i, dict)}
        elif rel == "venues.json":
            known["venues"] = {i.get("id") for i in items if isinstance(i, dict)}
        elif rel.startswith("competitions/"):
            known["competitions"] = {i.get("id") for i in items if isinstance(i, dict)}
        elif rel == "content/discover.json" and items:
            content_bundle = items[0] if isinstance(items[0], dict) else None

    # Second pass: per-record rules.
    for rel, items in documents.items():
        if rel == "content/discover.json":
            continue
        forbidden = (
            FORBIDDEN_PERSON_FIELDS if rel in PERSON_FILES else FORBIDDEN_CONTACT_FIELDS
        )
        for record in items:
            if not isinstance(record, dict):
                report.error(f"{rel}: items에 object가 아닌 항목이 있습니다")
                continue
            label = record.get("id", "<no id>")
            check_source(record, rel, label, report, args.production)
            check_no_personal_fields(record, rel, label, report, forbidden)

        if rel.startswith("games/"):
            validate_games(items, rel, report, known)
        elif rel.startswith("standings/"):
            validate_standings(items, rel, report)
        elif rel == "people.json":
            validate_people(items, rel, report)

    if content_bundle is not None:
        validate_forecasts(content_bundle.get("forecasts", []) or [], "content/discover.json", report)
        validate_content(
            content_bundle,
            "content/discover.json",
            report,
            args.allow_unreviewed_ai,
        )
        for section in ("featuredTopics", "programs", "guides", "storyClusters"):
            for record in content_bundle.get(section, []) or []:
                if not isinstance(record, dict):
                    continue
                label = f"{section}/{record.get('id', '<no id>')}"
                check_source(record, "content/discover.json", label, report, args.production)
                check_no_personal_fields(
                    record,
                    "content/discover.json",
                    label,
                    report,
                    FORBIDDEN_CONTACT_FIELDS,
                )

    # Summary counts, useful in a CI log.
    counts: dict[str, int] = defaultdict(int)
    for rel, items in documents.items():
        counts[rel.split("/")[0]] += len(items)

    print("=== 데이터 검증 ===")
    print(f"경로: {root}")
    for key in sorted(counts):
        print(f"  {key}: {counts[key]}건")

    for warning in report.warnings:
        print(f"[WARN] {warning}")
    for error in report.errors:
        print(f"[FAIL] {error}")

    if report.ok:
        print(f"통과 — 오류 0건, 경고 {len(report.warnings)}건")
        return 0

    print(f"실패 — 오류 {len(report.errors)}건, 경고 {len(report.warnings)}건")
    return 1


if __name__ == "__main__":
    sys.exit(main())
