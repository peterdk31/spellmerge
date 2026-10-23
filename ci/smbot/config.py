"""Fixed identities from ci/config.json (owner-only, so the bot can't change them).

  python3 -m smbot.config get game.slug              -> one value, for shell scripts
  python3 -m smbot.config render PROMPT.md           -> the prompt with {{REPO}}, {{GAME}}, {{PITCH}}, {{BOT}}
  python3 -m smbot.config runs                       -> the exported-build test runs, one per line (build.sh)
  python3 -m smbot.config ready                      -> the line the game's first screen prints
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass, fields
from pathlib import Path
from typing import Any

CI_DIR = Path(__file__).resolve().parent.parent
# The game's exported-build test runs. Bot-maintained (rules.BOT_PATHS), unlike this folder: the bot
# writes the runners they start, and build.sh only passes these values as quoted arguments.
RUNS_FILE = "tests/exported_runs.json"
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
    From tests/exported_runs.json, which the bot maintains."""
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


def parse_runs(data: dict[str, Any]) -> tuple[str, tuple[Run, ...]]:
    """The ready line and the runs, strictly checked; ValueError says what is wrong."""
    def line(value: Any, what: str) -> str:
        if not isinstance(value, str) or not _LINE.fullmatch(value):
            raise ValueError(f"{RUNS_FILE}: {what} must be one line of 1-200 characters without tabs")
        return value
    ready = line(data.get("ready"), "ready")
    rows = data.get("runs")
    if not isinstance(rows, list) or len(rows) > MAX_RUNS:
        raise ValueError(f"{RUNS_FILE}: runs must be a list of at most {MAX_RUNS}")
    runs: list[Run] = []
    for i, row in enumerate(rows):
        if not isinstance(row, dict) or set(row) != {f.name for f in fields(Run)}:
            raise ValueError(f"{RUNS_FILE}: run {i + 1} must have exactly {', '.join(f.name for f in fields(Run))}")
        if not isinstance(row["name"], str) or not _NAME.fullmatch(row["name"]):
            raise ValueError(f"{RUNS_FILE}: run {i + 1}: name must be lowercase letters, digits and dashes")
        if not isinstance(row["arg"], str) or not _ARG.fullmatch(row["arg"]):
            raise ValueError(f"{RUNS_FILE}: run {i + 1}: arg must look like --name")
        timeout = row["web_timeout"]
        if not isinstance(timeout, int) or isinstance(timeout, bool) or not 10 <= timeout <= 1800:
            raise ValueError(f"{RUNS_FILE}: run {i + 1}: web_timeout must be 10-1800 seconds")
        if not isinstance(row["bench"], bool):
            raise ValueError(f"{RUNS_FILE}: run {i + 1}: bench must be true or false")
        for key in ("label", "linux_ok", "web_ok"):
            line(row[key], f"run {i + 1}: {key}")
        runs.append(Run(**row))
    if len({r.name for r in runs}) != len(runs):
        raise ValueError(f"{RUNS_FILE}: two runs have the same name")
    return ready, tuple(runs)


def load_runs(root: Path = CI_DIR.parent) -> tuple[str, tuple[Run, ...]]:
    """The line the game's first screen prints (the web smoke test waits for it) and the runs.
    Kept out of Config, so a bad file only stops the build, never the gate or the intake."""
    path = root / RUNS_FILE
    return parse_runs(json.loads(path.read_text())) if path.exists() else ("main menu ready", ())


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
    args = parser.parse_args()
    if args.cmd == "get":
        print(get(raw(), args.key))
    elif args.cmd == "ready":
        print(load_runs()[0])
    elif args.cmd == "runs":
        for run in load_runs()[1]:
            print("\t".join((run.name, run.arg, run.label, run.linux_ok, run.web_ok, str(run.web_timeout))))
    else:
        print(render(args.template.read_text(), prompt_values(load())), end="")


if __name__ == "__main__":
    main()
