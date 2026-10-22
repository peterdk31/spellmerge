from __future__ import annotations

import datetime as dt
import unittest
from unittest import mock

from smbot import config, dailylog

CFG = config.load()


class DailyLogTest(unittest.TestCase):
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
                return {"number": 41}
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

    def test_render_mentions_the_owner_only_when_asked(self) -> None:
        now = dt.datetime(2026, 10, 22, 8, 0, tzinfo=dt.timezone.utc)
        self.assertNotIn("@", dailylog.render(CFG, "T", ["a"], False, now))
        self.assertIn(f"@{CFG.owner.login}", dailylog.render(CFG, "T", ["a"], True, now))


if __name__ == "__main__":
    unittest.main()
