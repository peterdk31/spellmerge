from __future__ import annotations

import copy
import datetime as dt
import tempfile
import unittest
from pathlib import Path

from smbot import commands, control, nexttask, pacing, panel, state

OWNER = 13425287
PANEL = """**SPELLMERGE CONTROL PANEL**

- [x] Automation enabled (untick = full stop, the kill switch)
- [ ] Pause development (still review PRs and release, build nothing new)
- [ ] Pause PR merging

QUIET_HOURS:
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
                .replace("QUIET_HOURS:", "QUIET_HOURS: 07-17").replace("FOCUS:", "FOCUS: fix bugs first"))
        s, _ = panel.settings_from_revisions([text])
        self.assertTrue(s.pause_development)
        self.assertEqual((s.quiet_hours, s.focus), ((7, 17), "fix bugs first"))

    def test_an_old_panel_with_vote_lines_still_reads(self) -> None:
        old = PANEL.replace("QUIET_HOURS:\n", "QUIET_HOURS:\nVOTE_SHARE: 15%   VOTE_MIN: 2\n")
        s, fallbacks = panel.settings_from_revisions([old])
        self.assertEqual((s.quiet_hours, fallbacks), (None, []))

    def test_unreadable_value_falls_back_to_older_owner_revision(self) -> None:
        older = PANEL.replace("QUIET_HOURS:", "QUIET_HOURS: 22-07")
        newer = PANEL.replace("QUIET_HOURS:", "QUIET_HOURS: lots")
        s, fallbacks = panel.settings_from_revisions([newer, older])
        self.assertEqual(s.quiet_hours, (22, 7))
        self.assertEqual(fallbacks, ["quiet_hours"])

    def test_missing_kill_switch_means_off(self) -> None:
        s, _ = panel.settings_from_revisions(["QUIET_HOURS:"])
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
        new = panel.Settings(pause_merging=True, quiet_hours=(7, 17))
        self.assertEqual(panel.changes(old, new, "peterdk31"),
                         ["Pause PR merging off → on (by peterdk31)", "QUIET_HOURS none → 07-17 (by peterdk31)"])


class PacingTest(unittest.TestCase):
    def fresh(self) -> dict:
        return copy.deepcopy(state.DEFAULT)

    def test_heavy_usage_does_not_stop_development(self) -> None:
        st = self.fresh()
        pacing.record(st, NOW - dt.timedelta(hours=1), 50_000_000, "dev")
        d = control.decide(True, panel.PanelResult(panel.Settings(), True), st, NOW, "Europe/Copenhagen", True)
        self.assertTrue(d.develop)

    def test_limit_backs_off_until_the_reset(self) -> None:
        st = self.fresh()
        reset = NOW + dt.timedelta(hours=2)
        pacing.limit_hit(st, NOW, weekly=False, resets_at=reset)
        self.assertEqual(pacing.backing_off_until(st, reset - dt.timedelta(minutes=1)), pacing.iso(reset))
        self.assertEqual(pacing.backing_off_until(st, reset + dt.timedelta(minutes=1)), "")
        d = control.decide(True, panel.PanelResult(panel.Settings(), True), st, NOW, "Europe/Copenhagen", True)
        self.assertFalse(d.develop)
        self.assertIn("backing off", d.reasons[-1])

    def test_limit_without_reset_time_backs_off_a_window(self) -> None:
        st = self.fresh()
        pacing.limit_hit(st, NOW, weekly=False)
        self.assertEqual(st["backoff_until"], pacing.iso(NOW + dt.timedelta(hours=5)))

    def test_usage_line(self) -> None:
        st = self.fresh()
        pacing.record(st, NOW - dt.timedelta(hours=6), 1_000_000, "dev")
        pacing.record(st, NOW, 450_000, "dev")
        self.assertEqual(pacing.usage_line(st, NOW),
                         "Claude usage: 450,000 tokens in the last 5 h, 1,450,000 tokens this week")


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

    def test_parked_tasks_are_skipped_until_their_time(self) -> None:
        now = dt.datetime(2026, 10, 17, 12, tzinfo=dt.timezone.utc)
        st = {"task_failures": {"First": {"count": 2, "parked_until": "2026-10-18T00:00:00Z"},
                                "Old": {"count": 2, "parked_until": "2026-10-17T00:00:00Z"},
                                "Once": {"count": 1}}}
        self.assertEqual(nexttask.parked(st, now), {"First"})
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp, "NEXT.md")
            path.write_text("## Queue\n\n- [ ] First\n- [ ] Second\n")
            self.assertEqual(nexttask.next_task(path, skip={"First"}), "Second")
            self.assertIsNone(nexttask.next_task(path, skip={"First", "Second"}))


if __name__ == "__main__":
    unittest.main()
