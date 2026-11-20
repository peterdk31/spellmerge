# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for tools/ptest_failures.py: why each failed unit test file failed, from its log."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import ptest_failures as pf  # noqa: E402


class Reasons(unittest.TestCase):
    def test_a_batch_note_comes_first_then_the_checks_and_errors(self) -> None:
        log = "\n".join([
            "Godot Engine v4.7.2.stable",
            "SUITE START: res://tests/a/test_a.gd",
            "TEST TIME: test_one 10 ms",
            "TEST FAILED: test_one: it stood in range (3 steps, needs 32)",
            "ERROR: a thing went wrong",
            "SUITE END: res://tests/a/test_a.gd FAIL 20 ms",
            "UNIT RUNNER: in its batch the process crashed or timed out in it (exit 137), and it passes alone",
        ])
        self.assertEqual(pf.reasons(log), [
            "UNIT RUNNER: in its batch the process crashed or timed out in it (exit 137), and it passes alone",
            "TEST FAILED: test_one: it stood in range (3 steps, needs 32)",
            "ERROR: a thing went wrong",
        ])

    def test_a_script_error_is_a_reason(self) -> None:
        self.assertEqual(pf.reasons("x\nSCRIPT ERROR: Invalid call\ny"), ["SCRIPT ERROR: Invalid call"])

    def test_an_error_keeps_the_line_that_places_it(self) -> None:
        log = "\n".join([
            "SCRIPT ERROR: Out of bounds get index '0'",
            "          at: _unreachable (res://tests/net/test_net_rtc.gd:407)",
            "          GDScript backtrace (most recent call first):",
            "ERROR: no place",
            "next",
        ])
        self.assertEqual(pf.reasons(log), [
            "SCRIPT ERROR: Out of bounds get index '0'",
            "          at: _unreachable (res://tests/net/test_net_rtc.gd:407)",
            "ERROR: no place",
        ])

    def test_a_crash_signal_is_a_reason(self) -> None:
        log = "SUITE START: x\nhandle_crash: Program crashed with signal 11\n[1] /lib/libc.so.6\n"
        self.assertEqual(pf.reasons(log), ["handle_crash: Program crashed with signal 11"])

    def test_with_no_reason_line_the_last_lines_are_shown(self) -> None:
        log = "\n".join(f"line {n}" for n in range(20)) + "\n\n"
        self.assertEqual(pf.reasons(log), [f"line {n}" for n in range(15, 20)])

    def test_many_reasons_are_cut_and_counted(self) -> None:
        log = "\n".join(f"ERROR: {n}" for n in range(30))
        shown = pf.reasons(log)
        self.assertEqual(len(shown), pf.LINES + 1)
        self.assertEqual(shown[-1], f"... and {30 - pf.LINES} more")


class Report(unittest.TestCase):
    def test_only_failures_are_reported_each_with_its_reasons(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            failed = Path(folder) / "unit-tests-a-test_a.log"
            failed.write_text("SUITE START: x\nTEST FAILED: test_one: wrong\n")
            passed = Path(folder) / "unit-tests-b-test_b.log"
            passed.write_text("TEST OK\n")
            results = "\n".join([
                f"PASS 0.5 tests/b/test_b.gd - {passed}",
                f"FAIL 0.6 tests/a/test_a.gd - {failed}",
                f"FAIL 3.0 tests/c/test_c.gd 1/3 {Path(folder) / 'gone.log'}",
            ])
            self.assertEqual(pf.report(results), [
                f"tests/a/test_a.gd: {failed}",
                "    TEST FAILED: test_one: wrong",
                f"tests/c/test_c.gd (shard 1/3): {Path(folder) / 'gone.log'}",
                "    (its log is missing)",
            ])

    def test_no_failure_reports_nothing(self) -> None:
        self.assertEqual(pf.report("PASS 0.5 tests/b/test_b.gd - /x.log\n"), [])


if __name__ == "__main__":
    unittest.main()
