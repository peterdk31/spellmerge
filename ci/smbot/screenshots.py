"""Posts the game's screenshots: on each bot PR, and as a gallery on the Pages site.

  python3 -m smbot.screenshots post --pr N --sha SHA --dir shots
      pushes the PNGs to the `screenshots` branch and comments on PR #N with them

The PNGs come from `ci/build/build.sh --quick --screenshots` (tests/screenshots/shot_*.gd
on a virtual display), run in a job with no secrets. They are only data here: each must
be a PNG under the size limit with a plain name, or it is left out. The images live on
an orphan branch so the PR comment can show them (the repository is public), under
pr-<N>/<sha7>/; the comment links them by commit, so later pushes never change it.
"""

from __future__ import annotations

import argparse
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from . import config as config_mod
from . import gh

BRANCH = "screenshots"
NAME = re.compile(r"^[a-z0-9_]{1,60}\.png$")
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
MAX_BYTES = 1_000_000
MAX_SHOTS = 12


def valid_shots(folder: Path) -> list[Path]:
    """The PNGs in `folder` that are safe to publish, sorted by name."""
    shots = []
    for path in sorted(folder.glob("*.png")) if folder.is_dir() else []:
        if (NAME.match(path.name) and path.is_file() and not path.is_symlink()
                and path.stat().st_size <= MAX_BYTES and path.read_bytes()[:8] == PNG_MAGIC):
            shots.append(path)
        else:
            print(f"skipping {path.name}: not a plain PNG under {MAX_BYTES} bytes")
    return shots[:MAX_SHOTS]


def title(path: Path) -> str:
    """arena_four_wizards.png -> 'Arena four wizards'."""
    return path.stem.replace("_", " ").capitalize()


def push(cfg: config_mod.Config, token: str, shots: list[Path], prefix: str, remote: str = "") -> str:
    """Adds the shots under `prefix` on the screenshots branch; returns the new commit."""
    remote = remote or f"https://x-access-token:{token}@github.com/{cfg.repo}.git"
    with tempfile.TemporaryDirectory() as tmp:
        def git(*args: str) -> str:
            return subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "-C", tmp, *args], check=True,
                                  capture_output=True, text=True).stdout.strip()

        git("init", "-q", "-b", BRANCH)
        git("config", "user.name", cfg.bot.login)
        git("config", "user.email", f"{cfg.bot.id}+{cfg.bot.login}@users.noreply.github.com")
        if subprocess.run(["git", "-C", tmp, "fetch", "-q", "--depth", "1", remote, BRANCH],
                          capture_output=True).returncode == 0:
            git("reset", "-q", "--hard", "FETCH_HEAD")
        dest = Path(tmp, prefix)
        dest.mkdir(parents=True, exist_ok=True)
        for shot in shots:
            shutil.copyfile(shot, dest / shot.name)
        git("add", "-A")
        git("commit", "-q", "--allow-empty", "-m", f"Screenshots for {prefix}")
        git("push", "-q", remote, f"HEAD:refs/heads/{BRANCH}")
        return git("rev-parse", "HEAD")


def comment(cfg: config_mod.Config, commit: str, prefix: str, shots: list[Path], sha: str) -> str:
    base = f"https://raw.githubusercontent.com/{cfg.repo}/{commit}/{prefix}"
    parts = [f"**Screenshots** of {sha[:7]} (640×360, taken by `ci/build/build.sh --quick --screenshots`)", ""]
    for shot in shots:
        parts += [f"**{title(shot)}**", "", f"![{title(shot)}]({base}/{shot.name})", ""]
    return "\n".join(parts)


def post(cfg: config_mod.Config, token: str, pr: int, sha: str, folder: Path) -> None:
    shots = valid_shots(folder)
    if not shots:
        print("no screenshots to post")
        return
    prefix = f"pr-{pr}/{sha[:7]}"
    commit = push(cfg, token, shots, prefix)
    gh.api(f"repos/{cfg.repo}/issues/{pr}/comments", "-X", "POST", input={"body": comment(cfg, commit, prefix, shots, sha)})
    print(f"posted {len(shots)} screenshot(s) on #{pr}")


def gallery(folder: Path, out: Path, version: str) -> bool:
    """Writes out/index.html with the shots of today's build; False when there are none."""
    shots = valid_shots(folder)
    if not shots:
        return False
    out.mkdir(parents=True, exist_ok=True)
    figures = []
    for shot in shots:
        shutil.copyfile(shot, out / shot.name)
        name = html.escape(title(shot))
        figures.append(f'<figure><img src="{html.escape(shot.name)}" alt="{name}" width="640" height="360">'
                       f"<figcaption>{name}</figcaption></figure>")
    (out / "index.html").write_text(f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Spellmerge screenshots</title>
<style>
body {{ background: #1b1a2e; color: #e8e6f0; font: 16px/1.5 system-ui, sans-serif; margin: 0 auto; max-width: 1340px; padding: 16px; }}
a {{ color: #f4c542; }}
.shots {{ display: grid; gap: 24px; grid-template-columns: repeat(auto-fill, minmax(min(100%, 640px), 1fr)); }}
figure {{ margin: 0; }}
img {{ width: 100%; height: auto; image-rendering: pixelated; border: 1px solid #3a3858; }}
</style></head><body>
<h1>Spellmerge screenshots</h1>
<p>Build {html.escape(version)}, taken by the daily build on a virtual display. <a href="../play/">Play the demo</a>.</p>
<div class="shots">
{chr(10).join(figures)}
</div>
</body></html>
""")
    return True


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("post")
    p.add_argument("--pr", type=int, required=True)
    p.add_argument("--sha", required=True)
    p.add_argument("--dir", type=Path, required=True)
    args = ap.parse_args(argv)
    if not re.fullmatch(r"[0-9a-f]{7,40}", args.sha):
        ap.error(f"not a commit sha: {args.sha!r}")
    post(config_mod.load(), os.environ["GH_TOKEN"], args.pr, args.sha, args.dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
