from __future__ import annotations

import datetime as dt
import unittest
from unittest import mock

from smbot import release


class ReleaseTest(unittest.TestCase):
    def test_next_tag(self) -> None:
        day = dt.date(2026, 10, 17)
        self.assertEqual(release.next_tag(set(), day), "v0.20261017")
        self.assertEqual(release.next_tag({"v0.20261016"}, day), "v0.20261017")
        self.assertEqual(release.next_tag({"v0.20261017"}, day), "v0.20261017.2")
        self.assertEqual(release.next_tag({"v0.20261017", "v0.20261017.2"}, day), "v0.20261017.3")

    def test_quality_gate(self) -> None:
        self.assertEqual(release.channel_for(0), "stable")
        self.assertEqual(release.channel_for(1), "nightly")

    def test_plan_follows_the_gate_unless_a_channel_is_named(self) -> None:
        day = dt.date(2026, 11, 5)
        with mock.patch.object(release, "remote_tags", return_value={"v0.20261105"}), \
                mock.patch.object(release, "open_gate_issues", return_value=["#1 (crash) boom"]):
            self.assertEqual(release.plan("o/r", day), {"version": "v0.20261105.2", "channel": "nightly"})
            self.assertEqual(release.plan("o/r", day, "stable")["channel"], "stable")
        with mock.patch.object(release, "remote_tags", return_value=set()), \
                mock.patch.object(release, "open_gate_issues", return_value=[]):
            self.assertEqual(release.plan("o/r", day)["channel"], "stable")
            self.assertEqual(release.plan("o/r", day, "nightly")["channel"], "nightly")

    def test_notes_point_to_the_right_build(self) -> None:
        self.assertIn("/play/", release.release_notes("o/r", "v0.1", "stable"))
        self.assertIn("/nightly/", release.release_notes("o/r", "v0.1", "nightly"))


if __name__ == "__main__":
    unittest.main()
