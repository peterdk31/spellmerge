from __future__ import annotations

import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest import mock

from smbot import contrib


def png(width: int = 2, height: int = 2, extra: bytes = b"") -> bytes:
    raw = b"".join(b"\x00" + b"\xff\x00\x00\xff" * width for _ in range(height))
    return (contrib.PNG_SIG + contrib._chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + extra + contrib._chunk(b"IDAT", zlib.compress(raw)) + contrib._chunk(b"IEND", b""))


URL = "https://github.com/user-attachments/assets/1234-abcd"


class ClaTest(unittest.TestCase):
    def test_the_signing_phrase(self) -> None:
        self.assertTrue(contrib.is_signing_comment("I have read the CLA and I agree to it."))
        self.assertFalse(contrib.is_signing_comment("I have read the CLA and I agree to it, mostly."))

    def test_only_the_authors_own_comment_signs(self) -> None:
        comments = [{"author": "other", "author_id": 9, "body": "I have read the CLA and I agree to it.", "url": "a"},
                    {"author": "ann", "author_id": 7, "body": "I have read the CLA and I agree to it.", "url": "b"}]
        sig = contrib.find_signature(comments, "ann", "1.0")
        self.assertEqual((sig["user_id"], sig["evidence"]), (7, "b"))
        self.assertIsNone(contrib.find_signature(comments[:1], "ann", "1.0"))

    def test_signatures_on_file_and_in_the_state_count_per_version(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp, "sigs.json")
            path.write_text(json.dumps({"signatures": [{"user_id": 1, "version": "1.0"}]}))
            st = {"cla_signatures": {"2:1.0": {"user_id": 2, "version": "1.0"}}}
            self.assertTrue(contrib.has_signed(st, 1, "1.0", path))
            self.assertTrue(contrib.has_signed(st, 2, "1.0", path))
            self.assertFalse(contrib.has_signed(st, 2, "2.0", path))
        self.assertRegex(contrib.current_version(), r"^\d")


class AssetTest(unittest.TestCase):
    def test_png_is_re_encoded_without_extra_chunks(self) -> None:
        out, w, h = contrib.reencode_png(png(extra=contrib._chunk(b"tEXt", b"hidden")))
        self.assertEqual((w, h), (2, 2))
        self.assertNotIn(b"hidden", out)
        with self.assertRaises(contrib.Invalid):
            contrib.reencode_png(b"GIF89a")

    def test_a_malformed_png_is_refused_not_crashed_on(self) -> None:
        bad_header = contrib.PNG_SIG + contrib._chunk(b"IHDR", b"\x00" * 12) + contrib._chunk(b"IEND", b"")
        with self.assertRaises(contrib.Invalid):
            contrib.reencode_png(bad_header)
        gathered = {"items": [{"ref": "discussion:7", "attachments": [URL]}]}
        decision = {"items": [{"ref": "discussion:7", "decision": "schedule", "assets": ["not a dict"]}]}
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIn("error", contrib.prepare_assets(decision, gathered, Path(tmp))["discussion:7"])

    def test_attachment_urls_and_hosts_are_strict(self) -> None:
        self.assertTrue(contrib.ATTACHMENT.fullmatch(URL))
        self.assertIsNone(contrib.ATTACHMENT.fullmatch("https://github.com/user-attachments/assets/../../x"))
        self.assertTrue(contrib._github_host("https://objects.githubusercontent.com/a"))
        self.assertFalse(contrib._github_host("https://github-production-user-asset-evil.com/a"))
        self.assertFalse(contrib._github_host("http://github.com/a"))

    def test_target_paths_stay_in_the_asset_folders(self) -> None:
        self.assertEqual(contrib.check_path("art/enemies/slime.png"), "art/enemies/slime.png")
        for bad in ("ci/x.png", "art/../ci/x.png", "/art/x.png", "art/x.gd", "art/%2e%2e/x.png",
                    "art/a?ref=main#.png", "art/Slime.png", 7):
            with self.assertRaises(contrib.Invalid):
                contrib.check_path(bad)

    def test_only_the_posters_attachments_become_files(self) -> None:
        gathered = {"items": [{"ref": "discussion:7", "attachments": [URL]}]}
        decision = {"items": [{"ref": "discussion:7", "decision": "schedule",
                               "assets": [{"url": URL, "path": "art/enemies/slime.png"}]}]}
        other = {"items": [{"ref": "discussion:7", "decision": "schedule",
                            "assets": [{"url": URL + "-other", "path": "art/x.png"}]}]}
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(contrib, "download", lambda url, limit: png()):
            results = contrib.prepare_assets(decision, gathered, Path(tmp))
            self.assertEqual(results["discussion:7"]["files"], ["art/enemies/slime.png (2×2 PNG)"])
            self.assertTrue(Path(tmp, "7", "art/enemies/slime.png").exists())
            self.assertIn("attached", contrib.prepare_assets(other, gathered, Path(tmp))["discussion:7"]["error"])

    def test_download_only_from_github_attachments(self) -> None:
        with self.assertRaises(contrib.Invalid):
            contrib.download("https://evil.example/x.png", 1000)


if __name__ == "__main__":
    unittest.main()
