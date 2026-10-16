"""No-git submissions through issue forms (docs/PLAN.md, "Contributing without git").

  python3 -m smbot.submissions collect     open submission issues not handled yet
                                           -> $GITHUB_OUTPUT `issues` (JSON)
  python3 -m smbot.submissions sandbox     downloads and validates each file and
                                           re-encodes it into submissions/ (no secrets
                                           in this job: the files are untrusted)
  python3 -m smbot.submissions publish     checks the CLA box, opens a bot PR per
                                           valid submission crediting the contributor
                                           as co-author, and answers the issue

PNG files are decoded and re-encoded here (only pixel data survives); OGG files
are re-encoded by ffmpeg in the sandbox job. Writing becomes a JSON file.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import urllib.request
import zlib
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

from . import config as config_mod
from . import dailylog, gh, state

LABELS = {"submission:art": "art", "submission:audio": "audio", "submission:writing": "writing"}
DONE_LABEL = "submission:handled"
ATTACHMENT = re.compile(r"https://(?:github\.com/user-attachments/(?:assets|files)/[\w./-]+|"
                        r"user-images\.githubusercontent\.com/[\w./-]+)")
MAX_BYTES = {"art": 1_000_000, "audio": 5_000_000}
OUT = Path("submissions")
ALLOWED_DIRS = {"art": ("art/", "content/"), "audio": ("audio/", "content/"), "writing": ("content/story/",)}
EXT = {"art": ".png", "audio": ".ogg", "writing": ".json"}
LICENSES = ("CC-BY-SA-4.0", "CC-BY-4.0", "CC0-1.0")


# --- Issue forms ---------------------------------------------------------------


def parse_form(body: str) -> dict[str, str]:
    """GitHub issue-form bodies: '### Label' headings, each followed by the answer."""
    fields: dict[str, str] = {}
    for block in re.split(r"^### ", body or "", flags=re.MULTILINE)[1:]:
        label, _, value = block.partition("\n")
        value = value.strip()
        fields[label.strip()] = "" if value == "_No response_" else value
    return fields


def checked(value: str, text: str) -> bool:
    return re.search(r"- \[[xX]\] " + re.escape(text), value or "") is not None


# --- PNG re-encoding ---------------------------------------------------------------

PNG_SIG = b"\x89PNG\r\n\x1a\n"
CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


class Invalid(ValueError):
    pass


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


# --- Collect, sandbox, publish ---------------------------------------------------


@dataclass
class Submission:
    issue: int
    kind: str
    author: str
    author_id: int
    fields: dict[str, str]


def body_hash(body: str) -> str:
    return hashlib.sha256((body or "").encode()).hexdigest()[:16]


def collect(cfg: config_mod.Config) -> list[dict[str, Any]]:
    """Open submissions that weren't checked yet, or were edited since their last check."""
    seen = state.load(cfg)[0].get("submissions_checked", {})
    out = []
    for label, kind in LABELS.items():
        for issue in gh.api_paginated(f"repos/{cfg.repo}/issues?state=open&labels={label}&per_page=100"):
            if "pull_request" in issue or any(lab["name"] == DONE_LABEL for lab in issue["labels"]):
                continue
            if seen.get(str(issue["number"])) == body_hash(issue["body"] or ""):
                continue
            out.append({"issue": issue["number"], "kind": kind, "author": issue["user"]["login"],
                        "author_id": issue["user"]["id"], "body": issue["body"] or ""})
    return out


def download(url: str, limit: int) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "spellmerge-submissions"})
    with urllib.request.urlopen(req, timeout=60) as resp:  # noqa: S310 (hosts checked by ATTACHMENT)
        final = resp.geturl()
        if not final.startswith(("https://github.com/", "https://objects.githubusercontent.com/",
                                 "https://github-production-user-asset-", "https://user-images.githubusercontent.com/",
                                 "https://private-user-images.githubusercontent.com/")):
            raise Invalid("the attachment didn't come from GitHub")
        data = resp.read(limit + 1)
    if len(data) > limit:
        raise Invalid(f"the file is larger than {limit // 1_000_000} MB")
    return data


