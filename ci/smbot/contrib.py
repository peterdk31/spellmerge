"""Outside contributions: the CLA, and art or sound attached to a discussion (docs/PLAN.md, "Community intake").

  python3 -m smbot.contrib assets    downloads, checks and re-encodes the attachments that the
                                     intake's decisions ($DECISIONS) take as assets, into
                                     submissions/ (runs with no secrets: the files are untrusted)

The CLA: before a contributor's PR or files are used, they sign CLA.md once by posting
"I have read the CLA and I agree to it." on their PR or discussion. A signature counts for
the CLA version current when it was posted. Signatures live in docs/cla-signatures.json (the
older ones) and the automation state (`cla_signatures`), each with a link to the comment.
"""

from __future__ import annotations

import json
import os
import re
import struct
import subprocess
import sys
import urllib.request
import zlib
from pathlib import Path, PurePosixPath
from typing import Any

SIGNATURES = Path("docs/cla-signatures.json")
CLA_FILE = Path("CLA.md")
PHRASE = "i have read the cla and i agree to it"
CLA_REQUEST = ("Before your work can be used, please sign the [Contributor License Agreement]({url}) once, by "
               "posting this exact comment here:\n\n> I have read the CLA and I agree to it.\n\n"
               "In short: you keep the copyright, the project may use and relicense your work (for example for "
               "Steam), and you confirm it is yours to give.")


def current_version(text: str | None = None) -> str:
    text = text if text is not None else CLA_FILE.read_text()
    m = re.search(r"\*\*Version ([0-9.]+)", text)
    if not m:
        raise ValueError("CLA.md has no version line")
    return m.group(1)


def is_signing_comment(body: str) -> bool:
    return " ".join(re.sub(r"[^a-z ]+", " ", (body or "").lower()).split()) == PHRASE


def has_signed(st: dict[str, Any], user_id: int, version: str, path: Path = SIGNATURES) -> bool:
    on_file = json.loads(path.read_text())["signatures"] if path.exists() else []
    in_state = list(st.get("cla_signatures", {}).values())
    return any(s.get("user_id") == user_id and s.get("version") == version for s in on_file + in_state)


def find_signature(comments: list[dict[str, Any]], author: str, version: str) -> dict[str, Any] | None:
    """The author's signing comment among `comments` (each: author, author_id, body, url, at), if any."""
    for c in comments:
        if c.get("author") == author and c.get("author_id") and is_signing_comment(c.get("body", "")):
            return {"user_id": c["author_id"], "login": author, "version": version, "signed_at": c.get("at", ""),
                    "evidence": c.get("url", "")}
    return None


# --- Attachments -------------------------------------------------------------------

ATTACHMENT = re.compile(r"https://(?:github\.com/user-attachments/(?:assets|files)/[\w./%-]+|"
                        r"user-images\.githubusercontent\.com/[\w./%-]+)")
MAX_BYTES = {".png": 1_000_000, ".ogg": 5_000_000}
ASSET_DIRS = ("art/", "audio/", "content/")
OUT = Path("submissions")
PNG_SIG = b"\x89PNG\r\n\x1a\n"
CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
MAX_ASSETS = 10  # per discussion


class Invalid(ValueError):
    pass


def check_path(path: str) -> str:
    """A target path inside the asset folders, with an allowed extension."""
    p = PurePosixPath(path)
    if p.is_absolute() or ".." in p.parts or p.suffix not in MAX_BYTES or not path.startswith(ASSET_DIRS):
        raise Invalid(f"{path!r} must be a .png or .ogg path under {', '.join(ASSET_DIRS)}")
    return str(p)


def _chunks(data: bytes) -> list[tuple[bytes, bytes]]:
    if not data.startswith(PNG_SIG):
        raise Invalid("not a PNG file")
    pos, out = len(PNG_SIG), []
    while pos < len(data):
        if pos + 8 > len(data):
            raise Invalid("truncated PNG")
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        crc = data[pos + 8 + length:pos + 12 + length]
        if len(body) != length or len(crc) != 4 or zlib.crc32(kind + body) != struct.unpack(">I", crc)[0]:
            raise Invalid("corrupt PNG chunk")
        out.append((kind, body))
        pos += 12 + length
        if kind == b"IEND":
            break
    if pos != len(data):
        raise Invalid("data after the end of the PNG")
    return out


def _chunk(kind: bytes, body: bytes) -> bytes:
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


