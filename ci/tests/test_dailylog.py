from __future__ import annotations

import copy
import datetime as dt
import unittest
from unittest import mock

from smbot import config, dailylog, gh, state

CFG = config.load()


class DailyLogTest(unittest.TestCase):
    def setUp(self) -> None:
        patcher = mock.patch("smbot.labels.ensure")  # labels are covered in test_intake
        patcher.start()
        self.addCleanup(patcher.stop)
        self.state = copy.deepcopy(state.DEFAULT)

        def update(cfg: object, change: object, message: str) -> dict:
            change(self.state)
            return self.state

        for name, fake in (("load", lambda cfg: (self.state, "sha")), ("update", update)):
            patcher = mock.patch.object(dailylog.state_mod, name, fake)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_shorten_cuts_at_a_sentence_or_a_word(self) -> None:
        self.assertEqual(dailylog.shorten("Short.  Fine"), "Short. Fine")
        self.assertEqual(dailylog.shorten("One two three. Four five six seven eight nine.", 30), "One two three.")
        self.assertEqual(dailylog.shorten("alpha beta gamma delta epsilon", 20), "alpha beta gamma…")

    def test_today_is_in_the_owners_time_zone(self) -> None:
        late = dt.datetime(2026, 10, 21, 23, 30, tzinfo=dt.timezone.utc)  # 01:30 in Copenhagen
        self.assertEqual(dailylog.today(CFG, late), "2026-10-22")

    def test_first_post_of_the_day_opens_its_issue_and_closes_older_logs(self) -> None:
        issues = [{"number": 40, "title": "Daily log 2026-10-21"}]
        calls: list = []

        def api(path: str, *args: str, input: object = None, token: object = None) -> object:
            calls.append((path, input))
            if "issues?state=open" in path:
                return list(issues)
            if path.endswith("/issues"):
                issues.append({"number": 41, "title": input["title"]})
                return {"number": 41, "title": input["title"]}
            if path.endswith("/issues/41"):
                return {"number": 41, "title": "Daily log 2026-10-22", "state": "open"}
            return {}

        with mock.patch.object(dailylog.gh, "api", api):
            self.assertEqual(dailylog.issue_for(CFG, "2026-10-22"), 41)
            self.assertEqual(dailylog.issue_for(CFG, "2026-10-22"), 41)
        closed = [(p, i) for p, i in calls if p.endswith("/issues/40")]
        self.assertEqual(closed[0][1]["state"], "closed")
        self.assertEqual(sum(1 for p, i in calls if p.endswith("/issues") and i), 1)

    def test_a_duplicate_log_of_the_same_day_is_closed(self) -> None:
        issues = [{"number": 41, "title": "Daily log 2026-10-22"}, {"number": 42, "title": "Daily log 2026-10-22"}]
        calls: list = []

        def api(path: str, *args: str, input: object = None, token: object = None) -> object:
            calls.append((path, input))
            return list(issues) if "issues?state=open" in path else {}

        with mock.patch.object(dailylog.gh, "api", api):
            self.assertEqual(dailylog.issue_for(CFG, "2026-10-22"), 41)
        self.assertEqual([p for p, i in calls if i], [f"repos/{CFG.repo}/issues/42"])

    def test_a_log_missing_from_the_lagging_list_is_still_found(self) -> None:
        # 2026-10-22: the open-issues list left out the day's log, and each post opened another one.
        listed: list = []
        calls: list = []
        created = iter(range(41, 50))

        def api(path: str, *args: str, input: object = None, token: object = None) -> object:
            calls.append((path, input))
            if "issues?state=open" in path:
                return list(listed)  # never shows the new log
            if path.endswith("/issues"):
                return {"number": next(created), "title": input["title"]}
            if path.endswith("/issues/41"):
                return {"number": 41, "title": "Daily log 2026-10-22", "state": "open"}
            return {}

        with mock.patch.object(dailylog.gh, "api", api):
            self.assertEqual([dailylog.issue_for(CFG, "2026-10-22") for _ in range(3)], [41, 41, 41])
        self.assertEqual(sum(1 for p, i in calls if p.endswith("/issues") and i), 1)

    def test_a_second_run_closes_the_log_it_opened_when_another_was_recorded_first(self) -> None:
        def api(path: str, *args: str, input: object = None, token: object = None) -> object:
            calls.append((path, input))
            if "issues?state=open" in path:
                return []
            if path.endswith("/issues"):
                self.state["daily_log"] = {"date": "2026-10-22", "number": 41}  # the other run got there first
                return {"number": 42, "title": input["title"]}
            return {}

        calls: list = []
        with mock.patch.object(dailylog.gh, "api", api):
            self.assertEqual(dailylog.issue_for(CFG, "2026-10-22"), 41)
        self.assertEqual([(p, i["state_reason"]) for p, i in calls if p.endswith("/issues/42")],
                         [(f"repos/{CFG.repo}/issues/42", "not_planned")])

    def test_a_recorded_log_the_owner_closed_is_replaced(self) -> None:
        self.state["daily_log"] = {"date": "2026-10-22", "number": 41}

        def api(path: str, *args: str, input: object = None, token: object = None) -> object:
            if "issues?state=open" in path:
                return []
            if path.endswith("/issues"):
                return {"number": 43, "title": input["title"]}
            if path.endswith("/issues/41"):
                return {"number": 41, "title": "Daily log 2026-10-22", "state": "closed"}
            return {}

        with mock.patch.object(dailylog.gh, "api", api):
            self.assertEqual(dailylog.issue_for(CFG, "2026-10-22"), 43)
        self.assertEqual(self.state["daily_log"], {"date": "2026-10-22", "number": 43})

    def test_without_state_access_the_log_is_still_opened(self) -> None:
        def denied(*args: object, **kwargs: object) -> None:
            raise gh.GhError("HTTP 403")

        def api(path: str, *args: str, input: object = None, token: object = None) -> object:
            if "issues?state=open" in path:
                return []
            return {"number": 44, "title": input["title"]} if path.endswith("/issues") else {}

        with mock.patch.object(dailylog.state_mod, "load", denied), \
                mock.patch.object(dailylog.state_mod, "update", denied), mock.patch.object(dailylog.gh, "api", api):
            self.assertEqual(dailylog.issue_for(CFG, "2026-10-22"), 44)

    def test_render_mentions_the_owner_only_when_asked(self) -> None:
        now = dt.datetime(2026, 10, 22, 8, 0, tzinfo=dt.timezone.utc)
        self.assertNotIn("@", dailylog.render(CFG, "T", ["a"], False, now))
        self.assertIn(f"@{CFG.owner.login}", dailylog.render(CFG, "T", ["a"], True, now))


if __name__ == "__main__":
    unittest.main()
