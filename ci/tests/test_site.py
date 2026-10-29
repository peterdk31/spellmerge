from __future__ import annotations

import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

from smbot import config, contribute, site

ROOT = Path(__file__).resolve().parents[2]


class ContributePageTest(unittest.TestCase):
    def test_parse_roadmap(self) -> None:
        text = ("| # | Milestone | Status | Done when |\n| --- | --- | --- | --- |\n"
                "| M0 | [Foundation](milestones/M0-foundation.md) | **Closed early** on 2026-10-16 | a |\n"
                "| M1 | [Core loop](milestones/M1-core-loop.md) | **In progress** since 2026-10-16 | b |\n"
                "| M2 | Spell system | Not started | c |\n")
        current, upcoming = contribute.parse_roadmap(text)
        self.assertEqual((current.code, current.name, current.design), ("M1", "Core loop", "milestones/M1-core-loop.md"))
        self.assertEqual(upcoming, [("M2", "Spell system", "c")])

    def test_the_real_plan_files_parse(self) -> None:
        """Doesn't depend on which milestone is current today."""
        current, upcoming = contribute.parse_roadmap((ROOT / "docs/ROADMAP.md").read_text())
        self.assertRegex(current.code, r"^M\d$")
        self.assertTrue(all(int(u[0][1]) > int(current.code[1]) for u in upcoming))
        m0 = ROOT / "docs/milestones/M0-foundation.md"
        if m0.exists():  # a new game's first task writes it
            contribute.parse_progress(current, m0.read_text())
            self.assertGreater(current.parts_total, 0)

    def test_parts_done_come_from_next_and_log(self) -> None:
        """M1 and M2's parts tables have no status column: the bar stayed at 0 for two milestones."""
        design = ("| # | Part | Delivers |\n| --- | --- | --- |\n"
                  "| 1 | a | x |\n| 2 | b | x |\n| 3 | c | x |\n| 4 | d | x |\n")
        next_md = ("- [ ] **Stabilisation (M2 part 4).** open\n"
                   "- [x] **Follow-up (M2 part 3 follow-up).** not the part itself\n"
                   "- [x] **Base classes (M2 part 1).** done\n"
                   "- [x] **Old milestone (M1 part 2).** another milestone\n")
        log_md = "## 2026-10-22: Events (M2 part 2)\n\nSee (M2 part 3) in passing.\n"
        m = contribute.parse_progress(contribute.Milestone(code="M2"), design, next_md, log_md)
        self.assertEqual((m.parts_done, m.parts_total), (2, 4))
        self.assertEqual(m.parts_left, [("3", "c"), ("4", "d")])

    def test_lettered_parts_count(self) -> None:
        """The staffs design names its parts A1, B6, F9a: the bar read "0 of 0" (2026-10-29)."""
        design = ("| # | Part | Delivers |\n| --- | --- | --- |\n"
                  "| A1 | **The plan** | x |\n| B2 | **Trigger kit** | x |\n| B6 | **Shot look** | x |\n"
                  "| F9a | **The imp on staffs** | x |\n| D1 | **Bots** | x |\n\n"
                  "| Needs | Cards |\n| --- | --- |\n| B2 | echo, burst |\n| B1 + B2 | sticky |\n")
        next_md = ("- [x] **Trigger kit, part 1 (staffs B2a).**\n- [x] **Trigger kit, part 2 (staffs B2b).**\n"
                   "- [ ] **Shot look, part 1 (staffs B6a).**\n- [x] **Shot look, part 2 (staffs B6b).**\n"
                   "- [x] **Leftover (staffs D1 leftover).** not the part itself\n")
        log_md = "## 2026-10-26: Pivot at C2 (staffs A1)\n"
        commits = "The imp and the shooting dummy on staffs (part F9a)\n\nCo-authored-by: x"
        m = contribute.parse_progress(contribute.Milestone(code="M2"), design, next_md, log_md)
        self.assertEqual((m.parts_done, m.parts_total), (2, 5))
        m = contribute.parse_progress(contribute.Milestone(code="M2"), design, next_md, log_md, commits)
        self.assertEqual((m.parts_done, m.parts_total), (3, 5))
        self.assertEqual(m.parts_left, [("B6", "Shot look"), ("D1", "Bots")])

    def test_the_real_design_has_parts(self) -> None:
        current, _ = contribute.parse_roadmap((ROOT / "docs/ROADMAP.md").read_text())
        design = ROOT / "docs" / current.design
        if current.design and design.exists():
            contribute.parse_progress(current, design.read_text())
            self.assertGreater(current.parts_total, 0, f"no parts found in {current.design}")

    def test_commits_come_from_the_api_and_fail_soft(self) -> None:
        now = contribute.dt.datetime(2026, 10, 29, tzinfo=contribute.dt.timezone.utc)
        found = [{"commit": {"message": "Enemy tags (part F3)"}}, {"commit": {"message": "Card: echo"}}]
        with mock.patch.object(contribute.gh, "api_paginated", return_value=found) as call:
            self.assertEqual(contribute.recent_commits(config.load(), now), "Enemy tags (part F3)\nCard: echo")
        self.assertIn("since=2026-07-31T00:00:00+00:00", call.call_args.args[0])
        with mock.patch.object(contribute.gh, "api_paginated", side_effect=contribute.gh.GhError("x")):
            self.assertEqual(contribute.recent_commits(config.load(), now), "")

    def test_render_lists_the_parts_left(self) -> None:
        m = contribute.Milestone("M2", "Spells", parts_done=1, parts_total=2, parts_left=[("D1", "Bots & <b>")])
        page = contribute.render(config.load(), contribute.PageData(current=m), "v0.1", "nightly", "v0.0")
        self.assertIn("Still to build", page)
        self.assertIn("<strong>D1</strong> Bots &amp; &lt;b&gt;", page)
        done = contribute.Milestone("M2", "Spells", parts_done=2, parts_total=2)
        page = contribute.render(config.load(), contribute.PageData(current=done), "v0.1", "nightly", "v0.0")
        self.assertNotIn("Still to build", page)

    def test_recently_merged_is_newest_merge_first(self) -> None:
        """Search sorted by update time: a comment after the merge moved an old PR to the top."""
        prs = [{"title": "old, commented today", "url": "u1", "mergedAt": "2026-10-20T10:00:00Z"},
               {"title": "newest", "url": "u2", "mergedAt": "2026-10-23T09:00:00Z"},
               {"title": "middle", "url": "u3", "mergedAt": "2026-10-22T09:00:00Z"}]
        with mock.patch.object(contribute.gh, "run", return_value=json.dumps(prs)), \
                mock.patch.object(contribute.gh, "api", side_effect=contribute.gh.GhError("x")), \
                mock.patch.object(contribute.gh, "api_paginated", side_effect=contribute.gh.GhError("x")):
            data = contribute.gather(config.load(), ROOT)
        self.assertEqual([p["title"] for p in data.merged or []], ["newest", "middle", "old, commented today"])

    def test_no_checks_bar_without_a_checklist(self) -> None:
        data = contribute.PageData(current=contribute.Milestone("M2", "Spells", parts_done=3, parts_total=4))
        page = contribute.render(config.load(), data, "v0.1", "nightly", "v0.0")
        self.assertIn("3 of 4 (75%)", page)
        self.assertNotIn("Checks passed", page)

    def test_render_escapes_and_handles_missing_data(self) -> None:
        data = contribute.PageData(merged=[{"title": "<script>x</script>", "url": "https://x", "author": "a"}])
        page = contribute.render(config.load(), data, "v0.1", "nightly", "v0.0")
        self.assertIn("&lt;script&gt;", page)
        self.assertIn("Couldn't load the queue", page)

    def test_render_shows_the_queue_and_done_reports(self) -> None:
        data = contribute.PageData(queue={"scheduled": 3, "backlog": 7}, merged=[],
                                   done=[{"title": "Doors stop bolts", "url": "https://x", "author": "ann-b"}])
        page = contribute.render(config.load(), data, "v0.1", "nightly", "v0.0")
        self.assertIn("3 in the work queue", page)
        self.assertIn("7 on the backlog", page)
        self.assertIn("reported by @ann-b", page)


