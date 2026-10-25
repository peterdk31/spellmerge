"""The gate every run passes first (docs/PLAN.md, "Owner control from the phone").

  python3 -m smbot.control [--commands]

1. Kill switch: the AUTOMATION_ENABLED repository variable must be "true".
2. Control panel: read from the owner's verified revisions (smbot.panel);
   changes since the last run are written to the Daily log.
3. Owner commands (with --commands): carried out or queued (smbot.commands).
4. Decides what this run may do and writes it to $GITHUB_OUTPUT:
   automation, develop, mode, merge, focus, next_task, and reasons.
   With nothing in the queue the session plans (mode plan) instead of
   stopping. The one wait is a milestone checkpoint (smbot.checkpoint): while
   its issue is unanswered only scheduled issues and the weekly planning run
   (which won't start the next milestone), and the owner's answer starts a
   planning session at once.

Needs GH_TOKEN with issues read; --commands and Daily log posts need the bot
app's token (Contents, Issues and Pull requests write).
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path
from zoneinfo import ZoneInfo

from . import checkpoint, commands, dailylog, gh, inbox, intake, nexttask, pacing, panel, stale, state
from . import config as config_mod


NEXT = Path("docs/NEXT.md")
PLAN_COOLDOWN = dt.timedelta(hours=3)  # an empty queue runs planning at most this often
WEEKLY_AT = (6, 6)  # the weekly planning is due from Sunday (weekday 6) 06:00 UTC


@dataclass
class Decision:
    automation: bool
    develop: bool
    merge: bool
    reasons: list[str] = field(default_factory=list)
    mode: str = "develop"  # develop, or plan
    weekly: bool = False  # the Sunday planning (devlog and playtest too)
    wake_at: str = ""  # when the bot should look again by itself (a usage limit or a cooldown)


def in_quiet_hours(quiet: tuple[int, int] | None, now: dt.datetime, tz: str) -> bool:
    if quiet is None:
        return False
    hour = now.astimezone(ZoneInfo(tz)).hour
    start, end = quiet
    return start <= hour < end if start < end else hour >= start or hour < end


def weekly_due_since(now: dt.datetime) -> dt.datetime:
    """The latest Sunday 06:00 UTC at or before now."""
    day, hour = WEEKLY_AT
    due = (now - dt.timedelta(days=(now.weekday() - day) % 7)).replace(hour=hour, minute=0, second=0, microsecond=0)
    return due if due <= now else due - dt.timedelta(days=7)


def decide(kill_switch_on: bool, result: panel.PanelResult, st: dict, now: dt.datetime, tz: str,
           has_task: bool, checkpoint_issue: int | None = None) -> Decision:
    """What this run may do. `has_task` already leaves out milestone work while a checkpoint waits."""
    s = result.settings
    reasons: list[str] = []
    if not kill_switch_on:
        return Decision(False, False, False, ["kill switch: AUTOMATION_ENABLED is not true"])
    if not result.verified:
        return Decision(False, False, False, ["Control panel not verified"])
    if not s.automation_enabled:
        return Decision(False, False, False, ["Control panel: automation disabled"])

    develop = merge = True
    if st.get("paused_by_command"):
        develop = merge = False
        reasons.append("paused by the owner's /pause")
    if s.pause_development:
        develop = False
        reasons.append("Control panel: development paused")
    if s.pause_merging:
        merge = False
        reasons.append("Control panel: PR merging paused")
    if develop and in_quiet_hours(s.quiet_hours, now, tz):
        develop = False
        reasons.append(f"quiet hours {panel.describe('quiet_hours', s.quiet_hours)} ({tz})")
    if develop and (until := pacing.backing_off_until(st, now)):
        return Decision(True, False, merge, reasons + [f"backing off after a usage limit until {until}"],
                        wake_at=until)
    if develop and st.get("errors_in_a_row", 0) >= state.MAX_ERRORS_IN_A_ROW:
        develop = False
        reasons.append(f"stopped after {st['errors_in_a_row']} errors in a row; comment /resume to try again")
    if not develop:
        return Decision(True, False, merge, reasons)

    last = pacing.parse_time(st["last_plan"]) if st.get("last_plan") else None
    cooled = last + PLAN_COOLDOWN if last else None
    weekly = st.get("last_weekly")
    answer = checkpoint.answer(st, checkpoint_issue)
    if weekly and pacing.parse_time(weekly) < weekly_due_since(now) and not st.get("pending_instructions"):
        return Decision(True, True, merge, reasons + ["the weekly planning is due"], "plan", weekly=True)
    if answer and not (last and last > pacing.parse_time(answer["at"]) and now < cooled):
        return Decision(True, True, merge,
                        reasons + [f"carrying out your answer to checkpoint #{checkpoint_issue} ({answer['verdict']})"],
                        "plan")
    if has_task or st.get("pending_instructions"):
        return Decision(True, True, merge, reasons)
    if checkpoint_issue and not answer:
        return Decision(True, False, merge, reasons + [
            f"waiting for your answer to checkpoint #{checkpoint_issue} (/go, /iterate or /pivot)"])
    if st.get("idle") and not answer:
        return Decision(True, False, merge, reasons + [
            f"idle since {st['idle']}: planning found nothing to do; new work or Sunday's planning restarts it"])
    if cooled and now < cooled:
        return Decision(True, False, merge, reasons + [f"planning ran at {st['last_plan']}; it plans again after "
                                                       f"{pacing.iso(cooled)}"], wake_at=pacing.iso(cooled))
    return Decision(True, True, merge, reasons + ["the queue is empty, so this session plans the next tasks"], "plan")


def write_outputs(values: dict[str, str]) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    for key, value in values.items():
        print(f"{key}: {value}")
    if path:
        with open(path, "a") as fh:
            for key, value in values.items():
                fh.write(f"{key}<<__END__\n{value}\n__END__\n")


def open_tasks(cfg: config_mod.Config, st: dict) -> set[str]:
    """The tasks still to do. Raises when GitHub or docs/NEXT.md can't be read, so nothing is judged gone by mistake."""
    if not NEXT.exists():
        raise FileNotFoundError(NEXT)
    return nexttask.open_tasks(NEXT, first=intake.queue_tasks(cfg, st, strict=True))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--commands", action="store_true", help="carry out owner commands (needs the app token)")
    ap.add_argument("--log-title", default="Hourly check")
    args = ap.parse_args(argv)

    cfg = config_mod.load()
    now = dt.datetime.now(dt.timezone.utc)
    kill_switch_on = os.environ.get("AUTOMATION_ENABLED") == "true"
    log: list[str] = []
    mention = False

    result = panel.read(cfg) if kill_switch_on else panel.PanelResult(panel.FAIL_CLOSED, False)
    st, _ = state.load(cfg)

    if kill_switch_on:
        new_problems = [p for p in result.problems if p not in (st.get("panel_problems") or [])]
        if new_problems:
            log += new_problems
            mention = True
        if result.verified:
            log += panel.changes(st.get("panel_applied"), result.settings, cfg.owner.login)
        effects = commands.Effects([], None, [])
        forget: list[str] = []
        if args.commands and result.verified and result.settings.automation_enabled:
            cmd_log, effects = commands.run(cfg, set(st["processed_comments"]), now, os.environ["GH_TOKEN"], st,
                                            lambda: open_tasks(cfg, st))
            log += cmd_log
            if not st.get("paused_by_command") and not effects.paused:
                try:
                    stale_log, forget = stale.sweep(cfg, st, open_tasks(cfg, st))
                    log += stale_log
                except (gh.GhError, FileNotFoundError):
                    pass  # an unreadable queue is no reason to close anything; the next check tries again

        def apply(s: dict) -> None:
            s["panel_problems"] = result.problems
            if result.verified:
                s["panel_applied"] = panel.to_json(result.settings)
            effects.apply(s)
            for task in forget:
                s.get("task_failures", {}).pop(task, None)
        changed = (st.get("panel_problems") != result.problems or effects.processed or forget
                   or not st.get("last_weekly") or (result.verified and st.get("panel_applied") != panel.to_json(result.settings)))

        def apply_all(s: dict) -> None:
            apply(s)
            s.setdefault("last_weekly", None)
            s["last_weekly"] = s["last_weekly"] or pacing.iso(now)  # the first weekly planning is next Sunday
        if changed:
            st = state.update(cfg, apply_all, "control: panel and owner commands")

    try:
        open_checkpoint = checkpoint.open_issue(cfg)
    except gh.GhError:
        open_checkpoint = None
    # While a checkpoint waits for the owner, only scheduled issues (fixes from players) run.
    milestone_work = not open_checkpoint or checkpoint.answer(st, open_checkpoint) is not None
    task = nexttask.next_task(skip=nexttask.parked(st, now), first=intake.queue_tasks(cfg, st),
                              milestone=milestone_work, answered=inbox.answered_keys(cfg, st))
    decision = decide(kill_switch_on, result, st, now, cfg.timezone, task is not None, open_checkpoint)
    if log:
        dailylog.post(cfg, args.log_title, log, mention_owner=mention)

    write_outputs({
        "automation": str(decision.automation).lower(),
        "develop": str(decision.develop).lower(),
        "mode": decision.mode,
        "weekly": str(decision.weekly).lower(),
        "merge": str(decision.merge).lower(),
        "focus": result.settings.focus,
        "next_task": task or "",
        "reasons": "; ".join(decision.reasons) or "none",
        # When set, the workflow starts resume.yml, which starts develop again at that time.
        "wake_at": decision.wake_at,
    })
    return 0


if __name__ == "__main__":
    sys.exit(main())
