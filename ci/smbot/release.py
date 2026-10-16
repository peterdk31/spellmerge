"""Plans and publishes the daily release (docs/PLAN.md, "Daily run", step 7).

  python3 -m smbot.release plan                      -> version and channel
  python3 -m smbot.release publish --version V --channel C --commit SHA

Every passing daily build is released. It is labelled stable only when it also
passes the quality gate (docs/PLAN.md, "Bugs"): no open issue labelled crash or
blocker. Failing tests stop the build before this, so nothing broken ships.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import subprocess
import sys
from pathlib import Path

from . import config, gh

GATE_LABELS = ("crash", "blocker")


def next_tag(existing: set[str], today: dt.date) -> str:
    """v0.YYYYMMDD, or v0.YYYYMMDD.N when the day already has a release."""
    base = f"v0.{today:%Y%m%d}"
    if base not in existing:
        return base
    n = 2
    while f"{base}.{n}" in existing:
        n += 1
    return f"{base}.{n}"


def channel_for(open_gate_issues: int) -> str:
    return "stable" if open_gate_issues == 0 else "nightly"


def remote_tags(repo: str) -> set[str]:
    out = subprocess.run(["git", "ls-remote", "--tags", f"https://github.com/{repo}.git"],
                         check=True, capture_output=True, text=True).stdout
    return {m.group(1) for m in re.finditer(r"refs/tags/([^\s^]+)$", out, re.MULTILINE)}


def open_gate_issues(repo: str) -> list[str]:
    found = []
    for label in GATE_LABELS:
        for issue in gh.api_paginated(f"repos/{repo}/issues?state=open&labels={label}&per_page=100"):
            if "pull_request" not in issue:
                found.append(f"#{issue['number']} ({label}) {issue['title']}")
    return found


def plan(repo: str, today: dt.date) -> dict[str, str]:
    blockers = open_gate_issues(repo)
    for line in blockers:
        print(f"quality gate: {line}", file=sys.stderr)
    return {"version": next_tag(remote_tags(repo), today), "channel": channel_for(len(blockers))}


def release_notes(repo: str, version: str, channel: str) -> str:
    owner, name = repo.split("/")
    pages = f"https://{owner}.github.io/{name}/"
    play = f"{pages}play/" if channel == "stable" else f"{pages}nightly/"
    label = ("**Stable**: passed the quality gate (all tests green, no known crashes or blockers)."
             if channel == "stable" else
             "**Nightly**: all tests passed, but open crash or blocker issues keep it from being stable.")
    return (f"{label}\n\n"
            f"- Play in the browser: {play}\n"
            "- Windows and Linux downloads are below. Windows builds are not signed yet, so Windows may "
            "show a SmartScreen warning.\n"
            "- Check a download: compare it with `SHA256SUMS`, or run "
            f"`gh attestation verify <file> --repo {repo}`.\n")


def publish(repo: str, version: str, channel: str, commit: str, dist: Path) -> None:
    assets = sorted(str(p) for p in dist.glob("*.zip")) + [str(dist / "SHA256SUMS")]
    title = f"Spellmerge {version} ({channel})"
    notes = release_notes(repo, version, channel)
    # Draft first, so every asset is attached before the release becomes immutable.
    gh.run("release", "create", version, *assets, "--repo", repo, "--draft", "--target", commit,
           "--title", title, "--notes", notes, "--generate-notes",
           *(["--prerelease"] if channel != "stable" else []))
    gh.run("release", "edit", version, "--repo", repo, "--draft=false",
           "--latest" if channel == "stable" else "--latest=false")
    print(f"published {title}")


def _write_outputs(values: dict[str, str]) -> None:
    for key, value in values.items():
        print(f"{key}={value}")
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a") as fh:
            fh.writelines(f"{k}={v}\n" for k, v in values.items())


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("plan")
    pub = sub.add_parser("publish")
    pub.add_argument("--version", required=True)
    pub.add_argument("--channel", choices=("stable", "nightly"), required=True)
    pub.add_argument("--commit", required=True)
    pub.add_argument("--dist", type=Path, default=Path("dist"))
    args = ap.parse_args(argv)

    repo = config.load().repo
    if args.cmd == "plan":
        _write_outputs(plan(repo, dt.datetime.now(dt.timezone.utc).date()))
    else:
        publish(repo, args.version, args.channel, args.commit, args.dist)
    return 0


if __name__ == "__main__":
    sys.exit(main())
