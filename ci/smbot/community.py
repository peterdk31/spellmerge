"""Daily count of the community, for voting (docs/PLAN.md, "Community voting").

- Active contributors: accounts with a merged PR, an accepted bug report
  (label `bug`) or a Discussions post in the last 30 days.
- Active voters (N): accounts eligible to vote with any activity in the
  project (vote, PR, bug report, Discussions post) in the last 30 days.
- First participation: the earliest merged PR, accepted bug report or
  Discussions post, for the Community phase's 7-day rule.

The owner and bots are never counted.
"""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field
from typing import Any

from . import config as config_mod
from . import gh, votes

ACTIVE_SPAN = dt.timedelta(days=30)

_DISCUSSIONS = """
query($owner: String!, $name: String!, $cursor: String) {
  repository(owner: $owner, name: $name) {
    discussions(first: 50, after: $cursor, orderBy: {field: UPDATED_AT, direction: DESC}) {
      pageInfo { hasNextPage endCursor }
      nodes {
        updatedAt createdAt author { login }
        comments(first: 100) { nodes { createdAt author { login } } }
      }
    }
  }
}"""


def _time(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


@dataclass
class Activity:
    recent: dict[str, dt.datetime] = field(default_factory=dict)  # any activity, last 30 days
    contributions: dict[str, dt.datetime] = field(default_factory=dict)  # merged/bug/discussion, last 30 days
    first: dict[str, dt.datetime] = field(default_factory=dict)  # earliest participation, all time

    def see(self, login: str | None, at: dt.datetime, now: dt.datetime, participation: bool) -> None:
        if not login or login.endswith("[bot]"):
            return
        if now - at <= ACTIVE_SPAN:
            self.recent[login] = max(at, self.recent.get(login, at))
            if participation:
                self.contributions[login] = max(at, self.contributions.get(login, at))
        if participation and (login not in self.first or at < self.first[login]):
            self.first[login] = at


def gather(cfg: config_mod.Config, now: dt.datetime, discussions_token: str | None = None) -> Activity:
    """Collects activity; Discussions need a token with discussions: read (the bot app has none)."""
    act = Activity()
    owner, name = cfg.repo.split("/")
    for issue in gh.api_paginated(f"repos/{cfg.repo}/issues?state=all&per_page=100"):
        login = (issue.get("user") or {}).get("login")
        created = _time(issue["created_at"])
        if "pull_request" in issue:
            merged_at = (issue["pull_request"] or {}).get("merged_at")
            act.see(login, created, now, participation=False)
            if merged_at:
                act.see(login, _time(merged_at), now, participation=True)
        elif any(label["name"] == "bug" for label in issue.get("labels", [])):
            act.see(login, created, now, participation=True)
    cursor: str | None = None
    while True:
        try:
            data = gh.graphql(_DISCUSSIONS, gh_token=discussions_token, owner=owner, name=name,
                              **({"cursor": cursor} if cursor else {}))
        except gh.GhError as e:
            print(f"Discussions couldn't be read, so they don't count today: {e}")
            break
        page = data["repository"]["discussions"]
        for d in page["nodes"]:
            act.see((d.get("author") or {}).get("login"), _time(d["createdAt"]), now, participation=True)
            for c in d["comments"]["nodes"]:
                act.see((c.get("author") or {}).get("login"), _time(c["createdAt"]), now, participation=True)
        if not page["pageInfo"]["hasNextPage"] or now - _time(page["nodes"][-1]["updatedAt"]) > 2 * ACTIVE_SPAN:
            break
        cursor = page["pageInfo"]["endCursor"]
    for login in (cfg.owner.login,):
        act.recent.pop(login, None)
        act.contributions.pop(login, None)
    return act


def add_votes(act: Activity, reactions: list[dict[str, Any]], now: dt.datetime) -> None:
    for r in reactions:
        act.see((r.get("user") or {}).get("login"), _time(r["created_at"]), now, participation=False)


def eligible(login: str, act: Activity, phase: str, vote_started: dt.datetime, now: dt.datetime,
             user_cache: dict[str, dict[str, Any]]) -> bool:
    if phase == "community":
        return votes.community_phase_eligible(act.first.get(login), vote_started)
    if login not in user_cache:
        try:
            user_cache[login] = gh.api(f"users/{login}")
        except gh.GhError:
            return False
    return votes.open_phase_eligible(user_cache[login], now)


def counts(act: Activity, now: dt.datetime, user_cache: dict[str, dict[str, Any]]) -> tuple[int, int, str]:
    """(active contributors, active voters N, phase)."""
    contributors = len(act.contributions)
    phase = votes.phase(contributors)
    voters = sum(eligible(login, act, phase, now, now, user_cache) for login in act.recent)
    return contributors, voters, phase
