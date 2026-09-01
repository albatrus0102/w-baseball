#!/usr/bin/env python3
"""One-command commit gate: runs every check CI runs, in the same order,
locally, before you push.

Why this exists
----------------
Before this script, "run the checks" meant remembering to run six or seven
separate commands from `.github/workflows/ci.yml` by hand, in the right
order, with the right flags. Separate steps mean one eventually gets skipped
-- not out of malice, just because a person is in a hurry and `flutter test`
"looks" like the whole story. This script is the single command: run it, and
either everything CI would run passes, or you find out exactly which thing
did not, before it becomes someone else's problem in a PR review.

This mirrors `.github/workflows/ci.yml`'s `analyze-and-test` and `data` jobs
step for step (the `build-android` job is a release-artefact build, not a
check -- it needs a JDK/Android SDK most dev machines won't have configured,
and building an APK proves nothing `flutter analyze` + `flutter test` don't
already cover). If CI changes, update STEPS here to match, or the two will
drift apart -- which is exactly the failure mode this script exists to close.

Skip semantics -- read this before touching the skip logic
------------------------------------------------------------
Two rules about skipping are in tension, and resolving that tension is the
whole design of `resolve_tool()` / `run_step()`:

  1. "When a dependency is missing and a check can't run, don't silently skip
     -- fail. To skip, require an explicit flag, and even then say so in the
     summary."
  2. "Don't call an external executable by name directly -- go through a
     resolver, and if it can't be found, that's a skip, not a failure
     (because failing would corrupt the baseline and bury a real defect
     under an environment problem)."

These are not actually the same rule pointing two ways once you separate
*what* is missing from *how loud the gate is about it*:

  * Rule 2 is about *why* a skip can be legitimate: a tool that is not
    installed on this machine is a fact about the machine, not a fact about
    the change being committed. Treating "python happens to be 3.9 here" or
    "nobody installed the Android toolchain on this laptop" as a code defect
    would poison the same ratchet idea Task A relies on -- the gate would
    "fail" for reasons that have nothing to do with what changed, teaching
    everyone to ignore red.
  * Rule 1 is about *how the gate behaves by default*, and it wins the
    default: a step whose tool cannot be resolved makes the WHOLE gate exit
    non-zero unless the caller has explicitly opted in to tolerating that
    (`--allow-missing-tools` / `WB_GATE_ALLOW_MISSING_TOOLS=1`), and even
    with that opt-in, the step is printed as `SKIP (tool not found)` in the
    summary -- never folded silently into a green run. Nobody who reads the
    output can mistake "skipped" for "passed".

So: resolution goes through `resolve_tool()` (rule 2's mechanism). Whether a
resolution failure is allowed to end the run as anything other than a hard
failure is gated by an explicit flag and always logged (rule 1's
requirement). A step whose tool *is* found but whose check *fails* is always
a hard failure, full stop -- no flag changes that, because that is exactly
the "real defect" rule 2 warns against burying.

Cross-platform, and where Flutter is allowed to live
-------------------------------------------------------
`flutter` is not assumed to be on PATH (this dev box does not have it
there). Resolution order: PATH, then `FLUTTER_ROOT`/`FLUTTER_HOME` env var
-> `<root>/bin`, then a `.flutter_root` file at the repo root (one line,
the SDK path) -> `<that path>/bin`. `shutil.which` already applies
`PATHEXT` on Windows, so the same code finds `flutter.bat` there and the
plain `flutter` script elsewhere.

That third option exists because of a real tension, worth stating plainly
rather than picking silently: a one-command gate that requires the user to
export an environment variable before the one command still works is a gate
people learn to skip, on exactly the machine this project actually runs on
(Flutter not on PATH, `FLUTTER_ROOT` unset, by default). The tempting fix --
probe a list of common install spots (`C:/dev/flutter`, `~/flutter`,
`~/development/flutter`, `/opt/flutter`, ...) -- was rejected on purpose:
that makes the gate's behaviour depend on which machine runs it and in what
order those guesses happen to resolve. Two developers with Flutter in two
different, equally reasonable places get silently different tool
resolution, and if a machine happens to have two installs, the "winner" is
whichever guess is listed first -- not a decision anyone made. That is
precisely what a deterministic, portable gate must not do.

`.flutter_root` splits the difference instead of compromising on it: it is
still an explicit, inspectable, one-line declaration (`cat .flutter_root`
tells you exactly what will be used -- nothing is guessed), so it carries
none of the "which of N guessed paths won" problem a probe has. What it
removes is the *recurring* cost: it is set up once per clone, lives outside
of any single shell session, and is listed in `.gitignore` so it can never
become a machine-specific path hard-coded into a committed file (the same
rule this file's own `resolve_flutter_tool` already had to honour). A
missing-everything error names all three options with copy-pasteable
syntax, because "set FLUTTER_ROOT" alone left the reader to go find the
right shell syntax themselves.

Usage:
    python tools/commit_gate.py
    python tools/commit_gate.py --allow-missing-tools
    python tools/commit_gate.py --dry-run     # prove every step is reachable; runs nothing
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Fixed instant CI pins the seed generator to, so the reproducibility check
# compares like with like on every run rather than drifting with "now". Kept
# equal to ci.yml's value on purpose -- change both together or not at all.
SEED_GENERATED_AT = "2026-08-30T00:00:00Z"

# Measured on the dev box this gate was built on, tools resolved via
# FLUTTER_ROOT, on a tree with real uncommitted work in it (not a clean
# checkout): declared-assets check <1s, pub get ~2s, codegen check ~3s,
# format ~4s, analyze ~10s, Dart tests ~35s, the remaining Python-only checks
# ~2s combined -- about 57s end to end. Recorded here so the next person
# doesn't have to re-measure "is this gate slow enough that people will skip
# it" (it isn't). If a step's typical cost changes by more than a little,
# update this comment alongside it -- a stale number here is a smaller
# version of the same trust problem as a stale contrast baseline entry.


# --------------------------------------------------------------------------
# Tool resolution
# --------------------------------------------------------------------------


FLUTTER_ROOT_FILE = os.path.join(REPO_ROOT, ".flutter_root")


def _dotfile_flutter_root() -> Optional[str]:
    """Read a one-line, git-ignored `.flutter_root` at the repo root, if a
    developer has set one up. Never committed (see .gitignore) and never
    guessed at -- if the file is absent, this returns None and resolution
    falls through, it does not go looking anywhere else."""
    if not os.path.isfile(FLUTTER_ROOT_FILE):
        return None
    with open(FLUTTER_ROOT_FILE, "r", encoding="utf-8") as f:
        value = f.read().strip()
    return value or None


def resolve_flutter_tool(exe_name: str) -> Optional[str]:
    """Resolve `flutter` or `dart` to an absolute path without assuming PATH
    and without guessing at machine-specific install locations (see the
    module docstring's "where Flutter is allowed to live" section for why
    that tradeoff was made this way).

    Order: PATH, then `FLUTTER_ROOT`/`FLUTTER_HOME` env var -> `<root>/bin`,
    then the repo-local, git-ignored `.flutter_root` file -> `<path>/bin`.
    PATH goes first so a developer who already has Flutter set up the normal
    way never needs either fallback. Never hard-codes a filesystem path in
    this committed file."""
    found = shutil.which(exe_name)
    if found:
        return found

    for root in (
        os.environ.get("FLUTTER_ROOT"),
        os.environ.get("FLUTTER_HOME"),
        _dotfile_flutter_root(),
    ):
        if not root:
            continue
        found = shutil.which(exe_name, path=os.path.join(root, "bin"))
        if found:
            return found
    return None


def resolve_python_tool() -> str:
    """The interpreter already running this script. Always resolvable --
    there is no "python not found" case when python is what got us here --
    so this is deliberately not routed through the missing-tool skip path."""
    return sys.executable


# --------------------------------------------------------------------------
# Step definitions
# --------------------------------------------------------------------------


@dataclass
class Step:
    id: str
    name_ko: str
    """Returns the argv to run, or None if the tool could not be resolved."""
    build_argv: Callable[[], Optional[List[str]]]
    cwd: str = REPO_ROOT
    # Which resolver failing should be treated as a missing-tool skip
    # (rule 2), vs. a step that has no external tool to resolve at all.
    tool_kind: Optional[str] = None  # "flutter" | "python" | None
    # Optional hook run immediately before the subprocess, and one run
    # immediately after it exits 0 -- see _codegen_drift_check below. Neither
    # fires during --dry-run, matching the "no subprocess spawned" contract
    # dry-run already has for build_argv.
    pre_run: Optional[Callable[[], None]] = None
    post_check: Optional[Callable[[], int]] = None


def _generated_file_snapshot(patterns: List[str]) -> Dict[str, str]:
    """sha256 of every file matching any of `patterns` (globs, relative to
    the repo root, `**` recursive), keyed by repo-relative path."""
    snapshot: Dict[str, str] = {}
    for pattern in patterns:
        for path in glob.glob(os.path.join(REPO_ROOT, pattern), recursive=True):
            if not os.path.isfile(path):
                continue
            rel = os.path.relpath(path, REPO_ROOT).replace(os.sep, "/")
            with open(path, "rb") as f:
                snapshot[rel] = hashlib.sha256(f.read()).hexdigest()
    return snapshot


def _format_codegen_outputs() -> None:
    """Run `dart format` (the writing form) on exactly the files
    `_CODEGEN_PATTERNS` matches -- never a bare `dart format .`.

    Why this step exists at all, so the next person does not delete it as
    redundant: `build_runner` resolves `dart_style` through `pubspec.lock`
    (a library dependency, pinned like any other), while the standalone
    `dart format` CLI ships bundled inside the Flutter SDK itself. The two
    disagree on how to wrap a `typedef X = Y Function({...})` -- confirmed by
    formatting a fresh `build_runner` regeneration of `database.g.dart` and
    diffing it against the committed file: hundreds of lines differ, all of
    them exactly this typedef-wrapping style, nothing semantic. Comparing
    raw `build_runner` output against the committed (which was, itself,
    formatted before being committed) file therefore reports "drift" that
    isn't real. The canonical form both this gate and `ci.yml` compare
    against is *`build_runner` output, then passed through `dart format`* --
    not `build_runner` output alone.

    Restricted to the generator's own output files (not `dart format .`)
    because unlike `dart_format`'s own gate step, this one runs unconditionally
    as part of *checking* codegen, including on a tree full of someone else's
    unrelated in-progress edits -- the same reason the earlier accidental
    repo-wide reformat was a mistake in the first place. A `.g.dart` file is
    never hand-edited by a person while this runs, so formatting exactly the
    files the generator just wrote carries none of that risk."""
    files = [
        path
        for pattern in _CODEGEN_PATTERNS
        for path in glob.glob(os.path.join(REPO_ROOT, pattern), recursive=True)
        if os.path.isfile(path)
    ]
    if not files:
        return
    dart_exe = resolve_flutter_tool("dart")
    if dart_exe is None:
        # Unreachable in practice: build_argv already resolved and ran `dart`
        # earlier in this same step. Left as a no-op rather than a crash so a
        # future refactor that decouples the two doesn't turn a resolver gap
        # into an unrelated traceback.
        return
    subprocess.run([dart_exe, "format", *files], cwd=REPO_ROOT)


def _codegen_drift_check(patterns: List[str], label: str, normalize=None):
    """Build a (pre_run, post_check) pair that answers "did *this run* of the
    generator change a generated file" -- not ci.yml's `git status
    --porcelain <dir>`, which answers "is this directory dirty at all".

    Those are the same question only on CI's disposable, from-clean
    checkout: there, nothing under e.g. `lib/` *can* be dirty except
    generator output, so a directory-wide git-diff is an accurate proxy. A
    local pre-commit gate runs on a tree that is dirty by definition -- you
    run this gate *because* you have uncommitted work -- so the same
    directory-wide check reports every unrelated uncommitted file under that
    directory as "codegen drift", which is wrong on every real run and was
    caught exactly that way in review: 14 dirty files under `lib/`, 1 of
    them actually generated, `dart run build_runner build` itself reporting
    "wrote 0 outputs", and the gate failing regardless.

    Hashing only the files the generator actually owns -- before its run and
    after -- sidesteps the whole distinction: unrelated feature work never
    touches these paths, so it can never appear in the comparison, dirty
    tree or not.

    `normalize`, when given, runs after the generator and before the "after"
    snapshot -- for the codegen check this is `_format_codegen_outputs`,
    because the comparison has to be against build_runner-output-as-it-will-
    actually-be-committed (i.e. formatted), not raw generator output; see
    that function's docstring for why the two differ on this toolchain."""
    state: Dict[str, Dict[str, str]] = {}

    def pre_run() -> None:
        state["before"] = _generated_file_snapshot(patterns)

    def post_check() -> int:
        if normalize is not None:
            normalize()
        after = _generated_file_snapshot(patterns)
        before = state.get("before", {})
        changed = {
            path
            for path in set(before) | set(after)
            if before.get(path) != after.get(path)
        }
        if changed:
            print(
                f"[gate] {label}: 생성된 파일이 이번 실행으로 바뀌었습니다 "
                f"(커밋이 필요합니다):"
            )
            for path in sorted(changed):
                print(f"  {path}")
            return 1
        return 0

    return pre_run, post_check


# Drift/build_runner's own output-suffix convention -- not this repo's one
# current file (`database.g.dart`) hard-coded, so a second generated file
# added later is covered without anyone remembering to update this list.
_CODEGEN_PATTERNS = ["lib/**/*.g.dart", "lib/**/*.freezed.dart", "lib/**/*.gr.dart"]
# Every file build_schemas.py writes, and nothing it does not -- schemas/
# also holds a hand-written README.md that must never be treated as drift.
_SCHEMA_PATTERNS = ["schemas/*.schema.json"]

_codegen_pre, _codegen_post = _codegen_drift_check(
    _CODEGEN_PATTERNS, "코드 생성 확인", normalize=_format_codegen_outputs
)
# Schema outputs are JSON, not Dart -- no dart_style/SDK-formatter disagreement
# is possible, so no normalize step is needed here.
_schema_pre, _schema_post = _codegen_drift_check(_SCHEMA_PATTERNS, "스키마 재생성 확인")


def _flutter_argv(*args: str) -> Optional[List[str]]:
    exe = resolve_flutter_tool("flutter")
    return [exe, *args] if exe else None


def _dart_argv(*args: str) -> Optional[List[str]]:
    exe = resolve_flutter_tool("dart")
    return [exe, *args] if exe else None


def _python_argv(*args: str) -> Optional[List[str]]:
    return [resolve_python_tool(), *args]


STEPS: List[Step] = [
    Step(
        "declared_assets_tracked",
        "선언된 asset 경로 git 추적 확인",
        # Runs first, and before any flutter step: it's the check that would
        # have caught `assets/icons/` (declared in pubspec.yaml, present on
        # disk, tracked by git nowhere) before spending a minute on
        # everything else. It answers "would a fresh clone have this path",
        # which `flutter analyze` against *this* working tree cannot -- see
        # scripts/validate/check_declared_assets.py's module docstring for
        # the incident this closes and why the scope stays pubspec.yaml's
        # assets: list rather than trying to generalise further.
        lambda: _python_argv("scripts/validate/check_declared_assets.py"),
        tool_kind="python",
    ),
    Step(
        "flutter_pub_get",
        "의존성 설치",
        lambda: _flutter_argv("pub", "get"),
        tool_kind="flutter",
    ),
    Step(
        "codegen_check",
        "코드 생성 확인",
        lambda: _dart_argv("run", "build_runner", "build"),
        tool_kind="flutter",
        pre_run=_codegen_pre,
        post_check=_codegen_post,
    ),
    Step(
        "dart_format",
        "포맷 확인",
        # Deliberately NOT ci.yml's exact invocation (`dart format
        # --set-exit-if-changed .`, no `-o`): that default overwrites every
        # unformatted file on disk as a side effect of "checking". Harmless
        # on CI's disposable checkout; not harmless on a developer's real
        # working tree, which may hold someone else's in-progress, unsaved-
        # to-git edits this gate has no business rewriting out from under
        # them. `-o none` keeps the exact same pass/fail signal
        # (`--set-exit-if-changed`'s exit code) without writing a single
        # byte back to disk. Same check, strictly safer locally.
        lambda: _dart_argv("format", "--output=none", "--set-exit-if-changed", "."),
        tool_kind="flutter",
    ),
    Step(
        "flutter_analyze",
        "정적 분석",
        lambda: _flutter_argv("analyze"),
        tool_kind="flutter",
    ),
    Step(
        "flutter_test",
        "테스트 (Dart)",
        # Screenshots excluded: golden pixels depend on host fonts and must
        # never block a build -- same reasoning ci.yml states for this flag.
        lambda: _flutter_argv("test", "--exclude-tags", "screenshots", "--reporter", "expanded"),
        tool_kind="flutter",
    ),
    Step(
        "python_tests",
        "파이프라인 단위 테스트 (Python)",
        lambda: _python_argv("-m", "unittest", "discover", "-s", "scripts/tests", "-v"),
        tool_kind="python",
    ),
    Step(
        "schema_regen_check",
        "스키마 재생성 확인",
        lambda: _python_argv("scripts/publish/build_schemas.py"),
        tool_kind="python",
        pre_run=_schema_pre,
        post_check=_schema_post,
    ),
    Step(
        "data_validate",
        "배포본 검증",
        lambda: _python_argv("scripts/validate/validate_data.py", "public-data"),
        tool_kind="python",
    ),
    Step(
        "seed_reproducibility",
        "seed 재생성 가능 여부",
        lambda: _python_argv(
            "scripts/publish/build_seed.py", "--generated-at", SEED_GENERATED_AT
        ),
        tool_kind="python",
    ),
    Step(
        "seed_reproducibility_revalidate",
        "seed 재생성 후 재검증",
        lambda: _python_argv("scripts/validate/validate_data.py", "public-data"),
        tool_kind="python",
    ),
    Step(
        "contrast_check",
        "색 대비 검사 (Task A ratchet)",
        lambda: _python_argv("scripts/validate/check_contrast.py"),
        tool_kind="python",
    ),
]


