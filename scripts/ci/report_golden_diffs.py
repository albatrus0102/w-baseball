#!/usr/bin/env python3
"""Summarise a `flutter test test/screenshots --tags screenshots` run.

Why this exists
----------------
As of 00550d4 the 31 golden screenshots are byte-identical across ten
consecutive regenerations on one Windows machine. Whether that holds on the
Ubuntu CI runner is a separate, unanswered question -- FreeType version,
hinting, subpixel AA and the Skia backend can all differ from a desktop even
with the exact same font file bundled. `.github/workflows/ci.yml` now runs
that comparison on the runner with `continue-on-error: true` (a measurement,
not a gate -- see this repo's CLAUDE.md on why a pixel diff must never block
a build before anyone has even seen whether it fails).

But "it failed" without "by how much, where" is not a measurement anyone can
act on. `flutter test --reporter expanded` prints one exception block per
failing golden, each containing a line in the shape:

    Golden "../../docs/screenshots/<name>.png": Pixel test failed, X.XX%,
    Npx diff detected.

-- but where that line wraps depends on the golden's path length (confirmed
by inspecting real CI/local runs: the same message wraps in a different
place depending on filename), so a plain grep for one line does not reliably
find every failure, and 31 of these scattered through possibly hundreds of
lines of test names is not something a human should have to eyeball to rank.

This script reads that raw text output (captured to a file -- never piped in,
so its own exit code was never at risk of being someone else's, per this
repo's four-times-repeated pipe/exit-code mistake) and prints:

  1. how many of the (total) goldens in this run failed
  2. each failing golden's diff percentage, sorted worst-first
  3. the max and median diff percentage, one line, so a human can tell "a
     few stray pixels" from "everything shifted" without reading the table

Optionally (if Pillow is importable on the runner -- this script never
installs it, only checks) it also diffs the `_masterImage.png` /
`_testImage.png` pairs `test/screenshots/failures/` holds after a failing
run, for a changed-pixel count and max single-channel delta that does not
depend on trusting Flutter's own arithmetic.

This script does not decide whether the Linux mismatch is "close enough to
gate on" -- it only measures. That judgement call, and any change to
docs/design-system.md's "measurement in progress" note, comes after a human
reads its output.

Usage
-----
    python scripts/ci/report_golden_diffs.py <test-output-file> [--failures-dir DIR]

Exit code is always 0: this is a reporting step, run with `if: always()` in
CI, and it must never itself fail the job -- that would defeat the point of
`continue-on-error` on the step it is reporting on.
"""

from __future__ import annotations

import argparse
import re
import statistics
import sys
import warnings
from dataclasses import dataclass
from typing import List, Optional

# Matches the fixed, non-wrapping prefix of the message
# (`_goldens_io.dart`'s `compareLists`), then tolerates a line wrap
# *anywhere* a space would otherwise be -- `\s+` matches a newline exactly
# like it matches a space, so this finds the numbers whether Flutter wrapped
# after "failed," or in the middle of "84px diff\ndetected.". Confirmed
# against a real captured run (see module docstring).
_GOLDEN_DIFF_RE = re.compile(
    r'Golden\s+"([^"]+)":\s+Pixel\s+test\s+failed,\s*'
    r"([0-9]+(?:\.[0-9]+)?)%,\s*([0-9]+)px\s+diff\s+detected\.",
    re.MULTILINE,
)

# The other failure shape `compareLists` can produce: dimensions differ, so
# there is no percentage to rank by. Rare (would mean the widget tree itself
# rendered at a different size, not just different pixels), but a run that
# hits it should still be counted as a golden failure, not silently dropped
# from the "N of 31 failed" total.
_GOLDEN_SIZE_MISMATCH_RE = re.compile(
    r'Golden\s+"([^"]+)":\s+Pixel\s+test\s+failed,\s+image\s+sizes\s+do\s+not\s+match\.',
    re.MULTILINE,
)

