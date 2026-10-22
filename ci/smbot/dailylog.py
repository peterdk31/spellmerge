"""The Daily log: one issue per day that lists every bot action (docs/PLAN.md, "Kill switch").

Each day's log is its own issue, "Daily log YYYY-MM-DD" (the owner's time zone),
labelled `daily-log`. Each post is a comment on it, so the owner can follow
everything from the GitHub app's notifications. The first post of a day opens
the new issue and closes the older ones, so the open log is always today's.
The day's issue number is kept in the state, so each post finds it without
trusting the (lagging) list of open issues.
Posts also go to the run's job summary, so the Actions tab shows them next to
the logs.

Lines that need the owner mention them; everything else is a plain record.
"""

from __future__ import annotations

import datetime as dt
import os
import re
from zoneinfo import ZoneInfo

from . import config as config_mod
from . import labels as labels_mod
from . import gh
from . import state as state_mod

LABEL = "daily-log"
TITLE = "Daily log {date}"


def shorten(text: str, limit: int = 300) -> str:
    """`text` cut to at most `limit` characters at a sentence end, else at a word, with an ellipsis."""
    text = " ".join(str(text or "").split())
    if len(text) <= limit:
        return text
    cut = text[:limit - 1]
    ends = [m.end() for m in re.finditer(r"[.!?](?=\s)", cut)]
    if ends and ends[-1] >= limit // 3:
        return cut[:ends[-1]]
    return cut.rsplit(" ", 1)[0].rstrip(",;:") + "…"


def today(cfg: config_mod.Config, now: dt.datetime | None = None) -> str:
    now = now or dt.datetime.now(dt.timezone.utc)
    return now.astimezone(ZoneInfo(cfg.timezone)).strftime("%Y-%m-%d")


def _open_logs(cfg: config_mod.Config) -> list[dict]:
    return gh.api(f"repos/{cfg.repo}/issues?state=open&labels={LABEL}&per_page=100")


def _is_open_log(cfg: config_mod.Config, number: int, title: str) -> bool:
    """Whether issue `number` is open and titled `title`. Fetching one issue is consistent, the list isn't."""
    try:
        issue = gh.api(f"repos/{cfg.repo}/issues/{number}")
    except gh.GhError:
        return False
    return issue.get("state") == "open" and issue.get("title") == title


def _remember(cfg: config_mod.Config, date: str, number: int, stale: int | None) -> int:
    """Records `number` as `date`'s log, unless another run already recorded a live one; returns the one kept.

    Best effort: a run whose token can't write the state keeps its own issue.
    """
    def apply(st: dict) -> None:
        current = st.get("daily_log") or {}
        if current.get("date") != date or current.get("number") in (None, stale):
            st["daily_log"] = {"date": date, "number": number}

    try:
        return int(state_mod.update(cfg, apply, f"daily log: {date} is #{number}")["daily_log"]["number"])
    except (gh.GhError, KeyError, TypeError, ValueError):
        return number


def issue_for(cfg: config_mod.Config, date: str) -> int:
    """Today's log issue: found, or opened now (closing the older ones).

    The day's number is kept in the state, because the list of open issues lags behind:
    a log opened minutes ago can be missing from it, and every miss opened another log.
    """
    title = TITLE.format(date=date)
    try:
        recorded = (state_mod.load(cfg)[0].get("daily_log") or {})
    except gh.GhError:
        recorded = {}
    stale = None
    if recorded.get("date") == date and recorded.get("number"):
        if _is_open_log(cfg, int(recorded["number"]), title):
            return int(recorded["number"])
        stale = int(recorded["number"])
    logs = _open_logs(cfg)
    mine = sorted(i["number"] for i in logs if i["title"] == title and i["number"] != stale)
    if mine:
        keep = _remember(cfg, date, mine[0], stale)
    else:
        labels_mod.ensure(cfg, [LABEL])
        created = gh.api(f"repos/{cfg.repo}/issues", "-X", "POST", input={
            "title": title, "labels": [LABEL],
            "body": f"What the bot did on {date} ({cfg.timezone}). Every action is a comment below; posts that "
                    f"need @{cfg.owner.login} mention them. Tomorrow's log closes this one.",
        })
        # Two runs can open the day's log at the same moment: the one recorded first wins.
        keep = _remember(cfg, date, int(created["number"]), stale)
        if keep != created["number"]:
            logs = [*logs, {"number": created["number"], "title": title}]
    if recorded.get("number") and recorded.get("date") != date and int(recorded["number"]) != keep:
        # The day before's log, closed by number too: the list can leave it out.
        logs = [*logs, {"number": int(recorded["number"]), "title": ""}]
    closed: set[int] = set()
    for issue in logs:
        if issue["number"] != keep and issue["number"] not in closed:
            closed.add(issue["number"])
            reason = "duplicate" if issue["title"] == title else "completed"
            gh.api(f"repos/{cfg.repo}/issues/{issue['number']}", "-X", "PATCH",
                   input={"state": "closed", "state_reason": "not_planned" if reason == "duplicate" else reason})
    return keep


def render(cfg: config_mod.Config, title: str, lines: list[str], mention_owner: bool, now: dt.datetime) -> str:
    stamp = now.astimezone(ZoneInfo(cfg.timezone)).strftime("%H:%M")
    body = f"**{title}** · {stamp}\n\n" + "\n".join(f"- {line}" for line in lines)
    if mention_owner:
        body += f"\n\n@{cfg.owner.login}, this needs your attention."
    return body


def _step_summary(text: str) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a") as fh:
            fh.write(text + "\n\n")


def post(cfg: config_mod.Config, title: str, lines: list[str], mention_owner: bool = False) -> None:
    lines = [line for line in lines if line]
    if not lines:
        return
    now = dt.datetime.now(dt.timezone.utc)
    body = render(cfg, title, lines, mention_owner, now)
    _step_summary(body)
    number = issue_for(cfg, today(cfg, now))
    gh.api(f"repos/{cfg.repo}/issues/{number}/comments", "-X", "POST", input={"body": body})
