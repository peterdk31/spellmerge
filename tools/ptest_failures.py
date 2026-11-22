#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Why each unit test file failed, from a run's results (tools/ptest.sh prints it at the end).

  tools/ptest_failures.py <logs dir>/unit-results.txt

For every FAIL line of the results (ci/build/unit_tests.sh: "FAIL <seconds> <test> <K/N or -> <log>")
it prints the test and the lines of its log that say why: the runner's notes ("UNIT RUNNER:": a file
that failed only in its batch, with the exit code of a crash or a timeout, or one run alone because
its batch failed), the suite's "TEST FAILED:" lines, the engine's "ERROR:" lines with the "at:" line
that places each and the test of the suite it was logged in ("during:", class Places), and a crash's
signal ("handle_crash:"), whole reasons up to LINES lines, or the log's last lines when none says. The logs are gone with the machine that ran them (a cloud session's
container), so a flaky failure is only explained if this reaches the report. Standard library only.
"""

from __future__ import annotations

import bisect
import re
import sys
from pathlib import Path

# The most reason lines shown for one file, and the last lines shown when none is a reason.
LINES = 12
TAIL = 5
REASON = re.compile(r"^(UNIT RUNNER:|TEST FAILED:|(SCRIPT )?ERROR:|handle_crash:)")
ERROR = re.compile(r"^(SCRIPT )?ERROR:")
# The line after an error that says where it was ("   at: func (res://file.gd:12)").
PLACE = re.compile(r"^\s+at: ")
# The lines a suite's log is cut by: its start, each test's end (after_each included; both
# tests/support/run.gd and tests/support/suite.gd print them) and its end.
SUITE_START = re.compile(r"^SUITE START: ")
TEST_ENDED = re.compile(r"^TEST TIME: (\S+) ")
SUITE_END = re.compile(r"^SUITE END: ")


class Places:
    """Where in a suite's log each line falls: before the suite, in which test, after the suite.

    An error no check caught (one an engine thread logs, as WebRTC's are) names no test, and a
    file's log is its process's output in the order it was written (stdout is flushed on each
    print), so the test it was logged in is the first to end after it. An engine thread may log
    what a test's end began (a peer closed there) after that test's end line: so the test that
    ended before it is named too."""

    def __init__(self, lines: list[str]) -> None:
        self.start = next((at for at, line in enumerate(lines) if SUITE_START.match(line)), None)
        self.end = next((at for at, line in enumerate(lines) if SUITE_END.match(line)), None)
        self.ends: list[int] = []
        self.names: list[str] = []
        for at, line in enumerate(lines):
            found = TEST_ENDED.match(line)
            if found:
                self.ends.append(at)
                self.names.append(found.group(1))

    def of(self, at: int) -> str | None:
        """Where line `at` falls, in words; None when the log is no suite's."""
        if self.start is None:
            return None
        if at < self.start:
            return "before the suite started"
        if self.end is not None and at > self.end:
            return "after the suite ended"
        after = bisect.bisect_right(self.ends, at)
        before = f" (or the end of {self.names[after - 1]})" if after > 0 else ""
        if after < len(self.names):
            return self.names[after] + before
        return f"after its last test ({self.names[-1]}) ended" if self.names else "before its first test ended"


def reasons(log_text: str) -> list[str]:
    """The lines of a test's log that say why it failed (see the module's docs)."""
    lines = log_text.splitlines()
    places = Places(lines)
    # Each reason with the lines that go with it (an error's place and test), never parted.
    found: list[list[str]] = []
    for at, line in enumerate(lines):
        if REASON.match(line):
            group = [line]
            if ERROR.match(line):
                if at + 1 < len(lines) and PLACE.match(lines[at + 1]):
                    group.append(lines[at + 1].rstrip())
                place = places.of(at)
                if place is not None:
                    group.append("      during: " + place)
            found.append(group)
    if not found:
        return [line for line in lines if line.strip()][-TAIL:]
    # The runner's note is last in a log but says the most: show it first.
    notes = [group for group in found if group[0].startswith("UNIT RUNNER:")]
    ordered = notes + [group for group in found if not group[0].startswith("UNIT RUNNER:")]
    shown: list[str] = []
    kept = 0
    for group in ordered:
        if len(shown) + len(group) > LINES and kept > 0:
            break
        shown.extend(group)
        kept += 1
    if kept < len(ordered):
        shown.append(f"... and {len(ordered) - kept} more")
    return shown


def report(results_text: str) -> list[str]:
    """For each FAIL line of the results: the test, then its reasons indented."""
    out: list[str] = []
    for line in results_text.splitlines():
        words = line.split()
        if len(words) < 5 or words[0] != "FAIL":
            continue
        test, shard, log = words[2], words[3], " ".join(words[4:])
        out.append(f"{test}" + ("" if shard == "-" else f" (shard {shard})") + f": {log}")
        path = Path(log)
        if not path.is_file():
            out.append("    (its log is missing)")
            continue
        out.extend("    " + reason for reason in reasons(path.read_text(errors="replace")))
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    results = Path(argv[1])
    if not results.is_file():
        print(f"ptest_failures.py: no results at {results}", file=sys.stderr)
        return 2
    for line in report(results.read_text(errors="replace")):
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
