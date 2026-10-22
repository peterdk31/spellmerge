"""The owner inbox: questions only the owner can answer, as labelled issues.

  python3 -m smbot.inbox ask        opens the questions in $RESULT (a session's structured output)
  python3 -m smbot.inbox reminder   prints the Daily log line listing the open questions

A session that needs the owner puts the question in `owner_questions` instead of a file.
Each becomes an issue labelled `owner-question` that mentions the owner, with the options,
Claude's recommendation and what happens meanwhile. A question that is already open, or
was closed in the last 30 days, under the same `key` or a similar title is not asked again. The owner answers with `/claude <answer>`
in the issue (a verified owner command); the next session carries it out and its PR closes
the issue. A question whose answer needs an owner-only change (`.github/`, `ci/`, ...) also
gets `owner-change` and the exact change, so an interactive session can apply it.
"""

from __future__ import annotations

import datetime as dt
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
RECENT_DAYS = 30  # a question closed this recently is not asked again
SIMILAR = 0.6  # share of title words two questions must have in common to be the same one
CONTAINED = 0.85  # or the share of the shorter title's words found in the longer one
_KEY_MARKER = re.compile(r"<!-- smbot:question key=([a-z0-9-]*) -->")
_STOP = {"a", "an", "the", "to", "of", "and", "or", "in", "on", "for", "it", "is", "be", "should", "we",
         "do", "does", "make", "add", "also", "once", "with", "this", "that"}


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
    parts.append(f"<!-- smbot:question key={_key(q.get('key', ''))} -->")
    return "\n".join(parts)


def open_questions(cfg: config_mod.Config) -> list[dict[str, Any]]:
    return gh.api(f"repos/{cfg.repo}/issues?state=open&labels={LABEL}&per_page=100")


def recent_questions(cfg: config_mod.Config, now: dt.datetime) -> list[dict[str, Any]]:
    """Open questions plus those closed in the last RECENT_DAYS (answered or dropped)."""
    since = (now - dt.timedelta(days=RECENT_DAYS)).strftime("%Y-%m-%dT%H:%M:%SZ")
    closed = gh.api(f"repos/{cfg.repo}/issues?state=closed&labels={LABEL}&since={since}&per_page=100")
    return open_questions(cfg) + [i for i in closed if (i.get("closed_at") or "") >= since]


def _key(text: str) -> str:
    return "-".join(re.sub(r"[^a-z0-9]+", " ", str(text or "").lower()).split())[:80]


def _words(title: str) -> set[str]:
    return {w for w in re.sub(r"[^a-z0-9]+", " ", title.lower()).split() if w not in _STOP}


def key_of(issue: dict[str, Any]) -> str:
    m = _KEY_MARKER.search(issue.get("body") or "")
    return m.group(1) if m else ""


def same_question(q: dict[str, Any], issue: dict[str, Any]) -> bool:
    """The same key, or titles that share most of their words (sessions reword the same question)."""
    key = _key(q.get("key", ""))
    if key and key == key_of(issue):
        return True
    a, b = _words(q["title"]), _words(issue["title"])
    if not (a and b):
        return False
    shared = len(a & b)
    # Most words in common, or one title is the other with a few words added.
    return shared / len(a | b) >= SIMILAR or (min(len(a), len(b)) >= 3 and shared / min(len(a), len(b)) >= CONTAINED)


def _ensure_labels(cfg: config_mod.Config) -> None:
    for name, (color, description) in LABELS.items():
        try:
            gh.api(f"repos/{cfg.repo}/labels", "-X", "POST",
                   input={"name": name, "color": color, "description": description})
        except gh.GhError:
            pass  # it exists already


def ask(cfg: config_mod.Config, questions: list[dict[str, Any]], source: str = "",
        now: dt.datetime | None = None) -> list[str]:
    """Opens an issue per new question.

    A question is new unless an open question, or one closed in the last RECENT_DAYS, has the
    same key or a similar title: then it's only noted in the log, never asked again.
    """
    questions = [q for q in questions if q.get("title") and q.get("question")][:MAX_PER_SESSION]
    if not questions:
        return []
    _ensure_labels(cfg)
    known = recent_questions(cfg, now or dt.datetime.now(dt.timezone.utc))
    log = []
    for q in questions:
        title = _inert(q["title"], 120)
        q = {**q, "title": title}
        twin = next((i for i in known if same_question(q, i)), None)
        if twin:
            state = "open" if twin.get("state") == "open" else "answered or closed"
            log.append(f"Not asked again: \"{title}\" is #{twin['number']} ({state})")
            continue
        labels = [LABEL] + ([CHANGE_LABEL] if q.get("owner_change") else [])
        created = gh.api(f"repos/{cfg.repo}/issues", "-X", "POST",
                         input={"title": title, "body": render(cfg, q, source), "labels": labels})
        known.append({"number": created["number"], "title": title, "state": "open",
                      "body": f"<!-- smbot:question key={_key(q.get('key', ''))} -->"})
        log.append(f"Question for the owner: #{created['number']} {title}")
    return log


def reminder(cfg: config_mod.Config) -> str:
    """e.g. 'Waiting for you: #61 Allow X, #62 Pick Y' (empty when the inbox is empty)."""
    checkpoints = gh.api(f"repos/{cfg.repo}/issues?state=open&labels=checkpoint&per_page=20")
    issues = sorted(open_questions(cfg) + checkpoints, key=lambda i: i["number"])
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
