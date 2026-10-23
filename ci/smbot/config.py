"""Fixed identities from ci/config.json (owner-only, so the bot can't change them).

  python3 -m smbot.config get game.slug              -> one value, for shell scripts
  python3 -m smbot.config render PROMPT.md           -> the prompt with {{REPO}}, {{GAME}}, {{PITCH}}, {{BOT}}
  python3 -m smbot.config runs                       -> the exported-build test runs, one per line (build.sh)
  python3 -m smbot.config ready                      -> the line the game's first screen prints
  python3 -m smbot.config budget web_mb              -> one budget from tests/build.json
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass, fields
from pathlib import Path
from typing import Any

CI_DIR = Path(__file__).resolve().parent.parent
# The game's build settings: the ready line, the size and load-time budgets (warnings only) and the
# exported-build test runs. Bot-maintained (rules.BOT_PATHS), unlike this folder: the bot writes the
# runners they start, and build.sh only passes these values as quoted arguments and numbers.
BUILD_FILE = "tests/build.json"
BUDGET_LIMITS = {"web_mb": (1, 1000), "desktop_mb": (1, 5000), "web_load_s": (1, 120)}
MAX_RUNS = 10
_NAME = re.compile(r"[a-z0-9][a-z0-9-]{0,39}")
_ARG = re.compile(r"--[a-z0-9][a-z0-9-]{0,39}")
_LINE = re.compile(r"[^\t\r\n]{1,200}")  # build.sh reads the runs as tab-separated lines


@dataclass(frozen=True)
class Identity:
    login: str
    id: int


@dataclass(frozen=True)
class Game:
    name: str
    slug: str  # file and folder names: release zips, the Godot cache
    pitch: str  # one line, used in Claude's prompts: "a 2D top-down roguelite about ..."
    tagline: str  # under the name on the Contribute page
    description: str  # the repository description
    itch: str  # the itch.io page, or "" when there is none


@dataclass(frozen=True)
class Run:
    """A test the exported "Linux Test" and "Web Test" builds run, started by a user argument (build.sh).
    From tests/build.json, which the bot maintains."""
    name: str  # build/logs/<name>-linux.log and <name>-web.log
    arg: str  # e.g. --stress; the game starts the runner on it
    label: str
    linux_ok: str  # a grep pattern the Linux log must match
    web_ok: str  # the line websmoke waits for
    web_timeout: int
    bench: bool  # its result lines go into the Daily log (smbot.summary)


@dataclass(frozen=True)
class Config:
    repo: str
    game: Game
    owner: Identity
    bot: Identity
    bot_client_id: str
    dependency_bots: tuple[str, ...]
    control_panel_issue: int
    timezone: str
    state_branch: str

    @property
    def pages(self) -> str:
        owner, name = self.repo.split("/")
        return f"https://{owner.lower()}.github.io/{name}"


def raw(path: Path | None = None) -> dict[str, Any]:
    return json.loads((path or CI_DIR / "config.json").read_text())


@dataclass(frozen=True)
class Build:
    ready: str  # the line the game's first screen prints; the web smoke test waits for it
    budgets: dict[str, int]  # web_mb, desktop_mb (download sizes) and web_load_s; over them only warns
    runs: tuple[Run, ...]


DEFAULT_BUILD = Build("main menu ready", {"web_mb": 40, "desktop_mb": 300, "web_load_s": 10}, ())


def parse_build(data: dict[str, Any]) -> Build:
    """tests/build.json, strictly checked; ValueError says what is wrong."""
    if not isinstance(data, dict):
        raise ValueError(f"{BUILD_FILE} must be a JSON object")
    def line(value: Any, what: str) -> str:
        if not isinstance(value, str) or not _LINE.fullmatch(value):
            raise ValueError(f"{BUILD_FILE}: {what} must be one line of 1-200 characters without tabs")
        return value
    ready = line(data.get("ready"), "ready")
    rows = data.get("runs")
    if not isinstance(rows, list) or len(rows) > MAX_RUNS:
        raise ValueError(f"{BUILD_FILE}: runs must be a list of at most {MAX_RUNS}")
    runs: list[Run] = []
    for i, row in enumerate(rows):
        if not isinstance(row, dict) or set(row) != {f.name for f in fields(Run)}:
            raise ValueError(f"{BUILD_FILE}: run {i + 1} must have exactly {', '.join(f.name for f in fields(Run))}")
        if not isinstance(row["name"], str) or not _NAME.fullmatch(row["name"]):
            raise ValueError(f"{BUILD_FILE}: run {i + 1}: name must be lowercase letters, digits and dashes")
        if not isinstance(row["arg"], str) or not _ARG.fullmatch(row["arg"]):
            raise ValueError(f"{BUILD_FILE}: run {i + 1}: arg must look like --name")
        timeout = row["web_timeout"]
        if not isinstance(timeout, int) or isinstance(timeout, bool) or not 10 <= timeout <= 1800:
            raise ValueError(f"{BUILD_FILE}: run {i + 1}: web_timeout must be 10-1800 seconds")
        if not isinstance(row["bench"], bool):
            raise ValueError(f"{BUILD_FILE}: run {i + 1}: bench must be true or false")
        for key in ("label", "linux_ok", "web_ok"):
            line(row[key], f"run {i + 1}: {key}")
        runs.append(Run(**row))
    if len({r.name for r in runs}) != len(runs):
        raise ValueError(f"{BUILD_FILE}: two runs have the same name")
    budgets = data.get("budgets", DEFAULT_BUILD.budgets)
    if not isinstance(budgets, dict) or set(budgets) != set(BUDGET_LIMITS):
        raise ValueError(f"{BUILD_FILE}: budgets must have exactly {', '.join(BUDGET_LIMITS)}")
    for key, (low, high) in BUDGET_LIMITS.items():
        value = budgets[key]
        if not isinstance(value, int) or isinstance(value, bool) or not low <= value <= high:
            raise ValueError(f"{BUILD_FILE}: budgets.{key} must be a whole number from {low} to {high}")
    return Build(ready, dict(budgets), tuple(runs))


def load_build(root: Path = CI_DIR.parent) -> Build:
    """Kept out of Config, so a bad file only stops the build, never the gate or the intake."""
    path = root / BUILD_FILE
    return parse_build(json.loads(path.read_text())) if path.exists() else DEFAULT_BUILD


def load(path: Path | None = None) -> Config:
    data = raw(path)
    return Config(
        repo=data["repo"],
        game=Game(**data["game"]),
        owner=Identity(**data["owner"]),
        bot=Identity(login=data["bot"]["login"], id=data["bot"]["id"]),
        bot_client_id=data["bot"]["client_id"],
        dependency_bots=tuple(data["dependency_bots"]),
        control_panel_issue=data["issues"]["control_panel"],
        timezone=data["timezone"],
        state_branch=data["state_branch"],
    )


def prompt_values(cfg: Config) -> dict[str, str]:
    """The values every maintainer prompt may use."""
    return {"REPO": cfg.repo, "GAME": cfg.game.name, "PITCH": cfg.game.pitch, "BOT": cfg.bot.login}


def render(template: str, values: dict[str, str]) -> str:
    return re.sub(r"\{\{(\w+)\}\}", lambda m: values.get(m.group(1), m.group(0)), template)


def get(data: dict[str, Any], key: str) -> str:
    value: Any = data
    for part in key.split("."):
        value = value[part]
    if isinstance(value, (dict, list)):
        raise SystemExit(f"{key} is not a single value")
    return str(value)


def main() -> None:
    parser = argparse.ArgumentParser(prog="smbot.config")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("get").add_argument("key")
    sub.add_parser("render").add_argument("template", type=Path)
    sub.add_parser("runs")
    sub.add_parser("ready")
    sub.add_parser("budget").add_argument("key", choices=sorted(BUDGET_LIMITS))
    args = parser.parse_args()
    if args.cmd == "get":
        print(get(raw(), args.key))
    elif args.cmd == "ready":
        print(load_build().ready)
    elif args.cmd == "budget":
        print(load_build().budgets[args.key])
    elif args.cmd == "runs":
        for run in load_build().runs:
            print("\t".join((run.name, run.arg, run.label, run.linux_ok, run.web_ok, str(run.web_timeout))))
    else:
        print(render(args.template.read_text(), prompt_values(load())), end="")


if __name__ == "__main__":
    main()
