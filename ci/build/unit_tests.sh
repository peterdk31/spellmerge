#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
# Runs the unit tests side by side: ci/build/unit_tests.sh <logs dir> <data dir> [path regex]
# (ci/build/build.sh --tests and tools/ptest.sh run it; it needs $GODOT and the XDG_CONFIG_HOME
# and XDG_CACHE_HOME they set, and an imported project).
#
# Every tests/**/test_*.gd and card test (content/**/test_*.gd; none under fixtures/) is a test file.
# A suite (a script extending tests/support/suite.gd) is run by the host tests/support/run.gd; any
# other test file is a SceneTree script of its own. Each Godot process has a data folder of its own
# (user:// is under $XDG_DATA_HOME), up to TEST_JOBS at once (default: the cores). A file fails on a
# non-zero exit or an ERROR line in its log.
# - Batches: a Godot start compiles the whole game (seconds), so the suites are run TEST_BATCH
#   (default 8) to a process, in batches by path (the same batches on every run of the same tree);
#   the host starts each file on a fresh game. A file that needs a process of its own says
#   `# unit-test-alone`. A batch whose start or end logged an error (not inside one file), or that
#   stopped before its end, has its files run again alone, and their results are those. A file that
#   fails in its batch is run again alone too, to say whether it fails only after the files before
#   it (state they left behind: still a failure).
# - Fixed frames (`--fixed-fps 60`): every frame is 1/60 s of game time and none waits for the
#   clock, so a test of 600 physics ticks takes what they cost, not 10 s.
# - Shards: a test file with a line `# unit-test-shards: N` runs alone as N processes, each with the
#   user argument `--shard=K/N` (tests/support/suite.gd runs every Nth test method from the Kth).
# - Longest first: the runs are started in the order of their times in the last run
#   (build/unit-test-times.txt, per file; a batch weighs its files' sum; a file with no time yet goes
#   first), so a long one does not start last.
# - The tests that time the machine (TIMED_TESTS: budgets in wall time) run alone, with the rest;
#   one that fails is run again alone after, and fails only if it fails alone too.
# Writes one line per file (per shard) to <logs dir>/unit-results.txt, "PASS|FAIL <seconds> <test>
# <K/N or -> <log>" (a batched file's seconds are its own, without the start), and one log per file
# (<logs dir>/unit-<path>[-shard-K].log, the test's path with "-" for "/":
# unit-tests-core-test_loading.log; a batched file's is the batch's start and its own part). Exits 1
# on a failure.
set -u
cd "$(dirname "$0")/../.."
LOGS="$1"
DATA="$2"
FILTER="${3:-.}"
: "${GODOT:?set GODOT to the pinned Godot}"
JOBS="${TEST_JOBS:-$(nproc)}"
BATCH="${TEST_BATCH:-8}"
TIMES=build/unit-test-times.txt
TIMED_TESTS='test_projectiles_kit|test_spell_fuzz'
HOST=tests/support/run.gd
RESULTS="$LOGS/unit-results.txt"
mkdir -p "$LOGS" "$DATA" build
touch "$TIMES"

# Whether the test file $1 is a suite: its `extends` reaches tests/support/suite.gd.
is_suite() {
  local file="$1" depth
  for ((depth = 0; depth < 8; depth++)); do
    [[ "$file" == tests/support/suite.gd ]] && return 0
    file=$(grep -m1 -oE '^extends "res://[^"]+"' "$file" 2>/dev/null | sed -E 's|^extends "res://||; s|"$||')
    [[ -n "$file" && -f "$file" ]] || return 1
  done
  return 1
}

