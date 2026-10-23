"""Posts the daily run's summary to the Daily log (docs/PLAN.md, "Daily run", step 4).

  python3 -m smbot.summary

Reads the job results from environment variables set by daily.yml
(RESULT_<JOB>, VERSION, CHANNEL) and adds the Claude token usage. With BUILD_LOGS (the
build's logs folder) it also quotes the stress and timing results, BENCH lines included, so
development sessions (which can't read CI logs) and the owner find the numbers in the log.
"""

from __future__ import annotations

import datetime as dt
import html
import os
import re
import sys
from pathlib import Path

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
        if job == "intake" and env.get("INTAKE_STATUS") not in (None, "", "ok"):
            result = f"failure (Claude: {env['INTAKE_STATUS']})"
        out.append(f"{ICONS.get(result.split(' ')[0], '•')} {label}: {result}")
    if env.get("RUN_URL"):
        out.append(f"[Workflow run]({env['RUN_URL']})")
    return out


def bench_logs(runs: tuple[config_mod.Run, ...]) -> dict[str, str]:
    """build/logs name -> what ran, for the game's runs that print BENCH lines (tests/exported_runs.json)."""
    runs = tuple(r for r in runs if r.bench)
    return {**{f"{r.name}-linux": f"Linux Test, {r.label}" for r in runs},
            **{f"{r.name}-web": f"Web Test (WASM), {r.label}" for r in runs}}


BENCH_LINE = re.compile(r"BENCH|(STRESS|TIMING|WEB SMOKE) (OK|FAILED)|FAILED|::error::")
MAX_BENCH_LINES = 40  # per log; 4 logs of at most 40 lines of 300 characters fit in a comment


def bench_line(runs: tuple[config_mod.Run, ...], logs: Path) -> str:
    """The stress and timing results from the build's logs, as one collapsed Daily log line; "" if none ran."""
    out: list[str] = []
    for name, label in bench_logs(runs).items():
        try:
            text = (logs / f"{name}.log").read_text(errors="replace")
        except OSError:
            continue
        found = [re.sub(r"^console\.[a-z]+: ", "", line.strip())[:300]
                 for line in text.splitlines() if BENCH_LINE.search(line)][-MAX_BENCH_LINES:]
        out.append(f"<b>{label}</b>")
        out += [html.escape(line, quote=False) for line in found] or ["(no result lines)"]
    if not out:
        return ""
    return ("<details><summary>Stress and timing results (BENCH lines)</summary>"
            + "<br>".join(out) + "</details>")


def parked_lines(st: dict, now: dt.datetime) -> list[str]:
    """Every task that is set aside now: why, until when, and how to bring it back."""
    out = []
    for task, entry in sorted(st.get("task_failures", {}).items(), key=lambda kv: kv[1].get("parked_until", "")):
        until = entry.get("parked_until")
        if not until or pacing.parse_time(until) <= now:
            continue
        title = (re.match(r"\*\*(.+?)\*\*", task) or re.match(r"(.{1,80})", task)).group(1).rstrip(".")
        where = f" (#{entry['pr']}: `/retry` there brings it back)" if entry.get("pr") else ""
        out.append(f"Parked until {until[:16].replace('T', ' ')} UTC: {title}{where}. "
                   f"Why: {dailylog.shorten(entry.get('parked_reason', ''), 160)}")
    return out


def main() -> int:
    cfg = config_mod.load()
    env = dict(os.environ)
    lines = lines_for(env, cfg.repo)
    st, _ = state.load(cfg)
    now = dt.datetime.now(dt.timezone.utc)
    lines.append(pacing.usage_line(st, now))
    lines += parked_lines(st, now)
    if env.get("BUILD_LOGS"):
        try:
            runs = config_mod.load_runs()[1]
        except (OSError, ValueError) as e:  # the build has failed on it already; say so, post the rest
            runs = ()
            lines.append(f"⚠️ {e}")
        lines.append(bench_line(runs, Path(env["BUILD_LOGS"])))
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
