"""Clips: short looping animations of every spell, combo and reaction (#245), from the recorder's frames.

  python3 -m smbot.clips publish --dir clips --previous published/atlas --version V
      (daily.yml) encodes today's clips, pushes the Spell atlas to the `screenshots` branch and
      posts the clips that changed since yesterday to the Daily log

The recorder (tests/clips/record.gd, run by `ci/build/build.sh --quick --clips`) records each clip
on a virtual display and writes one folder per clip, copied to build/clips/:

  <id>/meta.json        {"id": "<id>", "kind": "combo", "title": "Shatter", "fps": 20}
  <id>/frame_0000.png   the frames in order, numbered from 0000 with no gap
  atlas.json            the Spell atlas data, from `python3 tools/atlas.py <out>` (optional)

`id` equals its folder name (a-z, 0-9 and _, at most 60 characters); `kind` is one of KINDS;
`title` is optional (the id is shown otherwise); `fps` is 1 to 60. The frames are PNGs of one
size, at most MAX_SIZE, 8-bit RGB or RGBA, not interlaced, at most MAX_FRAMES of them. The
recorder gets the ids to record as user arguments (`-- id_a id_b`; none means all of them).

atlas.json is {"entries": [...]}, one entry per component, combo and reaction:
{"id", "kind", "name", "description", "does", "clips": [clip ids], "source": "repo/path"}.
Only `id`, `kind` and `name` are required; `source` is the file that defines it, linked to its
history. Without atlas.json the atlas lists the clips by their meta.json.

A clip is encoded as an animated PNG built from the frames' own compressed data, so no image
library is needed and the pixel art stays exact; identical frames in a row become one longer
frame. Browsers and GitHub play it inline, and it is still a .png. Clips are build output and
never committed to main: they live on the `screenshots` branch and the Pages site, like the
screenshots. Everything in a clip folder is data: a file that breaks a rule is left out, with a
message, and never stops the build.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import shutil
import struct
import sys
import tempfile
import zlib
from dataclasses import dataclass
from pathlib import Path

from . import config as config_mod
from . import dailylog, gh, screenshots

KINDS = ("form", "element", "modifier", "trigger", "multicast", "combo", "reaction")
KIND_TITLES = {"form": "Forms", "element": "Elements", "modifier": "Modifiers", "trigger": "Triggers",
               "combo": "Combos", "reaction": "Reactions"}
ID = re.compile(r"^[a-z0-9_]{1,60}$")
FRAME = re.compile(r"^frame_(\d{4})\.png$")
SOURCE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_./-]{0,199}$")
MAX_FRAMES = 240
MAX_SIZE = (640, 360)
MAX_FRAME_BYTES = 1_000_000
MAX_CLIP_BYTES = 4_000_000
MAX_CLIPS = 400
MAX_PR_CLIPS = 4
MAX_LOG_CLIPS = 8
MAX_TEXT = 300
ATLAS = "atlas"  # the folder on the screenshots branch and on the site
HASHES = "hashes.json"
HEADING = "**What this PR changes in motion**"


@dataclass(frozen=True)
class Clip:
    id: str
    kind: str
    title: str
    fps: int
    frames: tuple[Path, ...]


def _chunks(data: bytes) -> list[tuple[bytes, bytes]]:
    """A PNG's chunks as (type, data), with every length and CRC checked."""
    if data[:8] != screenshots.PNG_MAGIC:
        raise ValueError("not a PNG")
    out, pos = [], 8
    while pos < len(data):
        if pos + 12 > len(data):
            raise ValueError("truncated chunk")
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if len(body) != length or pos + 12 + length > len(data):
            raise ValueError("truncated chunk")
        (crc,) = struct.unpack(">I", data[pos + 8 + length:pos + 12 + length])
        if zlib.crc32(kind + body) != crc:
            raise ValueError(f"bad CRC in {kind!r}")
        out.append((kind, body))
        pos += 12 + length
        if kind == b"IEND":
            break
    if not out or out[0][0] != b"IHDR" or out[-1][0] != b"IEND":
        raise ValueError("no IHDR first or no IEND last")
    return out


