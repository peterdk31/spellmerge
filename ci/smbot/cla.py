"""The project's own CLA check (docs/PLAN.md, "Protection"; CLA.md).

Contributors sign by commenting "I have read the CLA and I agree to it." on
their PR once (or by ticking the CLA box in a no-git submission form). The
daily run records signatures in docs/cla-signatures.json by numeric user ID and
CLA version. A comment counts only if its author and every editor in its edit
history is the PR author.

  python3 -m smbot.cla check --pr N     exit 0 if the PR's author has signed
                                        (checks.yml's informational cla job)
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from . import config as config_mod
from . import gh

SIGNATURES = Path("docs/cla-signatures.json")
CLA_FILE = Path("CLA.md")
PHRASE = "i have read the cla and i agree to it"
REMINDER_MARKER = "<!-- spellmerge:cla-reminder -->"


def current_version(text: str | None = None) -> str:
    text = text if text is not None else CLA_FILE.read_text()
    m = re.search(r"\*\*Version ([0-9.]+)", text)
    if not m:
        raise ValueError("CLA.md has no version line")
    return m.group(1)


def is_signing_comment(body: str) -> bool:
    words = re.sub(r"[^a-z ]+", " ", body.lower()).split()
    return " ".join(words) == PHRASE


def load_signatures(path: Path = SIGNATURES) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    return json.loads(path.read_text())["signatures"]


def has_signed(signatures: list[dict[str, Any]], user_id: int, version: str) -> bool:
    return any(s["user_id"] == user_id and s["version"] == version for s in signatures)


def exempt(login: str, cfg: config_mod.Config) -> bool:
    return login in (cfg.owner.login, cfg.bot.login, *cfg.dependency_bots)


_EDITS = """
query($id: ID!) {
  node(id: $id) {
    ... on IssueComment {
      author { ... on User { databaseId } }
      userContentEdits(first: 50) { nodes { editor { ... on User { databaseId } } } }
    }
  }
}"""


@dataclass(frozen=True)
class Signature:
    user_id: int
    login: str
    version: str
    signed_at: str
    evidence: str

    def as_json(self) -> dict[str, Any]:
        return {"user_id": self.user_id, "login": self.login, "version": self.version,
                "signed_at": self.signed_at, "evidence": self.evidence}


def find_signature_on_pr(cfg: config_mod.Config, number: int, author_id: int, version: str,
                         token: str | None = None) -> Signature | None:
    comments = gh.api(f"repos/{cfg.repo}/issues/{number}/comments?per_page=100", token=token)
    for c in comments:
        if (c.get("user") or {}).get("id") != author_id or not is_signing_comment(c.get("body") or ""):
            continue
        node = gh.graphql(_EDITS, gh_token=token, id=c["node_id"])["node"]
        editors = [(e.get("editor") or {}).get("databaseId") for e in node["userContentEdits"]["nodes"]]
        if (node.get("author") or {}).get("databaseId") == author_id and all(e == author_id for e in editors):
            return Signature(author_id, c["user"]["login"], version, c["created_at"], c["html_url"])
    return None


def add_signatures(path: Path, new: list[Signature], version: str) -> int:
    """Adds signatures to the file; returns how many were new."""
    data = json.loads(path.read_text()) if path.exists() else {"signatures": []}
    known = {(s["user_id"], s["version"]) for s in data["signatures"]}
    added = 0
    for sig in new:
        if (sig.user_id, sig.version) not in known:
            data["signatures"].append(sig.as_json())
            known.add((sig.user_id, sig.version))
            added += 1
    data["cla_version"] = version
    data["signatures"].sort(key=lambda s: (s["signed_at"], s["user_id"]))
    path.write_text(json.dumps(data, indent=2) + "\n")
    return added


def reminder_text(login: str, repo: str, grace_days: int) -> str:
    return (f"{REMINDER_MARKER}\nThanks for your contribution, @{login}! Before it can be merged, please sign the "
            f"[Contributor License Agreement](https://github.com/{repo}/blob/main/CLA.md) once by posting this "
            "exact comment here:\n\n> I have read the CLA and I agree to it.\n\n"
            "In short: you keep the copyright, the project may use and relicense your contribution (for example "
            f"for Steam), and you confirm it is yours to give. If it isn't signed within {grace_days} days, this "
            "PR is closed; you can reopen it after signing.")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check").add_argument("--pr", type=int, required=True)
    args = ap.parse_args(argv)
    cfg = config_mod.load()
    pr = gh.api(f"repos/{cfg.repo}/pulls/{args.pr}")
    login, user_id = pr["user"]["login"], pr["user"]["id"]
    if exempt(login, cfg):
        print(f"{login} doesn't need to sign the CLA.")
        return 0
    version = current_version()
    if has_signed(load_signatures(), user_id, version):
        print(f"@{login} has signed CLA version {version}.")
        return 0
    if find_signature_on_pr(cfg, args.pr, user_id, version):
        print(f"@{login} signed CLA version {version} on this PR; it is recorded by the next daily run.")
        return 0
    print(f"::error::@{login} hasn't signed the CLA yet. Post this exact comment on the PR: "
          "I have read the CLA and I agree to it.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
