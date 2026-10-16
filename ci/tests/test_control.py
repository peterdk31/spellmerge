from __future__ import annotations

import copy
import datetime as dt
import unittest

from smbot import commands, control, nexttask, pacing, panel, state

OWNER = 13425287
PANEL = """**SPELLMERGE CONTROL PANEL**

- [x] Automation enabled (untick = full stop, the kill switch)
- [ ] Pause development (still review PRs and release, build nothing new)
- [ ] Pause PR merging

DEV_INTENSITY: 90%
WEEKLY_SHARE: 90%
QUIET_HOURS:
VOTE_SHARE: 15%   VOTE_MIN: 2   VOTE_MAX: 25   VOTE_APPROVAL: 60%
FOCUS:
"""
NOW = dt.datetime(2026, 10, 17, 12, 0, tzinfo=dt.timezone.utc)


def issue(*revs: tuple[int | None, str]) -> dict:
    """An issue as GraphQL returns it; revisions newest first."""
    return {
        "body": revs[0][1],
        "author": {"databaseId": revs[-1][0]},
        "userContentEdits": {"nodes": [
            {"editedAt": "x", "deletedAt": None, "diff": text, "editor": {"databaseId": who, "login": f"u{who}"}}
            for who, text in revs
        ]},
    }


class PanelTest(unittest.TestCase):
    def test_defaults_parse(self) -> None:
        settings, fallbacks = panel.settings_from_revisions([PANEL])
        self.assertEqual(settings, panel.Settings())
        self.assertEqual(fallbacks, [])

    def test_values(self) -> None:
        text = (PANEL.replace("- [ ] Pause development", "- [x] Pause development")
                .replace("DEV_INTENSITY: 90%", "DEV_INTENSITY: 50%").replace("QUIET_HOURS:", "QUIET_HOURS: 07-17")
                .replace("VOTE_MAX: 25", "VOTE_MAX: 30").replace("FOCUS:", "FOCUS: fix bugs first"))
        s, _ = panel.settings_from_revisions([text])
        self.assertTrue(s.pause_development)
        self.assertEqual((s.dev_intensity, s.quiet_hours, s.vote_max, s.focus), (50, (7, 17), 30, "fix bugs first"))

    def test_values_are_clamped(self) -> None:
        s, _ = panel.settings_from_revisions([PANEL.replace("DEV_INTENSITY: 90%", "DEV_INTENSITY: 400%")
                                              .replace("VOTE_APPROVAL: 60%", "VOTE_APPROVAL: 10%")])
        self.assertEqual((s.dev_intensity, s.vote_approval), (100, 50))

    def test_unreadable_value_falls_back_to_older_owner_revision(self) -> None:
        older = PANEL.replace("DEV_INTENSITY: 90%", "DEV_INTENSITY: 40%")
        newer = PANEL.replace("DEV_INTENSITY: 90%", "DEV_INTENSITY: lots")
        s, fallbacks = panel.settings_from_revisions([newer, older])
        self.assertEqual(s.dev_intensity, 40)
        self.assertEqual(fallbacks, ["dev_intensity"])

    def test_missing_kill_switch_means_off(self) -> None:
        s, _ = panel.settings_from_revisions(["DEV_INTENSITY: 90%"])
        self.assertFalse(s.automation_enabled)

    def test_edit_by_someone_else_is_ignored_and_reported(self) -> None:
        tampered = PANEL.replace("- [x] Automation enabled", "- [ ] Automation enabled")
        result = panel.evaluate(issue((999, tampered), (OWNER, PANEL)), OWNER)
        self.assertTrue(result.verified)
        self.assertTrue(result.settings.automation_enabled)
        self.assertIn("not the owner", result.problems[0])

    def test_no_owner_revision_fails_closed(self) -> None:
        result = panel.evaluate(issue((999, PANEL)), OWNER)
        self.assertFalse(result.verified)
        self.assertFalse(result.settings.automation_enabled)

    def test_never_edited_issue_uses_body(self) -> None:
        unedited = {"body": PANEL, "author": {"databaseId": OWNER}, "userContentEdits": {"nodes": []}}
        self.assertTrue(panel.evaluate(unedited, OWNER).verified)

    def test_audit_lines(self) -> None:
        old = panel.to_json(panel.Settings())
        new = panel.Settings(dev_intensity=50, quiet_hours=(7, 17))
        self.assertEqual(panel.changes(old, new, "peterdk31"),
                         ["DEV_INTENSITY 90% → 50% (by peterdk31)", "QUIET_HOURS none → 07-17 (by peterdk31)"])