def read_frame(data: bytes) -> tuple[bytes, bytes]:
    """(IHDR, compressed image data) of one frame; ValueError when it is not a plain 8-bit RGB(A) PNG."""
    chunks = _chunks(data)
    ihdr = chunks[0][1]
    if len(ihdr) != 13:
        raise ValueError("bad IHDR")
    width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", ihdr)
    if not (0 < width <= MAX_SIZE[0] and 0 < height <= MAX_SIZE[1]):
        raise ValueError(f"{width}x{height} is over {MAX_SIZE[0]}x{MAX_SIZE[1]}")
    if depth != 8 or colour not in (2, 6) or interlace != 0:
        raise ValueError("not 8-bit RGB or RGBA without interlace")
    for kind, _ in chunks:
        if kind[0:1].isupper() and kind not in (b"IHDR", b"PLTE", b"IDAT", b"IEND"):
            raise ValueError(f"unknown critical chunk {kind!r}")
    idat = b"".join(body for kind, body in chunks if kind == b"IDAT")
    if not idat:
        raise ValueError("no image data")
    return ihdr, idat


def _chunk(kind: bytes, body: bytes) -> bytes:
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


def encode(frames: list[bytes], fps: int) -> bytes:
    """An animated PNG that loops forever, from frames of one size; identical frames in a row are merged."""
    if not frames:
        raise ValueError("no frames")
    runs: list[list] = []  # [compressed data, how many frames it stays]
    ihdr = b""
    for data in frames:
        header, idat = read_frame(data)
        if ihdr and header != ihdr:
            raise ValueError("frames differ in size or colour type")
        ihdr = header
        if runs and runs[-1][0] == idat:
            runs[-1][1] += 1
        else:
            runs.append([idat, 1])
    width, height = struct.unpack(">II", ihdr[:8])
    out = [screenshots.PNG_MAGIC, _chunk(b"IHDR", ihdr), _chunk(b"acTL", struct.pack(">II", len(runs), 0))]
    seq = 0
    for index, (idat, count) in enumerate(runs):
        # fcTL: sequence, size, offset 0,0, delay count/fps seconds, dispose none, blend source.
        out.append(_chunk(b"fcTL", struct.pack(">IIIIIHHBB", seq, width, height, 0, 0, count, fps, 0, 0)))
        seq += 1
        if index == 0:
            out.append(_chunk(b"IDAT", idat))  # the first frame is also the still image
        else:
            out.append(_chunk(b"fdAT", struct.pack(">I", seq) + idat))
            seq += 1
    out.append(_chunk(b"IEND", b""))
    return b"".join(out)


def _text(value: object, limit: int = MAX_TEXT) -> str:
    """A plain one-line string from the data, at most `limit` characters; mentions can't ping anyone."""
    text = " ".join(str(value).split())[:limit] if isinstance(value, (str, int, float)) else ""
    return re.sub(r"@(?=[\w-])", "@​", text)


def load(folder: Path) -> Clip | None:
    """The clip in `folder`, checked against the format above; None (with a message) when it breaks a rule."""
    def skip(why: str) -> None:
        print(f"skipping clip {folder.name}: {why}")

    if folder.is_symlink() or not folder.is_dir() or not ID.match(folder.name):
        return skip("not a plain folder named like a clip id")
    try:
        meta = json.loads((folder / "meta.json").read_text())
    except (OSError, ValueError):
        return skip("no readable meta.json")
    if not isinstance(meta, dict) or meta.get("id") != folder.name:
        return skip("meta.json's id is not the folder name")
    kind, fps = meta.get("kind"), meta.get("fps")
    if kind not in KINDS:
        return skip(f"kind {kind!r} is not one of {', '.join(KINDS)}")
    if not isinstance(fps, int) or isinstance(fps, bool) or not 1 <= fps <= 60:
        return skip("fps is not a whole number from 1 to 60")
    frames = sorted(p for p in folder.iterdir() if FRAME.match(p.name))
    if not frames or len(frames) > MAX_FRAMES:
        return skip(f"needs 1 to {MAX_FRAMES} frames, has {len(frames)}")
    if [int(FRAME.match(p.name).group(1)) for p in frames] != list(range(len(frames))):
        return skip("frames are not numbered from frame_0000.png with no gap")
    for path in frames:
        if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_FRAME_BYTES:
            return skip(f"{path.name} is not a plain file under {MAX_FRAME_BYTES} bytes")
    return Clip(folder.name, kind, _text(meta.get("title"), 80) or folder.name.replace("_", " ").capitalize(),
                fps, tuple(frames))


