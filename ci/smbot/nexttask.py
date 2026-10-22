"""The ordered task queue (docs/PLAN.md, "Planning system").

Scheduled issues from the community intake go first (smbot.intake.queue_tasks, priority
order), then docs/NEXT.md: under its "## Queue" heading, one task per line as "- [ ] ...".
The first task that isn't parked is the next one.

A task is parked when it can't move without someone else: it was reported
blocked, failed review too often, or its approved PR waits on GitHub or the
owner. Parked tasks are skipped for a while, so work moves on to the next one
instead of waiting (docs/PLAN.md, "Never stuck").
"""

from __future__ import annotations

import datetime as dt
import re
from pathlib import Path
from typing import Any, Collection, Sequence

from . import pacing

_TASK = re.compile(r"^- \[ \] (.+)$")


def queue(text: str) -> list[str]:
    tasks, in_queue = [], False
    for line in text.splitlines():
        if line.startswith("## "):
            in_queue = line.strip().lower() == "## queue"
            continue
        m = _TASK.match(line) if in_queue else None
        if m:
            tasks.append(m.group(1).strip())
    return tasks


def parked(state: dict[str, Any], now: dt.datetime) -> set[str]:
    """Tasks parked in the state's task_failures, until their parked_until time."""
    return {task for task, f in state.get("task_failures", {}).items()
            if f.get("parked_until") and now < pacing.parse_time(f["parked_until"])}


def next_task(path: Path = Path("docs/NEXT.md"), skip: Collection[str] = (),
              first: Sequence[str] = (), milestone: bool = True) -> str | None:
    """The first task of `first` (the scheduled issues), then of docs/NEXT.md, that isn't in `skip`.

    With `milestone` False (a checkpoint waits for the owner) only `first` counts.
    """
    tasks = [*first, *(queue(path.read_text()) if milestone and path.exists() else [])]
    return next((t for t in tasks if t not in skip), None)
