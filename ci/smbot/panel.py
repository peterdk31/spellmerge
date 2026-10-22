"""Reads the Control panel issue (docs/PLAN.md, "Control panel issue").

Trust model:
- Values come only from revisions in GitHub's own edit history whose editor is
  the owner's fixed numeric user ID, never from storage the bot can change.
- The newest owner revision wins. A newer revision by anyone else is ignored
  and reported, so the owner is told.
- Strict parsing: numbers are clamped to valid ranges and unknown fields are
  ignored. A value that can't be read falls back to the same field in an older
  owner revision, then to the default.
- Fail closed: if no owner revision can be verified, automation is off.
"""

from __future__ import annotations

import re
from dataclasses import asdict, dataclass, field, fields
from typing import Any, Callable

from . import config as config_mod
from . import gh


@dataclass(frozen=True)
class Settings:
    automation_enabled: bool = True
    pause_development: bool = False
    pause_merging: bool = False
    quiet_hours: tuple[int, int] | None = None
    focus: str = ""


FAIL_CLOSED = Settings(automation_enabled=False)

_CHECKBOXES = {
    "automation_enabled": "Automation enabled",
    "pause_development": "Pause development",
    "pause_merging": "Pause PR merging",
}
FOCUS_MAX = 500


def _checkbox(label: str) -> Callable[[str], bool | None]:
    rx = re.compile(r"^\s*[-*]\s*\[([ xX])\]\s*" + re.escape(label) + r"\b", re.MULTILINE)

    def parse(text: str) -> bool | None:
        m = rx.search(text)
        return None if m is None else m.group(1).lower() == "x"
    return parse


_QUIET = re.compile(r"\bQUIET_HOURS:[ \t]*(\S*)")
_FOCUS = re.compile(r"^FOCUS:[ \t]*(.*)$", re.MULTILINE)


def _quiet_hours(text: str) -> tuple[int, int] | None | str:
    """(start, end), None for 'no quiet hours', or "invalid"/"missing"."""
    m = _QUIET.search(text)
    if m is None:
        return "missing"
    value = m.group(1)
    # VOTE_ lines are from panels written before community voting was removed.
    if value == "" or value.startswith("VOTE_") or value.startswith("FOCUS"):
        return None
    hm = re.fullmatch(r"(\d{1,2})(?::00)?-(\d{1,2})(?::00)?", value)
    if hm is None:
        return "invalid"
    start, end = int(hm.group(1)), int(hm.group(2))
    if not (0 <= start <= 24 and 0 <= end <= 24) or start % 24 == end % 24:
        return "invalid"
    return (start % 24, end % 24)


def _focus(text: str) -> str | None:
    m = _FOCUS.search(text)
    if m is None:
        return None
    value = m.group(1).strip()
    if value.startswith("(optional"):
        value = ""
    return value[:FOCUS_MAX]


def parse_field(name: str, text: str) -> Any:
    """The field's value in one revision, or the sentinel _UNREADABLE."""
    if name in _CHECKBOXES:
        value = _checkbox(_CHECKBOXES[name])(text)
    elif name == "quiet_hours":
        q = _quiet_hours(text)
        return _UNREADABLE if isinstance(q, str) else q
    elif name == "focus":
        value = _focus(text)
    else:
        raise KeyError(name)
    return _UNREADABLE if value is None else value


_UNREADABLE = object()


def settings_from_revisions(owner_revisions: list[str]) -> tuple[Settings, list[str]]:
    """Builds settings from owner revisions, newest first.

    Returns the settings and the names of fields that came from an older
    revision or the default because the newest one couldn't be read.
    """
    values: dict[str, Any] = {}
    fallbacks: list[str] = []
    for f in fields(Settings):
        for i, text in enumerate(owner_revisions):
            value = parse_field(f.name, text)
            if value is not _UNREADABLE:
                values[f.name] = value
                if i > 0:
                    fallbacks.append(f.name)
                break
        else:
            fallbacks.append(f.name)
            if f.name == "automation_enabled":
                values[f.name] = False  # never assume the kill switch is off
    return Settings(**values), fallbacks


@dataclass
class PanelResult:
    settings: Settings
    verified: bool
    problems: list[str] = field(default_factory=list)


_QUERY = """
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      body
      author { ... on User { databaseId } }
      userContentEdits(first: 100) {
        nodes { editedAt deletedAt diff editor { login ... on User { databaseId } } }
      }
    }
  }
}"""


def revisions(issue: dict) -> list[tuple[int | None, str | None, str]]:
    """(editor id, editor login, text) for each revision, newest first."""
    edits = issue["userContentEdits"]["nodes"]
    if not edits:  # never edited: the body is the author's only revision
        return [(issue["author"]["databaseId"] if issue["author"] else None, None, issue["body"])]
    out = []
    for e in edits:
        if e["deletedAt"] or e["diff"] is None:
            continue
        editor = e["editor"] or {}
        out.append((editor.get("databaseId"), editor.get("login"), e["diff"]))
    return out


def evaluate(issue: dict, owner_id: int) -> PanelResult:
    revs = revisions(issue)
    problems = []
    owner_texts = [text for editor, _, text in revs if editor == owner_id]
    if revs and revs[0][0] != owner_id:
        who = revs[0][1] or "an unknown account"
        problems.append(f"The newest Control panel edit is by {who}, not the owner; it is ignored.")
    if not owner_texts:
        problems.append("No Control panel revision by the owner could be verified; automation is paused.")
        return PanelResult(FAIL_CLOSED, False, problems)
    settings, fallbacks = settings_from_revisions(owner_texts)
    if fallbacks:
        problems.append("Unreadable Control panel values, using the previous owner value or the default for: "
                        + ", ".join(fallbacks))
    return PanelResult(settings, True, problems)


def read(cfg: config_mod.Config) -> PanelResult:
    owner, name = cfg.repo.split("/")
    try:
        data = gh.graphql(_QUERY, owner=owner, name=name, number=cfg.control_panel_issue)
        issue = data["repository"]["issue"]
    except (gh.GhError, KeyError, TypeError) as e:
        return PanelResult(FAIL_CLOSED, False, [f"The Control panel could not be read ({e}); automation is paused."])
    if issue is None:
        return PanelResult(FAIL_CLOSED, False, ["The Control panel issue is missing; automation is paused."])
    return evaluate(issue, cfg.owner.id)


def describe(name: str, value: Any) -> str:
    if name == "quiet_hours":
        return "none" if value is None else f"{value[0]:02d}-{value[1]:02d}"
    if isinstance(value, bool):
        return "on" if value else "off"
    return repr(value) if name == "focus" else str(value)


LABELS = {**_CHECKBOXES, "quiet_hours": "QUIET_HOURS", "focus": "FOCUS"}


def changes(old: dict | None, new: Settings, owner_login: str) -> list[str]:
    """Audit lines for the Daily log, e.g. 'QUIET_HOURS none → 07-17 (by peterdk31)'."""
    if old is None:
        return []
    new_d = asdict(new)
    lines = []
    for name, value in new_d.items():
        before = old.get(name)
        if isinstance(before, list):
            before = tuple(before)
        if before != value:
            lines.append(f"{LABELS[name]} {describe(name, before)} → {describe(name, value)} (by {owner_login})")
    return lines


def to_json(settings: Settings) -> dict:
    return asdict(settings)