def sandbox_one(sub: dict[str, Any]) -> dict[str, Any]:
    """Validates one submission and writes its re-encoded file; returns the result."""
    fields = parse_form(sub["body"])
    result: dict[str, Any] = {"issue": sub["issue"], "kind": sub["kind"], "ok": False}
    try:
        name = OUT / f"{sub['issue']}{EXT[sub['kind']]}"
        if sub["kind"] == "writing":
            text = fields.get("Text", "").strip()
            if not text or len(text) > 20_000:
                raise Invalid("the text is empty or longer than 20,000 characters")
            name.write_text(json.dumps({"text": text, "title": fields.get("Title", "")}, indent=2,
                                       ensure_ascii=False) + "\n")
        else:
            urls = ATTACHMENT.findall(fields.get("File", ""))
            if len(urls) != 1:
                raise Invalid("attach exactly one file in the File field")
            data = download(urls[0], MAX_BYTES[sub["kind"]])
            if sub["kind"] == "art":
                png, w, h = reencode_png(data)
                name.write_bytes(png)
                result["size"] = f"{w}×{h}"
            else:
                if not data.startswith(b"OggS"):
                    raise Invalid("not an OGG file")
                raw = OUT / f"{sub['issue']}.upload"
                raw.write_bytes(data)
                ff = subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(raw), "-map_metadata", "-1", "-vn",
                                     "-c:a", "libvorbis", "-q:a", "6", str(name)], capture_output=True, text=True,
                                    timeout=300)
                raw.unlink()
                if ff.returncode != 0 or not name.exists():
                    raise Invalid("the audio couldn't be read as OGG Vorbis")
                if name.stat().st_size > MAX_BYTES["audio"]:
                    raise Invalid("the re-encoded audio is larger than 5 MB")
        result.update(ok=True, file=str(name))
    except (Invalid, OSError, zlib.error, subprocess.TimeoutExpired) as e:
        result["error"] = str(e)
    return result


_ISSUE_EDITS = """
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      author { ... on User { databaseId } }
      userContentEdits(first: 50) { nodes { editor { ... on User { databaseId } } } }
    }
  }
}"""


def only_author_edited(cfg: config_mod.Config, number: int, author_id: int) -> bool:
    owner, name = cfg.repo.split("/")
    issue = gh.graphql(_ISSUE_EDITS, owner=owner, name=name, number=number)["repository"]["issue"]
    editors = [(e.get("editor") or {}).get("databaseId") for e in issue["userContentEdits"]["nodes"]]
    return (issue.get("author") or {}).get("databaseId") == author_id and all(e == author_id for e in editors)


def target_path(cfg: config_mod.Config, kind: str, fields: dict[str, str]) -> str:
    path = fields.get("Where should it go?", "").strip().strip("`").lstrip("/")
    task = re.search(r"#(\d+)", fields.get("Task", ""))
    if not path and task:
        body = gh.api(f"repos/{cfg.repo}/issues/{task.group(1)}").get("body") or ""
        m = re.search(r"\*\*Where:\*\*\s*`([^`]+)`", body)
        path = m.group(1) if m else ""
    if not path:
        raise Invalid("tell us where the file should go (a path, or the task issue it's for)")
    p = PurePosixPath(path)
    if ".." in p.parts or p.suffix != EXT[kind] or not path.startswith(ALLOWED_DIRS[kind]):
        raise Invalid(f"`{path}` isn't a valid place for this file (a {EXT[kind]} file under "
                      f"{' or '.join(ALLOWED_DIRS[kind])})")
    return path


