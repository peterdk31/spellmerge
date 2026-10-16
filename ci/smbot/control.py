"""The gate every run passes first (docs/PLAN.md, "Owner control from the phone").

  python3 -m smbot.control [--commands]

1. Kill switch: the AUTOMATION_ENABLED repository variable must be "true".
2. Control panel: read from the owner's verified revisions (smbot.panel);
   changes since the last run are written to the Daily log.
3. Owner commands (with --commands): carried out or queued (smbot.commands).
4. Decides what this run may do and writes it to $GITHUB_OUTPUT:
   automation, develop, merge, focus, next_task, and reasons.

Needs GH_TOKEN with issues read; --commands and Daily log posts need the bot
app's token (Contents, Issues and Pull requests write).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from dataclasses import dataclass, field
from zoneinfo import ZoneInfo

from . import commands, dailylog, nexttask, pacing, panel, state
from . import config as config_mod


@dataclass
class Decision:
    automation: bool
    develop: bool
    merge: bool
    reasons: list[str] = field(default_factory=list)


def in_quiet_hours(quiet: tuple[int, int] | None, now: dt.datetime, tz: str) -> bool:
    if quiet is None:
        return False
    hour = now.astimezone(ZoneInfo(tz)).hour
    start, end = quiet
    return start <= hour < end if start < end else hour >= start or hour < end


def decide(kill_switch_on: bool, result: panel.PanelResult, st: dict, now: dt.datetime, tz: str,
           has_task: bool) -> Decision:
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
    if develop:
        b = pacing.budget(st, now, s.dev_intensity, s.weekly_share)
        if not b.allowed:
            develop = False
            reasons.append(b.reason)
    if develop and not has_task and not st.get("pending_instructions"):
        develop = False
        reasons.append("no task in docs/NEXT.md and no owner instructions")
    return Decision(True, develop, merge, reasons)


def write_outputs(values: dict[str, str]) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    for key, value in values.items():
        print(f"{key}: {value}")
    if path:
        with open(path, "a") as fh:
            for key, value in values.items():
                fh.write(f"{key}<<__END__\n{value}\n__END__\n")


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
        if args.commands and result.verified and result.settings.automation_enabled:
            cmd_log, effects = commands.run(cfg, set(st["processed_comments"]), now, os.environ["GH_TOKEN"])
            log += cmd_log

        def apply(s: dict) -> None:
            s["panel_problems"] = result.problems
            if result.verified:
                s["panel_applied"] = panel.to_json(result.settings)
            effects.apply(s)
        st = state.update(cfg, apply, "control: panel and owner commands")

    task = nexttask.next_task()
    decision = decide(kill_switch_on, result, st, now, cfg.timezone, task is not None)
    if log:
        dailylog.post(cfg, args.log_title, log, mention_owner=mention)

    write_outputs({
        "automation": str(decision.automation).lower(),
        "develop": str(decision.develop).lower(),
        "merge": str(decision.merge).lower(),
        "focus": result.settings.focus,
        "next_task": task or "",
        "reasons": "; ".join(decision.reasons) or "none",
        "settings": json.dumps(panel.to_json(result.settings)),
    })
    return 0


if __name__ == "__main__":
    sys.exit(main())
