"""The repository's labels, defined once in ci/settings/labels.json (setup.sh applies them all).

Scripts that label something call ensure() first, so a label added to the file works before
setup.sh runs again.
"""

from __future__ import annotations

import json
from pathlib import Path

from . import config as config_mod
from . import gh

PATH = config_mod.CI_DIR / "settings" / "labels.json"


def definitions(path: Path = PATH) -> dict[str, dict[str, str]]:
    return {label["name"]: label for label in json.loads(path.read_text())}


def ensure(cfg: config_mod.Config, names: list[str] | tuple[str, ...]) -> None:
    """Creates any of `names` the repository doesn't have yet, from labels.json."""
    existing = {label["name"] for label in gh.api_paginated(f"repos/{cfg.repo}/labels?per_page=100")}
    known = definitions()
    for name in names:
        if name not in existing and name in known:
            gh.api(f"repos/{cfg.repo}/labels", "-X", "POST", input={
                "name": name, "color": known[name]["color"], "description": known[name]["description"]})
