#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
# Runs the unit tests in parallel: tools/ptest.sh [jobs] [path-regex]
#
# Every tests/**/test_*.gd is its own Godot process (as in ci/build/build.sh --quick --tests),
# so they can run side by side: one import, then up to `jobs` (default 12) tests at once, each
# with its own user:// folder. The whole suite takes about a minute instead of 20-40. Needs the
# pinned Godot in build/godot (run ci/build/build.sh --quick once). Logs: build/logs/ptest/.
# test_projectiles_kit times the projectile manager and can fail under load: run it alone
# (tools/ptest.sh 1 test_projectiles_kit). The daily build still runs them one by one.
set -u
cd "$(dirname "$0")/.."
JOBS="${1:-12}"
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
export GODOT LOG
find tests -name 'test_*.gd' -not -path '*/fixtures/*' | grep -E "$FILTER" | sort \
  | xargs -P "$JOBS" -I{} bash -c 'name=$(echo {} | tr / _); mkdir -p "$LOG/data/$name"
      if XDG_DATA_HOME="$LOG/data/$name" timeout 900 "$GODOT" --headless --path . --script "res://{}" \
        >"$LOG/$name.log" 2>&1; then echo "PASS {}"; else echo "FAIL {}"; fi' \
  | sort >"$LOG/_summary.txt"
echo "passed: $(grep -c PASS "$LOG/_summary.txt")"
if grep FAIL "$LOG/_summary.txt"; then
  exit 1
fi
echo "no failures"
