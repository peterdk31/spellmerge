"""Assembles the GitHub Pages site (docs/PLAN.md, "Daily run", step 7).

  python3 -m smbot.site --dist dist --version V --channel C --out site

  /          landing page (the full Contribute page arrives with onboarding)
  /play/     the latest stable web demo (the default)
  /nightly/  today's web build
"""

from __future__ import annotations

import argparse
import html
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

from . import config, gh


def unpack(zip_path: Path, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as zf:
        for member in zf.namelist():
            # Our own zips, but never write outside dest regardless.
            target = (dest / member).resolve()
            if not target.is_relative_to(dest.resolve()):
                raise ValueError(f"unsafe path in {zip_path}: {member}")
        zf.extractall(dest)


def latest_stable_web_zip(repo: str, workdir: Path) -> tuple[str, Path] | None:
    """Downloads the web build of the latest stable release, if there is one."""
    try:
        tag = gh.run("release", "view", "--repo", repo, "--json", "tagName", "--jq", ".tagName").strip()
    except gh.GhError:
        return None
    gh.run("release", "download", tag, "--repo", repo, "--pattern", "spellmerge-web-*.zip", "--dir", str(workdir))
    zips = sorted(workdir.glob("spellmerge-web-*.zip"))
    return (tag, zips[0]) if zips else None


def landing_page(repo: str, version: str, channel: str, stable: str) -> str:
    esc = html.escape
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Spellmerge</title>
<style>
  :root {{ color-scheme: dark; --bg: #1b1830; --fg: #e8e6f5; --muted: #9a98b8; --accent: #f2c14e; }}
  body {{ margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.5 system-ui, sans-serif; }}
  main {{ max-width: 40rem; margin: 0 auto; padding: 3rem 1rem; }}
  h1 {{ color: var(--accent); font-size: 2.5rem; margin: 0; }}
  .tag {{ color: var(--muted); margin-top: 0.25rem; }}
  a {{ color: var(--accent); }}
  .buttons a {{ display: inline-block; margin: 1.5rem 1rem 0 0; padding: 0.6rem 1.2rem; border: 2px solid var(--accent);
                border-radius: 4px; text-decoration: none; font-weight: 600; }}
  .small {{ color: var(--muted); font-size: 0.9rem; margin-top: 2.5rem; }}
</style>
</head>
<body>
<main>
  <h1>Spellmerge</h1>
  <p class="tag">Merge spells. Cause chaos. Together.</p>
  <p>A 2D roguelite about building deep, combinable spells, for 1&ndash;4 local co-op players.
     Claude writes the code, reviews community pull requests and ships a new build every day.</p>
  <p><strong>Status:</strong> milestone M0, the foundation. There is nothing to play yet.</p>
  <div class="buttons">
    <a href="play/">Play {esc(stable)}</a>
    <a href="nightly/">Today's build: {esc(version)}</a>
  </div>
  <p class="small">
    <a href="https://github.com/{esc(repo)}">Source on GitHub</a> &middot;
    <a href="https://github.com/{esc(repo)}/releases">Downloads for Windows and Linux</a><br>
    Today's build is {esc(channel)}. Free on the web forever; code GPL-3.0-or-later, assets CC-BY-SA-4.0.
  </p>
</main>
</body>
</html>
"""


def build(repo: str, dist: Path, version: str, channel: str, out: Path) -> None:
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    today_zip = dist / f"spellmerge-web-{version}.zip"
    unpack(today_zip, out / "nightly")

    if channel == "stable":
        stable_name = version
        unpack(today_zip, out / "play")
    else:
        with tempfile.TemporaryDirectory() as tmp:
            found = latest_stable_web_zip(repo, Path(tmp))
            if found:
                stable_name, zip_path = found
                unpack(zip_path, out / "play")
            else:  # no stable release yet
                stable_name = f"{version} (nightly)"
                unpack(today_zip, out / "play")

    (out / "index.html").write_text(landing_page(repo, version, channel, stable_name))
    (out / ".nojekyll").write_text("")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dist", type=Path, default=Path("dist"))
    ap.add_argument("--version", required=True)
    ap.add_argument("--channel", choices=("stable", "nightly"), required=True)
    ap.add_argument("--out", type=Path, default=Path("site"))
    args = ap.parse_args(argv)
    build(config.load().repo, args.dist, args.version, args.channel, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
