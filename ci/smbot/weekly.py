"""The weekly planning run (docs/PLAN.md, "Weekly planning run").

  python3 -m smbot.weekly gather          collects the week's ideas, feedback, bug
                                          reports, merges and metrics into weekly-input.json
                                          (community text is untrusted data)
  python3 -m smbot.weekly publish-digest  stores Claude's digest ($DIGEST) on the
                                          automation-state branch and answers each idea
                                          in Discussions (needs DISCUSSIONS_TOKEN)
  python3 -m smbot.weekly publish-plan    posts the devlog and creates contributor task
                                          issues from the planning session's output ($PLAN)

The digest is written by a Claude session with read-only tools and no write
token; the planning session (a normal development session) only ever sees it
as data.
"""

from __future__ import annotations

import base64
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

from . import config as config_mod
from . import dailylog, gh, nexttask
from .pacing import iso

DIGEST_PATH = "weekly/digest.json"
MAX_REPLY = 1200
MAX_ISSUES_PER_AREA = 10
LOOKBACK = dt.timedelta(days=7)

_DISCUSSIONS = """
query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    id
    discussionCategories(first: 25) { nodes { id name slug } }
    discussions(first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes {
        id number title body createdAt updatedAt url
        author { login }
        category { name slug }
        comments(first: 30) { nodes { author { login } body createdAt } }
      }
    }
  }
}"""


def gather(cfg: config_mod.Config, now: dt.datetime) -> dict[str, Any]:
    owner, name = cfg.repo.split("/")
    since = now - LOOKBACK
    data = gh.graphql(_DISCUSSIONS, owner=owner, name=name)["repository"]
    discussions = []
    for d in data["discussions"]["nodes"]:
        if dt.datetime.fromisoformat(d["updatedAt"].replace("Z", "+00:00")) < since:
            continue
        replied = any((c.get("author") or {}).get("login") in (cfg.bot.login, "github-actions")
                      for c in d["comments"]["nodes"])
        discussions.append({
            "id": d["id"], "number": d["number"], "category": d["category"]["name"], "title": d["title"][:200],
            "body": (d["body"] or "")[:4000], "author": (d.get("author") or {}).get("login"), "url": d["url"],
            "already_replied": replied,
            "comments": [{"author": (c.get("author") or {}).get("login"), "body": (c["body"] or "")[:1000]}
                         for c in d["comments"]["nodes"]][-10:],
        })
    bugs = [{"number": i["number"], "title": i["title"][:200], "body": (i["body"] or "")[:3000],
             "labels": [lab["name"] for lab in i["labels"]]}
            for i in gh.api_paginated(f"repos/{cfg.repo}/issues?state=open&labels=bug&per_page=100")
            if "pull_request" not in i]
    ideas = [{"number": i["number"], "title": i["title"][:200], "body": (i["body"] or "")[:3000]}
             for i in gh.api_paginated(f"repos/{cfg.repo}/issues?state=open&labels=idea:spell&per_page=100")
             if "pull_request" not in i]
    merged = gh.api(f"search/issues?q=repo:{cfg.repo}+is:pr+is:merged+merged:>={since.date().isoformat()}"
                    "&per_page=100").get("items", [])
    return {
        "generated": iso(now),
        "discussions": discussions,
        "bug_reports": bugs,
        "spell_ideas": ideas,
        "merged_this_week": [{"number": i["number"], "title": i["title"], "author": i["user"]["login"]}
                             for i in merged],
        "next_task": nexttask.next_task(),
        "categories": {c["name"]: c["id"] for c in data["discussionCategories"]["nodes"]},
        "repository_id": data["id"],
    }


def safe_reply(text: str) -> str:
    """Replies are written from untrusted text, so keep them short and inert."""
    text = re.sub(r"@(?=[\w-])", "@​", text.strip())  # no mentions
    text = re.sub(r"https?://(?!github\.com/peterdk31/spellmerge)\S+", "(link removed)", text)
    return text[:MAX_REPLY]


