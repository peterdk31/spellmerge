from __future__ import annotations

import datetime as dt
import unittest

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

    def test_notes_point_to_the_right_build(self) -> None:
        self.assertIn("/play/", release.release_notes("o/r", "v0.1", "stable"))
        self.assertIn("/nightly/", release.release_notes("o/r", "v0.1", "nightly"))


if __name__ == "__main__":
    unittest.main()
