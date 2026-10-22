"""Pacing of Claude usage (docs/PLAN.md, "Capacity").

The exact remaining quota isn't available to automation, and estimating it from
token counts proved unreliable, so runs are not gated by estimate. Every run
records its token usage for the Daily log, and when Claude reports a usage limit
the bot backs off until the reset the limit names.
"""

from __future__ import annotations

import datetime as dt
from typing import Any

WINDOW = dt.timedelta(hours=5)
WEEK = dt.timedelta(days=7)
DAY = dt.timedelta(days=1)


def parse_time(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def iso(t: dt.datetime) -> str:
    return t.astimezone(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def used(state: dict[str, Any], now: dt.datetime, span: dt.timedelta) -> int:
    return sum(u["tokens"] for u in state["usage"] if now - parse_time(u["at"]) <= span)


def record(state: dict[str, Any], now: dt.datetime, tokens: int, kind: str) -> None:
    state["usage"].append({"at": iso(now), "tokens": int(tokens), "kind": kind})
    state["usage"] = [u for u in state["usage"] if now - parse_time(u["at"]) <= dt.timedelta(days=8)]


def limit_hit(state: dict[str, Any], now: dt.datetime, weekly: bool, resets_at: dt.datetime | None = None) -> None:
    """Backs off until the window (or week) resets."""
    until = resets_at or now + (DAY if weekly else WINDOW)
    state["backoff_until"] = iso(until)


def backing_off_until(state: dict[str, Any], now: dt.datetime) -> str:
    """The end of the current back-off after a usage limit as an ISO time, or "" when there is none."""
    until = state.get("backoff_until")
    return until if until and now < parse_time(until) else ""


def usage_line(state: dict[str, Any], now: dt.datetime) -> str:
    """e.g. 'Claude usage: 4,677,474 tokens in the last 5 h, 20,082,870 tokens this week'."""
    line = (f"Claude usage: {used(state, now, WINDOW):,} tokens in the last 5 h, "
            f"{used(state, now, WEEK):,} tokens this week")
    until = backing_off_until(state, now)
    return line + (f", backing off after a usage limit until {until}" if until else "")