def publish_one(cfg: config_mod.Config, sub: dict[str, Any], result: dict[str, Any], token: str) -> str:
    fields = parse_form(sub["body"])
    number, login, user_id = sub["issue"], sub["author"], sub["author_id"]
    if not result.get("ok"):
        raise Invalid(result.get("error", "the file couldn't be checked"))
    cla_ok = checked(fields.get("Agreement", ""), "I have read the CLA and I agree to it")
    rights_ok = checked(fields.get("Agreement", ""), "I made this, or I have the right to submit it")
    if not (cla_ok and rights_ok) or not only_author_edited(cfg, number, user_id):
        raise Invalid("both agreement boxes must be ticked by you (and the issue edited only by you)")
    path = target_path(cfg, sub["kind"], fields)
    license_id = fields.get("License", "").split()[0] if fields.get("License") else "CC-BY-SA-4.0"
    if license_id not in LICENSES:
        raise Invalid(f"license must be one of {', '.join(LICENSES)}")
    origin = "ai" if fields.get("How was it made?", "").lower().startswith("with an ai") else "human"
    credit = fields.get("Credit as", "").strip()[:80] or login

    branch = f"submission/issue-{number}"
    git = ["git", "-c", f"user.name={cfg.bot.login}", "-c",
           f"user.email={cfg.bot.id}+{cfg.bot.login}@users.noreply.github.com"]
    subprocess.run(["git", "switch", "--quiet", "-C", branch, "origin/main"], check=True)
    dest = Path(path)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(Path(result["file"]).read_bytes())
    if license_id != "CC-BY-SA-4.0" or sub["kind"] == "writing":
        Path(f"{path}.license").write_text(f"SPDX-FileCopyrightText: 2026 {credit}\n"
                                           f"SPDX-License-Identifier: {license_id}\n")
    if sub["kind"] in ("art", "audio"):
        manifest = Path(f"{sub['kind']}/manifest.json")
        data = json.loads(manifest.read_text()) if manifest.exists() else {"assets": []}
        data["assets"] = [a for a in data["assets"] if a["path"] != path]
        entry = {"path": path, "origin": origin, "author": credit, "github": login, "license": license_id,
                 "source": f"https://github.com/{cfg.repo}/issues/{number}", "tier": "good"}
        if origin == "ai":
            entry["tool"] = fields.get("AI tool", "")[:200]
            entry["prompt"] = fields.get("AI prompt", "")[:2000]
        data["assets"].append(entry)
        data["assets"].sort(key=lambda a: a["path"])
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    subprocess.run(["git", "add", "-A", "--", path, f"{path}.license", "art/manifest.json", "audio/manifest.json"],
                   check=False, capture_output=True)
    message = (f"Add {path} (submitted in #{number})\n\n"
               f"Co-authored-by: {login} <{user_id}+{login}@users.noreply.github.com>")
    subprocess.run([*git, "commit", "--quiet", "-m", message], check=True)
    subprocess.run(["git", "push", "--quiet", "--force", f"https://x-access-token:{token}@github.com/{cfg.repo}.git",
                    f"HEAD:refs/heads/{branch}"], check=True)
    subprocess.run(["git", "switch", "--quiet", "--detach", "origin/main"], check=True)
    pr = gh.api(f"repos/{cfg.repo}/pulls", "-X", "POST", input={
        "title": f"Submission from @{login}: {path}", "head": branch, "base": "main",
        "body": f"Submitted by @{login} through the form in #{number}, without git. The file was validated and "
                f"re-encoded. Origin: {origin}; license: {license_id}; credited as {credit}.\n\nCloses #{number}",
    })
    gh.api(f"repos/{cfg.repo}/issues/{pr['number']}/labels", "-X", "POST", input={"labels": ["submission"]})
    return f"#{pr['number']}"


def main(argv: list[str] | None = None) -> int:
    cmd = (argv or sys.argv[1:] or [""])[0]
    cfg = config_mod.load()
    out_path = os.environ.get("GITHUB_OUTPUT")
    if cmd == "collect":
        subs = collect(cfg)
        if out_path:
            with open(out_path, "a") as fh:
                fh.write(f"issues<<__END__\n{json.dumps(subs)}\n__END__\ncount={len(subs)}\n")
        print(f"{len(subs)} submission(s)")
    elif cmd == "sandbox":
        OUT.mkdir(exist_ok=True)
        results = [sandbox_one(s) for s in json.loads(os.environ["ISSUES"])]
        (OUT / "results.json").write_text(json.dumps(results, indent=2))
        print(json.dumps(results, indent=2))
    elif cmd == "publish":
        subs = {s["issue"]: s for s in json.loads(os.environ["ISSUES"])}
        results = json.loads((OUT / "results.json").read_text())
        log = []
        for r in results:
            sub = subs[r["issue"]]
            try:
                pr = publish_one(cfg, sub, r, os.environ["GH_TOKEN"])
                reply = (f"Thank you, @{sub['author']}! Your submission passed the checks and is now {pr}. It gets "
                         "rated (and voted on, once there are voters) like any other contribution.")
                log.append(f"Submission #{r['issue']} by @{sub['author']} became {pr}")
            except (Invalid, gh.GhError, subprocess.CalledProcessError) as e:
                reply = (f"Thanks, @{sub['author']}! This submission couldn't be accepted yet: {e}. Edit the issue "
                         "to fix it (or open a new one), and it's checked again within a day.")
                log.append(f"Submission #{r['issue']} by @{sub['author']} needs changes: {e}")
            gh.api(f"repos/{cfg.repo}/issues/{r['issue']}/comments", "-X", "POST", input={"body": reply})
            if "became" in log[-1]:
                gh.api(f"repos/{cfg.repo}/issues/{r['issue']}/labels", "-X", "POST", input={"labels": [DONE_LABEL]})
        checked_now = {str(r["issue"]): body_hash(subs[r["issue"]]["body"]) for r in results}
        state.update(cfg, lambda s: s.setdefault("submissions_checked", {}).update(checked_now),
                     "submissions: checked")
        dailylog.post(cfg, "Submissions", log)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