def reencode_png(data: bytes, max_side: int = 4096) -> tuple[bytes, int, int]:
    """Decodes and re-encodes a PNG, keeping only IHDR, PLTE, tRNS and the pixels."""
    chunks = _chunks(data)
    if not chunks or chunks[0][0] != b"IHDR":
        raise Invalid("PNG without a header")
    width, height, depth, color, comp, filt, interlace = struct.unpack(">IIBBBBB", chunks[0][1])
    if not (0 < width <= max_side and 0 < height <= max_side):
        raise Invalid(f"image size {width}×{height} is out of range")
    if color not in CHANNELS or comp != 0 or filt != 0 or interlace != 0:
        raise Invalid("unsupported PNG format (save as a non-interlaced RGBA or indexed PNG)")
    raw = zlib.decompress(b"".join(body for kind, body in chunks if kind == b"IDAT"))
    row_bytes = (width * CHANNELS[color] * depth + 7) // 8
    if len(raw) != height * (row_bytes + 1):
        raise Invalid("PNG pixel data has the wrong length")
    if any(raw[i * (row_bytes + 1)] > 4 for i in range(height)):
        raise Invalid("PNG uses an unknown row filter")
    keep = [_chunk(kind, body) for kind, body in chunks if kind in (b"PLTE", b"tRNS")]
    out = PNG_SIG + _chunk(b"IHDR", chunks[0][1]) + b"".join(keep) + _chunk(b"IDAT", zlib.compress(raw, 9)) \
        + _chunk(b"IEND", b"")
    return out, width, height


def download(url: str, limit: int) -> bytes:
    if not ATTACHMENT.fullmatch(url):
        raise Invalid("only files attached on GitHub can be used")
    req = urllib.request.Request(url, headers={"User-Agent": "spellmerge-intake"})
    with urllib.request.urlopen(req, timeout=60) as resp:  # noqa: S310 (hosts checked above and below)
        final = resp.geturl()
        if not final.startswith(("https://github.com/", "https://objects.githubusercontent.com/",
                                 "https://github-production-user-asset-", "https://user-images.githubusercontent.com/",
                                 "https://private-user-images.githubusercontent.com/")):
            raise Invalid("the attachment didn't come from GitHub")
        data = resp.read(limit + 1)
    if len(data) > limit:
        raise Invalid(f"the file is larger than {limit // 1_000_000} MB")
    return data


def prepare_asset(url: str, path: str, out: Path) -> str:
    """Downloads one attachment and writes its re-encoded file to out/path; returns a short description."""
    target = out / check_path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    data = download(url, MAX_BYTES[target.suffix])
    if target.suffix == ".png":
        png, w, h = reencode_png(data)
        target.write_bytes(png)
        return f"{path} ({w}×{h} PNG)"
    if not data.startswith(b"OggS"):
        raise Invalid("not an OGG file")
    raw = target.with_suffix(".upload")
    raw.write_bytes(data)
    ff = subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(raw), "-map_metadata", "-1", "-vn",
                         "-c:a", "libvorbis", "-q:a", "6", str(target)], capture_output=True, text=True, timeout=300)
    raw.unlink()
    if ff.returncode != 0 or not target.exists() or target.stat().st_size > MAX_BYTES[".ogg"]:
        target.unlink(missing_ok=True)
        raise Invalid("the audio couldn't be read as OGG Vorbis under 5 MB")
    return f"{path} (OGG)"


def prepare_assets(decisions: dict[str, Any], gathered: dict[str, Any], out: Path = OUT) -> dict[str, Any]:
    """For each scheduled discussion with assets: {ref: {"files": [...]} or {"error": ...}}, files under out/<n>/."""
    known = {item["ref"]: item for item in gathered["items"]}
    results: dict[str, Any] = {}
    for d in decisions.get("items", []):
        item = known.get(d.get("ref", ""))
        if not item or not d.get("assets") or d.get("decision") != "schedule" or not item["ref"].startswith(
                "discussion:"):
            continue
        number = item["ref"].split(":")[1]
        allowed = set(item.get("attachments", []))
        try:
            if len(d["assets"]) > MAX_ASSETS:
                raise Invalid(f"at most {MAX_ASSETS} files a discussion")
            files = []
            for a in d["assets"]:
                if a.get("url") not in allowed:
                    raise Invalid("an asset must be a file the poster attached")
                files.append(prepare_asset(a["url"], a.get("path", ""), out / number))
            results[item["ref"]] = {"files": files}
        except (Invalid, OSError, zlib.error, subprocess.TimeoutExpired) as e:
            results[item["ref"]] = {"error": str(e)}
    return results


def main(argv: list[str] | None = None) -> int:
    cmd = (argv or sys.argv[1:] or [""])[0]
    if cmd != "assets":
        print(__doc__)
        return 2
    gathered = json.loads(Path("intake-input.json").read_text())
    results = prepare_assets(json.loads(os.environ.get("DECISIONS") or "{}"), gathered)
    OUT.mkdir(exist_ok=True)
    (OUT / "results.json").write_text(json.dumps(results, indent=2))
    print(json.dumps(results, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
