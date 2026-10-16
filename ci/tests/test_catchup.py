from __future__ import annotations

import datetime as dt
import unittest

from smbot import catchup

UTC = dt.timezone.utc


def t(day: int, hour: int, minute: int = 0) -> dt.datetime:
    return dt.datetime(2026, 10, day, hour, minute, tzinfo=UTC)  # 2026-10-18 is a Sunday


class CatchupTest(unittest.TestCase):
    def test_last_due(self) -> None:
        self.assertEqual(catchup.last_due(t(17, 2), "daily.yml"), t(16, 3))
        self.assertEqual(catchup.last_due(t(17, 3), "daily.yml"), t(17, 3))
        self.assertEqual(catchup.last_due(t(18, 5), "weekly.yml"), t(11, 6))
        self.assertEqual(catchup.last_due(t(18, 7), "weekly.yml"), t(18, 6))
        self.assertEqual(catchup.last_due(t(21, 12), "weekly.yml"), t(18, 6))

    def test_missed(self) -> None:
        added = t(16, 16)
        self.assertFalse(catchup.missed(t(16, 23), t(16, 3), added, []))  # due before the workflow existed
        self.assertTrue(catchup.missed(t(17, 4), t(17, 3), added, [t(16, 23)]))
        self.assertFalse(catchup.missed(t(17, 3, 10), t(17, 3), added, []))  # within the grace period
        self.assertFalse(catchup.missed(t(17, 4), t(17, 3), added, [t(17, 3, 5)]))  # ran, late is fine


if __name__ == "__main__":
    unittest.main()
