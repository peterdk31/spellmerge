#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
# SPDX-License-Identifier: GPL-3.0-or-later
# The room server's own tests, then the game's handshake through it on this machine: tools/online_signal.sh
#
# 1. `node --test` in server/signal/ (the rooms, their limits, a fuzz, real sockets).
# 2. server/signal/local.js started on a free port (the same rooms as the deployed server, with
#    Node alone: nothing is installed), and tests/net/signal_runner.gd against it: a host and a
#    joining machine with the engine's real WebSocket and real WebRTC peers come to hold a link
#    by a room code (online lobby L2, docs/milestones/online-lobby.md). The server hands every
#    join a relay that is no relay (`--fake-relay`): the game must take it, give it to WebRTC
#    (`--relay=given`) and still link directly.
#
# Needs Node 22 or later, the pinned Godot and the WebRTC extension (ci/build/build.sh --quick
# once). Logs: build/logs/signal/.
set -u
cd "$(dirname "$0")/.."
TOOLS="$(readlink -f build/godot)"
GODOT="$(find "$TOOLS" -maxdepth 1 -name 'Godot_v*_linux.x86_64' -type f | head -1)"
if [[ ! -x "$GODOT" ]]; then
  echo "No pinned Godot in build/godot: run ci/build/build.sh --quick first." >&2
  exit 2
fi
if ! command -v node >/dev/null; then
  echo "online_signal: Node is needed (22 or later)." >&2
  exit 2
fi
LOG="$PWD/build/logs/signal"
rm -rf "$LOG"
mkdir -p "$LOG/data"
status=0
if ! (cd server/signal && node --test) >"$LOG/server-tests.txt" 2>&1; then
  echo "online_signal: the server's tests FAILED (see $LOG/server-tests.txt)" >&2
  status=1
fi
grep -E '^# (tests|pass|fail) ' "$LOG/server-tests.txt"

node server/signal/local.js 0 --fake-relay >"$LOG/server.txt" 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null' EXIT
url=""
for _ in $(seq 50); do
  url="$(sed -n 's/^signal: //p' "$LOG/server.txt")"
  [[ -n "$url" ]] && break
  sleep 0.1
done
if [[ -z "$url" ]]; then
  echo "online_signal: the local server did not start (see $LOG/server.txt)" >&2
  exit 1
fi
export XDG_CONFIG_HOME="$TOOLS/xdg/config" XDG_CACHE_HOME="$TOOLS/xdg/cache" XDG_DATA_HOME="$LOG/data"
"$GODOT" --headless --path . --script res://tests/net/signal_runner.gd -- "--signal=$url" --relay=given >"$LOG/game.txt" 2>&1 || status=1
grep -h '^SIGNAL' "$LOG/game.txt"
grep -q '^SIGNAL OK' "$LOG/game.txt" || status=1
if [[ "$status" != 0 ]]; then
  echo "online_signal: FAILED (see $LOG)" >&2
fi
exit "$status"
