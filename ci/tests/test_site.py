from __future__ import annotations

import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

from smbot import config, contribute, site

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


def web_zip(folder: Path, version: str) -> Path:
    path = folder / f"spellmerge-web-{version}.zip"
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
