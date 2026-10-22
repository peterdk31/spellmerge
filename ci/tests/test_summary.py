from __future__ import annotations

import datetime as dt
import tempfile
import unittest
from pathlib import Path

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

    def test_the_stress_and_timing_results_are_quoted_from_the_build_logs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            logs = Path(tmp)
            self.assertEqual(summary.bench_line(logs), "")
            (logs / "stress-web.log").write_text(
                "==> Stress run\nconsole.log: BENCH: frames 128, p95 108.60 ms <script>\nconsole.log: noise\n"
                "console.log: STRESS OK: 2 scenarios\nWEB SMOKE OK\n")
            (logs / "timing-web.log").write_text("::error::web smoke test: no console line containing 'TIMING OK'\n"
                                                 + "console.log: BENCH: x\n" * 100)
            line = summary.bench_line(logs)
        self.assertTrue(line.startswith("<details><summary>"))
        self.assertIn("<b>Web Test (WASM), stress</b><br>BENCH: frames 128, p95 108.60 ms &lt;script&gt;<br>"
                      "STRESS OK: 2 scenarios<br>WEB SMOKE OK", line)
        self.assertNotIn("noise", line)
        self.assertNotIn("Linux", line)  # only the logs the build wrote
        self.assertEqual(line.count("BENCH: x"), summary.MAX_BENCH_LINES)  # the last ones, the error line dropped
        self.assertLess(len(line), 65536)


if __name__ == "__main__":
    unittest.main()
