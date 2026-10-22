"""Posts the daily run's summary to the Daily log (docs/PLAN.md, "Daily run", step 8).

  python3 -m smbot.summary

Reads the job results from environment variables set by daily.yml
(RESULT_<JOB>, VERSION, CHANNEL) and adds the Claude token usage.
"""

from __future__ import annotations

import datetime as dt
import os
import sys

from . import config as config_mod
from . import dailylog, gh, inbox, pacing, state

JOBS = {  # job id -> what it does, for the summary
    "intake": "Community intake",
    "build": "Build and smoke tests",
    "release": "Release",
    "pages": "Web build on GitHub Pages",
    "itch": "itch.io",
    "alarms": "Alarm checks",
}
ICONS = {"success": "✅", "failure": "❌", "cancelled": "⏹️", "skipped": "⏭️"}


def lines_for(env: dict[str, str], repo: str) -> list[str]:
    out = []
    version, channel = env.get("VERSION", ""), env.get("CHANNEL", "")
    if env.get("RESULT_RELEASE") == "success":
        out.append(f"Released [{version}](https://github.com/{repo}/releases/tag/{version}) as **{channel}**.")
    elif env.get("RESULT_BUILD") == "failure":
        out.append("**No release today: the build or a smoke test failed.** See the run's build-logs artifact.")
    for job, label in JOBS.items():
        result = env.get(f"RESULT_{job.upper()}", "skipped")
        if job == "itch" and result == "skipped":
            continue  # not set up yet
        if job == "intake" and env.get("INTAKE_COUNT") == "0":
            out.append(f"{ICONS['success']} {label}: no new posts")
            continue
        out.append(f"{ICONS.get(result, '•')} {label}: {result}")
    if env.get("RUN_URL"):
        out.append(f"[Workflow run]({env['RUN_URL']})")
    return out


def main() -> int:
    cfg = config_mod.load()
    env = dict(os.environ)
    lines = lines_for(env, cfg.repo)
    st, _ = state.load(cfg)
    lines.append(pacing.usage_line(st, dt.datetime.now(dt.timezone.utc)))
    try:
        waiting = inbox.reminder(cfg)
    except gh.GhError:
        waiting = ""
    if waiting:
        lines.append(waiting)
    failed = any(env.get(f"RESULT_{job.upper()}") == "failure" for job in JOBS)
    dailylog.post(cfg, "Daily run", lines, mention_owner=failed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