_ADD_COMMENT = """
mutation($id: ID!, $body: String!) {
  addDiscussionComment(input: {discussionId: $id, body: $body}) { comment { url } }
}"""
_CREATE_DISCUSSION = """
mutation($repo: ID!, $category: ID!, $title: String!, $body: String!) {
  createDiscussion(input: {repositoryId: $repo, categoryId: $category, title: $title, body: $body}) {
    discussion { url }
  }
}"""


def publish_digest(cfg: config_mod.Config, digest: dict[str, Any], gathered: dict[str, Any],
                   discussions_token: str) -> list[str]:
    log = []
    known = {d["id"]: d for d in gathered["discussions"]}
    for item in digest.get("ideas", []):
        d = known.get(item.get("discussion_id", ""))
        if not d or d["already_replied"] or not item.get("reply"):
            continue
        body = safe_reply(item["reply"]) + "\n\n<sub>Claude, Spellmerge's AI maintainer, reads every idea weekly.</sub>"
        gh.graphql(_ADD_COMMENT, gh_token=discussions_token, id=d["id"], body=body)
        log.append(f"Replied to discussion #{d['number']} ({item.get('verdict', 'noted')})")
    stored = {"digest": digest, "categories": gathered["categories"], "repository_id": gathered["repository_id"],
              "merged_this_week": gathered["merged_this_week"]}
    content = base64.b64encode((json.dumps(stored, indent=2) + "\n").encode()).decode()
    path = f"repos/{cfg.repo}/contents/{DIGEST_PATH}"
    try:
        sha = gh.api(f"{path}?ref={cfg.state_branch}")["sha"]
    except gh.GhError:
        sha = None
    body: dict[str, Any] = {"message": "weekly: digest", "content": content, "branch": cfg.state_branch}
    if sha:
        body["sha"] = sha
    gh.api(path, "-X", "PUT", input=body)
    return log


def load_digest(cfg: config_mod.Config) -> dict[str, Any] | None:
    try:
        data = gh.api(f"repos/{cfg.repo}/contents/{DIGEST_PATH}?ref={cfg.state_branch}")
    except gh.GhError:
        return None
    return json.loads(base64.b64decode(data["content"]))


def task_issue_body(task: dict[str, Any]) -> str:
    """The fixed task template (docs/PLAN.md, "Issues as the task list")."""
    brief = (f"Task: {task['what']}\nWhere: {task['where']}\nSpecs: {task.get('specs', '')}\n"
             f"Example to copy: {task.get('example', '(see the area README)')}\nDone when: {task['done_when']}\n"
             "Constraints: follow AGENTS.md (hard rules, typed GDScript, allowed file types), run tools/check.sh, "
             "and open the PR against main mentioning this issue.")
    return "\n".join([
        f"**Milestone:** {task['milestone']} · **Area:** {task['area']} · **Skill:** {task['skill']} · "
        f"**Size:** {task['size']}", "",
        f"**What:** {task['what']}", "",
        f"**Where:** `{task['where']}`", "",
        f"**Specs:** {task.get('specs', '')}", "",
        f"**Example to copy:** {task.get('example', '(see the area README)')}", "",
        f"**Current placeholder:** {task.get('placeholder', 'none')}", "",
        f"**Done when:** {task['done_when']}", "",
        "Comment `/claim` to take it (claims last 2 days without a PR). See CONTRIBUTING.md.", "",
        "<details><summary>Brief for your AI</summary>", "", "```text", brief, "```", "", "</details>",
    ])