# Every run, as "alone <test> <K/N or ->" or "batch - <test> <test> ...".
runs() {
  local test shards k batched=()
  while read -r test; do
    shards=$(grep -m1 -oE '^# unit-test-shards: [0-9]+' "$test" | grep -oE '[0-9]+$' || true)
    if [[ -n "$shards" ]] && ((shards > 1)); then
      for ((k = 0; k < shards; k++)); do echo "alone $test $k/$shards"; done
    elif ((BATCH > 1)) && is_suite "$test" && ! grep -qE '^# unit-test-alone' "$test" \
      && ! [[ "$(basename "$test" .gd)" =~ ^($TIMED_TESTS)$ ]]; then
      batched+=("$test")
    else
      echo "alone $test -"
    fi
  done < <(find tests content -name 'test_*.gd' -not -path '*/fixtures/*' | { grep -E "$FILTER" || true; } | sort)
  for ((k = 0; k < ${#batched[@]}; k += BATCH)); do
    echo "batch - ${batched[*]:k:BATCH}"
  done
}

# The runs, longest first by the last times (a batch: its files' sum).
ordered() {
  runs | awk -v times="$TIMES" 'FILENAME == times { took[$2 " " $3] = $1; next }
    { weight = 0
      for (i = 2; i <= NF; i++) {
        if ($1 == "batch" && i == 2) continue
        key = ($1 == "batch") ? $i " -" : $2 " " $3
        weight += (key in took) ? took[key] : 1e9
        if ($1 != "batch") break
      }
      print weight, $0 }' "$TIMES" - \
    | sort -s -k1,1gr | cut -d' ' -f2-
}

log_of() { # log_of <test> <K/N or ->: the file's log
  local name="unit-${1%.gd}"
  name="${name//\//-}"
  [[ "$2" == - ]] || name+="-shard-${2%/*}"
  echo "$LOGS/$name.log"
}

run_one() { # run_one <test> <K/N or ->: one file alone, into its own log; prints its results line
  local test="$1" shard="$2" status=PASS args=() log data started="$EPOCHREALTIME"
  log=$(log_of "$test" "$shard")
  data="$DATA/$(basename "$log" .log)"
  if is_suite "$test"; then
    args=(--script "res://$HOST" -- "res://$test")
    [[ "$shard" == - ]] || args+=("--shard=$shard")
  else
    args=(--script "res://$test")
    [[ "$shard" == - ]] || args+=(-- "--shard=$shard")
  fi
  rm -rf "$data" && mkdir -p "$data"
  XDG_DATA_HOME="$data" timeout 900 "$GODOT" --headless --fixed-fps 60 --path . "${args[@]}" \
    >"$log" 2>&1 || status=FAIL
  grep -qE '^(SCRIPT )?ERROR:' "$log" && status=FAIL
  echo "$status $(awk "BEGIN { printf \"%.1f\", $EPOCHREALTIME - $started }") $test $shard $log"
}

run_batch() { # run_batch <test>...: the suites in one process; prints a results line per file
  local tests=("$@") test log status alone again
  local name="unit-batch-${tests[0]%.gd}"
  name="${name//\//-}"
  local batch_log="$LOGS/$name.log" data="$DATA/$name" clean=1 code=0
  rm -rf "$data" && mkdir -p "$data"
  XDG_DATA_HOME="$data" timeout 900 "$GODOT" --headless --fixed-fps 60 --path . --script "res://$HOST" \
    -- "${tests[@]/#/res://}" >"$batch_log" 2>&1 || code=$?
  # 1 is a file that failed (its own part says which); anything else is a crash or the timeout.
  ((code == 0 || code == 1)) || clean=0
  # An error at the start or the end (outside every file's part) is no one file's: all run alone.
  awk -v start="SUITE START: " -v end="SUITE END: " '
    index($0, start) == 1 { inside = 1; next } index($0, end) == 1 { inside = 0; next }
    !inside && /^(SCRIPT )?ERROR:/ { found = 1 } END { exit found ? 0 : 1 }' "$batch_log" && clean=0
  for test in "${tests[@]}"; do
    log=$(log_of "$test" -)
    # The batch's start (before the first file), then the file's own part.
    awk -v start="SUITE START: " -v file="res://$test" '
      index($0, start) == 1 { begun = 1; mine = ($0 == start file) }
      !begun || mine { print } mine && index($0, "SUITE END: " file " ") == 1 { exit }' "$batch_log" >"$log"
    local ended
    ended=$(grep -m1 -F "SUITE END: res://$test " "$log" || true)
    if ((!clean)) || [[ -z "$ended" ]]; then
      run_one "$test" -
      continue
    fi
    status=PASS
    [[ "$ended" == *" PASS "* ]] || status=FAIL
    grep -qE '^(SCRIPT )?ERROR:' "$log" && status=FAIL
    if [[ "$status" == FAIL ]]; then
      # Alone too (into the same log): a failure alone is the file's own. One that passes alone
      # fails only after the files before it: still a failure, its log the batch's part.
      mv "$log" "$log.batch"
      alone=$(run_one "$test" -)
      if [[ "$alone" == FAIL* ]]; then
        rm -f "$log.batch"
        echo "$alone"
        continue
      fi
      mv "$log.batch" "$log"
      echo "UNIT RUNNER: $test fails after the files before it in one process and passes alone:" \
        "a file before it left state behind (the batch's log: $batch_log)" >>"$log"
    fi
    echo "$status $(awk -v l="$ended" 'BEGIN { n = split(l, w, " "); printf "%.1f", w[n - 1] / 1000 }') $test - $log"
  done
}

run() { # run alone <test> <K/N or -> | run batch - <test>...
  if [[ "$1" == batch ]]; then
    shift 2
    run_batch "$@"
  else
    run_one "$2" "$3"
  fi
}

export -f is_suite log_of run_one run_batch run
export GODOT LOGS DATA HOST
ordered | xargs -P "$JOBS" -L1 bash -c 'run "$@"' _ >"$RESULTS"

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

echo "$(grep -c '^PASS' "$RESULTS") unit test files passed ($JOBS processes at once, suites $BATCH to a process); the longest:"
sort -k2,2gr "$RESULTS" | head -5 | awk '{ printf "  %6.1f s  %s%s\n", $2, $3, ($4 == "-" ? "" : " (shard " $4 ")") }'
! grep -q '^FAIL' "$RESULTS"
