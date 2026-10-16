"""Claims (docs/PLAN.md, "Claims").

- Anyone comments `/claim` on an issue labelled `now`, and it's assigned to them
  (hourly, from develop.yml's control job).
- A claim lasts 2 days without a PR: a reminder after 1 day, then it's released
  (daily). A PR by the claimant that mentions the issue keeps the claim.
- Claude never takes a claimed task; its own tasks carry `claude:working`.

`/claim` is not an owner command: anyone may claim, so nothing else in the
comment is acted on.
"""

from __future__ import annotations

import datetime as dt
import re
import sys
from typing import Any

from . import dailylog, gh, state
from . import config as config_mod
from .pacing import iso, parse_time

REMIND_AFTER = dt.timedelta(days=1)
RELEASE_AFTER = dt.timedelta(days=2)
SCAN = dt.timedelta(days=3)
_CLAIM = re.compile(r"^\s*/claim\b", re.IGNORECASE)


def is_claim(body: str) -> bool:
    return bool(_CLAIM.match(body or ""))


def _comment(cfg: config_mod.Config, number: int, body: str) -> None:
    gh.api(f"repos/{cfg.repo}/issues/{number}/comments", "-X", "POST", input={"body": body})


def process_new(cfg: config_mod.Config, st: dict[str, Any], now: dt.datetime) -> tuple[list[str], dict, list[int]]:
    """Handles new /claim comments; returns (log, new claims, processed comment ids)."""
    log: list[str] = []
    new_claims: dict[str, dict] = {}
    processed: list[int] = []
    seen = set(st.get("processed_claims", []))
    for c in gh.api_paginated(f"repos/{cfg.repo}/issues/comments?since={iso(now - SCAN)}&per_page=100"):
        if c["id"] in seen or not is_claim(c.get("body") or "") or "/pull/" in c["html_url"]:
            continue
        processed.append(c["id"])
        number = int(c["issue_url"].rsplit("/", 1)[1])
        login = c["user"]["login"]
        issue = gh.api(f"repos/{cfg.repo}/issues/{number}")
        labels = {label["name"] for label in issue["labels"]}
        assignees = [a["login"] for a in issue["assignees"]]
        if issue["state"] != "open":
            reply = "This issue is closed, so it can't be claimed."
        elif "now" not in labels:
            reply = ("This task isn't open for PRs yet (it needs the `now` label). Tasks marked `now` are listed "
                     f"on the [project board](https://github.com/users/{cfg.owner.login}/projects).")
        elif "claude:working" in labels:
            reply = "Claude is already working on this one; please pick another `now` task."
        elif assignees and login not in assignees:
            reply = f"This is already claimed by @{assignees[0]}. Claims expire after 2 days without a PR."
        elif login in assignees:
            reply = "It's already yours."
        else:
            gh.api(f"repos/{cfg.repo}/issues/{number}/assignees", "-X", "POST", input={"assignees": [login]})
            new_claims[str(number)] = {"login": login, "at": iso(now), "reminded": False}
            reply = (f"It's yours, @{login}! The claim lasts 2 days; open a PR that mentions #{number} to keep it. "
                     "Questions? Ask here.")
            log.append(f"#{number} claimed by @{login}")
        _comment(cfg, number, f"> /claim\n\n{reply}")
    return log, new_claims, processed


def has_pr(cfg: config_mod.Config, login: str, number: int) -> bool:
    found = gh.api(f"search/issues?q=repo:{cfg.repo}+is:pr+author:{login}+{number}+in:body,title")
    return any(f"#{number}" in ((i.get("body") or "") + " " + i["title"]) for i in found.get("items", []))


def expire(cfg: config_mod.Config, claims: dict[str, dict], now: dt.datetime) -> tuple[list[str], dict]:
    """Reminds and releases old claims; returns (log, remaining claims)."""
    log: list[str] = []
    remaining: dict[str, dict] = {}
    for number_s, claim in claims.items():
        number, login = int(number_s), claim["login"]
        issue = gh.api(f"repos/{cfg.repo}/issues/{number}")
        if issue["state"] != "open" or login not in [a["login"] for a in issue["assignees"]]:
            continue
        if has_pr(cfg, login, number):
            continue  # a PR keeps the claim; the PR pipeline takes it from here
        age = now - parse_time(claim["at"])
        if age >= RELEASE_AFTER:
            gh.api(f"repos/{cfg.repo}/issues/{number}/assignees", "-X", "DELETE", input={"assignees": [login]})
            _comment(cfg, number, f"@{login}, this claim has expired after 2 days without a PR, so the task is "
                                  "open again. You can claim it again with `/claim` if you're still on it.")
            log.append(f"#{number}: released @{login}'s claim")
            continue
        if age >= REMIND_AFTER and not claim.get("reminded"):
            _comment(cfg, number, f"@{login}, a friendly reminder: this claim expires tomorrow unless a PR mentions "
                                  f"#{number}. A draft PR is fine.")
            claim = {**claim, "reminded": True}
        remaining[number_s] = claim
    return log, remaining


def run_hourly(cfg: config_mod.Config, now: dt.datetime) -> list[str]:
    st, _ = state.load(cfg)
    log, new_claims, processed = process_new(cfg, st, now)

    def apply(s: dict[str, Any]) -> None:
        s.setdefault("claims", {}).update(new_claims)
        s["processed_claims"] = (s.get("processed_claims", []) + processed)[-1000:]
    state.update(cfg, apply, "claims: new")
    return log


def run_daily(cfg: config_mod.Config, now: dt.datetime) -> list[str]:
    st, _ = state.load(cfg)
    log, remaining = expire(cfg, st.get("claims", {}), now)
    checked = set(st.get("claims", {}))

    def apply(s: dict[str, Any]) -> None:
        # Keep claims added since this run started; replace the ones it checked.
        s["claims"] = {**{k: v for k, v in s.get("claims", {}).items() if k not in checked}, **remaining}
    state.update(cfg, apply, "claims: expiry")
    return log


def main(argv: list[str] | None = None) -> int:
    cmd = (argv or sys.argv[1:] or [""])[0]
    cfg = config_mod.load()
    now = dt.datetime.now(dt.timezone.utc)
    if cmd == "hourly":
        dailylog.post(cfg, "Claims", run_hourly(cfg, now))
    elif cmd == "daily":
        dailylog.post(cfg, "Claims", run_daily(cfg, now))
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
