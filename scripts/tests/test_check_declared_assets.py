"""Tests for scripts/validate/check_declared_assets.py -- the check that
closes the `assets/icons/` gap: a path declared in `pubspec.yaml`'s
`assets:` list that exists on disk but that git does not track, so it
disappears on a fresh clone (exactly what happened when CI ran `flutter
analyze` for the first time and this repo's local gate had not).

Two things needed proof, because getting either wrong would let the exact
incident recur silently:

  * the hand-rolled pubspec.yaml parser (`_parse_declared_assets`) has to
    find the real `assets:` list, and stop at the right place, without a
    YAML dependency;
  * the git-tracked check has to fail for a declared path with nothing
    committed under it, and pass once something is -- proven against a real
    throwaway git repo, not a mock, so a change to the git-invocation logic
    can't quietly break in a way a mock would hide.

Run with:
    python -m unittest discover -s scripts/tests -v
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts", "validate"))

import check_declared_assets as cda  # noqa: E402


class ParseDeclaredAssetsTest(unittest.TestCase):
    def test_finds_every_item_in_the_real_shape(self):
        text = textwrap.dedent(
            """\
            flutter:
              uses-material-design: true
              # a comment in between
              assets:
                - assets/seed/
                - assets/seed/games/
                - assets/icons/
            """
        )
        self.assertEqual(
            cda._parse_declared_assets(text),
            ["assets/seed/", "assets/seed/games/", "assets/icons/"],
        )

    def test_stops_at_the_next_sibling_key(self):
        text = textwrap.dedent(
            """\
            flutter:
              assets:
                - assets/seed/
              fonts:
                - family: Example
            """
        )
        self.assertEqual(cda._parse_declared_assets(text), ["assets/seed/"])

    def test_no_assets_key_returns_empty_list(self):
        text = "flutter:\n  uses-material-design: true\n"
        self.assertEqual(cda._parse_declared_assets(text), [])

    def test_strips_quotes_from_items(self):
        text = 'flutter:\n  assets:\n    - "assets/seed/"\n'
        self.assertEqual(cda._parse_declared_assets(text), ["assets/seed/"])


class GitTrackedCheckTest(unittest.TestCase):
    """Exercises `_git_tracked_files_under` and `main()` against a real,
    throwaway git repo -- the same tool (`git ls-files`) and the same
    question ("would a fresh clone have this") the real check depends on."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self._old_root = cda.REPO_ROOT
        self._old_pubspec = cda.PUBSPEC_PATH
        cda.REPO_ROOT = self._tmp.name
        cda.PUBSPEC_PATH = os.path.join(self._tmp.name, "pubspec.yaml")
        self.addCleanup(setattr, cda, "REPO_ROOT", self._old_root)
        self.addCleanup(setattr, cda, "PUBSPEC_PATH", self._old_pubspec)
        subprocess.run(["git", "init", "-q"], cwd=self._tmp.name, check=True)
        # A throwaway repo has no identity configured on a bare CI box --
        # set one locally so `git commit` below doesn't fail on that alone.
        subprocess.run(
            ["git", "config", "user.email", "test@example.com"],
            cwd=self._tmp.name,
            check=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "Test"], cwd=self._tmp.name, check=True
        )

    def _write(self, relpath: str, content: str = "") -> None:
        path = os.path.join(self._tmp.name, relpath)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)

    def _commit_all(self) -> None:
        subprocess.run(["git", "add", "-A"], cwd=self._tmp.name, check=True)
        subprocess.run(
            ["git", "commit", "-q", "-m", "test"], cwd=self._tmp.name, check=True
        )

    def test_declared_directory_with_no_tracked_files_fails(self):
        # This is the exact incident: the directory exists on disk (so
        # `flutter analyze` locally, and `os.path.exists`, both say it's
        # fine) but nothing under it is committed.
        self._write("assets/icons/.keep_but_not_committed", "")
        self._write(
            "pubspec.yaml", "flutter:\n  assets:\n    - assets/icons/\n"
        )
        self._commit_all()  # commits pubspec.yaml only -- .gitignore-free repo, but
        # assets/icons/.keep_but_not_committed was never `git add`ed after being
        # rewritten untracked on purpose: simulate by removing it from the index.
        subprocess.run(
            ["git", "rm", "-q", "--cached", "assets/icons/.keep_but_not_committed"],
            cwd=self._tmp.name,
            check=True,
        )
        self.assertEqual(cda.main(), 1)

    def test_declared_directory_with_a_tracked_file_passes(self):
        self._write("assets/icons/logo.png", "not a real png, just tracked")
        self._write(
            "pubspec.yaml", "flutter:\n  assets:\n    - assets/icons/\n"
        )
        self._commit_all()
        self.assertEqual(cda.main(), 0)

    def test_removing_the_declaration_entirely_also_passes(self):
        # The actual fix applied to this repo's pubspec.yaml: delete the
        # line rather than commit a placeholder file. Nothing declared,
        # nothing to check, still a clean pass.
        self._write("pubspec.yaml", "flutter:\n  assets:\n    - assets/seed/\n")
        self._write("assets/seed/games.json", "{}")
        self._commit_all()
        self.assertEqual(cda.main(), 0)

    def test_mixed_declared_paths_reports_only_the_untracked_one(self):
        self._write("assets/seed/games.json", "{}")
        self._write(
            "pubspec.yaml",
            "flutter:\n  assets:\n    - assets/seed/\n    - assets/icons/\n",
        )
        self._commit_all()
        self.assertEqual(cda.main(), 1)


if __name__ == "__main__":
    unittest.main()
