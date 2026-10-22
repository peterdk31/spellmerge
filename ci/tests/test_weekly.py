from __future__ import annotations

import unittest
from unittest import mock

from smbot import config, weekly

CFG = config.load()


class WeeklyTest(unittest.TestCase):
    def test_moves_only_issues_on_the_queue_or_backlog(self) -> None:
        calls: list = []

        def paginated(path: str, *args: str, token: object = None) -> list:
            if "labels=scheduled" in path:
                return [{"number": 5, "labels": [{"name": "scheduled"}]}]
            return [{"number": 6, "labels": [{"name": "backlog"}]}]

        def api(path: str, *args: str, input: object = None, token: object = None) -> object:
            calls.append((path, args, input))
            return {}

        with mock.patch.object(weekly.gh, "api_paginated", paginated), mock.patch.object(weekly.gh, "api", api):
            log = weekly.move_issues(CFG, schedule=[6, 99], unschedule=[5])
        self.assertEqual(log, ["#6 scheduled", "#5 moved to the backlog"])
        self.assertIn((f"repos/{CFG.repo}/issues/6/labels/backlog", ("-X", "DELETE"), None), calls)
        self.assertIn((f"repos/{CFG.repo}/issues/5/labels", ("-X", "POST"), {"labels": ["backlog"]}), calls)
        self.assertFalse(any("/99/" in c[0] for c in calls))

    def test_only_the_weekly_run_posts_and_only_a_merged_plan_announces(self) -> None:
        plan = {"progress_post": "news", "playtest": {"changes": "c", "questions": ["q"]},
                "owner_issues": [{"title": "M2 done, M3 started", "body": "b"}]}
        created: list = []

        def api(path: str, *args: str, input: object = None, token: object = None) -> object:
            created.append(input["title"])
            return {"number": 1}

        with mock.patch.object(weekly.gh, "api", api), mock.patch.object(weekly.gh, "api_paginated", lambda *a, **k: []), \
                mock.patch.object(weekly, "post_devlog", lambda *a: "Devlog posted"):
            self.assertEqual(weekly.publish_plan(CFG, plan, "t", weekly=False, merged=True),
                             ["Owner issue #1: M2 done, M3 started"])
            self.assertEqual(weekly.publish_plan(CFG, plan, "t", weekly=False, merged=False), [])
            log = weekly.publish_plan(CFG, plan, "t", weekly=True, merged=True)
        self.assertEqual(log[0], "Devlog posted")
        self.assertTrue(log[-1].startswith("Playtest of the week"))

    def test_a_merged_plan_opens_the_checkpoint(self) -> None:
        cp = {"milestone": "M2", "built": "b", "assessment": "a", "recommendation": "go"}
        with mock.patch.object(weekly.gh, "api_paginated", lambda *a, **k: []), \
                mock.patch.object(weekly.checkpoint, "open_checkpoint", lambda cfg, c: f"Checkpoint for {c['milestone']}"):
            self.assertEqual(weekly.publish_plan(CFG, {"checkpoint": cp}, None, merged=False), [])
            self.assertEqual(weekly.publish_plan(CFG, {"checkpoint": cp}, None, merged=True), ["Checkpoint for M2"])

    def test_checkpoint_issue_and_prompt(self) -> None:
        body = weekly.checkpoint.body(CFG, {"milestone": "M2", "built": "b", "assessment": "a",
                                            "recommendation": "go"})
        for part in (f"@{CFG.owner.login}", "`/go`", "`/iterate <what to rework>`", "`/pivot <the new direction>`"):
            self.assertIn(part, body)
        st: dict = {}
        self.assertIn("Don't start the next milestone", weekly.checkpoint.prompt_text(st, 50))
        weekly.checkpoint.record(st, 50, "iterate", "snappier dodge", "u", "t")
        text = weekly.checkpoint.prompt_text(st, 50)
        self.assertIn("snappier dodge", text)
        self.assertIn("Closes #50", text)


if __name__ == "__main__":
    unittest.main()
