#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
# Runs the unit tests in parallel, as ci/build/build.sh --quick --tests does: tools/ptest.sh [jobs] [path-regex]
#
# Every tests/**/test_*.gd and card test (content/**/test_*.gd) is its own Godot process, side by
# side, the longest first; one import first. The runner is ci/build/unit_tests.sh (fixed frames,
# shards, the timed tests run again alone if they fail among the others). Needs the pinned Godot
# in build/godot (run ci/build/build.sh --quick once). `jobs` defaults to the cores. Logs and
# each run's time: build/logs/ptest/ (unit-results.txt has one line per run).
set -u
cd "$(dirname "$0")/.."
JOBS="${1:-$(nproc)}"
FILTER="${2:-.}"
TOOLS="$(readlink -f build/godot)"
GODOT="$(find "$TOOLS" -maxdepth 1 -name 'Godot_v*_linux.x86_64' -type f | head -1)"
if [[ ! -x "$GODOT" ]]; then
  echo "No pinned Godot in build/godot: run ci/build/build.sh --quick first." >&2
  exit 2
fi
export XDG_CONFIG_HOME="$TOOLS/xdg/config" XDG_CACHE_HOME="$TOOLS/xdg/cache"
LOG="$PWD/build/logs/ptest"
rm -rf "$LOG"
mkdir -p "$LOG/data/_import"
XDG_DATA_HOME="$LOG/data/_import" "$GODOT" --headless --path . --import >"$LOG/_import.txt" 2>&1
status=0
GODOT="$GODOT" TEST_JOBS="$JOBS" ci/build/unit_tests.sh "$LOG" "$LOG/data" "$FILTER" || status=1
if grep '^FAIL' "$LOG/unit-results.txt"; then
  exit 1
fi
((status == 0)) && echo "no failures"
exit "$status"
