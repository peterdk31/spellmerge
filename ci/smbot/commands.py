"""Owner commands in comments (docs/PLAN.md, "Owner commands in comments").

A comment counts only if its author is the owner's numeric user ID and every
revision in its edit history is by the owner too. Commands from anyone else are
ignored and never treated as instructions.

Carried out here, by script: /pause, /resume, /close, /merge and /revert.
Queued for the next Claude session: /priority, /claude <text> and /ask <question>.
Checkpoint answers, only in an open `checkpoint` issue: /go, /iterate <what> and /pivot <how>
(smbot.checkpoint); the gate starts a planning session that carries them out.
"""

from __future__ import annotations

import datetime as dt
import re
import subprocess
import tempfile
from dataclasses import dataclass, field
from typing import Any

from . import checkpoint
from . import config as config_mod
from . import gh
from .pacing import iso, parse_time

COMMANDS = ("merge", "close", "revert", "priority", "claude", "ask", "pause", "resume", "go", "iterate", "pivot")
_COMMAND = re.compile(r"^/(" + "|".join(COMMANDS) + r")\b[ \t]*(.*)", re.DOTALL)
SCAN_DAYS = 3


@dataclass(frozen=True)
class Command:
    name: str
    text: str  # everything after the command word, including later lines
    comment_id: int
    node_id: str
    number: int  # issue or PR number
    is_pr: bool
    url: str
    created_at: str


def parse(body: str) -> tuple[str, str] | None:
    """(command, text) if the comment's first non-empty line is a command."""
    stripped = body.lstrip()
    m = _COMMAND.match(stripped)
    if m is None:
        return None
    return m.group(1), m.group(2).strip()


_EDITS = """
query($id: ID!) {
  node(id: $id) {
    ... on IssueComment {
      author { ... on User { databaseId } }
      userContentEdits(first: 50) { nodes { editor { ... on User { databaseId } } } }
    }
  }
}"""


def only_owner_edited(node: dict, owner_id: int) -> bool:
    if not node or (node.get("author") or {}).get("databaseId") != owner_id:
        return False
    return all((e.get("editor") or {}).get("databaseId") == owner_id for e in node["userContentEdits"]["nodes"])


def find(cfg: config_mod.Config, processed: set[int], now: dt.datetime) -> list[Command]:
    since = iso(now - dt.timedelta(days=SCAN_DAYS))
    comments = gh.api_paginated(f"repos/{cfg.repo}/issues/comments?since={since}&per_page=100")
    found = []
    for c in comments:
        if c["id"] in processed or (c.get("user") or {}).get("id") != cfg.owner.id:
            continue
        parsed = parse(c.get("body") or "")
        if parsed is None:
            continue
        node = gh.graphql(_EDITS, id=c["node_id"])["node"]
        if not only_owner_edited(node, cfg.owner.id):
            continue
        number = int(c["issue_url"].rsplit("/", 1)[1])
        found.append(Command(parsed[0], parsed[1], c["id"], c["node_id"], number,
                             "/pull/" in c["html_url"], c["html_url"], c["created_at"]))
    return sorted(found, key=lambda cmd: cmd.created_at)


def reply(cfg: config_mod.Config, cmd: Command, text: str) -> None:
    gh.api(f"repos/{cfg.repo}/issues/{cmd.number}/comments", "-X", "POST",
           input={"body": f"> /{cmd.name} ([command]({cmd.url}))\n\n{text}"})


def head_changed_since(cfg: config_mod.Config, sha: str, when: str) -> bool:
    """True if the PR head was pushed after `when`, judged by GitHub's own clock.

    Commit dates can be faked, so this uses the creation time of the checks run
    that GitHub started for the head commit when it was pushed.
    """
    runs = gh.api(f"repos/{cfg.repo}/actions/runs?head_sha={sha}&event=pull_request&per_page=100")
    times = [parse_time(r["created_at"]) for r in runs.get("workflow_runs", [])]
    return not times or min(times) > parse_time(when)


def do_merge(cfg: config_mod.Config, cmd: Command) -> str:
    if not cmd.is_pr:
        return "`/merge` only works on pull requests."
    pr = gh.api(f"repos/{cfg.repo}/pulls/{cmd.number}")
    if pr["state"] != "open":
        return "This pull request is not open."
    sha = pr["head"]["sha"]
    if head_changed_since(cfg, sha, cmd.created_at):
        return (f"Not merged: the pull request changed after your command (head is now `{sha[:7]}`). "
                "Check the new changes and comment `/merge` again.")
    try:
        gh.run("pr", "merge", str(cmd.number), "--repo", cfg.repo, "--squash", "--match-head-commit", sha)
    except gh.GhError as e:
        return ("Not merged: GitHub refused the merge. Pull requests that touch protected paths need your "
                f"approval in GitHub itself, and the required checks must pass.\n\n```\n{e}\n```")
    return f"Merged `{sha[:7]}` as you asked."


def do_close(cfg: config_mod.Config, cmd: Command) -> str:
    kind = "pulls" if cmd.is_pr else "issues"
    gh.api(f"repos/{cfg.repo}/{kind}/{cmd.number}", "-X", "PATCH", input={"state": "closed"})
    return "Closed as you asked."


