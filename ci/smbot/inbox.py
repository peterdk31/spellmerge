"""The owner inbox: questions only the owner can answer, as labelled issues.

  python3 -m smbot.inbox ask        opens the questions in $RESULT (a session's structured output)
  python3 -m smbot.inbox reminder   prints the Daily log line listing the open questions

A session that needs the owner puts the question in `owner_questions` instead of a file.
Each becomes an issue labelled `owner-question` that mentions the owner, with the options,
Claude's recommendation and what happens meanwhile. The owner answers with `/claude <answer>`
in the issue (a verified owner command); the next session carries it out and its PR closes
the issue. A question whose answer needs an owner-only change (`.github/`, `ci/`, ...) also
gets `owner-change` and the exact change, so an interactive session can apply it.
"""

from __future__ import annotations

import json
import os
import re
import sys
from typing import Any

from . import config as config_mod
from . import dailylog, gh

LABEL = "owner-question"
CHANGE_LABEL = "owner-change"
LABELS = {LABEL: ("d93f0b", "A question only the owner can answer; reply with /claude <answer>"),
          CHANGE_LABEL: ("b60205", "The answer needs an owner-only change; the issue has the exact change")}
MAX_PER_SESSION = 3


def _inert(text: str, limit: int) -> str:
    """Claude's text, with no @mentions (only the script mentions the owner)."""
    return re.sub(r"@(?=[\w-])", "@​", str(text or "").strip())[:limit]


def render(cfg: config_mod.Config, q: dict[str, Any], source: str = "") -> str:
    parts = [f"@{cfg.owner.login}, the bot needs your decision.", "", "## Question", "", _inert(q["question"], 4000)]
    options = [o for o in q.get("options") or [] if str(o).strip()][:6]
    if options:
        parts += ["", "## Options", ""] + [f"{i + 1}. {_inert(o, 1000)}" for i, o in enumerate(options)]
    parts += ["", "## Recommendation", "", _inert(q["recommendation"], 2000),
              "", "## Until you answer", "", _inert(q["meanwhile"], 1000)]
    if q.get("owner_change"):
        parts += ["", "## The change (owner-only path)", "",
                  "The bot can't make this change itself. An interactive Claude session can apply it: "
                  "\"do issue #<this issue>\".", ""]
        if q.get("change"):
            parts += ["```", _inert(q["change"], 8000).replace("```", "'''"), "```"]
    parts += ["", "---", "**To answer:** comment `/claude <your answer>` here, for example `/claude option 1`. "
              "The next development session carries it out, and its PR closes this issue."]
    if source:
        parts.append(f"Raised by {source}.")
    return "\n".join(parts)


def open_questions(cfg: config_mod.Config) -> list[dict[str, Any]]:
    return gh.api(f"repos/{cfg.repo}/issues?state=open&labels={LABEL}&per_page=100")


def _ensure_labels(cfg: config_mod.Config) -> None:
    for name, (color, description) in LABELS.items():
        try:
            gh.api(f"repos/{cfg.repo}/labels", "-X", "POST",
                   input={"name": name, "color": color, "description": description})
        except gh.GhError:
            pass  # it exists already


def ask(cfg: config_mod.Config, questions: list[dict[str, Any]], source: str = "") -> list[str]:
    """Opens an issue per new question; a question already open under the same title is skipped."""
    questions = [q for q in questions if q.get("title") and q.get("question")][:MAX_PER_SESSION]
    if not questions:
        return []
    _ensure_labels(cfg)
    known = {i["title"].strip().lower() for i in open_questions(cfg)}
    log = []
    for q in questions:
        title = _inert(q["title"], 120)
        if title.strip().lower() in known:
            continue
        labels = [LABEL] + ([CHANGE_LABEL] if q.get("owner_change") else [])
        created = gh.api(f"repos/{cfg.repo}/issues", "-X", "POST",
                         input={"title": title, "body": render(cfg, q, source), "labels": labels})
        known.add(title.strip().lower())
        log.append(f"Question for the owner: #{created['number']} {title}")
    return log


def reminder(cfg: config_mod.Config) -> str:
    """e.g. 'Waiting for you: #61 Allow X, #62 Pick Y' (empty when the inbox is empty)."""
    issues = sorted(open_questions(cfg), key=lambda i: i["number"])
    if not issues:
        return ""
    return "**Waiting for you:** " + ", ".join(f"#{i['number']} {i['title']}" for i in issues[:10])


def main(argv: list[str] | None = None) -> int:
    cmd = (argv or sys.argv[1:] or [""])[0]
    cfg = config_mod.load()
    if cmd == "ask":
        result = json.loads(os.environ.get("RESULT") or "{}")
        log = ask(cfg, result.get("owner_questions") or [], os.environ.get("SOURCE", ""))
        print("\n".join(log) or "no new questions for the owner")
        if log:
            dailylog.post(cfg, "Questions for the owner", log)
    elif cmd == "reminder":
        print(reminder(cfg))
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
