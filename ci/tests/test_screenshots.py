from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from smbot import config, screenshots

CFG = config.load()
PNG = screenshots.PNG_MAGIC + b"\0" * 32


class ScreenshotsTest(unittest.TestCase):
    def test_only_plain_small_pngs_are_published(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            (d / "arena_four_wizards.png").write_bytes(PNG)
            (d / "main_menu.png").write_bytes(PNG)
            (d / "Evil Name.png").write_bytes(PNG)
            (d / "fake.png").write_bytes(b"<svg onload=alert(1)>")
            (d / "huge.png").write_bytes(PNG + b"\0" * screenshots.MAX_BYTES)
            (d / "link.png").symlink_to(d / "main_menu.png")
            self.assertEqual([p.name for p in screenshots.valid_shots(d)], ["arena_four_wizards.png", "main_menu.png"])
            self.assertEqual(screenshots.valid_shots(d / "missing"), [])

    def shots(self, tmp: str, chosen: list, after: dict, before: dict) -> Path:
        """A screenshots artifact: list.json, after/ and before/ with shots.txt."""
        root = Path(tmp)
        (root / "list.json").write_text(json.dumps(chosen))
        for side, made in (("after", after), ("before", before)):
            (root / side).mkdir()
            lines = []
            for script, files in made.items():
                for name, data in files.items():
                    (root / side / name).write_bytes(data)
                    lines.append(f"{script} {name}")
            (root / side / "shots.txt").write_text("\n".join(lines) + "\n")
        return root

    def test_the_log_repeats_the_bots_latest_screenshots_comment(self) -> None:
        comments = [{"user": {"login": CFG.bot.login}, "body": screenshots.HEADING + " (old1234 against `main`)"},
                    {"user": {"login": "someone"}, "body": screenshots.HEADING + " ![x](https://evil.example/x.png)"},
                    {"user": {"login": CFG.bot.login}, "body": "**Revised after the critique.**"},
                    {"user": {"login": CFG.bot.login}, "body": screenshots.HEADING + " (new1234 against `main`)"}]
        with mock.patch.object(screenshots.gh, "api_paginated", lambda path: comments):
            self.assertEqual(screenshots.for_log(CFG, 7), "**What #7 changes on screen** (new1234 against `main`)")
        with mock.patch.object(screenshots.gh, "api_paginated", lambda path: comments[1:3]):
            self.assertEqual(screenshots.for_log(CFG, 7), "")

    def test_only_chosen_shots_that_changed_are_shown_before_and_after(self) -> None:
        changed, same = PNG + b"new", PNG
        with tempfile.TemporaryDirectory() as tmp:
            root = self.shots(tmp, [{"script": "shot_builder", "caption": "The builder's new bag @everyone"},
                                    {"script": "../evil", "caption": "x"}],
                              after={"shot_builder": {"builder_bag.png": changed, "builder_four.png": same,
                                                      "builder_new.png": PNG},
                                     "shot_m1": {"arena.png": changed}},
                              before={"shot_builder": {"builder_bag.png": PNG, "builder_four.png": same},
                                      "shot_m1": {"arena.png": PNG}})
            shown = screenshots.pairs(root)
            self.assertEqual([(name, old is not None) for _, name, _, old in shown],
                             [("builder_bag.png", True), ("builder_new.png", False)])
            body = screenshots.comment(CFG, "c0ffee", "pr-7/abc1234", shown, "abc1234def")
        self.assertIn("The builder's new bag @\u200beveryone", body)
        self.assertIn(f"/c0ffee/pr-7/abc1234/before/builder_bag.png", body)
        self.assertIn(f"/c0ffee/pr-7/abc1234/after/builder_bag.png", body)
        self.assertIn("| Before (`main`) | After (this PR) |", body)
        self.assertIn("New: *Builder new*", body)
        self.assertNotIn("arena.png", body)  # not chosen: not about this change

    def test_post_skips_when_nothing_was_chosen_or_changed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(screenshots.gh, "api") as api, \
                mock.patch.object(screenshots, "push") as push:
            screenshots.post(CFG, "t", 7, "abc1234", Path(tmp))
            root = self.shots(tempfile.mkdtemp(dir=tmp), [{"script": "shot_m1", "caption": "c"}],
                              after={"shot_m1": {"arena.png": PNG}}, before={"shot_m1": {"arena.png": PNG}})
            screenshots.post(CFG, "t", 7, "abc1234", root)
        api.assert_not_called()
        push.assert_not_called()

    def test_post_pushes_then_comments_on_the_pr(self) -> None:
        posted: list = []

        def api(path: str, *args: str, input: dict | None = None) -> object:
            posted.append((path, input["body"]))
            return {}

        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(screenshots.gh, "api", api), \
                mock.patch.object(screenshots, "push", return_value="c0ffee") as push:
            root = self.shots(tmp, [{"script": "shot_m1", "caption": "The menu"}],
                              after={"shot_m1": {"main_menu.png": PNG + b"x"}}, before={"shot_m1": {"main_menu.png": PNG}})
            screenshots.post(CFG, "t", 7, "abc1234def", root)
        self.assertEqual(push.call_args.args[3], "pr-7/abc1234")
        self.assertEqual(push.call_args.kwargs["names"], ["after/main_menu.png", "before/main_menu.png"])
        self.assertEqual([path for path, _ in posted], [f"repos/{CFG.repo}/issues/7/comments"])
        self.assertIn("/c0ffee/pr-7/abc1234/after/main_menu.png", posted[0][1])

    def test_a_question_shows_the_shots_it_names(self) -> None:
        """#192 asked the owner to pick an art direction; the samples belong in the question itself."""
        question = {"title": "Pick a style?", "screenshots": [
            {"script": "shot_samples", "caption": "Samples A–F side by side @everyone"},
            {"script": "../evil", "caption": "x"}, {"script": "shot_missing", "caption": "Not made"}]}
        with tempfile.TemporaryDirectory() as tmp, \
                mock.patch.object(screenshots, "push", return_value="c0ffee") as push:
            root = self.shots(tmp, [], after={"shot_samples": {"samples_a_c.png": PNG, "samples_d_f.png": PNG},
                                              "shot_m1": {"arena.png": PNG}}, before={})
            body = screenshots.for_question(CFG, "t", question, root, "abc1234def")
            self.assertEqual(screenshots.for_question(CFG, "t", {"title": "No shots"}, root, "abc1234def"), "")
        self.assertEqual(push.call_count, 1)
        self.assertEqual([p.name for p in push.call_args.args[2]], ["samples_a_c.png", "samples_d_f.png"])
        self.assertEqual(push.call_args.args[3], "questions/abc1234")
        self.assertTrue(body.startswith("**Samples A–F side by side @\u200beveryone**"))
        self.assertIn(f"![Samples a c](https://raw.githubusercontent.com/{CFG.repo}/c0ffee/questions/abc1234/samples_a_c.png)", body)
        self.assertIn("/samples_d_f.png)", body)
        self.assertNotIn("arena.png", body)

    def test_push_adds_to_the_branch(self) -> None:
        import subprocess
        with tempfile.TemporaryDirectory() as tmp:
            origin = Path(tmp, "origin.git")
            subprocess.run(["git", "init", "-q", "--bare", str(origin)], check=True)
            Path(tmp, "main_menu.png").write_bytes(PNG)
            first = screenshots.push(CFG, "t", [Path(tmp, "main_menu.png")], "pr-7/abc1234", str(origin))
            second = screenshots.push(CFG, "t", [Path(tmp, "main_menu.png")], "pr-8/def5678", str(origin))
            files = subprocess.run(["git", "-C", str(origin), "ls-tree", "-r", "--name-only", second],
                                   check=True, capture_output=True, text=True).stdout.split()
            self.assertEqual(files, ["pr-7/abc1234/main_menu.png", "pr-8/def5678/main_menu.png"])
            parent = subprocess.run(["git", "-C", str(origin), "rev-parse", f"{second}^"],
                                    check=True, capture_output=True, text=True).stdout.strip()
            self.assertEqual(parent, first)

    def test_gallery(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            shots, out = Path(tmp, "shots"), Path(tmp, "site/screenshots")
            self.assertFalse(screenshots.gallery(shots, out, "v1"))
            shots.mkdir()
            Path(shots, "main_menu.png").write_bytes(PNG)
            self.assertTrue(screenshots.gallery(shots, out, "v0.20261017"))
            page = (out / "index.html").read_text()
            self.assertIn('src="main_menu.png"', page)
            self.assertIn("v0.20261017", page)
            self.assertTrue((out / "main_menu.png").exists())

    def test_the_cli_refuses_a_bad_sha(self) -> None:
        with self.assertRaises(SystemExit):
            screenshots.main(["post", "--pr", "7", "--sha", "main; rm -rf /", "--dir", "x"])


if __name__ == "__main__":
    unittest.main()
