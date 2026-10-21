"""Pacing of Claude usage (docs/PLAN.md, "Capacity").

The exact remaining Pro quota isn't available to automation, so every run
records its token usage, and each time a usage limit is hit the bot learns how
many tokens a ~5-hour window (or a week) holds. It then stops at the Control
panel's DEV_INTENSITY share of a window. The week is not gated by estimate: the
bot just runs, and a weekly limit backs it off until the reset the limit names.
The WEEKLY_SHARE share of a week is only reported. Until a limit has been hit
once, only the back-off after a limit applies. All numbers are estimates.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass
from typing import Any

WINDOW = dt.timedelta(hours=5)
WEEK = dt.timedelta(days=7)
DAY = dt.timedelta(days=1)
REVIEW_SHARE = 0.30  # reviews may use about 30% of the window budget


def parse_time(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def iso(t: dt.datetime) -> str:
    return t.astimezone(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def used(state: dict[str, Any], now: dt.datetime, span: dt.timedelta, kinds: tuple[str, ...] | None = None) -> int:
    return sum(u["tokens"] for u in state["usage"]
               if now - parse_time(u["at"]) <= span and (kinds is None or u["kind"] in kinds))


def record(state: dict[str, Any], now: dt.datetime, tokens: int, kind: str) -> None:
    state["usage"].append({"at": iso(now), "tokens": int(tokens), "kind": kind})
    state["usage"] = [u for u in state["usage"] if now - parse_time(u["at"]) <= dt.timedelta(days=8)]


def limit_hit(state: dict[str, Any], now: dt.datetime, weekly: bool, resets_at: dt.datetime | None = None) -> None:
    """Learns the size of the window (or week) and backs off until it resets."""
    if weekly:
        state["limits"]["week_tokens"] = max(used(state, now, WEEK), 1)
        until = resets_at or now + DAY
    else:
        state["limits"]["window_tokens"] = max(used(state, now, WINDOW), 1)
        until = resets_at or now + WINDOW
    state["backoff_until"] = iso(until)


def backing_off_until(state: dict[str, Any], now: dt.datetime) -> str:
    """The end of the current back-off after a usage limit as an ISO time, or "" when there is none."""
    until = state.get("backoff_until")
    return until if until and now < parse_time(until) else ""


@dataclass(frozen=True)
class Budget:
    allowed: bool
    reason: str
    window_pct: float | None  # share of the window budget used, for the Daily log
    week_pct: float | None


def budget(state: dict[str, Any], now: dt.datetime, dev_intensity: int, weekly_share: int,
           kinds: tuple[str, ...] | None = None, share_of_window: float = 1.0) -> Budget:
    """Whether a new Claude run may start now."""
    if state.get("backoff_until") and now < parse_time(state["backoff_until"]):
        return Budget(False, f"backing off after a usage limit until {state['backoff_until']}", None, None)

    window_cap = state["limits"].get("window_tokens")
    week_cap = state["limits"].get("week_tokens")
    window_pct = week_pct = None
    if window_cap:
        allowance = window_cap * dev_intensity / 100 * share_of_window
        spent = used(state, now, WINDOW, kinds)
        window_pct = 100 * spent / allowance if allowance else 100.0
        if spent >= allowance:
            return Budget(False, f"window budget used ({window_pct:.0f}% of DEV_INTENSITY {dev_intensity}%)",
                          window_pct, week_pct)
    if week_cap:
        # Reported only: the learned week is a rolling estimate that doesn't know when the
        # quota resets, so gating on it kept the bot idle for days after a reset.
        weekly_allowance = week_cap * weekly_share / 100
        week_pct = 100 * used(state, now, WEEK) / weekly_allowance if weekly_allowance else 100.0
    return Budget(True, "ok", window_pct, week_pct)


def usage_line(state: dict[str, Any], now: dt.datetime, dev_intensity: int, weekly_share: int) -> str:
    """e.g. 'used ~62% of window budget, 41% of weekly share' (estimates)."""
    b = budget(state, now, dev_intensity, weekly_share)
    parts = []
    parts.append(f"~{b.window_pct:.0f}% of window budget" if b.window_pct is not None
                 else f"{used(state, now, WINDOW):,} tokens in the last 5 h (window size not learned yet)")
    parts.append(f"{b.week_pct:.0f}% of weekly share" if b.week_pct is not None
                 else f"{used(state, now, WEEK):,} tokens this week (weekly size not learned yet)")
    return "Claude usage: " + ", ".join(parts) + " (estimates)"
