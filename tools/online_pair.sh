#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
# Two game processes on this machine play one run through Host and Join: tools/online_pair.sh [ticks]
#
# The real game twice (headless), linked over WebRTC with no STUN server, their codes handed over
# through files (tests/net/online_runner.gd; netcode spike S4, docs/milestones/netcode-spike.md).
# The host plays `ticks` ticks (600) of a sandbox with the joining process, both seats scripted, and
# passes when every hash check agreed. Needs the pinned Godot and the WebRTC extension
# (ci/build/build.sh --quick once). Logs: build/logs/online/.
set -u
cd "$(dirname "$0")/.."
TICKS="${1:-600}"
TOOLS="$(readlink -f build/godot)"
GODOT="$(find "$TOOLS" -maxdepth 1 -name 'Godot_v*_linux.x86_64' -type f | head -1)"
if [[ ! -x "$GODOT" ]]; then
  echo "No pinned Godot in build/godot: run ci/build/build.sh --quick first." >&2
  exit 2
fi
LOG="$PWD/build/logs/online"
rm -rf "$LOG"
mkdir -p "$LOG/data"
# Both processes share one user:// (the codes are handed over there), apart from the player's own.
export XDG_CONFIG_HOME="$TOOLS/xdg/config" XDG_CACHE_HOME="$TOOLS/xdg/cache" XDG_DATA_HOME="$LOG/data"
"$GODOT" --headless --path . -- --online --online-role=host "--ticks=$TICKS" >"$LOG/host.txt" 2>&1 &
host=$!
"$GODOT" --headless --path . -- --online --online-role=join >"$LOG/join.txt" 2>&1 &
join=$!
status=0
wait "$host" || status=1
wait "$join" || status=1
grep -h '^ONLINE' "$LOG/host.txt" "$LOG/join.txt"
grep -q '^ONLINE host OK' "$LOG/host.txt" || status=1
grep -q '^ONLINE join OK' "$LOG/join.txt" || status=1
if [[ "$status" != 0 ]]; then
  echo "online_pair: FAILED (see $LOG)" >&2
fi
exit "$status"
