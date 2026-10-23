import datetime as dt
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from smbot import bootstrap, config, panel, rules

ROOT = Path(__file__).resolve().parents[2]
GAME = bootstrap.Game(name="Bee Keeper", repo="someone/bee-keeper", idea="A cozy co-op game about bees.\nMore.",
                      pitch="a cozy co-op game about bees", description="Keep bees. Together.",
                      owner_login="someone", owner_id=4242424, timezone="Europe/Copenhagen")


@unittest.skipUnless((ROOT / ".git").exists() and (ROOT / "ci" / "bootstrap" / "harness.json").exists(),
                     "needs a git checkout with the template (a new game's copy has none)")
class ScaffoldTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = Path(tempfile.mkdtemp())
        cls.dest = cls.tmp / "bee"
        identity = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
        with mock.patch.dict(os.environ, identity):  # CI has no git identity
            bootstrap.scaffold(GAME, cls.dest, ROOT, dt.date(2026, 11, 2))

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.tmp)

    def test_the_config_is_the_new_games_and_waits_for_the_bot(self) -> None:
        cfg = config.load(self.dest / "ci" / "config.json")
        self.assertEqual((cfg.repo, cfg.game.name, cfg.game.slug, cfg.owner.id), (GAME.repo, "Bee Keeper", "bee-keeper", 4242424))
        self.assertEqual((cfg.bot.login, cfg.bot_client_id, cfg.control_panel_issue), ("", "", 0))
        self.assertEqual(config.load_runs(self.dest), ("main menu ready", ()))

    def test_the_design_is_the_idea_and_a_draft(self) -> None:
        design = (self.dest / "docs" / "DESIGN.md").read_text()
        self.assertIn(rules.DESIGN_DRAFT_MARKER, design)
        self.assertIn("A cozy co-op game about bees.\nMore.", design)
        self.assertIn("**Draft the design (M0 part 1).**", (self.dest / "docs" / "NEXT.md").read_text())

    def test_the_plan_keeps_the_harness_and_leaves_the_game(self) -> None:
        plan = (self.dest / "docs" / "PLAN.md").read_text()
        self.assertTrue(plan.startswith("# Bee Keeper — Project Plan\n\nNov 2, 2026 · someone\n"))
        self.assertIn("## Security model", plan)
        self.assertIn("## Game design\n\nNot written yet", plan)
        self.assertNotIn("Spellmerge", plan)
        self.assertIn("### Name check\n\nNot done yet for Bee Keeper", plan)

    def test_only_the_harness_is_copied_and_renamed(self) -> None:
        self.assertFalse((self.dest / "content").exists())
        self.assertFalse((self.dest / "ci" / "bootstrap").exists())
        self.assertFalse((self.dest / ".github" / "ISSUE_TEMPLATE" / "spell_idea.yml").exists())
        self.assertIn("/docs/DESIGN.md              @someone", (self.dest / ".github" / "CODEOWNERS").read_text())
        self.assertIn('export_path="build/windows/Bee Keeper.exe"', (self.dest / "export_presets.cfg").read_text())
        self.assertIn('config/name="Bee Keeper"', (self.dest / "project.godot").read_text())
        self.assertEqual(json.loads((self.dest / "docs" / "cla-signatures.json").read_text())["signatures"], [])

    def test_the_new_repo_is_one_commit_and_its_own_harness_tests_pass(self) -> None:
        log = subprocess.run(["git", "-C", str(self.dest), "log", "--oneline"], capture_output=True, text=True).stdout
        self.assertEqual(len(log.splitlines()), 1)
        run = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "ci/tests", "-t", "ci",
                              "-k", "Config", "-k", "Rules", "-k", "Summary", "-k", "Site"],
                             cwd=self.dest, capture_output=True, text=True, env={**os.environ, "PYTHONPATH": "ci"})
        self.assertEqual(run.returncode, 0, run.stderr[-2000:])

    def test_a_folder_in_use_is_refused(self) -> None:
        with self.assertRaises(SystemExit):
            bootstrap.scaffold(GAME, self.dest, ROOT)


class WizardTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dest = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dest)
        (self.dest / ".git").mkdir()
        (self.dest / "ci").mkdir()
        shutil.copy(ROOT / "ci" / "config.json", self.dest / "ci" / "config.json")

    def steps(self, fail: str = "") -> tuple[tuple[str, str, object], ...]:
        self.ran: list[str] = []

        def make(key: str):  # noqa: ANN202
            def run(dest: Path, cfg: config.Config, data: dict) -> None:
                if key == fail:
                    raise bootstrap.StepFailed("no network")
                self.ran.append(key)
                data[key] = True
            return run
        return tuple((k, f"Step {k}", make(k)) for k in ("a", "b", "c"))

    def test_a_failed_step_keeps_what_was_done_and_the_next_run_carries_on(self) -> None:
        with mock.patch.object(bootstrap, "STEPS", self.steps(fail="b")), mock.patch("builtins.print"):
            with self.assertRaises(bootstrap.StepFailed) as failed:
                bootstrap.launch(self.dest)
        self.assertIn("Step b didn't work", str(failed.exception))
        self.assertEqual(bootstrap.progress(self.dest)["done"], ["a"])
        with mock.patch.object(bootstrap, "STEPS", self.steps()), mock.patch("builtins.print"):
            bootstrap.launch(self.dest)
        self.assertEqual(self.ran, ["b", "c"])  # a is not run again
        self.assertEqual(bootstrap.progress(self.dest)["done"], ["a", "b", "c"])

    def test_questions_take_the_default_and_ask_again_until_valid(self) -> None:
        with mock.patch("builtins.input", side_effect=[""]), mock.patch("builtins.print"):
            self.assertEqual(bootstrap.ask("Repo", "me/bees"), "me/bees")
        with mock.patch("builtins.input", side_effect=["a", "ab"]), mock.patch("builtins.print") as out:
            self.assertEqual(bootstrap.ask("Name", check=lambda a: "" if len(a) > 1 else "too short"), "ab")
        self.assertIn("too short", str(out.call_args_list))
        with mock.patch("builtins.input", side_effect=["", "Bees.", "  More.", ""]), mock.patch("builtins.print"):
            self.assertEqual(bootstrap.ask_idea(), "Bees.\n  More.\n")
        self.assertEqual(bootstrap.slugify("Bee Keeper: Hive!"), "bee-keeper-hive")

    def test_missing_tools_are_named_with_how_to_get_them(self) -> None:
        with mock.patch.object(bootstrap.shutil, "which", lambda cmd: None if cmd == "jq" else "/bin/x"):
            with self.assertRaises(bootstrap.StepFailed) as failed:
                bootstrap.preflight()
        self.assertIn("jq: sudo apt install jq", str(failed.exception))
        self.assertFalse(failed.exception.started)


class LaunchPartsTest(unittest.TestCase):
    CFG = config.load()

    def test_the_panel_reads_as_the_defaults(self) -> None:
        settings, fallbacks = panel.settings_from_revisions([bootstrap.panel_body(self.CFG)])
        self.assertEqual(settings, panel.Settings())
        self.assertEqual(fallbacks, [])

    def test_the_manifest_asks_for_three_permissions_and_no_webhook(self) -> None:
        m = bootstrap.manifest(self.CFG, "http://127.0.0.1:1/done")
        self.assertEqual(m["default_permissions"], {"contents": "write", "issues": "write", "pull_requests": "write"})
        self.assertFalse(m["hook_attributes"]["active"])
        self.assertFalse(m["public"])
        self.assertLessEqual(len(m["name"]), 34)
        page = bootstrap.manifest_page(self.CFG, "http://127.0.0.1:1/done", "s1")
        self.assertIn('action="https://github.com/settings/apps/new?state=s1"', page)


if __name__ == "__main__":
    unittest.main()
