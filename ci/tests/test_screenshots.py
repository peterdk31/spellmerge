from __future__ import annotations

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

    def test_comment_links_by_commit(self) -> None:
        body = screenshots.comment(CFG, "c0ffee", "pr-7/abc1234", [Path("arena_four_wizards.png")], "abc1234def")
        self.assertIn(f"https://raw.githubusercontent.com/{CFG.repo}/c0ffee/pr-7/abc1234/arena_four_wizards.png", body)
        self.assertIn("**Arena four wizards**", body)
        self.assertIn("abc1234", body)

    def test_post_skips_when_there_is_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(screenshots.gh, "api") as api, \
                mock.patch.object(screenshots, "push") as push:
            screenshots.post(CFG, "t", 7, "abc1234", Path(tmp))
        api.assert_not_called()
        push.assert_not_called()

    def test_post_pushes_then_comments(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(screenshots.gh, "api") as api, \
                mock.patch.object(screenshots, "push", return_value="c0ffee") as push:
            Path(tmp, "main_menu.png").write_bytes(PNG)
            screenshots.post(CFG, "t", 7, "abc1234def", Path(tmp))
        self.assertEqual(push.call_args.args[3], "pr-7/abc1234")
        self.assertIn("issues/7/comments", api.call_args.args[0])
        self.assertIn("/c0ffee/pr-7/abc1234/main_menu.png", api.call_args.kwargs["input"]["body"])

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