# `flutter test`'s own final tally, e.g. "00:11 +31: All tests passed!" or
# "00:09 +18 -13: Some tests failed." -- read for the total-run-count, which
# is a fact `flutter test` already computed and this script should not
# recompute by (e.g.) counting `Golden "..."` lines, since a failure that
# is not a pixel/size mismatch (a crash, a timeout) would silently vanish
# from that count instead of showing up as "unparsed failure".
_SUMMARY_RE = re.compile(
    r"^\d{2}:\d{2}\s+\+(\d+)(?:\s+-(\d+))?:\s+(?:All tests passed!|Some tests failed\.)\s*$",
    re.MULTILINE,
)


@dataclass
class GoldenFailure:
    golden_path: str
    diff_percent: Optional[float]  # None for a size mismatch -- unrankable
    diff_pixels: Optional[int]

    @property
    def basename(self) -> str:
        # Golden paths are relative (`../../docs/screenshots/name.png`);
        # `getFailureFile` in `_goldens_io.dart` names failure artefacts
        # after this basename alone, no directories.
        return self.golden_path.rsplit("/", 1)[-1]


def parse_failures(text: str) -> List[GoldenFailure]:
    failures: List[GoldenFailure] = [
        GoldenFailure(path, float(pct), int(px))
        for path, pct, px in _GOLDEN_DIFF_RE.findall(text)
    ]
    diff_paths = {f.golden_path for f in failures}
    for (path,) in _GOLDEN_SIZE_MISMATCH_RE.findall(text):
        if path not in diff_paths:
            failures.append(GoldenFailure(path, None, None))
    return failures


def parse_totals(text: str) -> Optional[tuple]:
    """Returns (passed, failed) from flutter test's last summary line, or
    None if no such line was found (e.g. the run crashed before finishing --
    that is itself worth reporting, not worth guessing a number for)."""
    match = None
    for match in _SUMMARY_RE.finditer(text):
        pass  # take the last match: intermediate retries can print earlier ones
    if match is None:
        return None
    passed = int(match.group(1))
    failed = int(match.group(2)) if match.group(2) else 0
    return passed, failed


def format_report(text: str) -> str:
    lines: List[str] = []
    totals = parse_totals(text)
    failures = parse_failures(text)

    if totals is None:
        lines.append(
            "골든 러너 요약을 찾지 못했습니다 -- flutter test가 요약 줄을 찍기 전에 "
            "죽었을 수 있습니다 (크래시/타임아웃). 아래는 그래도 찾은 실패 목록입니다."
        )
        total_run = None
        total_failed = len(failures)
    else:
        passed, failed = totals
        total_run = passed + failed
        total_failed = failed
        lines.append(f"골든 결과: {total_run}개 중 {failed}개 실패 (통과 {passed}개)")
        if failed != len(failures):
            # Not necessarily a bug in this script -- a failure that is not a
            # pixel/size mismatch (setup exception, timeout) would count
            # toward flutter's -N but never match either regex above. Say so
            # rather than silently presenting a table that looks complete.
            lines.append(
                f"  (주의: 실패로 집계된 {failed}개 중 {len(failures)}개만 골든 비교 "
                "실패로 식별했습니다 -- 나머지는 다른 원인일 수 있습니다.)"
            )

    if not failures:
        if total_failed == 0:
            lines.append("리눅스 CI 에서 골든이 모두 재현됐습니다 (픽셀 일치).")
        return "\n".join(lines)

    rankable = [f for f in failures if f.diff_percent is not None]
    unrankable = [f for f in failures if f.diff_percent is None]
    rankable.sort(key=lambda f: f.diff_percent, reverse=True)

    lines.append("")
    lines.append("차이 큰 순 (골든 | 차이% | 다른 픽셀 수):")
    lines.append(f"  {'골든':<55} {'차이%':>8} {'픽셀 수':>10}")
    for f in rankable:
        lines.append(f"  {f.basename:<55} {f.diff_percent:>7.2f}% {f.diff_pixels:>10}")
    for f in unrankable:
        lines.append(f"  {f.basename:<55} {'크기 불일치':>8} {'-':>10}")

    if rankable:
        percents = [f.diff_percent for f in rankable]
        lines.append("")
        lines.append(
            f"요약: 최대 {max(percents):.2f}%, 중앙값 {statistics.median(percents):.2f}% "
            f"({len(rankable)}개 랭킹 가능"
            + (f", {len(unrankable)}개 크기 불일치 별도" if unrankable else "")
            + ")"
        )

    return "\n".join(lines)


