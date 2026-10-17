"""Assembles the GitHub Pages site (docs/PLAN.md, "Daily run", step 7).

  python3 -m smbot.site --dist dist --version V --channel C --out site

  /          the Contribute page (smbot.contribute)
  /play/     the latest stable web demo (the default)
  /nightly/  today's web build
  /screenshots/  today's screenshots (smbot.screenshots), when the build took any
  /style-guide/  the Style Guide page and the art starter kit zip (smbot.styleguide)
"""

from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

from . import config, contribute, gh, screenshots, styleguide


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


def build(repo: str, dist: Path, version: str, channel: str, out: Path, shots: Path | None = None) -> None:
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

    if shots:
        screenshots.gallery(shots, out / "screenshots", version)
    try:
        styleguide.build(out / "style-guide", shots / "arena_four_wizards.png" if shots else None)
    except (OSError, ValueError, KeyError) as exc:  # never keep today's build off the site
        print(f"::warning::the Style Guide page was not built: {exc}")
    cfg = config.load()
    page = contribute.render(cfg, contribute.gather(cfg), version, channel, stable_name)
    (out / "index.html").write_text(page)
    (out / ".nojekyll").write_text("")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dist", type=Path, default=Path("dist"))
    ap.add_argument("--version", required=True)
    ap.add_argument("--channel", choices=("stable", "nightly"), required=True)
    ap.add_argument("--out", type=Path, default=Path("site"))
    ap.add_argument("--screenshots", type=Path, help="folder of today's screenshots (optional)")
    args = ap.parse_args(argv)
    build(config.load().repo, args.dist, args.version, args.channel, args.out, args.screenshots)
    return 0


if __name__ == "__main__":
    sys.exit(main())
