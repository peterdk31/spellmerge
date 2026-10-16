"""Reverting the day's merges when the daily build breaks (docs/PLAN.md, "Daily run" step 6).

  python3 -m smbot.revert bisect     reverts the merges since the last release,
                                     newest first, until the build passes; writes
                                     the culprits to $GITHUB_OUTPUT (runs PR code:
                                     no secrets in that job)
  python3 -m smbot.revert apply      opens a revert PR for each culprit, merges it
                                     with smbot.merge and comments on the original
                                     PR (needs the bot's token and READ_TOKEN)
"""

from __future__ import annotations

import json
import os
import subprocess
import sys

from . import commands, dailylog, gh, merge
from . import config as config_mod

MAX_REVERTS = 10


def _git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout.strip()


def todays_merges() -> list[str]:
    """First-parent commits on main since the latest release tag, newest first."""
    _git("fetch", "--quiet", "--tags", "origin", "main")
    try:
        tag = _git("describe", "--tags", "--abbrev=0", "--match", "v0.*", "origin/main")
    except subprocess.CalledProcessError:
        return []
    out = _git("log", "--first-parent", "--format=%H", f"{tag}..origin/main")
    return out.split() if out else []


def builds() -> bool:
    return subprocess.run(["ci/build/build.sh"], capture_output=True).returncode == 0


def bisect() -> list[str]:
    merges = todays_merges()[:MAX_REVERTS]
    _git("switch", "--quiet", "-C", "revert-test", "origin/main")
    culprits: list[str] = []
    for sha in merges:
        _git("-c", "user.name=revert", "-c", "user.email=revert@localhost", "revert", "--no-edit", sha)
        culprits.append(sha)
        if builds():
            return culprits
    return []  # reverting everything since the release didn't help: not caused by today's merges


def apply(cfg: config_mod.Config, culprits: list[str], read_token: str | None) -> list[str]:
    log = []
    token = os.environ["GH_TOKEN"]
    for sha in culprits:
        prs = gh.api(f"repos/{cfg.repo}/commits/{sha}/pulls")
        number = prs[0]["number"] if prs else None
        title = prs[0]["title"] if prs else sha[:7]
        try:
            revert_pr = commands.open_revert_pr(cfg, number or 0, sha, title, token,
                                                "The daily build failed, and reverting this merge fixes it.")
            info = gh.api(f"repos/{cfg.repo}/pulls/{revert_pr}")
            log.append(merge.merge(cfg, revert_pr, info["head"]["sha"], read_token))
        except (merge.NotMerged, gh.GhError, subprocess.CalledProcessError) as e:
            log.append(f"Couldn't revert {sha[:7]} automatically: {e}")
            continue
        if number:
            gh.api(f"repos/{cfg.repo}/issues/{number}/comments", "-X", "POST", input={
                "body": f"This PR broke the daily build, so it was reverted in #{revert_pr}. Nothing is lost: push a "
                        "fix and open a new PR (the reverted change is in the history). Sorry for the bump!"})
        log.append(f"Reverted {sha[:7]} (#{number}) in #{revert_pr}")
    return log


def main(argv: list[str] | None = None) -> int:
    cmd = (argv or sys.argv[1:] or [""])[0]
    if cmd == "bisect":
        culprits = bisect()
        print(json.dumps(culprits))
        path = os.environ.get("GITHUB_OUTPUT")
        if path:
            with open(path, "a") as fh:
                fh.write(f"culprits={json.dumps(culprits)}\n")
        return 0
    if cmd == "apply":
        cfg = config_mod.load()
        culprits = json.loads(os.environ.get("CULPRITS") or "[]")
        if not culprits:
            dailylog.post(cfg, "Broken build", ["The build failed, but reverting today's merges didn't fix it, so "
                                                "nothing was reverted. This needs a look."], mention_owner=True)
            return 0
        log = apply(cfg, culprits, os.environ.get("READ_TOKEN"))
        dailylog.post(cfg, "Broken build", log, mention_owner=True)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
