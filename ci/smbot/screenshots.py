"""Posts the game's screenshots: before and after on each bot PR, and as a gallery on the Pages site.

  python3 -m smbot.screenshots post --pr N --sha SHA --dir shots
      pushes the PNGs to the `screenshots` branch and comments on PR #N with them

A PR's screenshots show what it changes, and its clips show it in motion (smbot.clips: the
session names clip ids in `clips`, saved as clips.json; the recorder runs them on both sides
and the same comment shows them before and after). The session names the shot scripts that show its
change, each with a caption (`screenshots` in its result, saved as list.json). Only those
scripts run, on the PR's commit (after/) and on main (before/), with
`ci/build/build.sh --quick --screenshots` in a job with no secrets; shots.txt in each folder
says which script made which PNG. The comment shows each shot before and after, a new shot
alone, and leaves out shots that came out identical. With no scripts named, nothing is posted.
The session's Daily log post repeats the comment (`for_log`), since bot PRs merge on their own.

An owner question can name shot scripts too (`screenshots` in the question): they run on the
same commit, and the question shows them in its own body (`for_question`, called by smbot.inbox),
since the owner reads it after the PR has merged. A question that names none shows the PR's.

The files are only data here: each must be a PNG under the size limit with a plain name, or
it is left out. The images live on an orphan branch so the PR comment can show them (the
repository is public), under pr-<N>/<sha7>/; the comment links them by commit, so later
pushes never change it.
"""

from __future__ import annotations

import argparse
import html
import json
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
HEADING = "**What this PR changes on screen**"


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


def push(cfg: config_mod.Config, token: str, shots: list[Path], prefix: str, remote: str = "",
         names: list[str] | None = None, clear: bool = False) -> str:
    """Adds the shots under `prefix` on the screenshots branch (as `names`, if given); returns the new commit.

    With `clear`, whatever was under `prefix` before is removed first (the Spell atlas replaces itself).
    """
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
        if clear and dest.is_dir():
            shutil.rmtree(dest)
        for shot, name in zip(shots, names or [s.name for s in shots]):
            (dest / name).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(shot, dest / name)
        git("add", "-A")
        git("commit", "-q", "--allow-empty", "-m", f"Screenshots for {prefix}")
        git("push", "-q", remote, f"HEAD:refs/heads/{BRANCH}")
        return git("rev-parse", "HEAD")


SCRIPT = re.compile(r"^shot_[a-z0-9_]{1,60}$")
MAX_CAPTION = 300


MAX_QUESTION_SCRIPTS = 3


def chosen(folder: Path) -> list[dict[str, str]]:
    """The session's chosen scripts and captions (list.json), checked: names and lengths only."""
    try:
        data = json.loads((folder / "list.json").read_text())
    except (OSError, ValueError):
        return []
    return checked(data)[:6]


def checked(data: object) -> list[dict[str, str]]:
    """Scripts and captions as a session gave them, checked: names and lengths only."""
    out, seen = [], set()
    for entry in data if isinstance(data, list) else []:
        script = entry.get("script") if isinstance(entry, dict) else None
        if isinstance(script, str) and SCRIPT.match(script) and script not in seen:
            seen.add(script)
            caption = re.sub(r"@(?=[\w-])", "@\u200b", str(entry.get("caption", "")))[:MAX_CAPTION]
            out.append({"script": script, "caption": " ".join(caption.split())})
    return out


def made_by(folder: Path) -> dict[str, list[str]]:
    """shots.txt: script -> the PNG names it made (only valid shots)."""
    valid = {p.name for p in valid_shots(folder)}
    out: dict[str, list[str]] = {}
    try:
        lines = (folder / "shots.txt").read_text().splitlines()
    except OSError:
        return out
    for line in lines:
        script, _, name = line.partition(" ")
        if SCRIPT.match(script) and name in valid:
            out.setdefault(script, []).append(name)
    return out


def pairs(folder: Path) -> list[tuple[str, str, Path, Path | None]]:
    """(caption, name, after, before or None) for each chosen shot that changed or is new."""
    after, before = folder / "after", folder / "before"
    made_after, made_before = made_by(after), made_by(before)
    out = []
    for entry in chosen(folder):
        for name in made_after.get(entry["script"], []):
            old = before / name if name in made_before.get(entry["script"], []) else None
            if old is not None and old.read_bytes() == (after / name).read_bytes():
                continue  # identical: nothing to see
            out.append((entry["caption"], name, after / name, old))
    return out[:MAX_SHOTS]


