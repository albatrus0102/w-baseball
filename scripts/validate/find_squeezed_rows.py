"""Finds `Row(... Expanded(Text) ... <a button> ...)` layouts.

This shape never overflows -- `Expanded` absorbs the squeeze -- so the
overflow probes in `test/audit` cannot see it. What it does instead, at
larger text scales, is narrow the sentence until it breaks mid-word. That
defect shipped twice: once in the standings notice, once in the 내 기록
storage line. Both were found by looking at a rendered screen, not by a
test, so this exists to enumerate the remaining instances rather than wait
to trip over a third.

Reports rather than fails: some of these are fine (a short label beside a
narrow icon button). The output is a review list, not a verdict.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUTTONS = re.compile(
    r"\b(TextButton|OutlinedButton|FilledButton|ElevatedButton|WbButton"
    r"|IconButton|WbChip|ActionChip)\b"
)


def spans(source: str, opener: str):
    """Yields (start, end) of each balanced `opener(...)` call."""
    for match in re.finditer(re.escape(opener), source):
        i = match.end()
        if i > len(source) or source[i - 1] != "(":
            continue
        depth, j = 1, i
        while j < len(source) and depth:
            char = source[j]
            if char in "([{":
                depth += 1
            elif char in ")]}":
                depth -= 1
            j += 1
        if depth == 0:
            yield match.start(), j


def main() -> int:
    hits: list[str] = []
    for path in sorted((ROOT / "lib").rglob("*.dart")):
        source = path.read_text(encoding="utf-8")
        if ".g.dart" in path.name:
            continue
        for start, end in spans(source, "Row("):
            body = source[start:end]
            # Only the row's own children, not those of a nested Row.
            inner = [b for a, b in spans(body, "Row(") if a > 0]
            for a, b in spans(body, "Row("):
                if a > 0:
                    body = body[:a] + " " * (b - a) + body[b:]
            if "Expanded(" not in body or "Text(" not in body:
                continue
            button = BUTTONS.search(body)
            if not button:
                continue
            line = source.count("\n", 0, start) + 1
            rel = path.relative_to(ROOT).as_posix()
            hits.append(f"{rel}:{line}  Expanded(Text) + {button.group(1)}")
            del inner

    if not hits:
        print("긴 문장 옆에 버튼을 둔 Row 없음")
        return 0
    print(f"검토 대상 {len(hits)}건 — 큰 글자에서 문장이 좁아지는 배치:")
    for hit in hits:
        print(f"  {hit}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