# --------------------------------------------------------------------------
# Execution
# --------------------------------------------------------------------------


@dataclass
class StepResult:
    step: Step
    status: str  # "pass" | "fail" | "skip"
    seconds: float
    detail: str = ""


def run_step(step: Step, dry_run: bool, allow_missing_tools: bool) -> StepResult:
    start = time.monotonic()

    if dry_run:
        # Exercises the exact same call (`build_argv`, which resolves the
        # tool) that a real run would, without spawning the subprocess --
        # this is what test_commit_gate.py's completeness test depends on:
        # the loop must actually *reach* this line for every declared step.
        argv = step.build_argv()
        elapsed = time.monotonic() - start
        detail = "(dry run)" if argv else "(dry run; tool unresolved)"
        print(f"WOULD RUN: {step.id} {detail}")
        return StepResult(step, "pass", elapsed, detail)

    argv = step.build_argv()
    if argv is None:
        elapsed = time.monotonic() - start
        if not allow_missing_tools:
            print(
                f"[gate] {step.name_ko} ({step.id}): {step.tool_kind} 실행 파일을 "
                f"찾을 수 없습니다. 다음 중 하나를 선택하세요:\n"
                f"  1) PATH에 flutter/dart 추가\n"
                f"  2) 환경 변수 설정 -- PowerShell: "
                f"$env:FLUTTER_ROOT = 'C:\\path\\to\\flutter'"
                f"  /  bash: export FLUTTER_ROOT=/path/to/flutter\n"
                f"  3) 저장소 루트에 '.flutter_root' 파일을 만들고 "
                f"그 경로 한 줄만 적기 (커밋되지 않음, 한 번만 설정하면 계속 유효)\n"
                f"(건너뛰려면 --allow-missing-tools 또는 "
                f"WB_GATE_ALLOW_MISSING_TOOLS=1 을 명시적으로 지정하세요.)"
            )
            return StepResult(step, "fail", elapsed, "tool not found")
        print(
            f"[gate] SKIPPED — {step.name_ko} ({step.id}): {step.tool_kind} 실행 파일을 "
            f"찾지 못해 건너뛴 실행입니다. 이 결과는 통과가 아닙니다."
        )
        return StepResult(step, "skip", elapsed, "tool not found (explicitly allowed)")

    if step.pre_run is not None:
        step.pre_run()

    print(f"\n=== {step.name_ko} ({step.id}) ===")
    print("$", " ".join(argv))
    result = subprocess.run(argv, cwd=step.cwd)
    if result.returncode != 0:
        elapsed = time.monotonic() - start
        return StepResult(step, "fail", elapsed, f"exit code {result.returncode}")

    if step.post_check is not None:
        rc = step.post_check()
        if rc != 0:
            elapsed = time.monotonic() - start
            return StepResult(step, "fail", elapsed, "generated file changed")

    elapsed = time.monotonic() - start
    return StepResult(step, "pass", elapsed)