class PacingTest(unittest.TestCase):
    def fresh(self) -> dict:
        return copy.deepcopy(state.DEFAULT)

    def test_unknown_limits_allow_runs(self) -> None:
        st = self.fresh()
        pacing.record(st, NOW, 5_000_000, "dev")
        self.assertTrue(pacing.budget(st, NOW, 90, 90).allowed)

    def test_limit_hit_learns_window_and_backs_off(self) -> None:
        st = self.fresh()
        pacing.record(st, NOW - dt.timedelta(hours=1), 1_000_000, "dev")
        pacing.limit_hit(st, NOW, weekly=False)
        self.assertEqual(st["limits"]["window_tokens"], 1_000_000)
        self.assertFalse(pacing.budget(st, NOW + dt.timedelta(hours=1), 90, 90).allowed)
        later = NOW + dt.timedelta(hours=6)  # window reset, earlier usage aged out
        self.assertTrue(pacing.budget(st, later, 90, 90).allowed)

    def test_dev_intensity_caps_the_window(self) -> None:
        st = self.fresh()
        st["limits"]["window_tokens"] = 1_000_000
        pacing.record(st, NOW - dt.timedelta(hours=1), 850_000, "dev")
        self.assertTrue(pacing.budget(st, NOW, 90, 90).allowed)
        self.assertFalse(pacing.budget(st, NOW, 80, 90).allowed)

    def test_weekly_share_is_spread_over_days(self) -> None:
        st = self.fresh()
        st["limits"]["week_tokens"] = 7_000_000
        pacing.record(st, NOW - dt.timedelta(hours=2), 950_000, "dev")
        self.assertFalse(pacing.budget(st, NOW, 100, 90).allowed)  # day allowance 900k
        self.assertTrue(pacing.budget(st, NOW, 100, 100).allowed)  # day allowance 1M

    def test_usage_line(self) -> None:
        st = self.fresh()
        st["limits"]["window_tokens"] = 1_000_000
        pacing.record(st, NOW, 450_000, "dev")
        self.assertIn("~50% of window budget", pacing.usage_line(st, NOW, 90, 90))


class DecideTest(unittest.TestCase):
    def ok_panel(self, **kw: object) -> panel.PanelResult:
        return panel.PanelResult(panel.Settings(**kw), True)

    def test_everything_on(self) -> None:
        d = control.decide(True, self.ok_panel(), copy.deepcopy(state.DEFAULT), NOW, "Europe/Copenhagen", True)
        self.assertEqual((d.automation, d.develop, d.merge), (True, True, True))

    def test_kill_switch_and_panel(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        self.assertFalse(control.decide(False, self.ok_panel(), st, NOW, "UTC", True).automation)
        self.assertFalse(control.decide(True, self.ok_panel(automation_enabled=False), st, NOW, "UTC", True).automation)
        unverified = panel.PanelResult(panel.FAIL_CLOSED, False)
        self.assertFalse(control.decide(True, unverified, st, NOW, "UTC", True).automation)

    def test_pauses(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        d = control.decide(True, self.ok_panel(pause_development=True), st, NOW, "UTC", True)
        self.assertEqual((d.develop, d.merge), (False, True))
        st["paused_by_command"] = True
        d = control.decide(True, self.ok_panel(), st, NOW, "UTC", True)
        self.assertEqual((d.automation, d.develop, d.merge), (True, False, False))

    def test_quiet_hours_in_danish_time(self) -> None:
        # 12:00 UTC is 14:00 in Copenhagen (summer time until late October).
        self.assertTrue(control.in_quiet_hours((7, 17), NOW, "Europe/Copenhagen"))
        self.assertFalse(control.in_quiet_hours((15, 17), NOW, "Europe/Copenhagen"))
        self.assertTrue(control.in_quiet_hours((22, 15), NOW, "Europe/Copenhagen"))  # wraps midnight

    def test_no_task(self) -> None:
        d = control.decide(True, self.ok_panel(), copy.deepcopy(state.DEFAULT), NOW, "UTC", False)
        self.assertFalse(d.develop)


class CommandsTest(unittest.TestCase):
    def test_parse(self) -> None:
        self.assertEqual(commands.parse("/merge"), ("merge", ""))
        self.assertEqual(commands.parse("  /claude make frost slower\nand weaker"), ("claude", "make frost slower\nand weaker"))
        self.assertIsNone(commands.parse("please /merge this"))
        self.assertIsNone(commands.parse("/mergeall"))
        self.assertIsNone(commands.parse("/deploy"))

    def test_only_owner_edited(self) -> None:
        node = {"author": {"databaseId": OWNER}, "userContentEdits": {"nodes": [{"editor": {"databaseId": OWNER}}]}}
        self.assertTrue(commands.only_owner_edited(node, OWNER))
        node["userContentEdits"]["nodes"].append({"editor": {"databaseId": 5}})
        self.assertFalse(commands.only_owner_edited(node, OWNER))
        self.assertFalse(commands.only_owner_edited({"author": {"databaseId": 5}, "userContentEdits": {"nodes": []}}, OWNER))

    def test_effects_are_idempotent(self) -> None:
        st = copy.deepcopy(state.DEFAULT)
        eff = commands.Effects([1, 2], True, [{"url": "u1", "kind": "ask"}])
        eff.apply(st)
        eff.apply(st)
        self.assertEqual((st["processed_comments"], st["paused_by_command"], len(st["pending_instructions"])),
                         ([1, 2], True, 1))


class NextTaskTest(unittest.TestCase):
    def test_queue(self) -> None:
        text = "# Next\n\n## Queue\n\n- [x] done\n- [ ] **First** thing\n- [ ] Second\n\n## Blocked\n\n- [ ] not this\n"
        self.assertEqual(nexttask.queue(text), ["**First** thing", "Second"])


if __name__ == "__main__":
    unittest.main()
