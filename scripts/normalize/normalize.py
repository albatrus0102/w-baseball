#!/usr/bin/env python3
"""Turn raw snapshots into publishable records.

Stage 2 of the pipeline. Reads `build/raw/**` and writes `build/normalized/**`
in the published contract shape (see `schemas/`).

Three jobs, in order:

1. **Normalise** — map each source's field names onto the contract, strip HTML
   the search APIs return in titles, and put every timestamp into UTC ISO-8601
   with an explicit zone.
2. **Resolve aliases** — map a source's team spelling onto a canonical id using
   `assets/seed/teams.json` aliases plus Korean-aware normalisation. An alias we
   do not recognise is **never auto-published**; it is written to
   `review/unknown-aliases.json` for a person to decide.
3. **Cluster stories** — group articles that describe the same event so the app
   can show one card with several sources instead of five near-identical rows.

Rules this stage will not break:

  * A summary is only ever the description the API itself returned, a
    deterministic template built from structured fields, or text a person
    wrote. A headline is never expanded into a claim about what happened.
  * `summaryMethod` and `reviewStatus` are always set, so the app can label
    what the reader is looking at.
  * Nothing is marked `reviewed` by this script. Automation produces
    candidates; a person promotes them.

Usage:
    python scripts/normalize/normalize.py --in build/raw --out build/normalized
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import html
import json
import os
import re
import sys
import unicodedata
from datetime import datetime, timezone

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

TAG_RE = re.compile(r"<[^>]+>")
PUNCT = set(".,-_()[]·/'\"")

# Hangul syllable block, and the 19 lead consonants in Unicode order. Mirrors
# `KoreanText` in the app so both sides agree on what "the same name" means.
HANGUL_BASE = 0xAC00
HANGUL_END = 0xD7A3
JAMO_PER_LEAD = 588
LEADS = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"


def strip_markup(value: str) -> str:
    """Search APIs return `<b>` around matched terms. Store plain text."""
    return html.unescape(TAG_RE.sub("", value or "")).strip()


def normalize_name(value: str) -> str:
    """Case-folded, whitespace- and punctuation-free form used for matching."""
    out = []
    for char in unicodedata.normalize("NFC", value or ""):
        if char.isspace() or char in PUNCT:
            continue
        out.append(char.lower())
    return "".join(out)


def initials(value: str) -> str:
    """초성 extraction, so `ㅅㅇ` matches `서울`."""
    out = []
    for char in unicodedata.normalize("NFC", value or ""):
        if char.isspace():
            continue
        code = ord(char)
        if HANGUL_BASE <= code <= HANGUL_END:
            out.append(LEADS[(code - HANGUL_BASE) // JAMO_PER_LEAD])
        else:
            out.append(char.lower())
    return "".join(out)


def parse_rfc822(value: str) -> str | None:
    """Naver returns RFC 822 dates; the contract needs ISO-8601 UTC."""
    if not value:
        return None
    from email.utils import parsedate_to_datetime

    try:
        parsed = parsedate_to_datetime(value)
    except (TypeError, ValueError):
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_alias_index() -> dict[str, str]:
    """Canonical team ids keyed by every spelling we know."""
    index: dict[str, str] = {}
    teams_path = os.path.join(ROOT, "assets", "seed", "teams.json")
    if not os.path.isfile(teams_path):
        return index
    with open(teams_path, encoding="utf-8") as f:
        document = json.load(f)
    for team in document.get("items", []):
        team_id = team.get("id")
        if not team_id:
            continue
        forms = {team.get("name"), team.get("shortName"), *(team.get("aliases") or [])}
        for form in forms:
            if not form:
                continue
            index[normalize_name(form)] = team_id
            index[initials(form)] = team_id
    return index


def resolve_team(name: str, index: dict[str, str], unknown: list[dict]) -> str | None:
    """Never guesses. An unrecognised spelling goes to human review."""
    if not name:
        return None
    key = normalize_name(name)
    if key in index:
        return index[key]
    unknown.append({"name": name, "normalized": key, "initials": initials(name)})
    return None


def story_key(title: str) -> str:
    """A crude but stable event key: the significant words of a headline.

    Deliberately conservative. Grouping two unrelated stories is worse than
    leaving them separate, so short/common tokens are dropped and the rest must
    match exactly.
    """
    stopwords = {"여자야구", "야구", "관련", "기사", "속보", "종합", "포토", "영상"}
    tokens = [
        t
        for t in re.split(r"[^0-9A-Za-z가-힣]+", strip_markup(title))
        if len(t) >= 2 and t not in stopwords
    ]
    tokens = sorted(set(tokens))[:6]
    if not tokens:
        return hashlib.sha256(strip_markup(title).encode("utf-8")).hexdigest()[:16]
    return hashlib.sha256("|".join(tokens).encode("utf-8")).hexdigest()[:16]


def normalize_news(raw_files: list[str], alias_index: dict[str, str]) -> dict:
    """Articles -> story clusters, with sources preserved per cluster."""
    unknown_aliases: list[dict] = []
    clusters: dict[str, dict] = {}
    fetched_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    for path in raw_files:
        with open(path, encoding="utf-8") as f:
            document = json.load(f)
        for item in document.get("items", []):
            title = strip_markup(item.get("title", ""))
            url = item.get("originallink") or item.get("link")
            published = parse_rfc822(item.get("pubDate", ""))
            if not title or not url or not published:
                # A record we cannot attribute or date is not publishable.
                continue

            key = story_key(title)
            source_id = "src-" + hashlib.sha256(url.encode("utf-8")).hexdigest()[:16]

            cluster = clusters.setdefault(
                key,
                {
                    "id": f"story-{key}",
                    "title": title,
                    # No summary is generated here. A template summary is added
                    # below only when it states nothing beyond the counts.
                    "shortSummary": None,
                    "isTopStory": False,
                    "firstPublishedAt": published,
                    "lastUpdatedAt": published,
                    "sources": [],
                    "links": [],
                    "publishedAt": published,
                    "summaryMethod": "template",
                    # Automation never marks its own output reviewed.
                    "reviewStatus": "pending",
                    "spoilerLevel": "none",
                    "source": {
                        "sourceName": "naver-news",
                        "sourceUrl": url,
                        "fetchedAt": fetched_at,
                        "licenseStatus": "linkOnly",
                        "isDemo": False,
                    },
                },
            )

            if any(s["url"] == url for s in cluster["sources"]):
                continue

            cluster["sources"].append(
                {
                    "id": source_id,
                    "title": title,
                    "url": url,
                    "publishedAt": published,
                    "outlet": urlhost(url),
                    # Only the API's own description. Never the article body.
                    "apiDescription": strip_markup(item.get("description", "")) or None,
                }
            )
            cluster["firstPublishedAt"] = min(cluster["firstPublishedAt"], published)
            cluster["lastUpdatedAt"] = max(cluster["lastUpdatedAt"], published)

            for team_name in extract_team_names(title):
                team_id = resolve_team(team_name, alias_index, unknown_aliases)
                if team_id and not any(l["toId"] == team_id for l in cluster["links"]):
                    cluster["links"].append(
                        {
                            "id": f"link-{key}-{team_id}",
                            "fromKind": "storyCluster",
                            "fromId": cluster["id"],
                            "toKind": "team",
                            "toId": team_id,
                            # "mentions", never "isEntity": a headline naming a
                            # team is not a verified identity claim.
                            "relation": "mentions",
                            "label": team_name,
                        }
                    )

    # A template summary states only what can be counted, never what happened.
    for cluster in clusters.values():
        count = len(cluster["sources"])
        if count > 1:
            cluster["shortSummary"] = (
                f"{count}개 매체가 같은 사안을 보도했습니다. 각 매체의 원문에서 "
                "자세한 내용을 확인할 수 있습니다."
            )
        else:
            # One source and no human summary: show the headline only.
            cluster["shortSummary"] = None

    return {
        "storyClusters": sorted(
            clusters.values(), key=lambda c: c["lastUpdatedAt"], reverse=True
        ),
        "unknownAliases": unknown_aliases,
    }


def urlhost(url: str) -> str | None:
    from urllib.parse import urlparse

    host = urlparse(url).netloc
    return host.replace("www.", "") or None


def extract_team_names(title: str) -> list[str]:
    """Candidate team mentions. Only quite-specific tokens, to avoid noise."""
    return [t for t in re.findall(r"[가-힣]{2,}\s?[가-힣]{2,}", title) if len(t) >= 4]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--in", dest="src", default="build/raw")
    parser.add_argument("--out", dest="dst", default="build/normalized")
    args = parser.parse_args()

    os.makedirs(args.dst, exist_ok=True)
    review_dir = os.path.join(args.dst, "review")
    os.makedirs(review_dir, exist_ok=True)

    alias_index = load_alias_index()
    print(f"별칭 색인 {len(alias_index)}건 로드")

    news_files = sorted(glob.glob(os.path.join(args.src, "naver-news", "*.json")))
    if not news_files:
        print("수집된 뉴스 스냅샷이 없습니다. fetch 단계를 먼저 실행하세요.")

    result = normalize_news(news_files, alias_index)

    bundle_path = os.path.join(args.dst, "content-candidates.json")
    with open(bundle_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(
            {"storyClusters": result["storyClusters"]},
            f,
            ensure_ascii=False,
            indent=2,
        )

    unknown_path = os.path.join(review_dir, "unknown-aliases.json")
    with open(unknown_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(result["unknownAliases"], f, ensure_ascii=False, indent=2)

    print(f"이야기 묶음 {len(result['storyClusters'])}건 → {bundle_path}")
    print(
        f"미확인 팀 별칭 {len(result['unknownAliases'])}건 → {unknown_path} "
        "(사람 검수 전까지 자동 게시하지 않습니다)"
    )
    print(
        "\n모든 후보는 reviewStatus='pending' 입니다. "
        "검수 후에만 production 배포에 포함하세요."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
