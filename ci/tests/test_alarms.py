from __future__ import annotations

import datetime as dt
import unittest
from unittest import mock

from smbot import alarms

NOW = dt.datetime(2026, 10, 22, 3, 38, tzinfo=dt.timezone.utc)
STARTED = NOW - dt.timedelta(days=5)


class StallAlarmTest(unittest.TestCase):
    def run_check(self, st: dict, own_merge: dt.datetime | None) -> mock.MagicMock:
        with mock.patch.object(alarms, "raise_alarm", return_value="raised") as raise_alarm, \
                mock.patch.object(alarms, "clear_alarm", return_value=None):
            alarms.check(mock.Mock(), st, NOW, True, NOW, own_merge, STARTED)
        return raise_alarm

    def test_saved_merge_counts_when_the_search_is_empty(self) -> None:
        st = {"alarms": {}, "last_own_merge": alarms.iso(NOW - dt.timedelta(hours=1))}
        self.run_check(st, None).assert_not_called()

    def test_no_merge_anywhere_raises(self) -> None:
        self.run_check({"alarms": {}, "last_own_merge": None}, None).assert_called_once()

    def test_newest_merge_is_kept(self) -> None:
        newer = NOW - dt.timedelta(hours=1)
        st = {"alarms": {}, "last_own_merge": alarms.iso(newer)}
        self.run_check(st, NOW - dt.timedelta(days=4)).assert_not_called()
        self.assertEqual(st["last_own_merge"], alarms.iso(newer))


if __name__ == "__main__":
    unittest.main()
