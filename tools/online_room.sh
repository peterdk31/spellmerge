#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
# Two game processes on this machine play through a room: tools/online_room.sh [ticks]
#
# The real game twice (headless), as two machines of two players each would play it (online lobby
# L2, docs/milestones/online-lobby.md; tests/net/online_runner.gd with --signal): the host presses
# Play, opens a room at the hub's altar and hands over its code; the other joins by it through
# the room server (server/signal/local.js, started here on a free port: the same rooms as the
# deployed one) and is put into the host's hub; all four walk onto the stone, a run starts and is
# fought. The host plays `ticks` ticks (1500) with the joining process and passes when every hash
# check agreed, the joining machine held its two seats and a run was started from the stone.
# Needs Node 22 or later, the pinned Godot and the WebRTC extension (ci/build/build.sh --quick
# once). Logs: build/logs/room/.
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
  echo "online_room: Node is needed (22 or later)." >&2
  exit 2
fi
LOG="$PWD/build/logs/room"
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
  echo "online_room: the local server did not start (see $LOG/server.txt)" >&2
  exit 1
fi
# Both processes share one user:// (the room's code is handed over there), apart from the player's own.
export XDG_CONFIG_HOME="$TOOLS/xdg/config" XDG_CACHE_HOME="$TOOLS/xdg/cache" XDG_DATA_HOME="$LOG/data"
"$GODOT" --headless --path . -- --online --online-role=host "--signal=$url" "--ticks=$TICKS" >"$LOG/host.txt" 2>&1 &
host=$!
"$GODOT" --headless --path . -- --online --online-role=join "--signal=$url" >"$LOG/join.txt" 2>&1 &
join=$!
status=0
wait "$host" || status=1
wait "$join" || status=1
grep -h '^ONLINE' "$LOG/host.txt" "$LOG/join.txt"
grep -q '^ONLINE host OK' "$LOG/host.txt" || status=1
grep -q '^ONLINE join OK' "$LOG/join.txt" || status=1
if [[ "$status" != 0 ]]; then
  echo "online_room: FAILED (see $LOG)" >&2
fi
exit "$status"
