r"""The ordered task queue (docs/PLAN.md, "Planning system").

Scheduled issues from the community intake go first (smbot.intake.queue_tasks, priority
order), then docs/NEXT.md: under its "## Queue" heading, one task per line as "- [ ] ..." (a
numbered "1. [ ] ..." counts too: a planning session once wrote the queue that way, the parser
saw none, and development waited hours for the next planning run).
The first task that isn't parked is the next one.

A task that waits on the owner sits under "## Blocked" with the key of its owner question
(`key \`some-key\`` in the task or its sub-bullets). Once every question it names is answered,
it goes before the queue again: unblocking needs no session to notice it.

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

_TASK = re.compile(r"^(?:- |\d{1,3}\. )\[ \] (.+)$")
_QUESTION_KEY = re.compile(r"\bkey `([a-z0-9-]+)`")


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


def blocked(text: str) -> dict[str, set[str]]:
    """The tasks under "## Blocked", each with the owner question keys it waits on (maybe none)."""
    tasks: dict[str, set[str]] = {}
    task, in_blocked = None, False
    for line in text.splitlines():
        if line.startswith("## "):
            in_blocked, task = line.strip().lower() == "## blocked", None
            continue
        if not in_blocked:
            continue
        m = _TASK.match(line)
        if m:
            task = m.group(1).strip()
            tasks[task] = set(_QUESTION_KEY.findall(line))
        elif line.startswith((" ", "\t")) and task is not None:
            tasks[task] |= set(_QUESTION_KEY.findall(line))
        elif line.strip():
            task = None  # a line that isn't part of a task ends it
    return tasks


def unblocked(text: str, answered: Collection[str]) -> list[str]:
    """Blocked tasks whose owner questions are all answered, in file order.

    A blocked task that names no question waits for a planning session, as before.
    """
    return [task for task, keys in blocked(text).items() if keys and keys <= set(answered)]


def parked(state: dict[str, Any], now: dt.datetime) -> set[str]:
    """Tasks parked in the state's task_failures, until their parked_until time."""
    return {task for task, f in state.get("task_failures", {}).items()
            if f.get("parked_until") and now < pacing.parse_time(f["parked_until"])}


def open_tasks(path: Path = Path("docs/NEXT.md"), first: Sequence[str] = ()) -> set[str]:
    """Every task still to do: `first` (the scheduled issues) and docs/NEXT.md's queue and blocked tasks."""
    text = path.read_text() if path.exists() else ""
    return {*first, *blocked(text), *queue(text)}


def next_task(path: Path = Path("docs/NEXT.md"), skip: Collection[str] = (),
              first: Sequence[str] = (), milestone: bool = True, answered: Collection[str] = ()) -> str | None:
    """The first task of `first` (the scheduled issues), then of docs/NEXT.md, that isn't in `skip`.

    In docs/NEXT.md, blocked tasks whose questions are in `answered` (smbot.inbox.answered_keys)
    come before the queue. With `milestone` False (a checkpoint waits for the owner) only `first` counts.
    """
    text = path.read_text() if milestone and path.exists() else ""
    tasks = [*first, *unblocked(text, answered), *queue(text)]
    return next((t for t in tasks if t not in skip), None)
