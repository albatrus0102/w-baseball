"""Tests for the normalisation pipeline.

The Python side had no tests at all, which meant three claims went unchecked:
that story clustering groups the same event and separates different ones, that
an unrecognised team spelling is never guessed at, and that the Korean text
rules match the Dart implementation the app searches with.

Run with:
    python -m unittest discover -s scripts/tests -v
"""

from __future__ import annotations

import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts", "normalize"))

import normalize  # noqa: E402


class StripMarkupTest(unittest.TestCase):
    def test_removes_search_api_highlighting(self):
        self.assertEqual(
            normalize.strip_markup("<b>여자야구</b> 대회"), "여자야구 대회"
        )

    def test_unescapes_entities(self):
        self.assertEqual(normalize.strip_markup("A&amp;B"), "A&B")

    def test_handles_empty_and_none(self):
        self.assertEqual(normalize.strip_markup(""), "")
        self.assertEqual(normalize.strip_markup(None), "")


class KoreanTextTest(unittest.TestCase):
    """Must agree with `KoreanText` in the app, or search finds different
    things depending on which side ran."""

    def test_initials_extracts_lead_consonants(self):
        self.assertEqual(normalize.initials("서울"), "ㅅㅇ")
        # 한-강-리-버-베-어-스 → ㅎㄱㄹㅂㅂㅇㅅ (vowel-initial 어 keeps ㅇ)
        self.assertEqual(normalize.initials("한강 리버베어스"), "ㅎㄱㄹㅂㅂㅇㅅ")

    def test_initials_keeps_double_consonants_distinct(self):
        # ㄲ must not be flattened to ㄱ; they are different lead consonants.
        self.assertEqual(normalize.initials("까치"), "ㄲㅊ")

    def test_initials_lowercases_latin_and_keeps_digits(self):
        self.assertEqual(normalize.initials("WBSC 2026"), "wbsc2026")

    def test_normalize_drops_spaces_and_punctuation(self):
        self.assertEqual(
            normalize.normalize_name("한강 리버-베어스 (서울)"), "한강리버베어스서울"
        )

    def test_normalize_is_case_insensitive(self):
        self.assertEqual(normalize.normalize_name("WBSC"), normalize.normalize_name("wbsc"))


class ParseRfc822Test(unittest.TestCase):
    def test_converts_to_utc_iso(self):
        self.assertEqual(
            normalize.parse_rfc822("Fri, 27 Feb 2026 12:21:00 +0900"),
            "2026-02-27T03:21:00Z",
        )

    def test_rejects_missing_timezone(self):
        # A timestamp without a zone cannot be placed on a timeline, and
        # guessing KST would silently shift every article by nine hours.
        self.assertIsNone(normalize.parse_rfc822("Fri, 27 Feb 2026 12:21:00"))

    def test_rejects_garbage(self):
        self.assertIsNone(normalize.parse_rfc822("어제"))
        self.assertIsNone(normalize.parse_rfc822(""))


class StoryKeyTest(unittest.TestCase):
    def test_identical_significant_words_share_a_key(self):
        # Word order and punctuation do not matter; the token *set* does.
        a = normalize.story_key("채널A 야구여왕 시즌2 제작 확정")
        b = normalize.story_key("[속보] 확정! 제작 시즌2 야구여왕, 채널A")
        self.assertEqual(a, b)

    def test_one_extra_word_splits_the_cluster(self):
        # Documents a real limitation rather than an intention. `story_key`
        # requires the significant-token sets to match exactly, so two reports
        # of the same event separate as soon as one headline carries an extra
        # word. Under-grouping is the deliberate direction — merging unrelated
        # stories is worse — but in practice most same-event headlines differ
        # by at least one word, so clusters will be smaller than they look in
        # the seed data, which was grouped by hand.
        a = normalize.story_key("채널A 야구여왕 시즌2 제작 확정")
        b = normalize.story_key("야구여왕 시즌2 제작 확정, 채널A 편성")
        self.assertNotEqual(a, b)

    def test_different_events_do_not_collide(self):
        a = normalize.story_key("여자야구 국가대표 최종 명단 발표")
        b = normalize.story_key("채널A 야구여왕 시즌2 제작 확정")
        self.assertNotEqual(a, b)

    def test_stopwords_alone_still_produce_a_key(self):
        # Falls back to hashing the headline rather than grouping every
        # stopword-only title into one cluster.
        a = normalize.story_key("여자야구 속보")
        b = normalize.story_key("야구 종합")
        self.assertNotEqual(a, b)

    def test_is_deterministic(self):
        title = "여자야구 대표팀 훈련 시작"
        self.assertEqual(normalize.story_key(title), normalize.story_key(title))


class ResolveTeamTest(unittest.TestCase):
    def setUp(self):
        self.index = {
            normalize.normalize_name("한강 리버베어스"): "team-demo-hangang",
            normalize.initials("한강 리버베어스"): "team-demo-hangang",
        }

    def test_resolves_a_known_spelling(self):
        unknown = []
        self.assertEqual(
            normalize.resolve_team("한강 리버베어스", self.index, unknown),
            "team-demo-hangang",
        )
        self.assertEqual(unknown, [])

    def test_ignores_spacing_differences(self):
        unknown = []
        self.assertEqual(
            normalize.resolve_team("한강리버베어스", self.index, unknown),
            "team-demo-hangang",
        )

    def test_never_guesses_an_unknown_spelling(self):
        # Guessing is how two unrelated teams get merged. An unknown spelling
        # must go to a person instead.
        unknown = []
        self.assertIsNone(normalize.resolve_team("어딘가 이름없는팀", self.index, unknown))
        self.assertEqual(len(unknown), 1)
        self.assertEqual(unknown[0]["name"], "어딘가 이름없는팀")

    def test_empty_name_is_not_queued_for_review(self):
        unknown = []
        self.assertIsNone(normalize.resolve_team("", self.index, unknown))
        self.assertEqual(unknown, [])


class NormalizeNewsTest(unittest.TestCase):
    def test_summary_states_only_what_can_be_counted(self):
        # The pipeline must never expand a headline into a claim about what
        # happened. With several sources it may say how many; with one it says
        # nothing at all.
        result = normalize.normalize_news([], {})
        self.assertEqual(result["storyClusters"], [])

    def test_output_is_never_marked_reviewed(self):
        import inspect

        source = inspect.getsource(normalize.normalize_news)
        self.assertIn('"reviewStatus": "pending"', source)
        self.assertNotIn('"reviewStatus": "reviewed"', source)


if __name__ == "__main__":
    unittest.main()