def _pixel_stats_report(failures: List[GoldenFailure], failures_dir: str) -> str:
    """Best-effort per-golden pixel stats straight from the saved
    masterImage/testImage PNG pair, independent of Flutter's own diff-percent
    arithmetic. Returns a human-readable block, or a one-line explanation of
    why it was skipped -- never raises, since this is a bonus measurement
    (task item (3)), not a required one."""
    try:
        from PIL import Image, ImageChops
    except ImportError:
        return (
            "픽셀 통계: 이 러너에 Pillow 가 없어 건너뜁니다 (설치하지 않음 -- "
            "새 의존성을 임의로 추가하지 말라는 지침에 따름)."
        )

    if not failures:
        return "픽셀 통계: 실패한 골든이 없어 계산할 것이 없습니다."

    import os

    lines = ["", "픽셀 통계 (masterImage vs testImage, Pillow):"]
    lines.append(f"  {'골든':<55} {'변경 픽셀':>10} {'최대 채널차':>10}")
    any_computed = False
    for f in failures:
        stem = f.basename.rsplit(".", 1)[0]
        master_path = os.path.join(failures_dir, f"{stem}_masterImage.png")
        test_path = os.path.join(failures_dir, f"{stem}_testImage.png")
        if not (os.path.isfile(master_path) and os.path.isfile(test_path)):
            lines.append(f"  {f.basename:<55} {'(파일 없음)':>10} {'-':>10}")
            continue
        try:
            master = Image.open(master_path).convert("RGBA")
            test = Image.open(test_path).convert("RGBA")
            if master.size != test.size:
                lines.append(f"  {f.basename:<55} {'(크기 다름)':>10} {'-':>10}")
                continue
            diff = ImageChops.difference(master, test)
            extrema = diff.getextrema()
            max_channel_diff = max(hi for _lo, hi in extrema)
            # getbbox() on a zeroed image is None; on any nonzero pixel it is
            # the tight bounding box, which does not by itself give a pixel
            # *count* -- so count directly, same cost as the bbox check.
            # `getdata()` is slated for removal in Pillow 14 (2027-10-15) in
            # favour of `get_flattened_data`, but that replacement does not
            # exist on the Pillow versions most runners still have today, so
            # this only silences the forward-looking warning, not the call.
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", DeprecationWarning)
                changed = sum(1 for px in diff.getdata() if any(px))
            lines.append(f"  {f.basename:<55} {changed:>10} {max_channel_diff:>10}")
            any_computed = True
        except Exception as exc:  # noqa: BLE001 -- best-effort, report and move on
            lines.append(f"  {f.basename:<55} {'(오류: ' + str(exc)[:30] + ')':>10} {'-':>10}")
    if not any_computed:
        lines.append(
            "  (계산된 항목이 없습니다 -- failures/ 아티팩트가 예상 이름으로 없을 수 있습니다.)"
        )
    return "\n".join(lines)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_file", help="flutter test의 표준출력을 받은 파일 경로")
    parser.add_argument(
        "--failures-dir",
        default="test/screenshots/failures",
        help="matchesGoldenFile 이 실패 시 남기는 디렉터리 (기본: test/screenshots/failures)",
    )
    parser.add_argument(
        "--skip-pixel-stats",
        action="store_true",
        help="Pillow 픽셀 통계 계산을 건너뜁니다 (표와 요약만 출력).",
    )
    args = parser.parse_args(argv)

    try:
        with open(args.output_file, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError as exc:
        # A reporting step must not itself fail the job -- print the problem
        # and exit 0, matching the module docstring's contract.
        print(f"[report_golden_diffs] 출력 파일을 읽을 수 없습니다: {exc}")
        return 0

    print(format_report(text))

    if not args.skip_pixel_stats:
        failures = parse_failures(text)
        print(_pixel_stats_report(failures, args.failures_dir))

    return 0


if __name__ == "__main__":
    sys.exit(main())
