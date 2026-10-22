"""The owner inbox: questions only the owner can answer, as labelled issues.

  python3 -m smbot.inbox ask        opens the questions in $RESULT (a session's structured output),
                                    with the screenshots in $SHOTS (taken on $SHA) and those of PR $PR

A session that needs the owner puts the question in `owner_questions` instead of a file.
Each becomes an issue labelled `owner-question` that mentions the owner, with the options,
Claude's recommendation and what happens meanwhile. A question that is already open, or
was closed in the last 30 days, under the same `key` or a similar title is not asked again. The owner answers with `/claude <answer>`
in the issue (a verified owner command); the next session carries it out and its PR closes
the issue. A question whose answer needs an owner-only change (`.github/`, `ci/`, ...) also
gets `owner-change` and the exact change, so an interactive session can apply it.

A question shows what it's about: the shots it names (`screenshots`), or else the screenshots
of the PR it was raised in. That's why questions are asked after the screenshots are taken,
not when the PR opens: the notification the owner gets carries them.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable

from . import config as config_mod
from . import labels as labels_mod
from . import dailylog, gh, screenshots

LABEL = "owner-question"
CHANGE_LABEL = "owner-change"
MAX_PER_SESSION = 3
RECENT_DAYS = 30  # a question closed this recently is not asked again
SIMILAR = 0.75  # share of title words two questions must have in common to be the same one
CONTAINED = 0.85  # or the share of the shorter title's words found in the longer one
_KEY_MARKER = re.compile(r"<!-- smbot:question key=([a-z0-9-]*) -->")
_STOP = {"a", "an", "the", "to", "of", "and", "or", "in", "on", "for", "it", "is", "be", "should", "we",
         "do", "does", "make", "add", "also", "once", "with", "this", "that"}


def _inert(text: str, limit: int) -> str:
    """Claude's text, with no @mentions (only the script mentions the owner)."""
    return re.sub(r"@(?=[\w-])", "@​", str(text or "").strip())[:limit]


MAX_PICTURES = 30_000  # characters of image markdown; an issue body holds 65,536


def render(cfg: config_mod.Config, q: dict[str, Any], source: str = "", pr: int | None = None,
           pictures: str = "") -> str:
    parts = [f"@{cfg.owner.login}, the bot needs your decision.", "", "## Question", "", _inert(q["question"], 4000)]
    if pictures:  # made by smbot.screenshots, captions already inert
        parts += ["", "## What it looks like", "", pictures[:MAX_PICTURES]]
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
        parts.append(f"Raised by {source}" + (f", in PR #{pr}." if pr and f"#{pr}" not in source else "."))
    parts.append(f"<!-- smbot:question key={_key(q.get('key', ''))} -->")
    return "\n".join(parts)


def open_questions(cfg: config_mod.Config) -> list[dict[str, Any]]:
    return gh.api(f"repos/{cfg.repo}/issues?state=open&labels={LABEL}&per_page=100")


def recent_questions(cfg: config_mod.Config, now: dt.datetime) -> list[dict[str, Any]]:
    """Open questions plus those closed in the last RECENT_DAYS (answered or dropped)."""
    since = (now - dt.timedelta(days=RECENT_DAYS)).strftime("%Y-%m-%dT%H:%M:%SZ")
    closed = gh.api(f"repos/{cfg.repo}/issues?state=closed&labels={LABEL}&since={since}&per_page=100")
    return open_questions(cfg) + [i for i in closed if (i.get("closed_at") or "") >= since]


def answered_keys(cfg: config_mod.Config, st: dict[str, Any]) -> set[str]:
    """Keys of the owner questions that are answered, so the tasks blocked on them can go again.

    A question is answered once it's closed (its PR merged, or the owner closed it), or while it's
    open with an owner `/claude` answer waiting in the state. A key that still has an open,
    unanswered question isn't answered, even if a duplicate of it was closed. When GitHub can't be
    read nothing counts as answered, which is how it was before.
    """
    try:
        open_ = open_questions(cfg)
        closed = gh.api(f"repos/{cfg.repo}/issues?state=closed&labels={LABEL}&per_page=100")
    except gh.GhError:
        return set()
    replied = {int(i["number"]) for i in st.get("pending_instructions", []) if i.get("kind") == "claude"}
    waiting = {key_of(i) for i in open_ if int(i["number"]) not in replied}
    keys = {key_of(i) for i in closed} | {key_of(i) for i in open_ if int(i["number"]) in replied}
    return {k for k in keys - waiting if k}


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


def ask(cfg: config_mod.Config, questions: list[dict[str, Any]], source: str = "",
        now: dt.datetime | None = None, pr: int | None = None,
        pictures: Callable[[dict[str, Any]], str] | None = None) -> list[str]:
    """Opens an issue per new question, showing `pictures(question)` (markdown) when given.

    A question is new unless an open question, or one closed in the last RECENT_DAYS, has the
    same key or a similar title: then it's only noted in the log, never asked again.
    """
    questions = [q for q in questions if q.get("title") and q.get("question")][:MAX_PER_SESSION]
    if not questions:
        return []
    labels_mod.ensure(cfg, [LABEL, CHANGE_LABEL])
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
        try:  # a question without its pictures is still asked
            shown = pictures(q) if pictures else ""
        except (gh.GhError, OSError, subprocess.SubprocessError) as e:
            print(f"couldn't show the screenshots of \"{title}\": {e}")
            shown = ""
        created = gh.api(f"repos/{cfg.repo}/issues", "-X", "POST",
                         input={"title": title, "body": render(cfg, q, source, pr, shown), "labels": labels})
        known.append({"number": created["number"], "title": title, "state": "open",
                      "body": f"<!-- smbot:question key={_key(q.get('key', ''))} -->"})
        log.append(f"Question for the owner: #{created['number']} {title}")
    return log


def pictures_for(cfg: config_mod.Config, token: str, folder: Path | None, sha: str,
                 pr: int | None) -> Callable[[dict[str, Any]], str]:
    """What a question shows: the shots it names, taken on `sha`, or else the screenshots of PR #`pr`."""
    def pictures(q: dict[str, Any]) -> str:
        own = screenshots.for_question(cfg, token, q, folder, sha) if folder and folder.is_dir() and sha else ""
        return own or (screenshots.for_log(cfg, pr) if pr else "")
    return pictures


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
        pr = int(os.environ["PR"]) if os.environ.get("PR", "").isdigit() else None
        sha = os.environ.get("SHA", "")
        sha = sha if re.fullmatch(r"[0-9a-f]{7,40}", sha) else ""
        folder = Path(os.environ["SHOTS"]) if os.environ.get("SHOTS") else None
        log = ask(cfg, result.get("owner_questions") or [], os.environ.get("SOURCE", ""), pr=pr,
                  pictures=pictures_for(cfg, os.environ.get("GH_TOKEN", ""), folder, sha, pr))
        print("\n".join(log) or "no new questions for the owner")
        if log:
            dailylog.post(cfg, "Questions for the owner", log)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
