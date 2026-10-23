"""Fixed identities from ci/config.json (owner-only, so the bot can't change them).

  python3 -m smbot.config get game.slug              -> one value, for shell scripts
  python3 -m smbot.config render PROMPT.md           -> the prompt with {{REPO}}, {{GAME}}, {{PITCH}}, {{BOT}}
  python3 -m smbot.config runs                       -> the exported-build test runs, one per line (build.sh)
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

CI_DIR = Path(__file__).resolve().parent.parent


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
    """A test the exported "Linux Test" and "Web Test" builds run, started by a user argument (build.sh)."""
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
    ready_line: str  # the line the game prints once its first screen is up (the web smoke test waits for it)
    runs: tuple[Run, ...]

    @property
    def pages(self) -> str:
        owner, name = self.repo.split("/")
        return f"https://{owner.lower()}.github.io/{name}"


def raw(path: Path | None = None) -> dict[str, Any]:
    return json.loads((path or CI_DIR / "config.json").read_text())


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
        ready_line=data["build"]["ready"],
        runs=tuple(Run(**r) for r in data["build"]["runs"]),
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
    args = parser.parse_args()
    if args.cmd == "get":
        print(get(raw(), args.key))
    elif args.cmd == "runs":
        for run in load().runs:
            print("\t".join((run.name, run.arg, run.label, run.linux_ok, run.web_ok, str(run.web_timeout))))
    else:
        print(render(args.template.read_text(), prompt_values(load())), end="")


if __name__ == "__main__":
    main()
