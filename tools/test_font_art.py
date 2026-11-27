# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/font_art.py: the font's sheet and metrics up to date, every glyph inside its cell."""

import json
import re
import unittest

import font_art


class FontArtTest(unittest.TestCase):
    def test_the_files_are_up_to_date(self) -> None:
        self.assertEqual(font_art.main(["--check"]), 0, "run tools/font_art.py")

    def test_every_character_the_game_writes_is_drawn(self) -> None:
        warmup = (font_art.ROOT / "core/base/glyph_warmup.gd").read_text(encoding="utf-8")
        extra = re.search(r'const EXTRA: String = "([^"]*)"', warmup).group(1)
        for ch in extra + "".join(chr(c) for c in range(32, 127)):
            self.assertIn(ch, font_art.CHARS)

    def test_every_glyph_is_inside_its_cell(self) -> None:
        for size in font_art.FACES:
            face = font_art.Face(size)
            for ch in font_art.CHARS:
                cv = font_art.draw(face, ch)
                self.assertGreater(cv.width, 0, f"{ch!r} at {size}")
                if ch != " ":
                    self.assertTrue(cv.on, f"{ch!r} at {size} draws something")
                for x, y in cv.on:
                    self.assertTrue(0 <= x < cv.width and -face.desc <= y < face.asc, f"{ch!r} at {size}")

    def test_the_metrics_name_every_face(self) -> None:
        meta = json.loads(font_art.OUT_JSON.read_text(encoding="utf-8"))
        self.assertEqual([f["size"] for f in meta["faces"]], font_art.FACES)
        for face in meta["faces"]:
            self.assertEqual(len(face["glyphs"]), len(meta["chars"]))


if __name__ == "__main__":
    unittest.main()
