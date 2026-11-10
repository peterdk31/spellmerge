#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
# Four game processes on this machine play as one party: tools/online_party.sh [ticks]
#
# The real game four times (headless), as a host and three guest machines of one player each
# would play it (online lobby L3, docs/milestones/online-lobby.md; tests/net/online_runner.gd
# with --signal, --players and --party): the host presses Play, opens a room at the hub's altar
# and hands over its code; the three others join by it through the room server
# (server/signal/local.js, started here on a free port), each put into the host's hub as it is
# ready, the later ones catching up on what was recorded; all four walk onto the stone, a run
# starts and is fought. The host plays `ticks` ticks (1500) and passes when every machine's
# hash checks agreed, the guests held three seats and a run was started from the stone.
# Needs Node 22 or later, the pinned Godot and the WebRTC extension (ci/build/build.sh --quick
# once). Logs: build/logs/party/.
set -u
cd "$(dirname "$0")/.."
TICKS="${1:-1500}"
TOOLS="$(readlink -f build/godot)"
GODOT="$(find "$TOOLS" -maxdepth 1 -name 'Godot_v*_linux.x86_64' -type f | head -1)"
if [[ ! -x "$GODOT" ]]; then
  echo "No pinned Godot in build/godot: run ci/build/build.sh --quick first." >&2
  exit 2
fi
if ! command -v node >/dev/null; then
  echo "online_party: Node is needed (22 or later)." >&2
  exit 2
fi
LOG="$PWD/build/logs/party"
rm -rf "$LOG"
mkdir -p "$LOG/data"
node server/signal/local.js 0 >"$LOG/server.txt" 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null' EXIT
url=""
for _ in $(seq 50); do
  url="$(sed -n 's/^signal: //p' "$LOG/server.txt")"
  [[ -n "$url" ]] && break
  sleep 0.1
done
if [[ -z "$url" ]]; then
  echo "online_party: the local server did not start (see $LOG/server.txt)" >&2
  exit 1
fi
# Both processes share one user:// (the room's code is handed over there), apart from the player's own.
export XDG_CONFIG_HOME="$TOOLS/xdg/config" XDG_CACHE_HOME="$TOOLS/xdg/cache" XDG_DATA_HOME="$LOG/data"
"$GODOT" --headless --path . -- --online --online-role=host "--signal=$url" "--ticks=$TICKS" --players=1 --party=4 >"$LOG/host.txt" 2>&1 &
host=$!
joins=()
for n in 1 2 3; do
  "$GODOT" --headless --path . -- --online --online-role=join "--signal=$url" --players=1 >"$LOG/join$n.txt" 2>&1 &
  joins+=($!)
done
status=0
wait "$host" || status=1
for pid in "${joins[@]}"; do
  wait "$pid" || status=1
done
grep -h '^ONLINE' "$LOG/host.txt" | grep -E 'ROOM|LINE|OK|FAILED'
for n in 1 2 3; do
  grep -h '^ONLINE join \(OK\|FAILED\)' "$LOG/join$n.txt" | sed "s/^ONLINE join/ONLINE join $n/"
  grep -q '^ONLINE join OK' "$LOG/join$n.txt" || status=1
done
grep -q '^ONLINE host OK' "$LOG/host.txt" || status=1
if [[ "$status" != 0 ]]; then
  echo "online_party: FAILED (see $LOG)" >&2
fi
exit "$status"
