"""Automation state: a JSON file on the automation-state branch.

Holds pacing data (token usage, back-off), processed owner
commands, alarm issues and the last applied Control panel values. It is only
ever trusted for pacing and bookkeeping, never for security decisions: those
come from the Control panel's edit history and ci/config.json.

Writes use the file's blob SHA, so two runs can't silently overwrite each other;
update() re-reads and retries on a conflict.
"""

from __future__ import annotations

import base64
import copy
import json
from typing import Any, Callable

from . import config as config_mod
from . import gh

PATH = "state.json"

DEFAULT: dict[str, Any] = {
    "version": 1,
    "paused_by_command": False,
    "backoff_until": None,
    "usage": [],  # [{"at": iso, "tokens": n, "kind": "dev" | "review" | "intake" | "plan"}]
    "processed_comments": [],
    "pending_instructions": [],  # verified owner instructions for Claude
    "panel_applied": None,
    "panel_problems": [],
    "alarms": {},  # alarm name -> issue number
    "automation_started": None,  # when the alarms first ran (the stall alarm's starting point)
    "task_failures": {},  # task -> failed reviews, its PR, the review's problems, parked_until and why
    "last_own_merge": None,
    "last_plan": None,  # when the last planning session finished
    "last_weekly": None,  # when the last weekly planning finished (smbot.control starts the next one)
    "errors_in_a_row": 0,  # sessions that ended in an error since the last one that made progress
    "idle": None,  # when planning last found nothing to do; cleared by the next progress
    "checkpoint_answers": {},  # checkpoint issue number -> the owner's verified /go, /iterate or /pivot
    "intake_tasks": {},  # issue number -> the intake's neutral task for it (smbot.intake)
    "cla_signatures": {},  # "user_id:version" -> a contributor's CLA signature and its comment (smbot.contrib)
}

MAX_PROCESSED = 1000
MAX_ERRORS_IN_A_ROW = 3  # sessions ending in an error are retried this often; then development stops


def _url(cfg: config_mod.Config) -> str:
    return f"repos/{cfg.repo}/contents/{PATH}"


def load(cfg: config_mod.Config) -> tuple[dict[str, Any], str | None]:
    """The state and its blob SHA (None if the file doesn't exist yet)."""
    try:
        data = gh.api(f"{_url(cfg)}?ref={cfg.state_branch}")
    except gh.GhError as e:
        if "404" in str(e) or "Not Found" in str(e):
            return copy.deepcopy(DEFAULT), None
        raise
    state = json.loads(base64.b64decode(data["content"]))
    merged = copy.deepcopy(DEFAULT)
    merged.update(state)
    return merged, data["sha"]


def save(cfg: config_mod.Config, state: dict[str, Any], sha: str | None, message: str) -> str:
    state["processed_comments"] = state["processed_comments"][-MAX_PROCESSED:]
    body = {
        "message": message,
        "content": base64.b64encode((json.dumps(state, indent=2, sort_keys=True) + "\n").encode()).decode(),
        "branch": cfg.state_branch,
    }
    if sha:
        body["sha"] = sha
    result = gh.api(_url(cfg), "-X", "PUT", input=body)
    return result["content"]["sha"]


def update(cfg: config_mod.Config, change: Callable[[dict[str, Any]], None], message: str, attempts: int = 5) -> dict:
    """Applies change() to the latest state and saves it, retrying on conflicts."""
    for attempt in range(attempts):
        state, sha = load(cfg)
        change(state)
        try:
            save(cfg, state, sha, message)
            return state
        except gh.GhError as e:
            if attempt == attempts - 1 or not any(code in str(e) for code in ("409", "422")):
                raise
    raise AssertionError("unreachable")
