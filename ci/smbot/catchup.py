"""Starts daily.yml and weekly.yml when GitHub misses their schedule.

  python3 -m smbot.catchup

GitHub's schedule is best effort, and in this repository it has never fired. Every
develop run therefore checks the last time each workflow was due: if that time is more
than GRACE ago, after the workflow was added, and no run of it has started since, it is
started with workflow_dispatch. Needs GH_TOKEN with actions: write.
"""

from __future__ import annotations

import datetime as dt
import sys
import time

from . import config as config_mod
from . import gh
from .pacing import iso, parse_time

GRACE = dt.timedelta(minutes=20)  # a late scheduled run still counts


def last_due(now: dt.datetime, workflow: str) -> dt.datetime:
    """The latest scheduled time at or before now: daily 03:00 UTC, weekly Sunday 06:00 UTC."""
    if workflow == "daily.yml":
        due = now.replace(hour=3, minute=0, second=0, microsecond=0)
        return due if due <= now else due - dt.timedelta(days=1)
    due = (now - dt.timedelta(days=(now.weekday() + 1) % 7)).replace(hour=6, minute=0, second=0, microsecond=0)
    return due if due <= now else due - dt.timedelta(days=7)


def missed(now: dt.datetime, due: dt.datetime, added: dt.datetime, run_times: list[dt.datetime]) -> bool:
    return due > added and now - due >= GRACE and not any(t >= due for t in run_times)


def main() -> int:
    cfg = config_mod.load()
    now = dt.datetime.now(dt.timezone.utc)
    for workflow in ("daily.yml", "weekly.yml"):
        info = gh.api(f"repos/{cfg.repo}/actions/workflows/{workflow}")
        runs = gh.api(f"repos/{cfg.repo}/actions/workflows/{workflow}/runs?per_page=10")["workflow_runs"]
        due = last_due(now, workflow)
        if info.get("state") == "active" and missed(now, due, parse_time(info["created_at"]),
                                                     [parse_time(r["created_at"]) for r in runs]):
            gh.api(f"repos/{cfg.repo}/actions/workflows/{workflow}/dispatches", "-X", "POST", input={"ref": "main"})
            print(f"{workflow}: missed its {iso(due)} run, started it")
            time.sleep(10)  # let the run appear before the next check (this job runs one at a time)
        else:
            print(f"{workflow}: nothing to do (last due {iso(due)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
