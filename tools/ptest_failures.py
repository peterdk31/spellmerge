#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Why each unit test file failed, from a run's results (tools/ptest.sh prints it at the end).

  tools/ptest_failures.py <logs dir>/unit-results.txt

For every FAIL line of the results (ci/build/unit_tests.sh: "FAIL <seconds> <test> <K/N or -> <log>")
it prints the test and the lines of its log that say why: the runner's note on a file that failed
in its batch and passed alone ("UNIT RUNNER:", with the exit code of a crash or a timeout), the
suite's "TEST FAILED:" lines and the engine's "ERROR:" lines, at most LINES of them, or the log's
last lines when none says. The logs are gone with the machine that ran them (a cloud session's
container), so a flaky failure is only explained if this reaches the report. Standard library only.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

## The most reason lines shown for one file, and the last lines shown when none is a reason.
LINES = 12
TAIL = 5
REASON = re.compile(r"^(UNIT RUNNER:|TEST FAILED:|(SCRIPT )?ERROR:)")


def reasons(log_text: str) -> list[str]:
    """The lines of a test's log that say why it failed (see the module's docs)."""
    lines = log_text.splitlines()
    found = [line for line in lines if REASON.match(line)]
    if not found:
        return [line for line in lines if line.strip()][-TAIL:]
    # The runner's note is last in a log but says the most: show it first.
    notes = [line for line in found if line.startswith("UNIT RUNNER:")]
    rest = [line for line in found if not line.startswith("UNIT RUNNER:")]
    shown = notes + rest[: max(LINES - len(notes), 0)]
    if len(found) > len(shown):
        shown.append(f"... and {len(found) - len(shown)} more")
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
