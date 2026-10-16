"""The merge script (docs/PLAN.md, "Filter 3: merge script").

The AI never holds the merge button: Claude's verdict is data, and this script
merges only when every hard rule also passes, pinned to the exact reviewed commit.

  python3 -m smbot.merge --pr N --sha REVIEWED_SHA

1. The PR is open against main and its head is still the reviewed commit.
2. The required checks for that commit have finished and passed.
3. The hard rules pass again, run from main's copy of the rules (this checkout)
   against the PR's head, so a PR that rewrote checks.yml gains nothing.
4. GitHub merges with --match-head-commit, so a push between the checks and the
   merge makes GitHub refuse it.

GH_TOKEN (the bot app's token) merges; READ_TOKEN (the workflow token with
checks: read) reads check results, which the app has no permission for.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from . import config as config_mod
from . import gh, rules

REQUIRED_CHECKS = ("rules", "ci-tests")
CHECK_TIMEOUT = 15 * 60


class NotMerged(Exception):
    pass


def wait_for_checks(repo: str, sha: str, read_token: str | None, timeout: float = CHECK_TIMEOUT) -> None:
    deadline = time.monotonic() + timeout
    while True:
        runs = gh.api(f"repos/{repo}/commits/{sha}/check-runs?per_page=100", token=read_token)["check_runs"]
        latest = {}
        for run in sorted(runs, key=lambda r: r["started_at"] or ""):
            latest[run["name"]] = run
        missing = [name for name in REQUIRED_CHECKS if name not in latest]
        pending = [name for name, run in latest.items() if name in REQUIRED_CHECKS and run["status"] != "completed"]
        if not missing and not pending:
            failed = [name for name in REQUIRED_CHECKS if latest[name]["conclusion"] != "success"]
            if failed:
                raise NotMerged(f"required checks failed: {', '.join(failed)}")
            return
        if time.monotonic() > deadline:
            raise NotMerged(f"checks didn't finish in time (missing: {missing}, pending: {pending})")
        time.sleep(20)


def rerun_rules(cfg: config_mod.Config, number: int, sha: str, author: str) -> list[rules.Finding]:
    """Runs main's rules against the PR head in a temporary worktree."""
    policy = Path.cwd()
    subprocess.run(["git", "fetch", "--quiet", "origin", "main", f"pull/{number}/head"], check=True)
    with tempfile.TemporaryDirectory() as tmp:
        worktree = Path(tmp) / "pr"
        subprocess.run(["git", "worktree", "add", "--quiet", "--detach", str(worktree), sha], check=True)
        try:
            return rules.run(worktree, policy, "origin/main", author, worktree=False)
        finally:
            subprocess.run(["git", "worktree", "remove", "--force", str(worktree)], check=True)


def merge(cfg: config_mod.Config, number: int, sha: str, read_token: str | None) -> str:
    pr = gh.api(f"repos/{cfg.repo}/pulls/{number}")
    if pr["state"] != "open":
        raise NotMerged("the PR is not open")
    if pr["base"]["ref"] != "main":
        raise NotMerged(f"the PR targets {pr['base']['ref']}, not main")
    if pr["head"]["sha"] != sha:
        raise NotMerged(f"the PR changed after review (reviewed {sha[:7]}, head is {pr['head']['sha'][:7]})")
    wait_for_checks(cfg.repo, sha, read_token)
    errors = [f for f in rerun_rules(cfg, number, sha, pr["user"]["login"]) if f.severity == "error"]
    if errors:
        raise NotMerged("hard rules fail: " + "; ".join(f"{f.rule} {f.path}: {f.message}" for f in errors[:5]))
    try:
        gh.run("pr", "merge", str(number), "--repo", cfg.repo, "--squash", "--match-head-commit", sha)
    except gh.GhError as e:
        raise NotMerged(f"GitHub refused the merge: {e}") from e
    return f"Merged #{number} at {sha[:7]}"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pr", type=int, required=True)
    ap.add_argument("--sha", required=True, help="the commit the review approved")
    args = ap.parse_args(argv)
    cfg = config_mod.load()
    try:
        print(merge(cfg, args.pr, args.sha, os.environ.get("READ_TOKEN")))
        return 0
    except NotMerged as e:
        print(f"Not merged: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