def create_task_issues(cfg: config_mod.Config, tasks: list[dict[str, Any]]) -> list[str]:
    log = []
    open_by_area: dict[str, int] = {}
    for issue in gh.api_paginated(f"repos/{cfg.repo}/issues?state=open&labels=now&per_page=100"):
        for label in issue["labels"]:
            if label["name"].startswith("area:"):
                open_by_area[label["name"]] = open_by_area.get(label["name"], 0) + 1
    for task in tasks:
        area = f"area:{task['area']}"
        if open_by_area.get(area, 0) >= MAX_ISSUES_PER_AREA:
            continue
        labels = [task.get("status", "now"), area, task["skill"], task["size"]]
        created = gh.api(f"repos/{cfg.repo}/issues", "-X", "POST",
                         input={"title": task["title"][:120], "body": task_issue_body(task), "labels": labels})
        open_by_area[area] = open_by_area.get(area, 0) + 1
        log.append(f"Task issue #{created['number']}: {task['title'][:80]}")
    return log


def publish_plan(cfg: config_mod.Config, plan: dict[str, Any], gathered: dict[str, Any] | None,
                 discussions_token: str | None) -> list[str]:
    """Posts the devlog, and creates contributor task issues, owner issues and the playtest issue."""
    log = []
    post = plan.get("progress_post")
    if post and gathered and discussions_token:
        category = gathered["categories"].get("Announcements") or next(iter(gathered["categories"].values()), None)
        if category:
            week = dt.datetime.now(dt.timezone.utc).strftime("%G-W%V")
            result = gh.graphql(_CREATE_DISCUSSION, gh_token=discussions_token, repo=gathered["repository_id"],
                                category=category, title=f"Devlog {week}", body=post[:20000])
            log.append(f"Devlog posted: {result['createDiscussion']['discussion']['url']}")
    log += create_task_issues(cfg, plan.get("task_issues", []))
    for issue in plan.get("owner_issues", [])[:3]:
        created = gh.api(f"repos/{cfg.repo}/issues", "-X", "POST", input={
            "title": issue["title"][:120], "body": f"{issue['body'][:20000]}\n\n@{cfg.owner.login}"})
        log.append(f"Owner issue #{created['number']}: {issue['title'][:80]}")
    if plan.get("playtest"):
        p = plan["playtest"]
        created = gh.api(f"repos/{cfg.repo}/issues", "-X", "POST", input={
            "title": f"Playtest of the week: {dt.datetime.now(dt.timezone.utc):%Y-%m-%d}",
            "body": f"@{cfg.owner.login}, about 30 minutes of play: https://{cfg.repo.split('/')[0]}.github.io/"
                    f"{cfg.repo.split('/')[1]}/nightly/\n\n**What changed:** {p.get('changes', '')}\n\n**Questions:**\n"
                    + "\n".join(f"{i + 1}. {q}" for i, q in enumerate(p.get("questions", [])[:5]))
                    + "\n\nA few lines from the phone are plenty. A skipped week blocks nothing."})
        log.append(f"Playtest of the week: #{created['number']}")
    return log


def main(argv: list[str] | None = None) -> int:
    cmd = (argv or sys.argv[1:] or [""])[0]
    cfg = config_mod.load()
    if cmd == "gather":
        data = gather(cfg, dt.datetime.now(dt.timezone.utc))
        Path("weekly-input.json").write_text(json.dumps(data, indent=2))
        print(f"{len(data['discussions'])} discussions, {len(data['bug_reports'])} bugs, "
              f"{len(data['merged_this_week'])} merges")
    elif cmd == "publish-digest":
        gathered = json.loads(Path("weekly-input.json").read_text())
        log = publish_digest(cfg, json.loads(os.environ["DIGEST"]), gathered, os.environ["DISCUSSIONS_TOKEN"])
        dailylog.post(cfg, "Weekly planning: community digest", log)
    elif cmd == "publish-plan":
        plan = json.loads(os.environ.get("PLAN") or "{}")
        log = publish_plan(cfg, plan, load_digest(cfg), os.environ.get("DISCUSSIONS_TOKEN"))
        dailylog.post(cfg, "Weekly planning", log)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
