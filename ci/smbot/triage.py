"""Daily triage of open PRs (docs/PLAN.md, "Daily run" steps 1 and "Filter 1").

  python3 -m smbot.triage

For each open PR from someone other than the owner and the bot:
1. Hard rules, run from main against the PR head: a PR that breaks them is
   closed with a reason that names the rule, file, line and fix.
2. Spam limit: an author who already had 2 PRs closed today gets further
   PRs closed.
3. CLA: unsigned authors get one reminder; after 7 days unsigned, the PR
   closes. New signatures are recorded through a small bot PR.
4. Labels by area and skill, from the changed paths.

Writes the PRs that may be rated today to $GITHUB_OUTPUT as `rate` (JSON list).
Run from a clean checkout of main. Needs the bot app's token.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any

from . import cla, dailylog, gh, pacing, rules, state
from . import config as config_mod
from .pacing import parse_time

CLA_GRACE_DAYS = 7
DAILY_CLOSE_LIMIT = 2
MAX_RATINGS_PER_DAY = 8
TRIAGE_MARKER = "<!-- spellmerge:triage-closed -->"
RATING_MARKER = "<!-- spellmerge:rating"
SUBMISSION_LABEL = "submission"

AREAS = {
    "content/spells/": "area:spells", "content/relics/": "area:relics", "content/wizard/": "area:wizard",
    "content/enemies/": "area:enemies", "content/bosses/": "area:bosses", "content/rooms/": "area:rooms",
    "content/story/": "area:story", "gameplay/": "area:gameplay", "hud/": "area:hud", "art/": "area:art",
    "audio/": "area:audio", "core/": "area:core",
}


def labels_for(paths: list[str]) -> set[str]:
    labels = set()
    for path in paths:
        labels.update(label for prefix, label in AREAS.items() if path.startswith(prefix))
        suffix = PurePosixPath(path).suffix.lower()
        if suffix == ".gd":
            labels.add("code")
        elif suffix in (".png", ".svg"):
            labels.add("pixel-art")
        elif suffix == ".ogg":
            labels.add("music" if path.startswith("audio/music/") or "/music/" in path else "sfx")
        elif path.startswith("content/story/") and suffix == ".json":
            labels.add("writing")
        elif path.startswith("content/rooms/") and suffix == ".tscn":
            labels.add("level-design")
    return labels


def rules_for_pr(number: int, sha: str, author: str) -> list[rules.Finding]:
    """Main's rules (this checkout) against the PR head, without running any PR code."""
    subprocess.run(["git", "fetch", "--quiet", "origin", "main", f"pull/{number}/head"], check=True)
    with tempfile.TemporaryDirectory() as tmp:
        worktree = Path(tmp) / "pr"
        subprocess.run(["git", "worktree", "add", "--quiet", "--detach", str(worktree), sha], check=True)
        try:
            return rules.run(worktree, Path.cwd(), "origin/main", author, worktree=False)
        finally:
            subprocess.run(["git", "worktree", "remove", "--force", str(worktree)], check=True)


def close_comment(login: str, findings: list[rules.Finding]) -> str:
    rows = "\n".join(
        f"| {f.rule} | `{f.path}` | {f.line or ''} | {f.message} | {f.fix} |".replace("\n", " ")
        for f in findings if f.severity == "error")
    return (f"{TRIAGE_MARKER}\nThanks for the PR, @{login}! It can't be merged because it breaks the project's hard "
            "rules, which cover only security and copyright. Each line says what to fix:\n\n"
            "| Rule | File | Line | Problem | Fix |\n| --- | --- | --- | --- | --- |\n"
            f"{rows}\n\nPush the fixes to this branch and reopen the PR (or open a new one). You can run the same "
            "checks locally with `tools/check.sh`, and the rules are explained in `CONTRIBUTING.md`.")


def rated_at(comments: list[dict[str, Any]], bot_login: str) -> set[str]:
    """Head SHAs the bot has already rated, from the markers in its comments."""
    shas = set()
    for c in comments:
        if (c.get("user") or {}).get("login") == bot_login and RATING_MARKER in (c.get("body") or ""):
            body = c["body"]
            start = body.index(RATING_MARKER) + len(RATING_MARKER)
            for part in body[start:body.index("-->", start)].split():
                if part.startswith("sha="):
                    shas.add(part[4:])
    return shas


