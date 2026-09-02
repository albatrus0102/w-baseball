#!/usr/bin/env python3
"""Catch the exact gap that let `assets/icons/` through: a path declared in
`pubspec.yaml`'s `assets:` list (or, since the Pretendard font bundle,
its `fonts:` list) that git does not track.

Why this check exists
----------------------
`flutter analyze` failed in CI (first run ever, after the first push) on
`asset_directory_does_not_exist` for `assets/icons/`. The directory existed
on the developer's machine -- empty, but present -- so every local run of
`flutter analyze`, and every run of `tools/commit_gate.py`, saw a directory
that satisfied the declaration and passed. Git does not track empty
directories, so a fresh checkout (CI's, or any other clone) never had the
directory at all, and only `flutter analyze` running against that fresh
checkout could see the mismatch.

That is a class of bug, not a one-off: anything declared in `pubspec.yaml`
that depends on a file or directory existing *on disk* rather than *in the
commit* can pass every local check and still fail the moment someone clones
the repo fresh. This script closes that gap by asking git directly --
`git ls-files`, not `os.path.exists` -- whether each declared asset path
would survive a fresh clone, which is the same question CI is actually
asking when it runs `flutter analyze` against a checkout it just made.

`fonts:` is exactly the same class of bug with a different key. A font
family declared under `flutter: fonts:` points at `asset:` paths the same
way `flutter: assets:` points at directories -- if one of those TTFs is
declared but never `git add`-ed, the build succeeds on the machine that has
the file on disk and fails on every fresh clone, CI included. So this
script parses both blocks and checks every path either one declares.

Scope, deliberately narrow
---------------------------
This checks exactly the paths declared under `flutter: assets:` and
`flutter: fonts:` in `pubspec.yaml` -- the concrete things that broke --
rather than trying to generalise to "every path referenced anywhere is
git-tracked". A fully general version would need to understand every place
a path can be referenced (Dart string literals used with rootBundle, native
manifests, CI YAML, ...) with no shared syntax to lean on, which is a much
larger and slower undertaking for a benefit this incident does not
demonstrate a need for. `pubspec.yaml`'s `assets:` and `fonts:` lists are
different: they are the well-known, machine-readable spots where "this path
must exist for Flutter to build" is declared, so checking them exhaustively
is cheap and precise. If a third such declaration surfaces (a native
manifest, say), extend this script or add a sibling next to it rather than
trying to generalise in the abstract now.

Usage:
    python scripts/validate/check_declared_assets.py
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from typing import List

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PUBSPEC_PATH = os.path.join(REPO_ROOT, "pubspec.yaml")


def _parse_declared_assets(pubspec_text: str) -> List[str]:
    """Extract the list items under `flutter: assets:` from raw pubspec.yaml
    text.

    Deliberately not a general YAML parser (and not a dependency on PyYAML,
    which nothing else in this repo requires) -- `pubspec.yaml`'s `assets:`
    block is a fixed, simple shape: a `assets:` key, followed by `- path`
    list items indented deeper than the key, ending at the first line that
    is blank, a comment, or indented back to the key's level or shallower.
    That shape is exactly what this hand-rolled scan looks for, so it stays
    correct for this one file without pulling in a parser to handle YAML
    features this file never uses.
    """
    lines = pubspec_text.splitlines()
    assets_key_indent = None
    items: List[str] = []
    in_block = False

    for line in lines:
        stripped = line.strip()
        if not in_block:
            if re.match(r"^assets:\s*(#.*)?$", stripped):
                assets_key_indent = len(line) - len(line.lstrip(" "))
                in_block = True
            continue

        if not stripped or stripped.startswith("#"):
            continue

        indent = len(line) - len(line.lstrip(" "))
        if indent <= assets_key_indent:
            break  # back out to a sibling/parent key -- the list block ended

        item_match = re.match(r"^-\s*(.+?)\s*(#.*)?$", stripped)
        if not item_match:
            break  # not a list item -- malformed or an unexpected shape
        value = item_match.group(1).strip("'\"")
        items.append(value)

    return items


def _parse_declared_font_assets(pubspec_text: str) -> List[str]:
    """Extract every `asset:` path nested under `flutter: fonts:` in raw
    pubspec.yaml text.

    The shape is deeper than `assets:` -- `fonts:` is a list of families,
    each with its own nested `fonts:` list of `{asset, weight}` maps -- but
    the only thing this check needs is every `asset:` value anywhere inside
    the outer `fonts:` block, regardless of nesting depth. So rather than
    modelling the family/weight structure, this scans every line from the
    `fonts:` key until indentation returns to that key's level (the same
    "block ends at the first sibling-or-shallower line" rule
    `_parse_declared_assets` uses) and picks out any `- asset: <path>` or
    `asset: <path>` line it finds.
    """
    lines = pubspec_text.splitlines()
    fonts_key_indent = None
    items: List[str] = []
    in_block = False

    for line in lines:
        stripped = line.strip()
        if not in_block:
            if re.match(r"^fonts:\s*(#.*)?$", stripped):
                fonts_key_indent = len(line) - len(line.lstrip(" "))
                in_block = True
            continue

        if not stripped or stripped.startswith("#"):
            continue

        indent = len(line) - len(line.lstrip(" "))
        if indent <= fonts_key_indent:
            break  # back out to a sibling/parent key -- the fonts block ended

        asset_match = re.match(r"^-?\s*asset:\s*(.+?)\s*(#.*)?$", stripped)
        if asset_match:
            items.append(asset_match.group(1).strip("'\""))

    return items


def _git_tracked_files_under(path: str) -> List[str]:
    """`git ls-files -- <path>`, repo-root-relative. For a directory prefix
    (trailing slash) this lists every tracked file under it (empty if none
    -- exactly the "would a fresh clone have anything here" question). For
    an exact file path it lists that one path if, and only if, it is
    tracked."""
    result = subprocess.run(
        ["git", "ls-files", "--", path],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return [line for line in result.stdout.splitlines() if line]


def main() -> int:
    # Windows consoles default stdout/stderr to the system codepage, which
    # mangles the Korean messages below into mojibake instead of erroring --
    # same fix, same reasoning, as check_contrast.py's main().
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass

    with open(PUBSPEC_PATH, "r", encoding="utf-8") as f:
        pubspec_text = f.read()

    declared_assets = _parse_declared_assets(pubspec_text)
    if not declared_assets:
        print(
            "[check_declared_assets] pubspec.yaml 에서 'flutter: assets:' 목록을 "
            "찾지 못했습니다 -- 파서가 파일 구조 변경을 따라가지 못하는 것일 수 "
            "있습니다. 이 검사를 건너뛰지 말고 확인하세요."
        )
        return 1

    # `fonts:` is optional in general (a project need not bundle any font),
    # so its absence is not itself an error. But if the key is present and
    # the parser still comes back empty, that is the same parser-drift
    # signal the `assets:` check above guards against, not "no fonts
    # declared" -- so it gets the same hard failure.
    fonts_key_present = re.search(r"^\s*fonts:\s*(#.*)?$", pubspec_text, re.MULTILINE) is not None
    declared_fonts = _parse_declared_font_assets(pubspec_text)
    if fonts_key_present and not declared_fonts:
        print(
            "[check_declared_assets] pubspec.yaml 에 'flutter: fonts:' 목록이 "
            "있지만 그 안에서 'asset:' 경로를 하나도 찾지 못했습니다 -- 파서가 "
            "파일 구조 변경을 따라가지 못하는 것일 수 있습니다. 이 검사를 "
            "건너뛰지 말고 확인하세요."
        )
        return 1

    # (block, path) pairs so an untracked hit can say which pubspec.yaml
    # block it came from.
    declared = [("assets", p) for p in declared_assets] + [
        ("fonts", p) for p in declared_fonts
    ]

    untracked = [(block, path) for block, path in declared if not _git_tracked_files_under(path)]

    if untracked:
        print(
            "[check_declared_assets] pubspec.yaml 에 선언되어 있지만 git에 "
            "커밋된 파일이 하나도 없는 경로가 있습니다 (새로 clone한 저장소에는 "
            "존재하지 않아, 로컬에서는 통과해도 CI의 `flutter analyze`는 "
            "실패합니다):"
        )
        for block, path in untracked:
            print(f"  - [{block}] {path}")
        print(
            "\n해결: 실제로 쓰이는 파일이라면 git에 커밋하세요. 쓰이지 않는다면 "
            "pubspec.yaml에서 그 줄을 지우세요 (디렉터리를 비워둔 채 유지하는 "
            "것은 근본 해결이 아닙니다)."
        )
        return 1

    print(
        f"[check_declared_assets] pubspec.yaml 의 assets 선언 {len(declared_assets)}개, "
        f"fonts 선언 {len(declared_fonts)}개 모두 git에 커밋된 파일을 갖고 "
        "있습니다."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
