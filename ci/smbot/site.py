"""Assembles the GitHub Pages site (docs/PLAN.md, "Daily run", step 7).

  python3 -m smbot.site --dist dist --version V --channel C --out site
  python3 -m smbot.site --dist dist --version V --preview --out site   (preview.yml)

  /          the Contribute page (smbot.contribute)
  /play/     the latest stable web demo (the default)
  /nightly/  today's web build
  /preview/  the newest web build of main: rebuilt after merges (preview.yml), today's build after the daily run
  /screenshots/  today's screenshots (smbot.screenshots), when the build took any
  /style-guide/  the Style Guide page and the art starter kit zip (smbot.styleguide)
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

from . import config, contribute, gh, screenshots, styleguide

WEB_ZIPS = f"{config.load().game.slug}-web-*.zip"


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
    gh.run("release", "download", tag, "--repo", repo, "--pattern", WEB_ZIPS, "--dir", str(workdir))
    zips = sorted(workdir.glob(WEB_ZIPS))
    return (tag, zips[0]) if zips else None


def newest_release_web_zip(repo: str, workdir: Path) -> tuple[str, str, Path] | None:
    """Downloads the web build of the newest release, stable or nightly: (tag, channel, zip)."""
    try:
        rows = json.loads(gh.run("release", "list", "--repo", repo, "--exclude-drafts", "--limit", "1",
                                 "--json", "tagName,isPrerelease"))
    except (gh.GhError, ValueError):
        return None
    if not rows:
        return None
    tag, channel = rows[0]["tagName"], "nightly" if rows[0]["isPrerelease"] else "stable"
    gh.run("release", "download", tag, "--repo", repo, "--pattern", WEB_ZIPS, "--dir", str(workdir))
    zips = sorted(workdir.glob(WEB_ZIPS))
    return (tag, channel, zips[0]) if zips else None


def build(repo: str, dist: Path, version: str, channel: str, out: Path, shots: Path | None = None) -> None:
    """The daily site: today's release is /nightly/ and /preview/, and /play/ if it is stable."""
    _reset(out)
    today_zip = dist / WEB_ZIPS.replace("*", version)
    unpack(today_zip, out / "nightly")
    unpack(today_zip, out / "preview")

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
    _finish(out, version, channel, stable_name, version, shots)


def build_preview(repo: str, dist: Path, version: str, out: Path, shots: Path | None = None) -> None:
    """The site between daily runs: this build is /preview/; /nightly/ and /play/ come from the releases."""
    _reset(out)
    preview_zip = dist / WEB_ZIPS.replace("*", version)
    unpack(preview_zip, out / "preview")
    with tempfile.TemporaryDirectory() as tmp:
        (Path(tmp) / "newest").mkdir()
        (Path(tmp) / "stable").mkdir()
        newest = newest_release_web_zip(repo, Path(tmp) / "newest")
        stable = latest_stable_web_zip(repo, Path(tmp) / "stable")
        if newest:
            day_version, day_channel, day_zip = newest
        else:  # no release yet
            day_version, day_channel, day_zip = version, "preview", preview_zip
        unpack(day_zip, out / "nightly")
        if stable:
            stable_name, zip_path = stable
            unpack(zip_path, out / "play")
        else:
            stable_name = f"{day_version} ({day_channel})"
            unpack(day_zip, out / "play")
    _finish(out, day_version, day_channel, stable_name, version, shots)


def _reset(out: Path) -> None:
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)


def _finish(out: Path, version: str, channel: str, stable_name: str, preview: str, shots: Path | None) -> None:
    """Screenshots, Style Guide and the Contribute page, shared by the daily and the preview site."""
    if shots:
        screenshots.gallery(shots, out / "screenshots", preview)
    try:
        if styleguide.STYLE.exists():  # a new game has no style yet
            styleguide.build(out / "style-guide", shots)
    except (OSError, ValueError, KeyError) as exc:  # never keep today's build off the site
        print(f"::warning::the Style Guide page was not built: {exc}")
    cfg = config.load()
    page = contribute.render(cfg, contribute.gather(cfg), version, channel, stable_name, preview)
    (out / "index.html").write_text(page)
    (out / ".nojekyll").write_text("")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dist", type=Path, default=Path("dist"))
    ap.add_argument("--version", required=True)
    ap.add_argument("--channel", choices=("stable", "nightly"), help="the daily release's channel")
    ap.add_argument("--preview", action="store_true", help="a preview build of main, not a release")
    ap.add_argument("--out", type=Path, default=Path("site"))
    ap.add_argument("--screenshots", type=Path, help="folder of today's screenshots (optional)")
    args = ap.parse_args(argv)
    if args.preview == bool(args.channel):
        ap.error("give either --channel (daily) or --preview")
    repo = config.load().repo
    if args.preview:
        build_preview(repo, args.dist, args.version, args.out, args.screenshots)
    else:
        build(repo, args.dist, args.version, args.channel, args.out, args.screenshots)
    return 0


if __name__ == "__main__":
    sys.exit(main())
