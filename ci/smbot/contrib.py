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
import urllib.parse
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

ATTACHMENT = re.compile(r"https://(?:github\.com/user-attachments/(?:assets|files)/[\w-]+(?:/[\w.-]+)?|"
                        r"user-images\.githubusercontent\.com/[\w-]+(?:/[\w.-]+)*)")
ASSET_PATH = re.compile(r"(?:art|audio|content)(?:/[a-z0-9_-]+)+\.(?:png|ogg)")
DOWNLOAD_HOSTS = {"github.com", "objects.githubusercontent.com", "user-images.githubusercontent.com",
                  "private-user-images.githubusercontent.com"}
MAX_PIXELS_BYTES = 4096 * 4096 * 8  # the largest decoded image accepted
MAX_BYTES = {".png": 1_000_000, ".ogg": 5_000_000}
ASSET_DIRS = ("art/", "audio/", "content/")
OUT = Path("submissions")
PNG_SIG = b"\x89PNG\r\n\x1a\n"
CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
MAX_ASSETS = 10  # per discussion


class Invalid(ValueError):
    pass


def check_path(path: str) -> str:
    """A target path inside the asset folders: lowercase names, a .png or .ogg file, nothing else."""
    if not isinstance(path, str) or not ASSET_PATH.fullmatch(path) or ".." in PurePosixPath(path).parts:
        raise Invalid(f"{str(path)[:80]!r} must be a lowercase .png or .ogg path under {', '.join(ASSET_DIRS)}")
    return path


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
    if len(chunks[0][1]) != 13:
        raise Invalid("PNG header has the wrong length")
    width, height, depth, color, comp, filt, interlace = struct.unpack(">IIBBBBB", chunks[0][1])
    if not (0 < width <= max_side and 0 < height <= max_side):
        raise Invalid(f"image size {width}×{height} is out of range")
    valid_depths = {0: (1, 2, 4, 8, 16), 2: (8, 16), 3: (1, 2, 4, 8), 4: (8, 16), 6: (8, 16)}
    if color not in CHANNELS or depth not in valid_depths[color] or comp != 0 or filt != 0 or interlace != 0:
        raise Invalid("unsupported PNG format (save as a non-interlaced RGBA or indexed PNG)")
    inflater = zlib.decompressobj()
    raw = inflater.decompress(b"".join(body for kind, body in chunks if kind == b"IDAT"), MAX_PIXELS_BYTES)
    if inflater.unconsumed_tail:
        raise Invalid("PNG pixel data is too large")
    row_bytes = (width * CHANNELS[color] * depth + 7) // 8
    if len(raw) != height * (row_bytes + 1):
        raise Invalid("PNG pixel data has the wrong length")
    if any(raw[i * (row_bytes + 1)] > 4 for i in range(height)):
        raise Invalid("PNG uses an unknown row filter")
    keep = [_chunk(kind, body) for kind, body in chunks if kind in (b"PLTE", b"tRNS")]
    out = PNG_SIG + _chunk(b"IHDR", chunks[0][1]) + b"".join(keep) + _chunk(b"IDAT", zlib.compress(raw, 9)) \
        + _chunk(b"IEND", b"")
    return out, width, height


def _github_host(url: str) -> bool:
    parts = urllib.parse.urlsplit(url)
    host = parts.hostname or ""
    return parts.scheme == "https" and (host in DOWNLOAD_HOSTS or re.fullmatch(
        r"github-production-user-asset-[a-z0-9]+\.s3\.amazonaws\.com", host) is not None)


class _GitHubOnly(urllib.request.HTTPRedirectHandler):
    """Follows a redirect only to GitHub's own file hosts, checked at every hop."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001, ANN201
        if not _github_host(newurl):
            raise Invalid("the attachment didn't come from GitHub")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download(url: str, limit: int) -> bytes:
    if not isinstance(url, str) or not ATTACHMENT.fullmatch(url):
        raise Invalid("only files attached on GitHub can be used")
    req = urllib.request.Request(url, headers={"User-Agent": "spellmerge-intake"})
    with urllib.request.build_opener(_GitHubOnly).open(req, timeout=60) as resp:  # noqa: S310 (hosts checked)
        if not _github_host(resp.geturl()):
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


def recheck(path: Path) -> None:
    """Checks a prepared file again where it's used: size, type, and a PNG's pixels only."""
    data = path.read_bytes()
    if len(data) > MAX_BYTES.get(path.suffix, 0):
        raise Invalid(f"{path.name} is too large")
    if path.suffix == ".png":
        clean, _, _ = reencode_png(data)
        path.write_bytes(clean)
    elif not data.startswith(b"OggS"):
        raise Invalid(f"{path.name} is not an OGG file")


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
            if not isinstance(d["assets"], list) or len(d["assets"]) > MAX_ASSETS:
                raise Invalid(f"at most {MAX_ASSETS} files a discussion")
            files = []
            for a in d["assets"]:
                if not isinstance(a, dict) or a.get("url") not in allowed:
                    raise Invalid("an asset must be a file the poster attached")
                files.append(prepare_asset(a["url"], a.get("path", ""), out / number))
            results[item["ref"]] = {"files": files}
        except Invalid as e:
            results[item["ref"]] = {"error": str(e)}
        except Exception as e:  # noqa: BLE001 (one bad file must never stop the other posts)
            results[item["ref"]] = {"error": f"the file couldn't be read ({type(e).__name__})"}
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
