"""Fixed identities from ci/config.json (owner-only, so the bot can't change them)."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

CI_DIR = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class Identity:
    login: str
    id: int


@dataclass(frozen=True)
class Config:
    repo: str
    owner: Identity
    bot: Identity
    dependency_bots: tuple[str, ...]


def load(path: Path | None = None) -> Config:
    data = json.loads((path or CI_DIR / "config.json").read_text())
    return Config(
        repo=data["repo"],
        owner=Identity(**data["owner"]),
        bot=Identity(**data["bot"]),
        dependency_bots=tuple(data["dependency_bots"]),
    )