def comment(cfg: config_mod.Config, commit: str, prefix: str, shown: list[tuple[str, str, Path, Path | None]],
            sha: str) -> str:
    base = f"https://raw.githubusercontent.com/{cfg.repo}/{commit}/{prefix}"
    parts = [f"{HEADING} ({sha[:7]} against `main`, 640×360)", ""]
    caption = None
    for text, name, _, old in shown:
        if text != caption:
            parts += [f"**{html.escape(text, quote=False) or title(Path(name))}**", ""]
            caption = text
        if old is None:
            parts += [f"New: *{title(Path(name))}*", "", f"![{title(Path(name))}]({base}/after/{name})", ""]
        else:
            parts += [f"*{title(Path(name))}*", "", "| Before (`main`) | After (this PR) |", "| --- | --- |",
                      f"| ![before]({base}/before/{name}) | ![after]({base}/after/{name}) |", ""]
    return "\n".join(parts)


def for_log(cfg: config_mod.Config, pr: int | str) -> str:
    """The bot's latest screenshots comment on PR #`pr`, worded for the Daily log; "" when there is none."""
    comments = gh.api_paginated(f"repos/{cfg.repo}/issues/{pr}/comments?per_page=100")
    mine = [c.get("body") or "" for c in comments
            if (c.get("user") or {}).get("login") == cfg.bot.login and (c.get("body") or "").startswith(HEADING)]
    return mine[-1].replace(HEADING, f"**What #{pr} changes on screen**", 1) if mine else ""


def post(cfg: config_mod.Config, token: str, pr: int, sha: str, folder: Path) -> None:
    from . import clips  # clips uses this module's push

    with tempfile.TemporaryDirectory() as work:
        shown, moving = pairs(folder), clips.pairs(folder, Path(work))
        if not shown and not moving:
            print("nothing visible changed in the chosen shots and clips (or none were chosen): nothing posted")
            return
        prefix = f"pr-{pr}/{sha[:7]}"
        files = [(after, f"after/{name}") for _, name, after, _ in shown]
        files += [(old, f"before/{name}") for _, name, _, old in shown if old is not None]
        files += [(after, f"clips/after/{clip.id}.png") for _, clip, after, _ in moving]
        files += [(old, f"clips/before/{clip.id}.png") for _, clip, _, old in moving if old is not None]
        commit = push(cfg, token, [f for f, _ in files], prefix, names=[n for _, n in files])
    body = comment(cfg, commit, prefix, shown, sha) if shown else f"{HEADING} ({sha[:7]} against `main`)"
    if moving:
        base = f"https://raw.githubusercontent.com/{cfg.repo}/{commit}/{prefix}/clips"
        body = body.rstrip() + "\n\n" + clips.section(base, moving)
    gh.api(f"repos/{cfg.repo}/issues/{pr}/comments", "-X", "POST", input={"body": body})
    print(f"posted {len(shown)} screenshot(s) and {len(moving)} clip(s) on #{pr}")


def for_question(cfg: config_mod.Config, token: str, question: dict, folder: Path, sha: str,
                 remote: str = "") -> str:
    """The shots an owner question names (its `screenshots`), as markdown for its body; "" when there are none.

    They were taken on `sha` (after/ in the screenshots artifact); they're pushed under
    questions/<sha7>/ so the question can show them.
    """
    made = made_by(folder / "after")
    shown = [(entry["caption"], name) for entry in checked(question.get("screenshots"))[:MAX_QUESTION_SCRIPTS]
             for name in made.get(entry["script"], [])][:MAX_SHOTS]
    if not shown:
        return ""
    prefix = f"questions/{sha[:7]}"
    commit = push(cfg, token, [folder / "after" / name for _, name in shown], prefix, remote)
    base = f"https://raw.githubusercontent.com/{cfg.repo}/{commit}/{prefix}"
    parts, caption = [], None
    for text, name in shown:
        if text != caption:
            parts += [f"**{html.escape(text, quote=False) or title(Path(name))}**", ""]
            caption = text
        parts += [f"![{title(Path(name))}]({base}/{name})", ""]
    return "\n".join(parts).strip()


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
<title>{html.escape(config_mod.load().game.name)} screenshots</title>
<style>
body {{ background: #1b1a2e; color: #e8e6f0; font: 16px/1.5 system-ui, sans-serif; margin: 0 auto; max-width: 1340px; padding: 16px; }}
a {{ color: #f4c542; }}
.shots {{ display: grid; gap: 24px; grid-template-columns: repeat(auto-fill, minmax(min(100%, 640px), 1fr)); }}
figure {{ margin: 0; }}
img {{ width: 100%; height: auto; image-rendering: pixelated; border: 1px solid #3a3858; }}
</style></head><body>
<h1>{html.escape(config_mod.load().game.name)} screenshots</h1>
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
