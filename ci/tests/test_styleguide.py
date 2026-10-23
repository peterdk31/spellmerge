from __future__ import annotations

import re
import tempfile
import unittest
import zipfile
from pathlib import Path

from smbot import styleguide


@unittest.skipUnless(styleguide.STYLE.exists(), "no docs/STYLE.md yet (a new game)")
class StyleGuideTest(unittest.TestCase):
    def test_the_palette_files_match_the_style_table(self) -> None:
        """art/kit's palette files and the SVG art test copy docs/STYLE.md's table; this keeps them
        from drifting. The palette's size isn't pinned: the bot may change the table as it sees fit."""
        table = styleguide.sections(styleguide.STYLE.read_text())["Palette"]
        from_table = [c.lower() for row in table.splitlines() if row.startswith("| **")
                      for c in re.findall(r"`#([0-9a-fA-F]{6})`", row)]
        self.assertTrue(from_table, "STYLE.md's palette table has no colours")
        self.assertEqual(len(set(from_table)), len(from_table), "a colour is listed twice")
        self.assertEqual(styleguide.palette(), from_table)
        gpl = [line.split()[:3] for line in (styleguide.KIT / f"{styleguide.PALETTE}.txt").read_text().splitlines()
               if re.match(r"\s*\d+\s+\d+\s+\d+", line)]
        self.assertEqual([f"{int(r):02x}{int(g):02x}{int(b):02x}" for r, g, b in gpl], from_table)
        svg_test = (styleguide.ROOT / "tests" / "core" / "test_svg_art.gd").read_text()
        block = re.search(r"const PALETTE: Array\[String\] = \[(.*?)\]", svg_test, re.S)
        self.assertIsNotNone(block, "tests/core/test_svg_art.gd has no PALETTE list")
        self.assertEqual(re.findall(r'"#([0-9a-f]{6})"', block.group(1)), from_table)

    def test_render(self) -> None:
        out = styleguide.render("1. **One** `a<b`\n2. Two\n\n- [ ] Box\n- [ ] Box 2\n\n| A | B |\n| --- | --- |\n"
                                "| x | [y](STYLE.md) |\n\nPlain <tag> text")
        self.assertIn("<ol><li><strong>One</strong> <code>a&lt;b</code></li>", out)
        self.assertIn("&#9744; Box", out)
        self.assertIn("<td>x</td>", out)
        self.assertIn("blob/main/docs/STYLE.md", out)
        self.assertIn("Plain &lt;tag&gt; text", out)

    def test_build_writes_the_page_kit_and_zip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp, "style-guide")
            styleguide.build(out)
            page = (out / "index.html").read_text()
            for name in styleguide.SECTIONS:
                self.assertIn(f"<h2>{name}</h2>", page)
            self.assertEqual(page.count('class="swatch"'), len(styleguide.palette()))
            self.assertNotIn("in_game.png", page)
            for example in styleguide.golden():
                self.assertTrue((out / "golden" / styleguide.flat_name(example["path"])).is_file())
            names = zipfile.ZipFile(out / styleguide.ZIP_NAME).namelist()
            self.assertIn(styleguide.PALETTE, names)
            self.assertIn("NOTICE.txt", names)
            self.assertEqual(len([n for n in names if n.startswith("golden/")]), len(styleguide.golden()))


if __name__ == "__main__":
    unittest.main()
