"""The weekly planning run (docs/PLAN.md, "Weekly planning run").

  python3 -m smbot.weekly publish-plan    carries out the planning session's output ($PLAN):
                                          the devlog post, owner issues, the playtest issue,
                                          and moving issues between the backlog and the queue

Community posts reach planning through the daily intake (smbot.intake): the
planning session sees the scheduled and backlog issues as data (backlog_text).
"""

from __future__ import annotations

import datetime as dt
import json
import os
import sys
from typing import Any

from . import config as config_mod
from . import dailylog, gh, intake

MAX_MOVES = 10  # issues moved between the backlog and the queue per week

_CATEGORIES = """
query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    id
    discussionCategories(first: 25) { nodes { id name } }
  }
}"""
_CREATE_DISCUSSION = """
mutation($repo: ID!, $category: ID!, $title: String!, $body: String!) {
  createDiscussion(input: {repositoryId: $repo, categoryId: $category, title: $title, body: $body}) {
    discussion { url }
  }
}"""


def backlog_text(cfg: config_mod.Config, st: dict[str, Any]) -> str:
    """The scheduled and backlog issues for the planning prompt, as JSON (restated by the intake)."""
    tasks = st.get("intake_tasks", {})
    out = []
    for label in (intake.SCHEDULED, intake.BACKLOG):
        try:
            issues = gh.api_paginated(f"repos/{cfg.repo}/issues?state=open&labels={label}&per_page=100")
        except gh.GhError:
            continue
        for issue in issues:
            entry = tasks.get(str(issue["number"]), {})
            labels = {lab["name"] for lab in issue.get("labels", [])}
            out.append({"issue": issue["number"], "list": label,
                        "priority": next((p for p in intake.PRIORITIES if p in labels), "p3"),
                        "kind": entry.get("kind", ""), "title": entry.get("title") or intake.inert(issue["title"], 120),
                        "task": entry.get("task", "")})
    return json.dumps(out, indent=2) if out else "[]"


def _move(cfg: config_mod.Config, number: int, to: str, open_labels: dict[int, set[str]]) -> str | None:
    """Moves an open issue between the queue and the backlog; only issues already on one of them."""
    labels = open_labels.get(number)
    if labels is None:
        return None
    frm = intake.BACKLOG if to == intake.SCHEDULED else intake.SCHEDULED
    if frm in labels:
        gh.api(f"repos/{cfg.repo}/issues/{number}/labels/{frm}", "-X", "DELETE")
    gh.api(f"repos/{cfg.repo}/issues/{number}/labels", "-X", "POST", input={"labels": [to]})
    return f"#{number} {'scheduled' if to == intake.SCHEDULED else 'moved to the backlog'}"


def move_issues(cfg: config_mod.Config, schedule: list[int], unschedule: list[int]) -> list[str]:
    open_labels: dict[int, set[str]] = {}
    for label in (intake.SCHEDULED, intake.BACKLOG):
        for issue in gh.api_paginated(f"repos/{cfg.repo}/issues?state=open&labels={label}&per_page=100"):
            open_labels[issue["number"]] = {lab["name"] for lab in issue.get("labels", [])}
    moves = [(n, intake.SCHEDULED) for n in schedule] + [(n, intake.BACKLOG) for n in unschedule]
    log = [_move(cfg, n, to, open_labels) for n, to in moves[:MAX_MOVES] if isinstance(n, int)]
    return [line for line in log if line]


def post_devlog(cfg: config_mod.Config, post: str, discussions_token: str) -> str | None:
    owner, name = cfg.repo.split("/")
    data = gh.graphql(_CATEGORIES, gh_token=discussions_token, owner=owner, name=name)["repository"]
    categories = {c["name"]: c["id"] for c in data["discussionCategories"]["nodes"]}
    category = categories.get("Announcements") or next(iter(categories.values()), None)
    if not category:
        return None
    week = dt.datetime.now(dt.timezone.utc).strftime("%G-W%V")
    result = gh.graphql(_CREATE_DISCUSSION, gh_token=discussions_token, repo=data["id"], category=category,
                        title=f"Devlog {week}", body=post[:20000])
    return f"Devlog posted: {result['createDiscussion']['discussion']['url']}"


def publish_plan(cfg: config_mod.Config, plan: dict[str, Any], discussions_token: str | None) -> list[str]:
    """Posts the devlog, moves issues, and creates owner issues and the playtest issue."""
    log = []
    if plan.get("progress_post") and discussions_token:
        log.append(post_devlog(cfg, plan["progress_post"], discussions_token))
    log += move_issues(cfg, plan.get("schedule_issues", []), plan.get("unschedule_issues", []))
    for issue in plan.get("owner_issues", [])[:3]:
        created = gh.api(f"repos/{cfg.repo}/issues", "-X", "POST", input={
            "title": issue["title"][:120], "body": f"{issue['body'][:20000]}\n\n@{cfg.owner.login}"})
        log.append(f"Owner issue #{created['number']}: {issue['title'][:80]}")
    if plan.get("playtest"):
        p = plan["playtest"]
        created = gh.api(f"repos/{cfg.repo}/issues", "-X", "POST", input={
            "title": f"Playtest of the week: {dt.datetime.now(dt.timezone.utc):%Y-%m-%d}", "labels": ["playtest"],
            "body": f"@{cfg.owner.login}, about 30 minutes of play: https://{cfg.repo.split('/')[0]}.github.io/"
                    f"{cfg.repo.split('/')[1]}/nightly/\n\n**What changed:** {p.get('changes', '')}\n\n**Questions:**\n"
                    + "\n".join(f"{i + 1}. {q}" for i, q in enumerate(p.get("questions", [])[:5]))
                    + "\n\nA few lines from the phone are plenty. A skipped week blocks nothing."})
        log.append(f"Playtest of the week: #{created['number']}")
    return [line for line in log if line]


def main(argv: list[str] | None = None) -> int:
    cmd = (argv or sys.argv[1:] or [""])[0]
    cfg = config_mod.load()
    if cmd == "publish-plan":
        plan = json.loads(os.environ.get("PLAN") or "{}")
        log = publish_plan(cfg, plan, os.environ.get("DISCUSSIONS_TOKEN"))
        dailylog.post(cfg, "Weekly planning", log)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