def clips_in(root: Path) -> list[Clip]:
    """Every valid clip under `root`, by kind (in KINDS order) and then id."""
    found = [c for p in sorted(root.iterdir() if root.is_dir() else []) if p.is_dir() and (c := load(p))]
    found.sort(key=lambda c: (KINDS.index(c.kind), c.id))
    return found[:MAX_CLIPS]


def encode_clip(clip: Clip) -> bytes | None:
    """The clip as an animated PNG; None (with a message) when a frame is broken or it is too big."""
    try:
        data = encode([p.read_bytes() for p in clip.frames], clip.fps)
    except (OSError, ValueError) as exc:
        print(f"skipping clip {clip.id}: {exc}")
        return None
    if len(data) > MAX_CLIP_BYTES:
        print(f"skipping clip {clip.id}: {len(data)} bytes is over {MAX_CLIP_BYTES} (crop it or use fewer frames)")
        return None
    return data


def encode_all(root: Path, out: Path) -> dict[str, tuple[Clip, Path]]:
    """Writes out/<id>.png for every valid clip under `root`; returns id -> (clip, file)."""
    out.mkdir(parents=True, exist_ok=True)
    done = {}
    for clip in clips_in(root):
        if (data := encode_clip(clip)) is not None:
            (out / f"{clip.id}.png").write_bytes(data)
            done[clip.id] = (clip, out / f"{clip.id}.png")
    return done


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# The Spell atlas page

def entries(root: Path, encoded: dict[str, tuple[Clip, Path]]) -> list[dict]:
    """The atlas entries: atlas.json checked, or one entry per clip when there is none."""
    try:
        data = json.loads((root / "atlas.json").read_text())
    except (OSError, ValueError):
        data = None
    rows = data.get("entries") if isinstance(data, dict) else None
    if not isinstance(rows, list):
        return [{"id": c.id, "kind": c.kind, "name": c.title, "description": "", "does": "", "clips": [c.id],
                 "source": ""} for c, _ in encoded.values()]
    out, seen = [], set()
    for row in rows[:MAX_CLIPS]:
        if not isinstance(row, dict) or row.get("kind") not in KINDS:
            continue
        key = (row["kind"], row.get("id"))
        if not (isinstance(row.get("id"), str) and ID.match(row["id"])) or key in seen or not _text(row.get("name")):
            continue
        seen.add(key)
        source = row.get("source") if isinstance(row.get("source"), str) else ""
        clip_ids = row.get("clips") if isinstance(row.get("clips"), list) else []
        out.append({"id": row["id"], "kind": row["kind"], "name": _text(row["name"], 80),
                    "description": _text(row.get("description", "")), "does": _text(row.get("does", "")),
                    "clips": [c for c in clip_ids if isinstance(c, str) and ID.match(c)][:4],
                    "source": source if SOURCE.match(source) and ".." not in source else ""})
    out.sort(key=lambda e: (KINDS.index(e["kind"]), e["name"].lower()))
    return out


