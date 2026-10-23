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

    def test_the_build_file_parses_and_odd_values_are_refused(self) -> None:
        build = config.load_build()
        runs = build.runs
        self.assertTrue(build.ready)
        self.assertEqual(set(build.budgets), set(config.BUDGET_LIMITS))
        self.assertEqual(len({r.name for r in runs}), len(runs))
        good = {"ready": "ok", "runs": [{"name": "bots", "arg": "--bots", "label": "Bots", "linux_ok": "^OK",
                                          "web_ok": "OK", "web_timeout": 60, "bench": False}]}
        self.assertEqual(config.parse_build(good).runs[0].arg, "--bots")
        self.assertEqual(config.parse_build(good).budgets, config.DEFAULT_BUILD.budgets)  # optional
        bad = [("arg", "--bots; rm -rf /"), ("arg", "-x"), ("name", "../x"), ("linux_ok", "a\tb"),
               ("web_ok", ""), ("web_timeout", 99999), ("web_timeout", True), ("bench", "yes")]
        for key, value in bad:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                config.parse_build({**good, "runs": [{**good["runs"][0], key: value}]})
        with self.assertRaises(ValueError):
            config.parse_build({**good, "runs": good["runs"] * 2})  # the same name twice
        with self.assertRaises(ValueError):
            config.parse_build({**good, "runs": [{**good["runs"][0], "extra": 1}]})
        for budgets in ({"web_mb": 40}, {"web_mb": 0, "desktop_mb": 300, "web_load_s": 10},
                        {"web_mb": "40", "desktop_mb": 300, "web_load_s": 10}):
            with self.subTest(budgets=budgets), self.assertRaises(ValueError):
                config.parse_build({**good, "budgets": budgets})
        self.assertEqual(config.load_build(Path("/nonexistent")), config.DEFAULT_BUILD)

    def test_the_build_file_is_the_bots_and_a_broken_one_fails_the_rules(self) -> None:
        self.assertTrue(rules.is_bot_path(config.BUILD_FILE))
        change = rules.Change("M", config.BUILD_FILE, "100644")
        self.assertEqual(rules.check_content(change, (ROOT / config.BUILD_FILE).read_bytes(), rules.BOT), [])
        found = rules.check_content(change, b'{"ready": "ok", "runs": [{"name": "x"}]}', rules.BOT)
        self.assertEqual([f.rule for f in found], ["build-file"])
        self.assertEqual([f.rule for f in rules.check_content(change, b"{not json", rules.BOT)], ["build-file"])

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
