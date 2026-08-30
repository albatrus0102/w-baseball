"""Structural test for tools/commit_gate.py: the runner must actually invoke
every declared check, in order.

Why a subprocess and not just `import commit_gate; assert commit_gate.STEPS`
------------------------------------------------------------------------------
Asserting against the `STEPS` list alone would not catch the actual failure
mode this test exists for: someone edits `main()`'s loop -- say, adds an
early `continue`, or replaces `for step in STEPS` with a hand-picked subset
while leaving `STEPS` itself untouched. A test that only inspects the list
would keep passing while the runner silently stopped calling one of its
checks, which is exactly the "worse than no gate" scenario the task calls
out. So this test runs the real CLI entry point (`python tools/commit_gate.py
--dry-run`) as a subprocess, the same way a person or CI would invoke it, and
checks the module's own dry-run log line for every step that was actually
*reached* by the loop, in order.

Run with:
    python -m unittest discover -s scripts/tests -v
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GATE_PATH = os.path.join(ROOT, "tools", "commit_gate.py")
sys.path.insert(0, os.path.join(ROOT, "tools"))

import commit_gate  # noqa: E402 -- only used to read the declared STEPS list


class CommitGateCompletenessTest(unittest.TestCase):
    def _dry_run_invoked_ids(self):
        result = subprocess.run(
            [sys.executable, GATE_PATH, "--dry-run"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        self.assertEqual(
            result.returncode,
            0,
            f"--dry-run itself must never fail:\n{result.stdout}\n{result.stderr}",
        )
        invoked = re.findall(r"^WOULD RUN: (\S+)", result.stdout, re.MULTILINE)
        return invoked, result.stdout

    def test_every_declared_step_is_actually_invoked_in_order(self):
        invoked, stdout = self._dry_run_invoked_ids()
        declared = [s.id for s in commit_gate.STEPS]
        self.assertEqual(
            invoked,
            declared,
            "the runner's loop did not reach every declared step, in "
            "declared order -- a step was skipped, reordered, or the loop "
            "was short-circuited\n\nfull output:\n" + stdout,
        )

    def test_at_least_the_task_minimum_is_present(self):
        # The task's explicit floor: formatting, static analysis, the Dart
        # test suite, the Python tests, data validation, and the contrast
        # check. This is a second, independent assertion (not derived from
        # STEPS) so a refactor that renames/removes one of these specific
        # checks -- while still passing the "every declared step runs" test
        # above -- still fails loudly here.
        invoked, stdout = self._dry_run_invoked_ids()
        required = {
            "dart_format",
            "flutter_analyze",
            "flutter_test",
            "python_tests",
            "data_validate",
            "contrast_check",
        }
        missing = required - set(invoked)
        self.assertEqual(
            missing, set(), f"required check(s) missing from the gate: {missing}"
        )

    def test_step_ids_are_unique(self):
        ids = [s.id for s in commit_gate.STEPS]
        self.assertEqual(len(ids), len(set(ids)), "duplicate step id in STEPS")


class CodegenDriftCheckTest(unittest.TestCase):
    """Acceptance review found the original implementation used `git status
    --porcelain <dir>` as its predicate -- accurate on CI's clean checkout,
    wrong on a real working tree, which is dirty *by definition* whenever
    this gate is worth running. These tests pin the replacement predicate:
    "did a file this generator owns actually change", using a throwaway
    directory so they exercise the real filesystem instead of asserting
    against a mock."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self._old_root = commit_gate.REPO_ROOT
        commit_gate.REPO_ROOT = self._tmp.name  # snapshot globs are REPO_ROOT-relative
        self.addCleanup(setattr, commit_gate, "REPO_ROOT", self._old_root)

    def _write(self, relpath: str, content: str) -> None:
        path = os.path.join(self._tmp.name, relpath)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)

    def test_no_change_is_not_drift(self):
        self._write("lib/core/database/database.g.dart", "// generated v1\n")
        pre, post = commit_gate._codegen_drift_check(["lib/**/*.g.dart"], "test")
        pre()
        # Generator "ran" and produced byte-identical output -- the real-world
        # case that used to still fail under `git status --porcelain lib`
        # whenever anything else in `lib/` was uncommitted.
        self.assertEqual(post(), 0)

    def test_changed_generated_file_is_drift(self):
        self._write("lib/core/database/database.g.dart", "// generated v1\n")
        pre, post = commit_gate._codegen_drift_check(["lib/**/*.g.dart"], "test")
        pre()
        self._write("lib/core/database/database.g.dart", "// generated v2 (changed)\n")
        self.assertEqual(post(), 1)

    def test_unrelated_dirty_file_outside_the_pattern_is_not_drift(self):
        # The exact bug: an uncommitted feature file living in the same
        # directory as generated output must never trip this check.
        self._write("lib/core/database/database.g.dart", "// generated v1\n")
        pre, post = commit_gate._codegen_drift_check(["lib/**/*.g.dart"], "test")
        pre()
        self._write("lib/features/unrelated_screen.dart", "// someone's WIP\n")
        self.assertEqual(post(), 0)

    def test_a_new_generated_file_appearing_is_drift(self):
        pre, post = commit_gate._codegen_drift_check(["lib/**/*.g.dart"], "test")
        pre()
        self._write("lib/core/database/database.g.dart", "// generated, brand new\n")
        self.assertEqual(post(), 1)

    def test_normalize_hook_runs_before_the_after_snapshot(self):
        # Coordinator-directed fix: build_runner's raw output and a
        # subsequent `dart format` pass disagree on this toolchain (a real,
        # separate dart_style-via-pubspec.lock vs SDK-bundled-dart-format
        # mismatch), so the comparison has to be against the *formatted*
        # generator output, not the raw one. `normalize` is where that
        # formatting pass hangs off of -- this test pins that it actually
        # runs, and runs before the "after" hash is taken, using a fake
        # normalize that mimics a formatter rewriting the file in place.
        self._write("lib/core/database/database.g.dart", "raw generator output\n")
        pre, post = commit_gate._codegen_drift_check(
            ["lib/**/*.g.dart"],
            "test",
            normalize=lambda: self._write(
                "lib/core/database/database.g.dart", "raw generator output\n"
            ),
        )
        pre()
        # Simulate build_runner producing output that only *looks* different
        # from what's committed until formatting normalises it back.
        self._write("lib/core/database/database.g.dart", "raw   generator    output\n")
        # normalize() above rewrites it back to the pre-run content, so this
        # must NOT be reported as drift -- proving normalize ran, and ran
        # before the after-snapshot, not after (a post-snapshot-then-
        # normalize ordering would still see the unformatted content).
        self.assertEqual(post(), 0)


if __name__ == "__main__":
    unittest.main()
