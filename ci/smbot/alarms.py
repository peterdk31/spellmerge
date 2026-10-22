"""Alarms that email the owner (docs/PLAN.md, "Measurement and alarms").

  python3 -m smbot.alarms check          stall and inactivity alarms (daily run)
  python3 -m smbot.alarms token-failed   the Claude token was rejected
  python3 -m smbot.alarms token-ok       the Claude token works again

Each alarm is one issue that mentions the owner, so GitHub emails them. It is
opened once, kept while the problem lasts, and closed when it's resolved.
"""

from __future__ import annotations

import argparse
import datetime as dt
import subprocess
import sys

from . import config as config_mod
from . import dailylog, gh, nexttask, state
from .pacing import iso

STALL_DAYS = 3
INACTIVE_DAYS = 14

ALARMS = {
    "stall": ("Stall alarm: no own PR merged for 3 days",
              "Claude hasn't merged one of its own PRs for {days} days while `docs/NEXT.md` has tasks.\n\n"
              "Likely causes: the Claude token or usage limits, a task that keeps failing review, or a broken "
              "check. See the Daily log and the latest `develop` runs in the Actions tab."),
    "inactive": ("Inactivity alarm: no commit to main for 14 days",
                 "Nothing has been committed to `main` for {days} days. GitHub disables scheduled workflows in "
                 "public repositories after 60 days without activity, which would stop the daily releases.\n\n"
                 "Check the Daily log and the Actions tab."),
    "token": ("Claude token needs regenerating",
              "Claude's steps failed because the subscription token was rejected or has expired. Scripted merges, "
              "builds and releases keep running; development and PR rating are paused until it's fixed.\n\n"
              "**To fix:** run `claude setup-token`, then\n\n"
              "```sh\ngh secret set CLAUDE_CODE_OAUTH_TOKEN --env automation --repo {repo}\n```\n\n"
              "This issue closes by itself after the next successful Claude run."),
}


def raise_alarm(cfg: config_mod.Config, st: dict, name: str, **fmt: object) -> str | None:
    """Opens the alarm issue if it isn't open yet; returns a Daily log line."""
    number = st["alarms"].get(name)
    if number:
        issue = gh.api(f"repos/{cfg.repo}/issues/{number}")
        if issue["state"] == "open":
            return None
    title, body = ALARMS[name]
    created = gh.api(f"repos/{cfg.repo}/issues", "-X", "POST", input={
        "title": title,
        "body": body.format(repo=cfg.repo, **fmt) + f"\n\n@{cfg.owner.login}",
        "labels": ["alarm"],
    })
    st["alarms"][name] = created["number"]
    return f"Alarm raised: {title} (#{created['number']})"


def clear_alarm(cfg: config_mod.Config, st: dict, name: str) -> str | None:
    number = st["alarms"].pop(name, None)
    if not number:
        return None
    gh.api(f"repos/{cfg.repo}/issues/{number}/comments", "-X", "POST",
           input={"body": "Resolved, so this alarm closes automatically."})
    gh.api(f"repos/{cfg.repo}/issues/{number}", "-X", "PATCH", input={"state": "closed", "state_reason": "completed"})
    return f"Alarm cleared: #{number}"


def last_own_merge(cfg: config_mod.Config) -> dt.datetime | None:
    slug = cfg.bot.login.removesuffix("[bot]")
    found = gh.api(f"search/issues?q=repo:{cfg.repo}+is:pr+is:merged+author:app/{slug}&sort=updated&per_page=20")
    merged = [dt.datetime.fromisoformat(i["pull_request"]["merged_at"].replace("Z", "+00:00"))
              for i in found.get("items", []) if i.get("pull_request", {}).get("merged_at")]
    return max(merged) if merged else None


def last_main_commit() -> dt.datetime:
    out = subprocess.run(["git", "log", "-1", "--format=%cI", "origin/main"], check=True,
                         capture_output=True, text=True).stdout.strip()
    return dt.datetime.fromisoformat(out)


def check(cfg: config_mod.Config, st: dict, now: dt.datetime, has_task: bool, main_commit: dt.datetime,
          own_merge: dt.datetime | None, automation_started: dt.datetime) -> list[str]:
    log = []
    # Sessions record their merges in the state too, so one empty search can't raise the alarm.
    saved = st.get("last_own_merge")
    merges = [d for d in (own_merge, saved and dt.datetime.fromisoformat(saved.replace("Z", "+00:00"))) if d]
    reference = max(merges) if merges else automation_started
    if has_task and now - reference > dt.timedelta(days=STALL_DAYS):
        log.append(raise_alarm(cfg, st, "stall", days=(now - reference).days))
    else:
        log.append(clear_alarm(cfg, st, "stall"))
    if now - main_commit > dt.timedelta(days=INACTIVE_DAYS):
        log.append(raise_alarm(cfg, st, "inactive", days=(now - main_commit).days))
    else:
        log.append(clear_alarm(cfg, st, "inactive"))
    if merges:
        st["last_own_merge"] = iso(max(merges))
    return [line for line in log if line]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("action", choices=("check", "token-failed", "token-ok"))
    args = ap.parse_args(argv)
    cfg = config_mod.load()
    now = dt.datetime.now(dt.timezone.utc)
    log: list[str] = []

    # Alarms change issues, so they run once and only their bookkeeping is retried.
    st, _ = state.load(cfg)
    if args.action == "check":
        started = st.setdefault("automation_started", iso(now))
        log = check(cfg, st, now, nexttask.next_task(skip=nexttask.parked(st, now)) is not None, last_main_commit(), last_own_merge(cfg),
                    dt.datetime.fromisoformat(started.replace("Z", "+00:00")))
    elif args.action == "token-failed":
        log = [line for line in [raise_alarm(cfg, st, "token")] if line]
    else:
        log = [line for line in [clear_alarm(cfg, st, "token")] if line]

    alarms, last_merge, started = st["alarms"], st.get("last_own_merge"), st.get("automation_started")

    def apply(s: dict) -> None:
        s["alarms"] = alarms
        s["last_own_merge"] = last_merge
        if started:
            s["automation_started"] = started
    state.update(cfg, apply, f"alarms: {args.action}")
    for line in log:
        print(line)
    dailylog.post(cfg, "Alarms", log, mention_owner=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