def web_zip(folder: Path, version: str) -> Path:
    path = folder / site.WEB_ZIPS.replace("*", version)
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr("index.html", version)
    return path


class PreviewSiteTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        (self.root / "dist").mkdir()
        (self.root / "releases").mkdir()
        web_zip(self.root / "dist", "v0.20261022.1042")
        for patch in (mock.patch.object(contribute, "gather", return_value=contribute.PageData()),
                      mock.patch.object(site.styleguide, "build")):
            patch.start()
            self.addCleanup(patch.stop)

    def page(self, name: str) -> str:
        return (self.root / "site" / name / "index.html").read_text()

    def test_preview_keeps_the_releases_on_nightly_and_play(self) -> None:
        nightly = ("v0.20261022", "nightly", web_zip(self.root / "releases", "v0.20261022"))
        stable = ("v0.20261020", web_zip(self.root / "releases", "v0.20261020"))
        with mock.patch.object(site, "newest_release_web_zip", return_value=nightly), \
                mock.patch.object(site, "latest_stable_web_zip", return_value=stable):
            site.build_preview("o/r", self.root / "dist", "v0.20261022.1042", self.root / "site")
        self.assertEqual(self.page("preview"), "v0.20261022.1042")
        self.assertEqual(self.page("nightly"), "v0.20261022")
        self.assertEqual(self.page("play"), "v0.20261020")
        index = (self.root / "site" / "index.html").read_text()
        self.assertIn("Today's build (v0.20261022, nightly)", index)
        self.assertIn('href="preview/">Latest preview (v0.20261022.1042)', index)

    def test_preview_before_any_release(self) -> None:
        with mock.patch.object(site, "newest_release_web_zip", return_value=None), \
                mock.patch.object(site, "latest_stable_web_zip", return_value=None):
            site.build_preview("o/r", self.root / "dist", "v0.20261022.1042", self.root / "site")
        for name in ("preview", "nightly", "play"):
            self.assertEqual(self.page(name), "v0.20261022.1042")

    def test_daily_site_also_fills_preview(self) -> None:
        web_zip(self.root / "dist", "v0.20261022")
        site.build("o/r", self.root / "dist", "v0.20261022", "stable", self.root / "site")
        for name in ("preview", "nightly", "play"):
            self.assertEqual(self.page(name), "v0.20261022")

    def test_cli_needs_channel_or_preview(self) -> None:
        with self.assertRaises(SystemExit), mock.patch("sys.stderr"):
            site.main(["--version", "v0"])
        with self.assertRaises(SystemExit), mock.patch("sys.stderr"):
            site.main(["--version", "v0", "--channel", "stable", "--preview"])


if __name__ == "__main__":
    unittest.main()
