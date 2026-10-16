"""Merging outside PRs (docs/PLAN.md, "Daily run" step 4 and "Filter 3").

  python3 -m smbot.communitymerge candidates
      PRs rated `merge` at their current head whose votes allow it, best first
      (needs the bot's token; updates the vote count in the rating comments)
  python3 -m smbot.communitymerge stage
      test-merges $CANDIDATES in order on a throwaway local staging branch and
      runs the quick build after each (runs PR code: no secrets in that job)
  python3 -m smbot.communitymerge finish
      merges what passed with smbot.merge, pinned to the rated commit, and
      comments on the rest (needs the bot's token and READ_TOKEN)

On conflicts the higher-rated PR wins and the other gets a rebase request.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import re
import subprocess
import sys
from typing import Any

from . import community, dailylog, gh, merge, quarantine, state, votes
from . import config as config_mod
from .rate import parse_marker
from .triage import RATING_MARKER

AUTOMATED_LABEL = "automated"
AUTOMATED_FILES = {"docs/cla-signatures.json"}
VOTE_HEADING = "**Community vote**"


def latest_rating(comments: list[dict[str, Any]], bot_login: str) -> tuple[dict[str, Any], dict[str, str]] | None:
    for c in reversed(comments):
        if (c.get("user") or {}).get("login") == bot_login and RATING_MARKER in (c.get("body") or ""):
            parsed = parse_marker(c["body"])
            if parsed:
                return c, parsed
    return None


def reactions_as_votes(reactions: list[dict[str, Any]], author: str) -> list[votes.Vote]:
    out = []
    for r in reactions:
        login = (r.get("user") or {}).get("login")
        if r.get("content") in ("+1", "-1") and login and login != author and not login.endswith("[bot]"):
            out.append(votes.Vote(login, r["content"] == "+1",
                                  dt.datetime.fromisoformat(r["created_at"].replace("Z", "+00:00"))))
    return out


def replace_vote_line(body: str, line: str) -> str:
    new = f"{VOTE_HEADING} (react 👍 or 👎 on the PR itself): {line}"
    if VOTE_HEADING in body:
        return re.sub(re.escape(VOTE_HEADING) + r"[^\n]*", lambda _: new, body, count=1)
    return body.replace("\n\n<sub>", f"\n\n{new}\n\n<sub>", 1)


def candidates(cfg: config_mod.Config, now: dt.datetime, settings: votes.VoteSettings) -> tuple[list[dict], list[str]]:
    out: list[dict] = []
    log: list[str] = []
    activity: community.Activity | None = None
    user_cache: dict[str, dict[str, Any]] = {}
    voters = phase = None

    for pr in gh.api_paginated(f"repos/{cfg.repo}/pulls?state=open&per_page=100"):
        number, sha, login = pr["number"], pr["head"]["sha"], pr["user"]["login"]
        labels = {label["name"] for label in pr["labels"]}
        if login == cfg.bot.login and AUTOMATED_LABEL in labels:
            files = {f["filename"] for f in gh.api_paginated(f"repos/{cfg.repo}/pulls/{number}/files")}
            if files <= AUTOMATED_FILES or quarantine.allowed_quarantine_change(files, pr["title"]):
                out.append({"pr": number, "sha": sha, "average": 5.0, "author": login})
            continue
        comments = gh.api_paginated(f"repos/{cfg.repo}/issues/{number}/comments?per_page=100")
        found = latest_rating(comments, cfg.bot.login)
        if not found:
            continue
        rating_comment, marker = found
        if marker.get("sha") != sha or marker.get("decision") != "merge":
            continue
        average = float(marker.get("average", 0))

        if votes.is_votable(labels):
            if activity is None:
                activity = community.gather(cfg, now, os.environ.get("DISCUSSIONS_TOKEN"))
                _, voters, phase = community.counts(activity, now, user_cache)
            started = dt.datetime.fromisoformat(rating_comment["created_at"].replace("Z", "+00:00"))
            reactions = gh.api_paginated(f"repos/{cfg.repo}/issues/{number}/reactions?per_page=100")
            cast = reactions_as_votes(reactions, login)
            eligible = {v.login for v in cast if community.eligible(v.login, activity, phase, started, now, user_cache)}
            newcomers = {v.login for v in cast if v.login not in activity.first}
            t = votes.tally(cast, eligible, newcomers, voters, settings)
            w = votes.window(started, now, t)
            line = votes.status_line(t, w, settings)
            gh.api(f"repos/{cfg.repo}/issues/comments/{rating_comment['id']}", "-X", "PATCH",
                   input={"body": replace_vote_line(rating_comment["body"], line)})
            verdict = votes.decision(t, w, settings, average)
            if verdict == "wait":
                log.append(f"#{number} waits for votes: {line}")
                continue
            if verdict == "close":
                reason = ("the community vote didn't approve it" if t.rejected(settings) or t.needed == 0 else
                          "the vote didn't reach the needed number in 48 hours, and on its own it falls short of "
                          f"the stricter bar (average {average:.1f}, needs {votes.STRICT_AVERAGE})")
                gh.api(f"repos/{cfg.repo}/issues/{number}/comments", "-X", "POST",
                       input={"body": f"Closing this, because {reason}. Thank you for contributing, @{login}; "
                                      "ideas are welcome in Discussions."})
                gh.api(f"repos/{cfg.repo}/pulls/{number}", "-X", "PATCH", input={"state": "closed"})
                log.append(f"Closed #{number} after the vote: {line}")
                continue
        out.append({"pr": number, "sha": sha, "average": average, "author": login})

    out.sort(key=lambda c: -c["average"])
    return out, log


def _run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(list(args), capture_output=True, text=True)


def stage(cands: list[dict]) -> dict[str, list]:
    """Merges candidates one by one on a local staging branch; keeps those that build."""
    passed: list[dict] = []
    conflicts: list[dict] = []
    broken: list[dict] = []
    subprocess.run(["git", "fetch", "--quiet", "origin", "main"], check=True)
    subprocess.run(["git", "switch", "--quiet", "-C", "staging", "origin/main"], check=True)
    for c in cands:
        subprocess.run(["git", "fetch", "--quiet", "origin", f"pull/{c['pr']}/head"], check=True)
        before = _run("git", "rev-parse", "HEAD").stdout.strip()
        merged = _run("git", "-c", "user.name=staging", "-c", "user.email=staging@localhost",
                      "merge", "--no-ff", "--no-edit", c["sha"])
        if merged.returncode != 0:
            _run("git", "merge", "--abort")
            conflicts.append(c)
            continue
        build = _run("ci/build/build.sh", "--quick")
        if build.returncode != 0:
            subprocess.run(["git", "reset", "--quiet", "--hard", before], check=True)
            broken.append({**c, "log": "\n".join((build.stdout + build.stderr).splitlines()[-30:])})
            continue
        passed.append(c)
    return {"passed": passed, "conflicts": conflicts, "broken": broken}


def finish(cfg: config_mod.Config, result: dict[str, list], read_token: str | None) -> list[str]:
    log: list[str] = []
    merged: list[dict] = []
    for c in result["passed"]:
        try:
            log.append(merge.merge(cfg, c["pr"], c["sha"], read_token))
            merged.append(c)
            if c["author"] != cfg.bot.login:
                gh.api(f"repos/{cfg.repo}/issues/{c['pr']}/comments", "-X", "POST", input={
                    "body": f"Merged. Thank you, @{c['author']}! It ships in tomorrow's build; small polish follows "
                            "in Claude's follow-up PR if the rating listed any."})
        except merge.NotMerged as e:
            log.append(f"Not merged #{c['pr']}: {e}")
            gh.api(f"repos/{cfg.repo}/issues/{c['pr']}/comments", "-X", "POST",
                   input={"body": f"Approved, but the merge script didn't merge it: {e}. It's tried again tomorrow."})
    for c in result["conflicts"]:
        log.append(f"#{c['pr']} conflicts with today's merges; asked for a rebase")
        gh.api(f"repos/{cfg.repo}/issues/{c['pr']}/comments", "-X", "POST", input={
            "body": f"@{c['author']}, this conflicts with `main` after today's merges (higher-rated PRs go first). "
                    "Please merge `main` into your branch and push; the approval carries over if nothing else changes "
                    "(a push means a new rating)."})
    for c in result["broken"]:
        log.append(f"#{c['pr']} broke the quick build on staging")
        gh.api(f"repos/{cfg.repo}/issues/{c['pr']}/comments", "-X", "POST", input={
            "body": f"@{c['author']}, this PR breaks the build when merged with today's `main` (import or smoke test), "
                    f"so it wasn't merged. The end of the log:\n\n```\n{c['log'][-3000:]}\n```\n\nPush a fix and it "
                    "will be rated again."})
    if merged:
        fixups = state.load(cfg)[0].get("fixups", {})

        def apply(s: dict[str, Any]) -> None:
            for c in merged:
                items = fixups.get(str(c["pr"]))
                if items:
                    s.setdefault("followups", []).append({"pr": c["pr"], "author": c["author"], "fixups": items})
                s.setdefault("fixups", {}).pop(str(c["pr"]), None)
        state.update(cfg, apply, "merge: follow-ups")
    return log


def _write(key: str, value: Any) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    text = json.dumps(value)
    print(f"{key}={text[:1000]}")
    if path:
        with open(path, "a") as fh:
            fh.write(f"{key}<<__END__\n{text}\n__END__\n")


def main(argv: list[str] | None = None) -> int:
    cmd = (argv or sys.argv[1:] or [""])[0]
    cfg = config_mod.load()
    if cmd == "candidates":
        s = json.loads(os.environ.get("SETTINGS") or "{}")
        settings = votes.VoteSettings(s.get("vote_share", 15), s.get("vote_min", 2), s.get("vote_max", 25),
                                      s.get("vote_approval", 60))
        cands, log = candidates(cfg, dt.datetime.now(dt.timezone.utc), settings)
        _write("candidates", cands)
        dailylog.post(cfg, "Votes", log)
    elif cmd == "stage":
        _write("result", stage(json.loads(os.environ.get("CANDIDATES") or "[]")))
    elif cmd == "finish":
        log = finish(cfg, json.loads(os.environ["RESULT"]), os.environ.get("READ_TOKEN"))
        dailylog.post(cfg, "Merges", log)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