def atlas_page(root: Path, out: Path, version: str, repo: str) -> int:
    """Writes the Spell atlas (out/index.html, the clips and hashes.json); returns how many clips it holds."""
    encoded = encode_all(root, out)
    rows = entries(root, encoded)
    esc = html.escape
    sections = []
    for kind in KINDS:
        cards = []
        for row in (r for r in rows if r["kind"] == kind):
            anchor = f"{kind}-{row['id']}"
            media = [f'<figure id="clip-{esc(c)}"><img src="{esc(c)}.png" alt="{esc(encoded[c][0].title)}" loading="lazy">'
                     f"<figcaption>{esc(encoded[c][0].title)}</figcaption></figure>"
                     for c in row["clips"] if c in encoded]
            text = [f'<p class="what">{esc(row["description"])}</p>' if row["description"] else "",
                    f'<p>{esc(row["does"])}</p>' if row["does"] else "",
                    "".join(media) or '<p class="none">No clip yet.</p>',
                    f'<p class="src"><a href="https://github.com/{esc(repo)}/commits/main/{esc(row["source"])}">'
                    f"History of {esc(row['source'])}</a></p>" if row["source"] else ""]
            cards.append(f'<article id="{esc(anchor)}"><h3><a href="#{esc(anchor)}">{esc(row["name"])}</a></h3>'
                         + "".join(text) + "</article>")
        if cards:
            sections.append(f'<section id="{kind}"><h2>{KIND_TITLES[kind]} ({len(cards)})</h2>'
                            f'<div class="cards">{"".join(cards)}</div></section>')
    nav = " · ".join(f'<a href="#{k}">{KIND_TITLES[k]}</a>' for k in KINDS if any(r["kind"] == k for r in rows))
    game = esc(config_mod.load().game.name)
    (out / "index.html").write_text(f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{game} spell atlas</title>
<style>
body {{ background: #1b1a2e; color: #e8e6f0; font: 16px/1.5 system-ui, sans-serif; margin: 0 auto; max-width: 1340px; padding: 16px; }}
a {{ color: #f4c542; }}
h3 a {{ color: inherit; text-decoration: none; }}
.cards {{ display: grid; gap: 24px; grid-template-columns: repeat(auto-fill, minmax(min(100%, 320px), 1fr)); }}
article {{ border: 1px solid #3a3858; padding: 12px; }}
h3 {{ margin: 0 0 4px; }}
p {{ margin: 4px 0; }}
.what {{ color: #c9c5dc; font-style: italic; }}
.none, .src {{ color: #8f8ba8; font-size: 14px; }}
figure {{ margin: 8px 0; }}
figcaption {{ color: #8f8ba8; font-size: 14px; }}
img {{ width: 100%; height: auto; image-rendering: pixelated; border: 1px solid #3a3858; background: #14121f; }}
</style></head><body>
<h1>{game} spell atlas</h1>
<p>Every component, combo and reaction, recorded on build {esc(version)} by the daily run (virtual display,
fixed seed). {nav}</p>
<p><a href="../play/">Play the demo</a> · <a href="../screenshots/">Screenshots</a></p>
{chr(10).join(sections) or "<p>No clips were recorded yet.</p>"}
</body></html>
""")
    (out / HASHES).write_text(json.dumps({cid: digest(path) for cid, (_, path) in encoded.items()}, indent=1,
                                         sort_keys=True) + "\n")
    return len(encoded)


# Before and after on a PR

def chosen(folder: Path) -> list[dict[str, str]]:
    """The session's chosen clips and captions (clips.json), checked: ids and lengths only."""
    try:
        data = json.loads((folder / "clips.json").read_text())
    except (OSError, ValueError):
        return []
    out, seen = [], set()
    for entry in data if isinstance(data, list) else []:
        cid = entry.get("id") if isinstance(entry, dict) else None
        if isinstance(cid, str) and ID.match(cid) and cid not in seen:
            seen.add(cid)
            out.append({"id": cid, "caption": _text(entry.get("caption", ""))})
    return out[:MAX_PR_CLIPS]


def pairs(folder: Path, work: Path) -> list[tuple[str, Clip, Path, Path | None]]:
    """(caption, clip, after, before or None) for each chosen clip that changed or is new, encoded into `work`."""
    out = []
    for entry in chosen(folder):
        after_clip = load(folder / "after" / "clips" / entry["id"])
        after = encode_clip(after_clip) if after_clip else None
        if after is None:
            continue
        before_dir = folder / "before" / "clips" / entry["id"]
        before_clip = load(before_dir) if before_dir.is_dir() else None  # a clip the PR adds has no before
        before = encode_clip(before_clip) if before_clip else None
        if before == after:
            continue  # identical: nothing to see
        (work / "after").mkdir(parents=True, exist_ok=True)
        (work / "after" / f"{entry['id']}.png").write_bytes(after)
        old = None
        if before is not None:
            (work / "before").mkdir(parents=True, exist_ok=True)
            old = work / "before" / f"{entry['id']}.png"
            old.write_bytes(before)
        out.append((entry["caption"], after_clip, work / "after" / f"{entry['id']}.png", old))
    return out


def section(base: str, shown: list[tuple[str, Clip, Path, Path | None]]) -> str:
    """Markdown for the chosen clips, before and after; `base` is the folder's raw URL."""
    parts = [HEADING, ""]
    for caption, clip, _, old in shown:
        name = html.escape(clip.title, quote=False)
        parts += [f"**{html.escape(caption, quote=False) or name}**", ""]
        if old is None:
            parts += [f"New: *{name}*", "", f"![{name}]({base}/after/{clip.id}.png)", ""]
        else:
            parts += [f"*{name}*", "", "| Before (`main`) | After (this PR) |", "| --- | --- |",
                      f"| ![before]({base}/before/{clip.id}.png) | ![after]({base}/after/{clip.id}.png) |", ""]
    return "\n".join(parts)


# The daily run: the atlas on the screenshots branch, and what changed in the Daily log

def changed(today: dict[str, str], previous: dict[str, str]) -> tuple[list[str], list[str]]:
    """(new ids, changed ids) between two hashes.json maps."""
    new = sorted(c for c in today if c not in previous)
    return new, sorted(c for c in today if c in previous and today[c] != previous[c])


def read_hashes(folder: Path | None) -> dict[str, str]:
    try:
        data = json.loads((folder / HASHES).read_text()) if folder else {}
    except (OSError, ValueError):
        return {}
    return {k: v for k, v in data.items() if isinstance(k, str) and ID.match(k) and isinstance(v, str)} \
        if isinstance(data, dict) else {}


def log_post(cfg: config_mod.Config, version: str, encoded: dict[str, Clip], new: list[str], diff: list[str],
             base: str) -> tuple[list[str], str]:
    """The Daily log post: (lines, markdown with the clips that changed today)."""
    atlas = f"{cfg.pages}/{ATLAS}/"
    lines = [f"Clips on {version}: {len(new)} new, {len(diff)} changed, {len(encoded)} in all. "
             f"[Spell atlas]({atlas})"]
    shown = (diff + new)[:MAX_LOG_CLIPS]
    parts = []
    for cid in shown:
        clip = encoded[cid]
        label = "New" if cid in new else "Changed"
        parts += [f"**{html.escape(clip.title, quote=False)}** ({label.lower()}, {clip.kind}) · "
                  f"[in the atlas]({atlas}#clip-{cid})", "", f"![{html.escape(clip.title)}]({base}/{cid}.png)",
                  ""]
    if len(diff) + len(new) > len(shown):
        parts.append(f"And {len(diff) + len(new) - len(shown)} more in the [Spell atlas]({atlas}).")
    return lines, "\n".join(parts)


def publish(cfg: config_mod.Config, token: str, folder: Path, previous: Path | None, version: str,
            remote: str = "") -> None:
    """Pushes the atlas (replacing yesterday's) and today's changed clips to the screenshots branch, then posts them."""
    with tempfile.TemporaryDirectory() as tmp:
        page = Path(tmp, ATLAS)
        count = atlas_page(folder, page, version, cfg.repo)
        if not count:
            print("no clips were recorded: the atlas and the Daily log are left as they are")
            return
        today = read_hashes(page)
        new, diff = changed(today, read_hashes(previous))
        clips = {c.id: c for c in clips_in(folder) if c.id in today}
        files = sorted(page.iterdir())
        commit = screenshots.push(cfg, token, files, ATLAS, remote, clear=True)
        print(f"published the atlas with {count} clip(s) on the {screenshots.BRANCH} branch")
        if not new and not diff:
            print("no clip changed since the last atlas: nothing posted")
            return
        lines, extra = log_post(cfg, version, clips, new, diff,
                                f"https://raw.githubusercontent.com/{cfg.repo}/{commit}/{ATLAS}")
        dailylog.post(cfg, "Clips", lines, extra=extra)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("publish")
    p.add_argument("--dir", type=Path, required=True, help="the recorder's clips (build/clips)")
    p.add_argument("--previous", type=Path, help="the atlas published last time (for what changed)")
    p.add_argument("--version", required=True)
    args = ap.parse_args(argv)
    publish(config_mod.load(), os.environ["GH_TOKEN"], args.dir, args.previous, args.version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
