#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
# Runs the unit tests side by side: ci/build/unit_tests.sh <logs dir> <data dir> [path regex]
# (ci/build/build.sh --tests and tools/ptest.sh run it; it needs $GODOT and the XDG_CONFIG_HOME
# and XDG_CACHE_HOME they set, and an imported project).
#
# Every tests/**/test_*.gd and card test (content/**/test_*.gd; none under fixtures/) is a SceneTree
# script that quits with a non-zero code on failure, so each is a Godot process of its own, with a
# data folder of its own (user:// is under $XDG_DATA_HOME), up to TEST_JOBS at once (default: the
# cores). A run fails on a non-zero exit or an ERROR line in its log.
# - Fixed frames (`--fixed-fps 60`): every frame is 1/60 s of game time and none waits for the
#   clock, so a test of 600 physics ticks takes what they cost, not 10 s.
# - Shards: a test file with a line `# unit-test-shards: N` runs as N processes, each with the user
#   argument `--shard=K/N` (tests/support/suite.gd runs every Nth test method from the Kth).
# - Longest first: the runs are started in the order of their times in the last run
#   (build/unit-test-times.txt; a run with no time yet goes first), so a long one does not start last.
# - The tests that time the machine (TIMED_TESTS: budgets in wall time) run with the rest; one that
#   fails is run again alone after, and fails only if it fails alone too.
# Writes one line per run to <logs dir>/unit-results.txt, "PASS|FAIL <seconds> <test> <K/N or -> <log>",
# and one log per run (<logs dir>/unit-<name>[-shard-K].log). Exits 1 on a failure.
set -u
cd "$(dirname "$0")/../.."
LOGS="$1"
DATA="$2"
FILTER="${3:-.}"
: "${GODOT:?set GODOT to the pinned Godot}"
JOBS="${TEST_JOBS:-$(nproc)}"
TIMES=build/unit-test-times.txt
TIMED_TESTS='test_projectiles_kit|test_spell_fuzz'
RESULTS="$LOGS/unit-results.txt"
mkdir -p "$LOGS" "$DATA" build
touch "$TIMES"

# Every run, as "<test> <K/N or ->".
runs() {
  local test shards k
  find tests content -name 'test_*.gd' -not -path '*/fixtures/*' | { grep -E "$FILTER" || true; } | sort \
    | while read -r test; do
      shards=$(grep -m1 -oE '^# unit-test-shards: [0-9]+' "$test" | grep -oE '[0-9]+$' || true)
      if [[ -n "$shards" ]] && ((shards > 1)); then
        for ((k = 0; k < shards; k++)); do echo "$test $k/$shards"; done
      else
        echo "$test -"
      fi
    done
}

# The runs, longest first by the last times.
ordered() {
  runs | awk -v times="$TIMES" 'FILENAME == times { took[$2 " " $3] = $1; next }
    { key = $1 " " $2; print ((key in took) ? took[key] : 1e9), $0 }' "$TIMES" - \
    | sort -s -k1,1gr | cut -d' ' -f2-
}

run_one() { # run_one <test> <K/N or ->: one run into its own log; prints its results line
  local test="$1" shard="$2" name status=PASS args=()
  name="unit-$(basename "$test" .gd)"
  if [[ "$shard" != - ]]; then
    name+="-shard-${shard%/*}"
    args=(-- "--shard=$shard")
  fi
  local log="$LOGS/$name.log" data="$DATA/$name" started="$EPOCHREALTIME"
  rm -rf "$data" && mkdir -p "$data"
  XDG_DATA_HOME="$data" timeout 900 "$GODOT" --headless --fixed-fps 60 --path . --script "res://$test" "${args[@]}" \
    >"$log" 2>&1 || status=FAIL
  grep -qE '^(SCRIPT )?ERROR:' "$log" && status=FAIL
  echo "$status $(awk "BEGIN { printf \"%.1f\", $EPOCHREALTIME - $started }") $test $shard $log"
}

export -f run_one
export GODOT LOGS DATA
ordered | xargs -P "$JOBS" -L1 bash -c 'run_one "$1" "$2"' _ >"$RESULTS"

# A timed test that failed among the others: again, alone.
while read -r _ _ test shard _; do
  echo "$test ($shard) failed with the other tests running: again, alone" >&2
  again=$(run_one "$test" "$shard")
  grep -vF " $test $shard " "$RESULTS" >"$RESULTS.new"
  echo "$again" >>"$RESULTS.new"
  mv "$RESULTS.new" "$RESULTS"
done < <(grep -E "^FAIL [0-9.]+ [^ ]*/($TIMED_TESTS)\.gd " "$RESULTS")

# This run's times, over the last run's (a filtered run keeps the others').
awk -v times="$TIMES" 'FILENAME == times { took[$2 " " $3] = $1; next } { took[$3 " " $4] = $2 }
  END { for (key in took) print took[key], key }' "$TIMES" "$RESULTS" \
  | sort -k1,1gr >"$TIMES.new" && mv "$TIMES.new" "$TIMES"

echo "$(grep -c '^PASS' "$RESULTS") unit test runs passed ($JOBS at once); the longest:"
sort -k2,2gr "$RESULTS" | head -5 | awk '{ printf "  %6.1f s  %s%s\n", $2, $3, ($4 == "-" ? "" : " (shard " $4 ")") }'
! grep -q '^FAIL' "$RESULTS"
