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


if __name__ == "__main__":
    unittest.main()