def comment(cfg: config_mod.Config, number: int, body: str) -> None:
    gh.api(f"repos/{cfg.repo}/issues/{number}/comments", "-X", "POST", input={"body": body})


def close(cfg: config_mod.Config, number: int, body: str) -> None:
    comment(cfg, number, body)
    gh.api(f"repos/{cfg.repo}/pulls/{number}", "-X", "PATCH", input={"state": "closed"})


def record_signatures(cfg: config_mod.Config, new: list[cla.Signature], version: str) -> str | None:
    """Commits new signatures on a branch and opens a bot PR; the merge step merges it."""
    if not new:
        return None
    path = cla.SIGNATURES
    added = cla.add_signatures(path, new, version)
    if not added:
        subprocess.run(["git", "checkout", "--", str(path)], check=True)
        return None
    branch = f"automation/cla-{dt.datetime.now(dt.timezone.utc):%Y%m%d%H%M}"
    token = os.environ["GH_TOKEN"]

    def git(*args: str) -> None:
        subprocess.run(["git", *args], check=True, capture_output=True)

    git("switch", "-c", branch)
    git("add", str(path))
    git("-c", f"user.name={cfg.bot.login}", "-c",
        f"user.email={cfg.bot.id}+{cfg.bot.login}@users.noreply.github.com",
        "commit", "-m", f"Record {added} CLA signature(s)")
    git("push", f"https://x-access-token:{token}@github.com/{cfg.repo}.git", f"HEAD:refs/heads/{branch}")
    git("switch", "-")
    names = ", ".join(f"@{s.login}" for s in new)
    pr = gh.api(f"repos/{cfg.repo}/pulls", "-X", "POST", input={
        "title": f"Record CLA signatures ({names})",
        "head": branch, "base": "main",
        "body": "Signatures found by the daily triage, each with a link to the signing comment.\n\n"
                + "\n".join(f"- @{s.login}: {s.evidence}" for s in new),
    })
    gh.api(f"repos/{cfg.repo}/issues/{pr['number']}/labels", "-X", "POST", input={"labels": ["automated"]})
    return str(pr["number"])


