"""Bot PRs whose task is gone from the queue are closed (docs/PLAN.md, "Never stuck").

A task's PR waits in the state's task_failures (it failed review, or it is parked) and is taken up
again only through its task in docs/NEXT.md or the scheduled issues. When the task leaves them
meanwhile (another PR did it, as #224 did #219's on 2026-10-23, or planning reworded or dropped it),
nothing would ever pick the PR up again. The hourly check closes it, says why on the PR and in the
Daily log, and forgets the task's failures.
"""

from __future__ import annotations

import re
from typing import Any, Collection

from . import config as config_mod
from . import dailylog, gh
from .commands import belongs_to

PARKED_LABEL = "parked"
_NUMBER = re.compile(r"#(\d+)\b")
# Sessions that don't come from the queue: planning (smbot.session.prepare_plan) and a session with only
# owner instructions. Their PRs are taken up again without a queue line.
NOT_FROM_THE_QUEUE = {"Planning", ""}


def is_open(task: str, entry: dict[str, Any], open_tasks: Collection[str]) -> bool:
    """True if the task, or a task for the same PR or issue (its wording may have changed), is still to do."""
    if task in open_tasks:
        return True
    numbers = {int(n) for n in _NUMBER.findall(task)}
    if str(entry.get("pr") or "").isdigit():
        numbers.add(int(entry["pr"]))
    return any(belongs_to(t, {}, n) for t in open_tasks for n in numbers)


def gone(st: dict[str, Any], open_tasks: Collection[str]) -> list[str]:
    """The tasks in task_failures that are no longer to do."""
    return [t for t, e in st.get("task_failures", {}).items()
            if t not in NOT_FROM_THE_QUEUE and not is_open(t, e, open_tasks)]


def close(cfg: config_mod.Config, task: str, pr: str) -> str | None:
    """Closes the bot's open PR for a task that is gone; the Daily log line, or None if it wasn't open.

    Raises gh.GhError when GitHub can't be read or written.
    """
    info = gh.api(f"repos/{cfg.repo}/pulls/{pr}")
    if info.get("state") != "open" or (info.get("user") or {}).get("login") != cfg.bot.login:
        return None
    gh.api(f"repos/{cfg.repo}/issues/{pr}/comments", "-X", "POST", input={"body": (
        "**Closed:** this pull request's task is no longer in the queue (`docs/NEXT.md` or the scheduled "
        "issues), so no session would take it up again. It was done or dropped on `main` meanwhile, "
        "maybe by another pull request. Reopen it if something here is still needed.")})
    gh.api(f"repos/{cfg.repo}/pulls/{pr}", "-X", "PATCH", input={"state": "closed"})
    try:
        gh.api(f"repos/{cfg.repo}/issues/{pr}/labels/{PARKED_LABEL}", "-X", "DELETE")
    except gh.GhError:
        pass  # it wasn't labelled
    title = dailylog.shorten(info.get("title") or task, 120)
    return f"Closed #{pr} {title}: its task is no longer queued (done or dropped on main meanwhile)."


def sweep(cfg: config_mod.Config, st: dict[str, Any], open_tasks: Collection[str]) -> tuple[list[str], list[str]]:
    """Closes the open bot PRs of gone tasks; returns the Daily log lines and the tasks to forget."""
    lines: list[str] = []
    forget: list[str] = []
    for task in gone(st, open_tasks):
        pr = str(st["task_failures"][task].get("pr") or "")
        try:
            line = close(cfg, task, pr) if pr.isdigit() else None
        except gh.GhError as e:
            lines.append(f"Couldn't close #{pr}, whose task is no longer queued: {dailylog.shorten(str(e), 200)}")
            continue  # tried again at the next check
        if line:
            lines.append(line)
        forget.append(task)
    return lines, forget