def main(argv=None) -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--allow-missing-tools",
        action="store_true",
        help=(
            "Treat a step whose external tool (flutter/dart) cannot be "
            "resolved as an explicit, logged SKIP instead of a failure. "
            "Off by default: rule 1 requires an explicit opt-in, not a "
            "silent pass, whenever a check cannot run at all."
        ),
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print which steps would run, in order, without running anything.",
    )
    args = parser.parse_args(argv)

    allow_missing = args.allow_missing_tools or os.environ.get(
        "WB_GATE_ALLOW_MISSING_TOOLS"
    ) == "1"

    results: List[StepResult] = []
    for step in STEPS:
        result = run_step(step, dry_run=args.dry_run, allow_missing_tools=allow_missing)
        results.append(result)
        if result.status == "fail":
            break  # fail fast: later steps assume earlier ones left a clean tree

    print("\n" + "=" * 60)
    print("커밋 게이트 요약 (commit gate summary)")
    print("=" * 60)
    total = 0.0
    any_skip = False
    any_fail = False
    for r in results:
        total += r.seconds
        mark = {"pass": "PASS", "fail": "FAIL", "skip": "SKIP"}[r.status]
        if r.status == "skip":
            any_skip = True
        if r.status == "fail":
            any_fail = True
        detail = f" — {r.detail}" if r.detail else ""
        print(f"  [{mark:4}] {r.step.name_ko:28} {r.seconds:6.1f}s{detail}")
    not_run = [s for s in STEPS if s.id not in {r.step.id for r in results}]
    for s in not_run:
        print(f"  [SKIP] {s.name_ko:28}    -- 이전 단계 실패로 실행되지 않음 (not run)")

    print(f"\n총 소요 시간 (total): {total:.1f}s")

    if any_fail:
        print("결과: 실패 (FAILED)")
        return 1
    if any_skip:
        print(
            "결과: 통과했지만 건너뛴 단계가 있습니다 "
            "(PASSED WITH SKIPPED STEPS -- this is not a clean pass)"
        )
        return 0
    print("결과: 통과 (PASSED)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
