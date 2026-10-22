from __future__ import annotations

import datetime as dt
import unittest

from smbot import summary

NOW = dt.datetime(2026, 10, 22, 14, 0, tzinfo=dt.timezone.utc)


class SummaryTest(unittest.TestCase):
    def test_the_daily_summary_lists_what_is_parked_and_why(self) -> None:
        st = {"task_failures": {
            "**Bots build spells (M2 part 20).** (`tests/bots`) more": {
                "pr": "156", "parked_until": "2026-10-23T11:08:02Z",
                "parked_reason": "the final review didn't approve it 2 times in a row"},
            "**Done long ago.**": {"parked_until": "2026-10-20T00:00:00Z", "parked_reason": "x"},
            "**Never parked.**": {"count": 1}}}
        self.assertEqual(summary.parked_lines(st, NOW), [
            "Parked until 2026-10-23 11:08 UTC: Bots build spells (M2 part 20) (#156: `/retry` there brings it back). "
            "Why: the final review didn't approve it 2 times in a row"])


if __name__ == "__main__":
    unittest.main()
