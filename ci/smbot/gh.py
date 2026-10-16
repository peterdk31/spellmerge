"""Thin wrapper around the GitHub CLI, which is preinstalled on GitHub's runners.

The token comes from GH_TOKEN in the environment, set per step by the workflow.
"""

from __future__ import annotations

import json
import subprocess
from typing import Any


class GhError(RuntimeError):
    pass


def run(*args: str, input: str | None = None) -> str:
    proc = subprocess.run(["gh", *args], input=input, capture_output=True, text=True)
    if proc.returncode != 0:
        raise GhError(f"gh {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc.stdout


def api(path: str, *args: str, input: Any = None) -> Any:
    """Calls the REST API and returns parsed JSON (None for empty bodies)."""
    extra = ["--input", "-"] if input is not None else []
    out = run("api", "-H", "X-GitHub-Api-Version: 2022-11-28", path, *args, *extra,
              input=json.dumps(input) if input is not None else None)
    return json.loads(out) if out.strip() else None


def api_paginated(path: str, *args: str) -> list[Any]:
    """All pages of a REST list endpoint, flattened into one list."""
    out = run("api", "-H", "X-GitHub-Api-Version: 2022-11-28", "--paginate", "--slurp", path, *args)
    return [item for page in json.loads(out) for item in page]


def graphql(query: str, **variables: Any) -> Any:
    args = ["api", "graphql", "-f", f"query={query}"]
    for key, value in variables.items():
        args += ["-F" if isinstance(value, (int, bool)) else "-f", f"{key}={value}"]
    data = json.loads(run(*args))
    if data.get("errors"):
        raise GhError(f"GraphQL errors: {data['errors']}")
    return data["data"]
