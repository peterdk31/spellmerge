"""Hard rules check (docs/PLAN.md, "Filter 1: hard rules").

Checks what a PR changes against the security and copyright rules. Hard rules
are kept to security and copyright; everything else is guidance for the review.
The one addition is typed GDScript: a warning for outside contributors (Claude
fixes it after merging) and an error for the bot's own PRs.

Every finding names the rule, the file, the line and the fix, so a person or an
agent can act on it directly.

Usage:
  python3 -m smbot.rules --base origin/main               committed changes
  python3 -m smbot.rules --base origin/main --worktree    also uncommitted files
  python3 -m smbot.rules --repo pr --policy trusted --base SHA \\
      --author LOGIN --format github                       in CI

--policy is the checkout that CODEOWNERS and ci/config.json are read from. In CI
it is the base branch, never the PR, so a PR can't loosen the rules it is
checked against.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path, PurePosixPath

from . import config as config_mod

# --- Policy -------------------------------------------------------------------

# Paths only Claude's own PRs may change (docs/PLAN.md, "Path tiers"), plus the
# Godot project files, which can register autoload scripts and export settings.
BOT_PATHS = (
    "docs/ROADMAP.md",
    "docs/NEXT.md",
    "docs/BACKLOG.md",
    "docs/DECISIONS.md",
    "docs/LOG.md",
    "docs/milestones/",
    "docs/STYLE.md",
    "docs/STORY.md",
    "docs/cla-signatures.json",
    "AGENTS.md",
    "CLAUDE.md",
    "llms.txt",
    "core/",
    "project.godot",
    "export_presets.cfg",
)

# File types outside contributors may add: images, .ogg, Godot text files,
# GDScript and JSON, plus REUSE .license sidecars and empty-folder markers.
CONTRIBUTOR_TYPES = frozenset(
    {".png", ".svg", ".ogg", ".gd", ".tscn", ".tres", ".import", ".uid", ".gdshader", ".json", ".license"}
)
CONTRIBUTOR_NAMES = frozenset({".gitkeep"})
# The bot also maintains docs and the Godot project files, and tools/ scripts.
BOT_TYPES = CONTRIBUTOR_TYPES | {".md", ".txt", ".cfg", ".godot", ".html", ".css"}
BOT_NAMES = CONTRIBUTOR_NAMES | {".gitignore", ".gitattributes", ".gdignore"}
BOT_TOOL_TYPES = frozenset({".sh", ".py"})

# Dependabot only updates GitHub Actions; those files still need owner review.
DEPENDENCY_BOT_PATHS = (".github/workflows/*.yml", ".github/workflows/*.yaml", ".github/dependabot.yml")

MB = 1_000_000
SIZE_LIMITS = {".png": 1 * MB, ".svg": 1 * MB, ".ogg": 5 * MB}
DEFAULT_SIZE_LIMIT = 1 * MB

# The only binary formats allowed, checked by their magic bytes.
BINARY_MAGIC = {".png": b"\x89PNG\r\n\x1a\n", ".ogg": b"OggS"}

SCRIPT_TYPES = frozenset({".gd", ".tscn", ".tres"})

# Licenses allowed for files that declare their own (docs/PLAN.md, "Copyright
# and licensing"). Files without a declaration get the REUSE.toml default.
CODE_LICENSES = frozenset(
    {"GPL-3.0-or-later", "GPL-3.0-only", "MIT", "BSD-2-Clause", "BSD-3-Clause", "Apache-2.0",
     "Zlib", "ISC", "0BSD", "CC0-1.0"}
)
ASSET_LICENSES = frozenset({"CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0"})
ASSET_TYPES = frozenset({".png", ".svg", ".ogg"})


@dataclass(frozen=True)
class BannedApi:
    id: str
    pattern: re.Pattern[str]
    message: str
    fix: str
    # core/ (bot-maintained) and tests/ (never exported) may load and read files.
    relaxed_in_core_and_tests: bool = False


def _rx(pattern: str) -> re.Pattern[str]:
    return re.compile(pattern, re.MULTILINE)


_NOT_USER_PATH = r"""\s*\(\s*(?!["']user://)"""

BANNED_APIS = (
    BannedApi(
        "process",
        _rx(r"\bOS\s*\.\s*(execute|execute_with_pipe|create_process|create_instance|shell_open|"
            r"shell_show_in_file_manager|kill|set_environment|unset_environment|move_to_trash|"
            r"set_restart_on_exit|crash)\b"),
        "Starting programs, opening URLs or changing the environment is not allowed in the game.",
        "Remove the call. If the feature truly needs it, open an issue to discuss it.",
    ),
    BannedApi(
        "dynamic-call",
        _rx(r"\bOS\s*\.\s*(call|callv|call_deferred)\b|\bCallable\s*\(\s*OS\b|\bEngine\s*\.\s*get_singleton\b"),
        "Calling engine singletons by name can hide banned calls.",
        "Call the method directly, for example `Input.is_action_pressed(...)`.",
    ),
    BannedApi(
        "network",
        _rx(r"\b(HTTPRequest|HTTPClient|StreamPeerTCP|StreamPeerTLS|TCPServer|UDPServer|PacketPeerUDP|"
            r"PacketPeerDTLS|DTLSServer|WebSocketPeer|WebSocketMultiplayerPeer|WebRTCPeerConnection|"
            r"WebRTCDataChannel|WebRTCMultiplayerPeer|ENetMultiplayerPeer|ENetConnection|ENetPacketPeer|"
            r"MultiplayerPeerExtension)\b|\bIP\s*\.\s*\w+"),
        "The game has no networking or HTTP code (no tracking, no downloads).",
        "Remove the networking code. Player feedback goes through GitHub Discussions links instead.",
    ),
    BannedApi(
        "javascript",
        _rx(r"\bJavaScript(Bridge|Object)\b"),
        "Calling into the browser's JavaScript is not allowed.",
        "Remove the JavaScriptBridge use; web-specific behaviour belongs in core/.",
    ),
    BannedApi(
        "native-code",
        _rx(r"\bGDExtensionManager\b|[\"'][^\"'\n]*\.gdextension[\"']"),
        "Native code (GDExtension) is not allowed.",
        "Write the feature in typed GDScript instead.",
    ),
    BannedApi(
        "dynamic-code",
        _rx(r"\bGDScript\s*\.\s*new\b|\.source_code\b|\bExpression\s*\.\s*new\b|\bClassDB\s*\.\s*(instantiate|"
            r"class_call_static|class_set_property)\b|\bbytes_to_var_with_objects\b|\bset_script\s*\("),
        "Creating or swapping code at runtime can hide banned calls.",
        "Use a normal script file attached in the scene or resource.",
    ),
    BannedApi(
        "editor-code",
        _rx(r"^\s*@tool\b|\bEditor(Plugin|Interface|Script|ImportPlugin|ExportPlugin)\b"),
        "Editor-only code (@tool scripts, editor plugins) runs inside other contributors' editors.",
        "Remove @tool and editor classes; the game must not need editor plugins.",
    ),
    BannedApi(
        "file-access",
        _rx(r"\b(FileAccess|DirAccess)\s*\.\s*(open|open_encrypted|open_encrypted_with_pass|open_compressed|"
            r"get_file_as_string|get_file_as_bytes|make_dir_absolute|make_dir_recursive_absolute|"
            r"remove_absolute|rename_absolute|copy_absolute|get_files_at|get_directories_at)"
            + _NOT_USER_PATH + r"|\bResourceSaver\s*\.\s*save\s*\(\s*[^,]+,\s*(?![\"']user://)"
            r"|\.save_(png|jpg|webp|exr)" + _NOT_USER_PATH
            + r"|(?<!ResourceLoader)(?<!ResourceSaver)\.\s*(load|save|load_from_file|load_encrypted|save_encrypted|load_encrypted_pass|"
            r"save_encrypted_pass)" + _NOT_USER_PATH),
        "File access is only allowed inside user:// and the path must be written out as text.",
        'Use a literal path starting with "user://", or load content through the content registry.',
        relaxed_in_core_and_tests=True,
    ),
    BannedApi(
        "dynamic-load",
        _rx(r"(?<![.\w])(load|ResourceLoader\s*\.\s*load|ResourceLoader\s*\.\s*load_threaded_request)"
            r"\s*\(\s*(?![\"']res://)|\bstr_to_var\s*\("),
        "Loading from a computed path (or from user://) could run code that was never reviewed.",
        'Use a literal "res://..." path or preload(); dynamic loading is done by core/registry.',
        relaxed_in_core_and_tests=True,
    ),
)

# --- Model ----------------------------------------------------------------------

OWNER, BOT, DEPENDENCY_BOT, CONTRIBUTOR = "owner", "bot", "dependency-bot", "contributor"


@dataclass(frozen=True)
class Change:
    status: str  # A, M, D, T (type change)
    path: str
    mode: str  # new git file mode, "000000" when deleted


@dataclass
class Finding:
    rule: str
    severity: str  # "error" or "warning"
    path: str
    line: int
    message: str
    fix: str


def role_for(author: str | None, cfg: config_mod.Config) -> str:
    if author == cfg.owner.login:
        return OWNER
    if author == cfg.bot.login:
        return BOT
    if author in cfg.dependency_bots:
        return DEPENDENCY_BOT
    return CONTRIBUTOR


# --- Git ------------------------------------------------------------------------


def _git(repo: Path, *args: str) -> bytes:
    return subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True).stdout


# Claude Code's sandbox protects these paths by leaving empty (or unreadable) placeholder files
# in the working directory. They are never part of a change, so local checks skip them.
SANDBOX_PLACEHOLDERS = {".bashrc", ".bash_profile", ".bash_login", ".bash_logout", ".zshrc", ".zprofile",
                        ".zshenv", ".zlogin", ".profile", ".gitconfig", ".gitmodules", ".ripgreprc", ".mcp.json"}
SANDBOX_PLACEHOLDER_DIRS = (".idea/", ".vscode/", ".claude/commands/", ".claude/agents/")


def is_sandbox_placeholder(repo: Path, path: str) -> bool:
    if path not in SANDBOX_PLACEHOLDERS and not path.startswith(SANDBOX_PLACEHOLDER_DIRS):
        return False
    try:
        return (repo / path).stat().st_size == 0 or not os.access(repo / path, os.R_OK)
    except OSError:
        return True


def changes_between(repo: Path, base: str, worktree: bool) -> list[Change]:
    if worktree:
        merge_base = _git(repo, "merge-base", base, "HEAD").decode().strip()
        raw = _git(repo, "diff", "--raw", "-z", "--no-renames", merge_base)
    else:
        raw = _git(repo, "diff", "--raw", "-z", "--no-renames", f"{base}...HEAD")
    parts = raw.decode("utf-8", "surrogateescape").split("\0")
    out: list[Change] = []
    i = 0
    while i + 1 < len(parts) and parts[i].startswith(":"):
        meta = parts[i][1:].split()
        out.append(Change(status=meta[4][0], path=parts[i + 1], mode=meta[1]))
        i += 2
    if worktree:
        untracked = _git(repo, "ls-files", "--others", "--exclude-standard", "-z").decode().split("\0")
        out += [Change("A", p, "100644") for p in untracked if p and not is_sandbox_placeholder(repo, p)]
    return out


def read_file(repo: Path, change: Change, worktree: bool) -> bytes:
    if worktree:
        return (repo / change.path).read_bytes()
    return _git(repo, "show", f"HEAD:{change.path}")


# --- Path tiers -------------------------------------------------------------------


def owner_only_patterns(codeowners: str, owner: str) -> list[str]:
    patterns = []
    for line in codeowners.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        pattern, *owners = line.split()
        if f"@{owner}" in owners:
            patterns.append(pattern)
    return patterns


def matches(path: str, pattern: str) -> bool:
    """CODEOWNERS-style match for the simple patterns used in this repo."""
    anchored = pattern.startswith("/")
    pattern = pattern.lstrip("/")
    if pattern.endswith("/"):
        return path.startswith(pattern) if anchored else f"/{pattern}" in f"/{path}"
    if anchored:
        return fnmatch.fnmatchcase(path, pattern)
    return fnmatch.fnmatchcase(path, pattern) or fnmatch.fnmatchcase(PurePosixPath(path).name, pattern)


def is_bot_path(path: str) -> bool:
    if PurePosixPath(path).name == "README.md":
        return True  # area READMEs and the root README
    return any(path.startswith(p) if p.endswith("/") else path == p for p in BOT_PATHS)


# --- Checks -----------------------------------------------------------------------


def _suffix(path: str) -> str:
    return PurePosixPath(path).suffix.lower()


def check_paths(change: Change, role: str, owner_only: list[str]) -> list[Finding]:
    path = change.path
    if role == OWNER:
        return []
    if role == DEPENDENCY_BOT:
        if any(fnmatch.fnmatchcase(path, p) for p in DEPENDENCY_BOT_PATHS):
            return []  # still needs the owner's review through CODEOWNERS
        return [Finding("dependency-bot", "error", path, 0, "Dependency updates may only change GitHub Actions files.",
                        "Close this PR; the owner updates other dependencies by hand.")]
    if any(matches(path, p) for p in owner_only):
        return [Finding("protected-path", "error", path, 0, "This path is owner-only.",
                        "Remove this change from the PR. If it is needed, open an issue instead.")]
    if is_bot_path(path) and role != BOT:
        return [Finding("bot-path", "error", path, 0,
                        "This path is maintained by Claude and only changes through Claude's own PRs.",
                        "Remove this change from the PR, or describe what should change in an issue.")]
    return []


def check_file_type(change: Change, role: str) -> list[Finding]:
    path = change.path
    if role in (OWNER, DEPENDENCY_BOT) or change.status == "D":
        return []
    name, suffix = PurePosixPath(path).name, _suffix(path)
    if role == BOT:
        allowed = name in BOT_NAMES or suffix in BOT_TYPES or (path.startswith("tools/") and suffix in BOT_TOOL_TYPES)
    else:
        allowed = name in CONTRIBUTOR_NAMES or suffix in CONTRIBUTOR_TYPES
    if allowed:
        return []
    return [Finding("file-type", "error", path, 0, f"Files of type '{suffix or name}' can't be added.",
                    "Allowed: .png and .svg images, .ogg audio, .gd, .tscn, .tres, .json and other Godot "
                    "text files. Convert the file or remove it.")]


def check_mode(change: Change, role: str) -> list[Finding]:
    if role == OWNER or change.status == "D":
        return []
    if change.mode == "120000":
        return [Finding("symlink", "error", change.path, 0, "Symbolic links are not allowed.",
                        "Replace the link with the real file.")]
    if change.mode == "160000":
        return [Finding("submodule", "error", change.path, 0, "Git submodules are not allowed.",
                        "Remove the submodule; third-party code is only added by the owner.")]
    return []


def check_content(change: Change, data: bytes, role: str) -> list[Finding]:
    path, suffix = change.path, _suffix(change.path)
    findings: list[Finding] = []

    limit = SIZE_LIMITS.get(suffix, DEFAULT_SIZE_LIMIT)
    if len(data) > limit:
        findings.append(Finding("file-size", "error", path, 0,
                                f"The file is {len(data) / MB:.1f} MB; the limit for this type is {limit // MB} MB.",
                                "Make the file smaller, for example split a sprite sheet or shorten the track."))

    magic = BINARY_MAGIC.get(suffix)
    if magic is not None:
        if not data.startswith(magic):
            findings.append(Finding("binary", "error", path, 0, f"This is not a real {suffix} file.",
                                    f"Export the file again as {suffix}."))
        return findings
    if b"\0" in data[:8192]:
        findings.append(Finding("binary", "error", path, 0, "Binary files are not allowed (only .png and .ogg).",
                                "Remove the file, or save it in a text format."))
        return findings

    text = data.decode("utf-8", "replace")
    if suffix == ".svg":
        findings += _check_svg(path, text)
    if suffix == ".gdextension" or "type=\"GDExtension\"" in text:
        findings.append(Finding("banned-api", "error", path, 1, "Native code (GDExtension) is not allowed.",
                                "Remove the GDExtension; write the feature in typed GDScript."))
    if suffix in SCRIPT_TYPES:
        findings += check_banned_apis(path, text)
    if suffix == ".gd":
        findings += check_typed(path, text, "error" if role == BOT else "warning")
    findings += check_license(path, text)
    return findings


def _check_svg(path: str, text: str) -> list[Finding]:
    if re.search(r"<\s*(script|foreignObject)\b|\son\w+\s*=|(href|src)\s*=\s*[\"']\s*(https?:|javascript:|data:text)",
                 text, re.IGNORECASE):
        return [Finding("svg-script", "error", path, 0, "SVGs may not contain scripts, event handlers or external links.",
                        "Export a plain SVG (for example 'Plain SVG' in Inkscape).")]
    return []


def _line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


# The one place the game may open a web page (docs/DECISIONS.md, "Opening web links, narrowly"):
# a bot-maintained file that opens only entries of its own constant table of known addresses.
LINKS_FILE = "core/links/links.gd"
def link_prefixes(cfg: config_mod.Config) -> tuple[str, ...]:
    """The project's own addresses: the repository, its Pages site and its itch.io page."""
    return tuple(p for p in (f"https://github.com/{cfg.repo}", cfg.pages, cfg.game.itch) if p)


LINK_PREFIXES = link_prefixes(config_mod.load())
_SHELL_OPEN = re.compile(r"\bOS\s*\.\s*shell_open\b")
_SHELL_OPEN_FROM_TABLE = re.compile(r"\bOS\s*\.\s*shell_open\s*\(\s*URLS\s*\[\s*\w+\s*\]\s*\)")
_URL_LITERAL = re.compile(r"[\"']([a-zA-Z][\w+.-]*://[^\"']*)[\"']")


def check_links_file(path: str, text: str) -> list[Finding]:
    """Rules for LINKS_FILE: shell_open only as OS.shell_open(URLS[key]), URLS a const of known addresses."""
    findings = []
    calls, safe = list(_SHELL_OPEN.finditer(text)), len(_SHELL_OPEN_FROM_TABLE.findall(text))
    if calls and (len(calls) != safe or not re.search(r"^const\s+URLS\b", text, re.MULTILINE)):
        findings.append(Finding("banned-api", "error", path, _line_of(text, calls[0].start()),
                                "Here `OS.shell_open` may only open an entry of the constant `URLS` table.",
                                "Write `const URLS := {...}` and call `OS.shell_open(URLS[key])`, nothing else."))
    if re.search(r"\bURLS\s*(\[[^\]]*\]\s*=(?!=)|\.(merge|erase|clear|assign)\b)", text):
        findings.append(Finding("banned-api", "error", path, 0, "The `URLS` table may not be changed at run time.",
                                "Keep `URLS` a constant with literal entries."))
    for m in _URL_LITERAL.finditer(text):
        if not m.group(1).startswith(LINK_PREFIXES):
            findings.append(Finding("banned-api", "error", path, _line_of(text, m.start()),
                                    f"`{m.group(1)}` is not one of the project's own addresses.",
                                    "Only " + ", ".join(LINK_PREFIXES) + " may be linked."))
    return findings


def check_banned_apis(path: str, text: str) -> list[Finding]:
    relaxed = path.startswith(("core/", "tests/"))
    findings = []
    for api in BANNED_APIS:
        if api.relaxed_in_core_and_tests and relaxed:
            continue
        for m in api.pattern.finditer(text):
            if path == LINKS_FILE and m.group(0).strip().endswith("shell_open"):
                continue  # checked by check_links_file
            findings.append(Finding("banned-api", "error", path, _line_of(text, m.start()),
                                    f"{api.message} (found `{m.group(0).strip()}`)", api.fix))
    if path == LINKS_FILE:
        findings += check_links_file(path, text)
    return findings


_UNTYPED_VAR = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?var\s+(\w+)\s*(?:=(?!=)|(?:#.*)?$)", re.MULTILINE)
_FUNC = re.compile(r"^\s*(?:static\s+)?func\s+(\w+)\s*\((.*?)\)\s*(->\s*[\w.\[\], ]+)?\s*:", re.MULTILINE | re.DOTALL)


def check_typed(path: str, text: str, severity: str) -> list[Finding]:
    findings = []
    for m in _UNTYPED_VAR.finditer(text):
        findings.append(Finding("untyped", severity, path, _line_of(text, m.start(1)),
                                f"Variable `{m.group(1)}` has no type.",
                                f"Add a type, for example `var {m.group(1)}: int = ...` or `var {m.group(1)} := ...`."))
    for m in _FUNC.finditer(text):
        name, params, ret = m.group(1), m.group(2), m.group(3)
        line = _line_of(text, m.start(1))
        for param in _split_params(params):
            pname = re.split(r"[:=]", param, maxsplit=1)[0].strip()
            if pname and ":" not in param:
                findings.append(Finding("untyped", severity, path, line,
                                        f"Parameter `{pname}` of `{name}()` has no type.",
                                        f"Write it as `{pname}: Type`."))
        if ret is None:
            findings.append(Finding("untyped", severity, path, line, f"Function `{name}()` has no return type.",
                                    "Add `-> Type` before the colon, or `-> void` if it returns nothing."))
    return findings


def _split_params(params: str) -> list[str]:
    out, depth, cur = [], 0, ""
    for ch in params:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    out.append(cur)
    return [p.strip() for p in out if p.strip()]


_SPDX = re.compile(
    r"^[ \t]*(?:#|//|;|<!--|\*)?[ \t]*SPDX-License-Identifier:[ \t]*([^\n*]+?)[ \t]*(?:-->|\*/)?[ \t]*$", re.MULTILINE)


def check_license(path: str, text: str) -> list[Finding]:
    target = path[: -len(".license")] if path.endswith(".license") else path
    is_asset = _suffix(target) in ASSET_TYPES or target.startswith("content/story/")
    allowed = ASSET_LICENSES if is_asset else CODE_LICENSES
    findings = []
    for m in _SPDX.finditer(text):
        ids = [t for t in re.findall(r"[A-Za-z0-9.+-]+", m.group(1)) if t not in ("AND", "OR", "WITH")]
        bad = [i for i in ids if i not in allowed]
        if bad:
            findings.append(Finding("license", "error", path, _line_of(text, m.start()),
                                    f"License {', '.join(bad)} is not allowed for this kind of file.",
                                    f"Use one of: {', '.join(sorted(allowed))}. Files without a license line "
                                    "get the project's default license."))
    return findings


# --- Runner -----------------------------------------------------------------------


def run(repo: Path, policy: Path, base: str, author: str | None, worktree: bool) -> list[Finding]:
    cfg = config_mod.load(policy / "ci" / "config.json")
    role = role_for(author, cfg)
    codeowners = (policy / ".github" / "CODEOWNERS").read_text()
    owner_only = owner_only_patterns(codeowners, cfg.owner.login)

    findings: list[Finding] = []
    for change in changes_between(repo, base, worktree):
        findings += check_paths(change, role, owner_only)
        findings += check_file_type(change, role)
        findings += check_mode(change, role)
        if change.status != "D" and change.mode not in ("120000", "160000") and role != DEPENDENCY_BOT:
            try:
                data = read_file(repo, change, worktree)
            except OSError as e:  # e.g. a sandbox's own unreadable files in a local checkout
                findings.append(Finding("unreadable", "warning", change.path, 0, f"Couldn't read the file ({e}).",
                                        "Check its permissions; if it isn't part of your change, remove it or "
                                        "add it to .gitignore."))
                continue
            findings += check_content(change, data, role)

    if role == OWNER:
        for f in findings:
            if f.severity == "error":
                f.severity = "warning"
                f.message += " (allowed: the owner made this change)"
    return findings


def _escape(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def report(findings: list[Finding], fmt: str) -> str:
    errors = sum(f.severity == "error" for f in findings)
    warnings = len(findings) - errors
    if fmt == "json":
        return json.dumps({"ok": errors == 0, "errors": errors, "warnings": warnings,
                           "findings": [asdict(f) for f in findings]}, indent=2)
    lines = []
    for f in findings:
        where = f"{f.path}:{f.line}" if f.line else f.path
        if fmt == "github":
            loc = f"file={f.path}" + (f",line={f.line}" if f.line else "")
            lines.append(f"::{f.severity} {loc},title={f.rule}::{_escape(f.message + ' Fix: ' + f.fix)}")
        else:
            lines.append(f"{f.severity.upper()} [{f.rule}] {where}\n  {f.message}\n  Fix: {f.fix}")
    lines.append(f"{errors} error(s), {warnings} warning(s)" + ("" if errors else " - the hard rules pass."))
    return "\n".join(lines)


def summary_markdown(findings: list[Finding]) -> str:
    if not findings:
        return "### Hard rules\n\nAll hard rules pass.\n"
    rows = ["### Hard rules\n", "| | Rule | File | Problem | Fix |", "| --- | --- | --- | --- | --- |"]
    for f in findings:
        icon = "❌" if f.severity == "error" else "⚠️"
        where = f"`{f.path}`" + (f" line {f.line}" if f.line else "")
        rows.append(f"| {icon} | {f.rule} | {where} | {f.message} | {f.fix} |".replace("\n", " "))
    return "\n".join(rows) + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", type=Path, default=Path("."), help="checkout to check (default: .)")
    ap.add_argument("--policy", type=Path, help="trusted checkout with the rules (default: --repo)")
    ap.add_argument("--base", required=True, help="base commit or branch, e.g. origin/main")
    ap.add_argument("--author", help="GitHub login of the PR author (default: an outside contributor)")
    ap.add_argument("--worktree", action="store_true", help="include uncommitted and untracked files")
    ap.add_argument("--format", choices=("text", "github", "json"), default="text")
    args = ap.parse_args(argv)

    try:
        findings = run(args.repo, args.policy or args.repo, args.base, args.author, args.worktree)
    except subprocess.CalledProcessError as e:
        print(f"git failed: {' '.join(e.cmd)}\n{e.stderr.decode(errors='replace')}", file=sys.stderr)
        return 2
    print(report(findings, args.format))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary and args.format == "github":
        with open(summary, "a") as fh:
            fh.write(summary_markdown(findings))
    return 1 if any(f.severity == "error" for f in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
