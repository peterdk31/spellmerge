"""Community voting (docs/PLAN.md, "Community voting").

Votes are 👍/👎 reactions on the PR itself, for art, audio and core gameplay
PRs (gameplay sub-areas and spell components). The number of 👍 needed grows
with the number of active voters; with 0–2 active voters there is no waiting.

- needed(N) = 0 for N <= 2, else clamp(ceil(VOTE_SHARE * N), VOTE_MIN, VOTE_MAX)
- approved when 👍 >= needed and 👍 share of cast votes >= VOTE_APPROVAL
- window 24 h from the rating comment, extended once by 24 h; after 48 h
  Claude decides alone with the stricter bar (average >= 3.8)
- who may vote: Open phase (< 20 active contributors) any account older than
  30 days with some public activity; Community phase accounts that took part
  in the project at least 7 days before the vote
- coordinated-looking votes (3+ votes within 10 minutes from accounts with no
  earlier activity here) are discounted, and the comment says so
"""

from __future__ import annotations

import datetime as dt
import math
from dataclasses import dataclass, field
from typing import Any

VOTABLE_LABELS = frozenset({"area:art", "area:audio", "area:gameplay", "area:spells"})
WINDOW = dt.timedelta(hours=24)
COMMUNITY_PHASE_AT = 20
ACCOUNT_MIN_AGE = dt.timedelta(days=30)
PRIOR_PARTICIPATION = dt.timedelta(days=7)
CLUSTER_SIZE = 3
CLUSTER_SPAN = dt.timedelta(minutes=10)
STRICT_AVERAGE = 3.8


@dataclass(frozen=True)
class VoteSettings:
    share: int = 15  # percent
    minimum: int = 2
    maximum: int = 25
    approval: int = 60  # percent


def is_votable(labels: set[str]) -> bool:
    return bool(labels & VOTABLE_LABELS)


def needed(active_voters: int, s: VoteSettings) -> int:
    if active_voters <= 2:
        return 0
    return max(s.minimum, min(s.maximum, math.ceil(s.share * active_voters / 100)))


@dataclass(frozen=True)
class Vote:
    login: str
    up: bool
    at: dt.datetime


@dataclass
class Tally:
    up: int
    down: int
    needed: int
    active_voters: int
    discounted: list[str] = field(default_factory=list)
    ineligible: list[str] = field(default_factory=list)

    def approved(self, s: VoteSettings) -> bool:
        cast = self.up + self.down
        return self.up >= self.needed and (cast == 0 or 100 * self.up / cast >= s.approval)

    def rejected(self, s: VoteSettings) -> bool:
        """Enough 👎 to reject (used for Claude's own gameplay changes)."""
        cast = self.up + self.down
        return self.needed > 0 and self.down >= self.needed and 100 * self.down / cast >= s.approval


def coordinated(votes: list[Vote], newcomers: set[str]) -> set[str]:
    """Logins whose votes look coordinated: a burst of votes from accounts new to the project."""
    fresh = sorted((v for v in votes if v.login in newcomers), key=lambda v: v.at)
    flagged: set[str] = set()
    for i, first in enumerate(fresh):
        burst = [v for v in fresh[i:] if v.at - first.at <= CLUSTER_SPAN]
        if len(burst) >= CLUSTER_SIZE:
            flagged.update(v.login for v in burst)
    return flagged


def tally(votes: list[Vote], eligible: set[str], newcomers: set[str], active_voters: int, s: VoteSettings) -> Tally:
    latest: dict[str, Vote] = {}
    for v in sorted(votes, key=lambda v: v.at):
        latest[v.login] = v  # someone who changed their mind counts once, as their latest vote
    ineligible = sorted(login for login in latest if login not in eligible)
    counted = [v for v in latest.values() if v.login in eligible]
    flagged = coordinated(counted, newcomers)
    counted = [v for v in counted if v.login not in flagged]
    return Tally(sum(v.up for v in counted), sum(not v.up for v in counted), needed(active_voters, s),
                 active_voters, sorted(flagged), ineligible)


@dataclass(frozen=True)
class Window:
    state: str  # "open", "extended", "closed"
    hours_left: float


def window(started: dt.datetime, now: dt.datetime, t: Tally) -> Window:
    elapsed = now - started
    if elapsed < WINDOW:
        return Window("open", (WINDOW - elapsed).total_seconds() / 3600)
    if elapsed < 2 * WINDOW and t.up < t.needed:
        return Window("extended", (2 * WINDOW - elapsed).total_seconds() / 3600)
    return Window("closed", 0.0)


def decision(t: Tally, w: Window, s: VoteSettings, average: float) -> str:
    """'merge', 'wait', 'close' or 'claude-strict' (Claude decides alone with the stricter bar)."""
    if t.needed == 0:
        return "merge"
    if t.approved(s):
        return "merge"
    if t.rejected(s) and w.state != "open":
        return "close"
    if w.state in ("open", "extended"):
        return "wait"
    return "merge" if average >= STRICT_AVERAGE else "close"


def status_line(t: Tally, w: Window, s: VoteSettings) -> str:
    """e.g. '4 👍 / 1 👎, needs 3 👍 (15% of 18 active voters), 14 hours left'"""
    if t.needed == 0:
        return f"{t.up} 👍 / {t.down} 👎. Votes are advisory while there are only {t.active_voters} active voters."
    text = f"{t.up} 👍 / {t.down} 👎, needs {t.needed} 👍 ({s.share}% of {t.active_voters} active voters)"
    if w.state != "closed":
        text += f", {w.hours_left:.0f} hours left" + (" (extended once)" if w.state == "extended" else "")
    else:
        text += ", voting closed"
    if t.discounted:
        text += f". Discounted as coordinated-looking: {', '.join('@' + d for d in t.discounted)}"
    if t.ineligible:
        text += f". Not counted (not eligible to vote yet): {', '.join('@' + i for i in t.ineligible)}"
    return text


# --- Eligibility ---------------------------------------------------------------


def open_phase_eligible(user: dict[str, Any], now: dt.datetime) -> bool:
    created = dt.datetime.fromisoformat(user["created_at"].replace("Z", "+00:00"))
    activity = user.get("public_repos", 0) + user.get("public_gists", 0) + user.get("followers", 0)
    return now - created >= ACCOUNT_MIN_AGE and activity > 0


def community_phase_eligible(first_participation: dt.datetime | None, vote_started: dt.datetime) -> bool:
    return first_participation is not None and vote_started - first_participation >= PRIOR_PARTICIPATION


def phase(active_contributors: int) -> str:
    return "community" if active_contributors >= COMMUNITY_PHASE_AT else "open"
