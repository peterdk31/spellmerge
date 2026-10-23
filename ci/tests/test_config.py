import re
import unittest
from pathlib import Path

from smbot import config, rules

ROOT = Path(__file__).resolve().parents[2]
CFG = config.load()


class ConfigTest(unittest.TestCase):
    def test_get_reads_one_value(self) -> None:
        data = config.raw()
        self.assertEqual(config.get(data, "game.slug"), CFG.game.slug)
        self.assertEqual(config.get(data, "bot.id"), str(CFG.bot.id))
        with self.assertRaises(SystemExit):
            config.get(data, "game")

    def test_render_fills_the_common_values_and_leaves_the_rest(self) -> None:
        out = config.render("{{GAME}}: {{PITCH}} ({{REPO}}) {{OTHER}}", config.prompt_values(CFG))
        self.assertEqual(out, f"{CFG.game.name}: {CFG.game.pitch} ({CFG.repo}) {{{{OTHER}}}}")

    def test_pages_and_link_prefixes(self) -> None:
        owner, name = CFG.repo.split("/")
        self.assertEqual(CFG.pages, f"https://{owner.lower()}.github.io/{name}")
        self.assertIn(f"https://github.com/{CFG.repo}", rules.LINK_PREFIXES)
        self.assertIn(CFG.pages, rules.LINK_PREFIXES)

    def test_the_harness_does_not_hardcode_the_identities(self) -> None:
        """They come from ci/config.json and the repository variables, so the harness can start another game."""
        values = [v for v in (CFG.bot_client_id, str(CFG.bot.id), str(CFG.owner.id), CFG.bot.login)
                  if v not in ("", "0")]  # a new game's bot is filled in by ci/bootstrap's launch
        files = [*(ROOT / ".github" / "workflows").glob("*.yml"), ROOT / ".github" / "actions" / "claude" / "action.yml",
                 *(ROOT / ".github" / "maintainer").glob("*.md")]
        for path in files:
            text = path.read_text()
            if path.name == "action.yml":
                text = "\n".join(line for line in text.splitlines() if "description:" not in line)
            for value in values:
                self.assertIsNone(re.search(rf"(?<![\w-]){re.escape(value)}(?![\w-])", text),
                                  f"{path.relative_to(ROOT)} hardcodes {value}")
        for path in (ROOT / ".github" / "maintainer").glob("*.md"):
            self.assertNotIn(CFG.game.name, path.read_text(), f"{path.name}: use {{{{GAME}}}}")


if __name__ == "__main__":
    unittest.main()
