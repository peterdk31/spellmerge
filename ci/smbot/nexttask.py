"""Reads docs/NEXT.md, the ordered task queue (docs/PLAN.md, "Planning system").

Format: under the "## Queue" heading, one task per line as "- [ ] ...". The
first unchecked task is the next one.
"""

from __future__ import annotations

import re
from pathlib import Path

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


def next_task(path: Path = Path("docs/NEXT.md")) -> str | None:
    if not path.exists():
        return None
    tasks = queue(path.read_text())
    return tasks[0] if tasks else None