def triage(cfg: config_mod.Config, now: dt.datetime) -> tuple[list[int], list[str], str | None]:
    """Returns (PRs to rate, Daily log lines, signatures PR number)."""
    st, _ = state.load(cfg)
    today = now.date().isoformat()
    closed_today: dict[str, int] = dict(st.get("triage_closed", {}).get(today, {}))
    version = cla.current_version()
    signatures = cla.load_signatures()
    new_signatures: list[cla.Signature] = []
    to_rate: list[tuple[str, int]] = []
    log: list[str] = []

    for pr in gh.api_paginated(f"repos/{cfg.repo}/pulls?state=open&per_page=100"):
        number, login, user_id = pr["number"], pr["user"]["login"], pr["user"]["id"]
        labels = {label["name"] for label in pr["labels"]}
        submission = login == cfg.bot.login and SUBMISSION_LABEL in labels
        if login == cfg.owner.login or login in cfg.dependency_bots or (login == cfg.bot.login and not submission):
            continue
        if pr["draft"]:
            continue
        if pr["base"]["ref"] != "main":
            close(cfg, number, f"{TRIAGE_MARKER}\nThanks, @{login}! PRs go to `main`; please open this one again "
                               "against `main`.")
            log.append(f"Closed #{number}: not against main")
            continue

        findings = rules_for_pr(number, pr["head"]["sha"], login)
        if any(f.severity == "error" for f in findings):
            close(cfg, number, close_comment(login, findings))
            closed_today[login] = closed_today.get(login, 0) + 1
            log.append(f"Closed #{number} by @{login}: hard rules ({', '.join(sorted({f.rule for f in findings}))})")
            continue
        if closed_today.get(login, 0) >= DAILY_CLOSE_LIMIT and not submission:
            close(cfg, number, f"{TRIAGE_MARKER}\nThanks, @{login}. You've had {DAILY_CLOSE_LIMIT} PRs closed "
                               "today, so further PRs are closed until tomorrow (a spam limit). Please reopen this "
                               "one tomorrow.")
            closed_today[login] = closed_today.get(login, 0) + 1
            log.append(f"Closed #{number} by @{login}: daily limit")
            continue

        files = [f["filename"] for f in gh.api_paginated(f"repos/{cfg.repo}/pulls/{number}/files?per_page=100")]
        missing = sorted(labels_for(files) - labels)
        if missing:
            gh.api(f"repos/{cfg.repo}/issues/{number}/labels", "-X", "POST", input={"labels": missing})

        comments = gh.api_paginated(f"repos/{cfg.repo}/issues/{number}/comments?per_page=100")
        if not submission and not has_signed_or_record(cfg, number, user_id, version, signatures, new_signatures):
            age = now - parse_time(pr["created_at"])
            if age > dt.timedelta(days=CLA_GRACE_DAYS):
                close(cfg, number, f"{TRIAGE_MARKER}\nThis PR is closed because the CLA wasn't signed within "
                                   f"{CLA_GRACE_DAYS} days. Sign it by commenting `I have read the CLA and I agree "
                                   "to it.` and reopen the PR; it will be reviewed then. Thanks!")
                log.append(f"Closed #{number} by @{login}: CLA not signed in {CLA_GRACE_DAYS} days")
            elif not any(cla.REMINDER_MARKER in (c.get("body") or "") for c in comments):
                comment(cfg, number, cla.reminder_text(login, cfg.repo, CLA_GRACE_DAYS))
                log.append(f"Asked @{login} to sign the CLA on #{number}")
            continue

        if pr["head"]["sha"] not in rated_at(comments, cfg.bot.login):
            to_rate.append((pr["created_at"], number))

    def apply(s: dict[str, Any]) -> None:
        s["triage_closed"] = {today: closed_today}
    state.update(cfg, apply, "triage: daily counts")

    signatures_pr = record_signatures(cfg, new_signatures, version)
    if signatures_pr:
        log.append(f"Recording {len(new_signatures)} new CLA signature(s) in #{signatures_pr}")
    rate = [n for _, n in sorted(to_rate)][:MAX_RATINGS_PER_DAY]
    return rate, log, signatures_pr


def has_signed_or_record(cfg: config_mod.Config, number: int, user_id: int, version: str,
                         signatures: list[dict[str, Any]], new: list[cla.Signature]) -> bool:
    if cla.has_signed(signatures, user_id, version) or any(s.user_id == user_id for s in new):
        return True
    found = cla.find_signature_on_pr(cfg, number, user_id, version)
    if found:
        new.append(found)
        return True
    return False


def rating_budget(cfg: config_mod.Config, now: dt.datetime, settings: dict[str, Any]) -> pacing.Budget:
    """Reviews may use about 30% of the window budget (docs/PLAN.md, "Capacity")."""
    st, _ = state.load(cfg)
    return pacing.budget(st, now, settings.get("dev_intensity", 90), settings.get("weekly_share", 90),
                         kinds=("review", "rate"), share_of_window=pacing.REVIEW_SHARE)


def main() -> int:
    cfg = config_mod.load()
    now = dt.datetime.now(dt.timezone.utc)
    rate, log, signatures_pr = triage(cfg, now)
    budget = rating_budget(cfg, now, json.loads(os.environ.get("SETTINGS") or "{}"))
    if rate and not budget.allowed:
        log.append(f"No PR ratings today: {budget.reason}. {len(rate)} PR(s) wait until tomorrow.")
        rate = []
    print(json.dumps({"rate": rate, "signatures_pr": signatures_pr}))
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a") as fh:
            fh.write(f"rate={json.dumps(rate)}\nsignatures_pr={signatures_pr or ''}\n")
    dailylog.post(cfg, "Triage", log)
    return 0


if __name__ == "__main__":
    sys.exit(main())
