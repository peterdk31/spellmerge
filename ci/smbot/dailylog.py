"""Posts to the pinned Daily log issue (docs/PLAN.md, "Kill switch").

Every bot action is written here, so the owner can follow everything from the
GitHub app's notifications.
"""

from __future__ import annotations

import datetime as dt

from . import config as config_mod
from . import gh


def post(cfg: config_mod.Config, title: str, lines: list[str], mention_owner: bool = False) -> None:
    if not lines:
        return
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    body = f"**{title}** · {stamp}\n\n" + "\n".join(f"- {line}" for line in lines)
    if mention_owner:
        body += f"\n\n@{cfg.owner.login}, this needs your attention."
    gh.api(f"repos/{cfg.repo}/issues/{cfg.daily_log_issue}/comments", "-X", "POST", input={"body": body})