def do_revert(cfg: config_mod.Config, cmd: Command, token: str) -> str:
    if not cmd.is_pr:
        return "`/revert` only works on merged pull requests."
    pr = gh.api(f"repos/{cfg.repo}/pulls/{cmd.number}")
    if not pr.get("merged"):
        return "This pull request isn't merged, so there is nothing to revert."
    number = open_revert_pr(cfg, cmd.number, pr["merge_commit_sha"], pr["title"], token,
                            f"Requested by the owner with `/revert` in {cmd.url}.")
    return f"Opened #{number} to revert this. It merges once its checks pass."


def open_revert_pr(cfg: config_mod.Config, number: int, merge_sha: str, title: str, token: str, reason: str) -> int:
    """Creates a branch that reverts a merge commit and opens a bot PR for it."""
    branch = f"revert/pr-{number}"
    with tempfile.TemporaryDirectory() as tmp:
        url = f"https://x-access-token:{token}@github.com/{cfg.repo}.git"

        def git(*args: str) -> None:
            subprocess.run(["git", "-C", tmp, *args], check=True, capture_output=True, text=True)

        subprocess.run(["git", "clone", "--quiet", "--filter=blob:none", url, tmp], check=True, capture_output=True)
        git("config", "user.name", cfg.bot.login)
        git("config", "user.email", f"{cfg.bot.id}+{cfg.bot.login}@users.noreply.github.com")
        git("switch", "-c", branch)
        parents = subprocess.run(["git", "-C", tmp, "rev-list", "--parents", "-n1", merge_sha],
                                 check=True, capture_output=True, text=True).stdout.split()
        git("revert", "--no-edit", *(["-m", "1"] if len(parents) > 2 else []), merge_sha)
        git("push", "--force", "origin", branch)
    created = gh.api(f"repos/{cfg.repo}/pulls", "-X", "POST", input={
        "title": f"Revert #{number}: {title}",
        "head": branch,
        "base": "main",
        "body": f"Reverts #{number}.\n\n{reason}",
    })
    return created["number"]


@dataclass
class Effects:
    """What the commands change in the state, merged in by the caller.

    Kept apart from the side effects (merges, replies) so that retrying a state
    write after a conflict never carries out a command twice.
    """
    processed: list[int]
    paused: bool | None
    instructions: list[dict[str, Any]]
    checkpoints: list[dict[str, Any]] = field(default_factory=list)  # answers: issue, verdict, text, url, at

    def apply(self, state: dict[str, Any]) -> None:
        seen = set(state["processed_comments"])
        state["processed_comments"] += [i for i in self.processed if i not in seen]
        if self.paused is not None:
            state["paused_by_command"] = self.paused
            if not self.paused:
                state["errors_in_a_row"] = 0  # /resume also restarts development stopped by errors
        known = {i["url"] for i in state["pending_instructions"]}
        state["pending_instructions"] += [i for i in self.instructions if i["url"] not in known]
        for a in self.checkpoints:
            checkpoint.record(state, a["issue"], a["verdict"], a["text"], a["url"], a["at"])


def queue_instruction(effects: Effects, cmd: Command) -> str:
    effects.instructions.append({
        "kind": cmd.name, "text": cmd.text, "number": cmd.number, "url": cmd.url, "at": cmd.created_at,
    })
    if cmd.name == "ask":
        return "Got it. Claude will answer here in the next development session."
    if cmd.name == "priority":
        return "Got it. This goes to the top of `docs/NEXT.md` in the next development session."
    return "Got it. Claude will act on this in the next development session."


def answer_checkpoint(cfg: config_mod.Config, effects: Effects, cmd: Command) -> str:
    issue = gh.api(f"repos/{cfg.repo}/issues/{cmd.number}")
    labels = {lab["name"] for lab in issue.get("labels", [])}
    if cmd.is_pr or issue["state"] != "open" or checkpoint.LABEL not in labels:
        return f"`/{cmd.name}` only works in an open checkpoint issue."
    if cmd.name != "go" and not cmd.text:
        return f"Say what you want after `/{cmd.name}`, for example `/{cmd.name} make the dodge snappier`."
    effects.checkpoints.append({"issue": cmd.number, "verdict": cmd.name, "text": cmd.text, "url": cmd.url,
                                "at": cmd.created_at})
    return {"go": "Got it: go. A planning session starts the next milestone now.",
            "iterate": "Got it: iterate. A planning session turns this into tasks now.",
            "pivot": "Got it: pivot. A planning session works out the new direction now."}[cmd.name]


def run(cfg: config_mod.Config, processed: set[int], now: dt.datetime, token: str) -> tuple[list[str], Effects]:
    """Carries out new owner commands; returns lines for the Daily log and the state effects."""
    log: list[str] = []
    effects = Effects([], None, [])
    for cmd in find(cfg, processed, now):
        effects.processed.append(cmd.comment_id)
        try:
            if cmd.name == "pause":
                effects.paused = True
                result = "Paused development and PR merging. Releases continue. Comment `/resume` to continue."
            elif cmd.name == "resume":
                effects.paused = False
                result = "Resumed development and PR merging."
            elif cmd.name == "merge":
                result = do_merge(cfg, cmd)
            elif cmd.name == "close":
                result = do_close(cfg, cmd)
            elif cmd.name == "revert":
                result = do_revert(cfg, cmd, token)
            elif cmd.name in checkpoint.VERDICTS:
                result = answer_checkpoint(cfg, effects, cmd)
            else:
                result = queue_instruction(effects, cmd)
        except (gh.GhError, subprocess.CalledProcessError) as e:
            result = f"Couldn't carry this out: {e}"
        reply(cfg, cmd, result)
        log.append(f"Owner command /{cmd.name} on #{cmd.number}: {result.splitlines()[0]}")
    return log, effects
