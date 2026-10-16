from __future__ import annotations

import unittest
from pathlib import Path

from smbot import config, contribute

ROOT = Path(__file__).resolve().parents[2]


class ContributePageTest(unittest.TestCase):
    def test_parse_roadmap(self) -> None:
        text = ("| # | Milestone | Status | Done when | Opens for PRs |\n| --- | --- | --- | --- | --- |\n"
                "| M0 | [Foundation](milestones/M0-foundation.md) | **Closed early** on 2026-10-16 | a | No areas yet |\n"
                "| M1 | [Core loop](milestones/M1-core-loop.md) | **In progress** since 2026-10-16 | b | Art, Audio |\n"
                "| M2 | Spell system | Not started | c | Spells, Story |\n")
        current, upcoming = contribute.parse_roadmap(text)
        self.assertEqual((current.code, current.name, current.design), ("M1", "Core loop", "milestones/M1-core-loop.md"))
        self.assertEqual(upcoming, [("M2", "Spell system", "c", "Spells, Story")])

    def test_the_real_plan_files_parse(self) -> None:
        """Doesn't depend on which milestone is current today."""
        current, upcoming = contribute.parse_roadmap((ROOT / "docs/ROADMAP.md").read_text())
        self.assertRegex(current.code, r"^M\d$")
        self.assertTrue(all(int(u[0][1]) > int(current.code[1]) for u in upcoming))
        contribute.parse_progress(current, (ROOT / "docs/milestones/M0-foundation.md").read_text())
        self.assertEqual(current.parts_total, 7)
        self.assertGreater(current.checks_total, 10)

    def test_render_escapes_and_handles_missing_data(self) -> None:
        data = contribute.PageData(merged=[{"title": "<script>x</script>", "url": "https://x", "author": "a"}])
        page = contribute.render(config.load(), data, "v0.1", "nightly", "v0.0")
        self.assertIn("&lt;script&gt;", page)
        self.assertIn("Couldn't load the task list", page)

    def test_submission_credit(self) -> None:
        cfg = config.load()
        item = {"user": {"login": cfg.bot.login}, "title": "Submission from @ann-b: art/x.png"}
        self.assertEqual(contribute.contributor_of(item, cfg), "ann-b")


if __name__ == "__main__":
    unittest.main()
