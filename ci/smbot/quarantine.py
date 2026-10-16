"""Copyright quarantine (docs/PLAN.md, "Response to a concern").

  python3 -m smbot.quarantine

For each open issue labelled `copyright` that hasn't been handled: the reported
asset is replaced by a placeholder (images: a same-size magenta checkerboard;
writing: a notice; audio: removed) and marked `quarantined` in the manifest,
through an automated bot PR that the daily merge step merges before the build.
So the asset is out of the next build while it's investigated. The owner is
notified. Restoring it, if the report turns out wrong, is a normal PR.
"""

from __future__ import annotations

import json
import os
import re
import struct
import subprocess
import sys
import zlib
from pathlib import Path, PurePosixPath

from . import config as config_mod
from . import dailylog, gh
from .submissions import PNG_SIG, _chunk, parse_form

HANDLED = "copyright:quarantined"
ASSET_TYPES = (".png", ".svg", ".ogg", ".json")


def placeholder_png(width: int, height: int) -> bytes:
    """A magenta and black 4×4 checkerboard, unmistakably a placeholder."""
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            on = ((x // 4) + (y // 4)) % 2 == 0
            row += bytes((255, 0, 255, 255) if on else (0, 0, 0, 255))
        rows.append(bytes(row))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return PNG_SIG + _chunk(b"IHDR", ihdr) + _chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + _chunk(b"IEND", b"")


def png_size(data: bytes) -> tuple[int, int]:
    width, height = struct.unpack(">II", data[16:24])
    return width, height


def quarantine_files(path: str, issue: int, repo: str) -> list[str]:
    """Changes the working tree; returns the paths it touched."""
    p = Path(path)
    touched = [path]
    suffix = PurePosixPath(path).suffix
    if suffix == ".png":
        w, h = png_size(p.read_bytes())
        p.write_bytes(placeholder_png(w, h))
    elif suffix == ".svg":
        p.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32" '
                     'fill="#ff00ff"/></svg>\n')
    elif suffix == ".json":
        p.write_text(json.dumps({"text": f"[Quarantined while a copyright report is checked: "
                                         f"https://github.com/{repo}/issues/{issue}]"}) + "\n")
    else:
        p.unlink()
    for manifest in (Path("art/manifest.json"), Path("audio/manifest.json")):
        if manifest.exists():
            data = json.loads(manifest.read_text())
            for asset in data.get("assets", []):
                if asset["path"] == path:
                    asset["quarantined"] = f"https://github.com/{repo}/issues/{issue}"
                    manifest.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
                    touched.append(str(manifest))
    return touched


def run(cfg: config_mod.Config, token: str) -> list[str]:
    log = []
    for issue in gh.api_paginated(f"repos/{cfg.repo}/issues?state=open&labels=copyright&per_page=100"):
        if "pull_request" in issue or any(lab["name"] == HANDLED for lab in issue["labels"]):
            continue
        number = issue["number"]
        path = parse_form(issue["body"] or "").get("File", "").strip().strip("`").lstrip("/")
        p = PurePosixPath(path)
        if not path or ".." in p.parts or p.suffix not in ASSET_TYPES or not Path(path).is_file() \
                or path.startswith(("ci/", ".github/", "docs/")):
            gh.api(f"repos/{cfg.repo}/issues/{number}/comments", "-X", "POST", input={
                "body": f"Thanks for the report. `{path or '(no path)'}` isn't an asset in the repository, so nothing "
                        "was quarantined automatically. The owner has been notified and will look at it."})
            log.append(f"Copyright report #{number}: couldn't find asset `{path}`")
            gh.api(f"repos/{cfg.repo}/issues/{number}/labels", "-X", "POST", input={"labels": [HANDLED]})
            continue
        branch = f"automation/quarantine-{number}"
        subprocess.run(["git", "switch", "--quiet", "-C", branch, "origin/main"], check=True)
        touched = quarantine_files(path, number, cfg.repo)
        subprocess.run(["git", "add", "-A", "--", *touched], check=True)
        subprocess.run(["git", "-c", f"user.name={cfg.bot.login}", "-c",
                        f"user.email={cfg.bot.id}+{cfg.bot.login}@users.noreply.github.com",
                        "commit", "--quiet", "-m", f"Quarantine {path} (copyright report #{number})"], check=True)
        subprocess.run(["git", "push", "--quiet", "--force",
                        f"https://x-access-token:{token}@github.com/{cfg.repo}.git", f"HEAD:refs/heads/{branch}"],
                       check=True)
        subprocess.run(["git", "switch", "--quiet", "--detach", "origin/main"], check=True)
        pr = gh.api(f"repos/{cfg.repo}/pulls", "-X", "POST", input={
            "title": f"Quarantine {path} (copyright report #{number})", "head": branch, "base": "main",
            "body": f"Automatic quarantine for #{number}: the asset is replaced by a placeholder and excluded from the "
                    "next build while the report is checked.",
        })
        gh.api(f"repos/{cfg.repo}/issues/{pr['number']}/labels", "-X", "POST", input={"labels": ["automated"]})
        gh.api(f"repos/{cfg.repo}/issues/{number}/labels", "-X", "POST", input={"labels": [HANDLED]})
        gh.api(f"repos/{cfg.repo}/issues/{number}/comments", "-X", "POST", input={
            "body": f"Thank you. `{path}` is quarantined in #{pr['number']}: replaced by a placeholder and left out of "
                    "the next build while this is checked. If copying is confirmed, it's removed for good and the "
                    "contributor's other submissions are re-reviewed."})
        log.append(f"Copyright report #{number}: quarantining `{path}` in #{pr['number']}")
    return log


def allowed_quarantine_change(files: set[str], title: str) -> bool:
    """An automated quarantine PR may only touch the reported asset and the manifests."""
    m = re.match(r"Quarantine (\S+) \(copyright report #\d+\)$", title)
    return bool(m) and files <= {m.group(1), "art/manifest.json", "audio/manifest.json"}


def main() -> int:
    cfg = config_mod.load()
    log = run(cfg, os.environ["GH_TOKEN"])
    dailylog.post(cfg, "Copyright reports", log, mention_owner=bool(log))
    return 0


if __name__ == "__main__":
    sys.exit(main())
