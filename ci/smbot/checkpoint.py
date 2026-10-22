"""Milestone checkpoints: the one place development waits for the owner (docs/PLAN.md, "Go/no-go checkpoints").

When the planning session finds the current milestone done, its output has a `checkpoint`;
once that plan's PR merges, an issue labelled `checkpoint` asks the owner to decide:

  /go               start the next milestone
  /iterate <what>   rework parts of this milestone first
  /pivot <how>      change direction (the design, the scope, the core mechanic)

While a checkpoint issue is open and unanswered, no milestone work starts and planning
doesn't run; scheduled issues (bug fixes from players) still do. The answer is a verified
owner command (smbot.commands) stored in the state; the gate then starts a planning
session that carries it out, and that plan's PR closes the issue.
"""

from __future__ import annotations

from typing import Any

from . import config as config_mod
from . import labels as labels_mod
from . import gh

LABEL = "checkpoint"
VERDICTS = ("go", "iterate", "pivot")


def open_issue(cfg: config_mod.Config) -> int | None:
    """The open checkpoint issue, if any (the oldest, if there are several)."""
    issues = [i for i in gh.api(f"repos/{cfg.repo}/issues?state=open&labels={LABEL}&per_page=20")
              if "pull_request" not in i]
    return min((i["number"] for i in issues), default=None)


def answer(st: dict[str, Any], number: int | None) -> dict[str, Any] | None:
    return st.get("checkpoint_answers", {}).get(str(number)) if number else None


def record(st: dict[str, Any], number: int, verdict: str, text: str, url: str, at: str) -> None:
    st.setdefault("checkpoint_answers", {})[str(number)] = {"verdict": verdict, "text": text, "url": url, "at": at}


def body(cfg: config_mod.Config, cp: dict[str, Any], run_url: str = "") -> str:
    owner, name = cfg.repo.split("/")
    parts = [
        f"@{cfg.owner.login}, **{cp['milestone']} is done.** Development waits for your decision before the "
        "next milestone starts. Scheduled bug fixes keep going meanwhile.", "",
        f"**Play it:** https://{owner}.github.io/{name}/nightly/", "",
        "## What was built", "", cp.get("built", ""), "",
        "## What was cut or left open", "", cp.get("cut", "") or "Nothing.", "",
        "## Claude's assessment", "", cp.get("assessment", ""), "",
        "## The question", "", cp.get("question", "") or "Go on to the next milestone?", "",
        "## Recommendation", "", cp.get("recommendation", ""), "",
        "---",
        "**To answer**, comment one of these here:",
        "- `/go`: start the next milestone",
        "- `/iterate <what to rework>`: rework parts of this milestone first",
        "- `/pivot <the new direction>`: change the design, the scope or the core mechanic",
        "",
        "A planning session starts as soon as you answer, and its PR closes this issue.",
    ]
    if run_url:
        parts.append(f"Raised by [this run]({run_url}).")
    return "\n".join(parts)


def open_checkpoint(cfg: config_mod.Config, cp: dict[str, Any]) -> str:
    """Opens the checkpoint issue unless one is open already; returns a log line."""
    existing = open_issue(cfg)
    if existing:
        return f"Checkpoint already open: #{existing}"
    labels_mod.ensure(cfg, [LABEL])
    title = f"Checkpoint: {cp['milestone']} is done. Go, iterate or pivot?"[:120]
    created = gh.api(f"repos/{cfg.repo}/issues", "-X", "POST",
                     input={"title": title, "body": body(cfg, cp), "labels": [LABEL]})
    return f"Checkpoint: #{created['number']} {title} (development waits for your answer)"


def prompt_text(st: dict[str, Any], number: int | None) -> str:
    """What the planning session is told about the checkpoint."""
    if not number:
        return "(no checkpoint is open)"
    a = answer(st, number)
    if not a:
        return (f"Checkpoint issue #{number} is open and the owner hasn't answered yet. Don't start the next "
                "milestone and don't add its tasks; only reorder what is there and handle the scheduled issues.")
    what = {"go": "go: start the next milestone (step 5)",
            "iterate": "iterate: rework parts of the finished milestone before going on",
            "pivot": "pivot: change direction as the owner says"}[a["verdict"]]
    return (f"The owner answered checkpoint #{number} with **{what}**. Their words (verified owner command, "
            f"{a['url']}): {a['text'] or '(none)'}\n\nCarry it out in this session (see step 5) and put "
            f"`Closes #{number}` in `pr_body`.")
