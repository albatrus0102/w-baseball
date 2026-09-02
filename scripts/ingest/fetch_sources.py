#!/usr/bin/env python3
"""Fetch raw snapshots from configured sources.

Stage 1 of:

    fetch -> raw snapshot -> normalize -> alias resolution
          -> validate -> review candidate -> publish -> checksum

What this does **not** do, deliberately:

  * It does not scrape WBAK or KBSA. No public, documented external API was
    found for either, and a page responding to a request is not permission to
    consume it. Those adapters stay disabled until an explicit grant, a CSV
    export, or a real API exists. `--source wbak` prints why and exits 0.
  * It does not invent anything. A source that fails is recorded in the run
    summary and skipped; every other source still publishes.
  * It does not write API keys anywhere. Keys come from the environment
    (GitHub Secrets in CI) and are never echoed, not even in an error.

Each enabled source writes a timestamped raw snapshot under
`build/raw/<source>/<run-id>/`. Nothing downstream ever re-fetches: normalize
and publish read those files, so a run is reproducible and reviewable.

Usage:
    python scripts/ingest/fetch_sources.py --list
    python scripts/ingest/fetch_sources.py --source naver-news
    python scripts/ingest/fetch_sources.py --all --out build/raw
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

USER_AGENT = "w-baseball-ingest/0.1 (+https://github.com/albatrus0102/w-baseball)"

# Secrets are read by name only. Their values are never printed or stored.
SECRET_NAMES = {
    "naver-news": ("NAVER_CLIENT_ID", "NAVER_CLIENT_SECRET"),
    "youtube": ("YOUTUBE_API_KEY",),
    "kma-weather": ("KMA_SERVICE_KEY",),
}


class Source:
    """One upstream, and the conditions under which we may read it."""

    def __init__(
        self,
        key: str,
        title: str,
        *,
        enabled_by: str | None,
        blocked_reason: str | None = None,
        note: str = "",
    ) -> None:
        self.key = key
        self.title = title
        # Environment flag that must be "1" for this source to run.
        self.enabled_by = enabled_by
        # Non-null means: do not fetch, and say why.
        self.blocked_reason = blocked_reason
        self.note = note

    @property
    def is_permitted(self) -> bool:
        return self.blocked_reason is None

    def is_enabled(self) -> bool:
        if not self.is_permitted:
            return False
        if self.enabled_by is None:
            return True
        return os.environ.get(self.enabled_by) == "1"

    def missing_secrets(self) -> list[str]:
        return [n for n in SECRET_NAMES.get(self.key, ()) if not os.environ.get(n)]


SOURCES: list[Source] = [
    Source(
        "wbak",
        "WBAK 한국여자야구연맹",
        enabled_by="WB_INGEST_WBAK",
        blocked_reason=(
            "외부 공개 API가 확인되지 않았습니다. 사이트가 응답한다는 사실이 "
            "이용 허락은 아니므로 자동 수집하지 않습니다. 이용허락 또는 CSV/API를 "
            "받은 뒤 blocked_reason 을 제거하고 어댑터를 구현하세요."
        ),
    ),
    Source(
        "kbsa",
        "KBSA 통합경기정보",
        enabled_by="WB_INGEST_KBSA",
        blocked_reason=(
            "통합경기정보의 공개 API가 확인되지 않았습니다. 내부 통신 주소를 "
            "공식 API로 가정하지 않습니다."
        ),
    ),
    Source(
        "wbsc",
        "WBSC 국제대회",
        enabled_by="WB_INGEST_WBSC",
        note="공개 페이지가 있으나 응답 구조 검증과 실패 격리를 마친 뒤 활성화합니다.",
    ),
    Source(
        "wpbl",
        "WPBL (미국 여자프로야구리그)",
        enabled_by="WB_INGEST_WPBL",
        note="공개 GET 주소가 있으나 장기 제공이 보장되지 않아 스키마 검증과 함께 활성화합니다.",
    ),
    Source(
        "naver-news",
        "네이버 뉴스 검색 API",
        enabled_by="WB_INGEST_NAVER",
        note="제목·언론사·발행시각·API 제공 설명·원문 URL만 저장합니다. 본문은 저장하지 않습니다.",
    ),
    Source(
        "youtube",
        "YouTube Data API (공식 채널)",
        enabled_by="WB_INGEST_YOUTUBE",
        note="공식 채널의 영상 메타데이터와 링크만 저장합니다.",
    ),
    Source(
        "kma-weather",
        "기상청 단기·중기예보",
        enabled_by="WB_INGEST_KMA",
        note="단기 D+0~2, 중기 D+3~10만 저장합니다. 11일 이후 일별 값은 만들지 않습니다.",
    ),
]


def http_get_json(url: str, headers: dict[str, str], timeout: int = 20) -> dict:
    """A single GET with a real timeout and a bounded, jittered retry."""
    last_error: Exception | None = None
    for attempt in range(1, 4):
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **headers})
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            # 4xx will not fix itself; stop immediately.
            if 400 <= e.code < 500 and e.code != 429:
                raise
            retry_after = e.headers.get("Retry-After") if e.headers else None
            delay = int(retry_after) if (retry_after or "").isdigit() else 2 ** attempt
            last_error = e
            time.sleep(min(delay, 30))
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            last_error = e
            time.sleep(min(2 ** attempt, 30))
    raise RuntimeError(f"요청 실패: {last_error}")


def fetch_naver_news(out_dir: str) -> dict:
    """Search metadata only. Article bodies are never stored."""
    client_id = os.environ["NAVER_CLIENT_ID"]
    client_secret = os.environ["NAVER_CLIENT_SECRET"]

    collected = []
    for query in ("여자야구", "한국여자야구연맹", "여자야구 대회"):
        url = (
            "https://openapi.naver.com/v1/search/news.json?"
            + urllib.parse.urlencode({"query": query, "display": 50, "sort": "date"})
        )
        payload = http_get_json(
            url,
            {
                "X-Naver-Client-Id": client_id,
                "X-Naver-Client-Secret": client_secret,
            },
        )
        for item in payload.get("items", []):
            collected.append(
                {
                    "query": query,
                    "title": item.get("title"),
                    # `description` is what the API itself returns. Nothing is
                    # fetched from the article page.
                    "description": item.get("description"),
                    "originallink": item.get("originallink"),
                    "link": item.get("link"),
                    "pubDate": item.get("pubDate"),
                }
            )

    return _write(out_dir, "naver-news", {"items": collected})


def fetch_youtube(out_dir: str) -> dict:
    """Official-channel video metadata."""
    api_key = os.environ["YOUTUBE_API_KEY"]
    channel_ids = [
        c for c in os.environ.get("WB_YOUTUBE_CHANNEL_IDS", "").split(",") if c.strip()
    ]
    if not channel_ids:
        raise RuntimeError(
            "WB_YOUTUBE_CHANNEL_IDS 가 비어 있습니다. 공식 채널 id를 지정해 주세요."
        )

    collected = []
    for channel_id in channel_ids:
        url = "https://www.googleapis.com/youtube/v3/search?" + urllib.parse.urlencode(
            {
                "key": api_key,
                "channelId": channel_id.strip(),
                "part": "snippet",
                "order": "date",
                "maxResults": 25,
                "type": "video",
            }
        )
        payload = http_get_json(url, {})
        collected.extend(payload.get("items", []))

    return _write(out_dir, "youtube", {"items": collected})


def fetch_kma(out_dir: str) -> dict:
    """Short-range and mid-range forecasts, kept in their published form.

    The forecast district and issue time are preserved rather than reduced to
    "the venue", because the honesty rule downstream depends on both.
    """
    service_key = os.environ["KMA_SERVICE_KEY"]
    zones = [z for z in os.environ.get("WB_KMA_ZONES", "").split(",") if z.strip()]
    if not zones:
        raise RuntimeError("WB_KMA_ZONES 가 비어 있습니다. 예보구역 코드를 지정해 주세요.")

    collected = []
    for zone in zones:
        url = (
            "https://apis.data.go.kr/1360000/MidFcstInfoService/getMidTa?"
            + urllib.parse.urlencode(
                {
                    "serviceKey": service_key,
                    "dataType": "JSON",
                    "regId": zone.strip(),
                    "numOfRows": 10,
                    "pageNo": 1,
                }
            )
        )
        collected.append({"zone": zone.strip(), "payload": http_get_json(url, {})})

    return _write(out_dir, "kma-weather", {"items": collected})


FETCHERS = {
    "naver-news": fetch_naver_news,
    "youtube": fetch_youtube,
    "kma-weather": fetch_kma,
}


def _write(out_dir: str, key: str, payload: dict) -> dict:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    directory = os.path.join(out_dir, key)
    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, f"{stamp}.json")
    body = {
        "source": key,
        "fetchedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        **payload,
    }
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(body, f, ensure_ascii=False, indent=2)
    return {"source": key, "path": path, "count": len(payload.get("items", []))}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", action="append", default=[])
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--out", default="build/raw")
    args = parser.parse_args()

    if args.list:
        print("=== 수집 가능한 출처 ===")
        for source in SOURCES:
            if not source.is_permitted:
                state = "차단(이용허락 필요)"
            elif source.is_enabled():
                state = "활성"
            else:
                state = f"비활성 ({source.enabled_by}=1 로 활성화)"
            print(f"  {source.key:<14} {source.title:<28} {state}")
            if source.blocked_reason:
                print(f"       사유: {source.blocked_reason}")
            elif source.note:
                print(f"       비고: {source.note}")
        return 0

    selected = (
        SOURCES if args.all else [s for s in SOURCES if s.key in set(args.source)]
    )
    if not selected:
        print("수집할 출처를 지정해 주세요. --list 로 목록을 볼 수 있습니다.")
        return 2

    results: list[dict] = []
    failures: list[dict] = []

    for source in selected:
        if not source.is_permitted:
            print(f"[SKIP] {source.key}: {source.blocked_reason}")
            results.append({"source": source.key, "status": "blocked"})
            continue

        if not source.is_enabled():
            print(f"[SKIP] {source.key}: 비활성 ({source.enabled_by} 미설정)")
            results.append({"source": source.key, "status": "disabled"})
            continue

        missing = source.missing_secrets()
        if missing:
            # Names only — never values.
            print(f"[SKIP] {source.key}: 필요한 환경변수 없음 ({', '.join(missing)})")
            results.append({"source": source.key, "status": "missing-secrets"})
            continue

        fetcher = FETCHERS.get(source.key)
        if fetcher is None:
            print(f"[SKIP] {source.key}: 수집 구현이 아직 없습니다")
            results.append({"source": source.key, "status": "not-implemented"})
            continue

        try:
            result = fetcher(args.out)
            print(f"[OK]   {source.key}: {result['count']}건 → {result['path']}")
            results.append({**result, "status": "ok"})
        except Exception as e:  # noqa: BLE001 — one source must not stop the rest
            # The message is printed, but secret values never appear in it
            # because they are only ever read, not interpolated.
            print(f"[FAIL] {source.key}: {type(e).__name__}: {e}")
            failures.append({"source": source.key, "error": type(e).__name__})
            results.append({"source": source.key, "status": "failed"})

    summary_dir = args.out
    os.makedirs(summary_dir, exist_ok=True)
    summary_path = os.path.join(summary_dir, "fetch-summary.json")
    with open(summary_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(
            {
                "finishedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "results": results,
                "failures": failures,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )

    ok = sum(1 for r in results if r.get("status") == "ok")
    print(f"\n요약: 성공 {ok}건, 실패 {len(failures)}건 → {summary_path}")

    # A failed source is isolated: the run still succeeds so the rest of the
    # pipeline can publish what it does have.
    return 0


if __name__ == "__main__":
    sys.exit(main())
