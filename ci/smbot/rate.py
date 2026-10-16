"""Claude's rating of outside PRs (docs/PLAN.md, "Filter 2: Claude's rating").

  python3 -m smbot.rate prepare --pr N    checks the PR's files out read-only into
                                          pr/ (nothing is run) and builds the prompt
  python3 -m smbot.rate post --pr N       posts the rating from $RATING as a comment

Claude rates with read-only tools and no write token; this script applies the
decision rules and posts the result with the bot's token. The comment carries a
marker with the rated head SHA, the decision and the average, which the merge
step reads; a later push makes the PR due for a new rating.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from . import config as config_mod
from . import gh, state, votes
from .triage import RATING_MARKER

CRITERIA = ("fit", "fun", "quality", "value", "performance", "risk", "scope")
MERGE_AVERAGE = 3.5
MIN_SCORE = 2

# Extra rating questions per area (docs/PLAN.md, "Areas").
AREA_QUESTIONS = {
    "area:spells": ["Does it create interesting interactions with other components?", "Is it within the power budget?"],
    "area:relics": ["Does it widen build diversity?", "Is it balanced?"],
    "area:wizard": ["Is the look or playstyle distinct?", "Does it follow the style guide?"],
    "area:enemies": ["Are its attacks readable and telegraphed?", "Does it scale for 1–4 players?"],
    "area:bosses": ["Is it fair?", "Is it a spectacle?", "Does it scale for 1–4 players?"],
    "area:rooms": ["Is there space for 4 players?", "Are doors and spawns valid?"],
    "area:gameplay": ["Does it keep the no-waiting pillar?", "Could it cause regressions?"],
    "area:hud": ["Is it readable with 4 players?", "Does it work with gamepad navigation?"],
    "area:art": ["Does it use the STYLE.md palette?", "Is it readable at 1×?"],
    "area:audio": ["Are format, loudness and length right? (Votes decide taste.)"],
    "area:story": ["Does it fit the STORY.md canon and tone?"],
    "area:core": ["Core is closed to outside PRs: suggest opening an issue instead."],
}


def average(scores: dict[str, int]) -> float:
    return sum(scores[c] for c in CRITERIA) / len(CRITERIA)


def final_decision(rating: dict[str, Any]) -> str:
    """Claude's decision, held to the plan's thresholds."""
    scores = rating["scores"]
    if rating["decision"] == "close":
        return "close"
    if rating["decision"] == "merge" and average(scores) >= MERGE_AVERAGE and min(scores.values()) >= MIN_SCORE:
        return "merge"
    return "changes"


def area_questions(labels: set[str]) -> str:
    qs = [f"- {q}" for label in sorted(labels) for q in AREA_QUESTIONS.get(label, [])]
    return "\n".join(qs) or "- (none for this area)"


def marker(sha: str, decision: str, avg: float) -> str:
    return f"{RATING_MARKER} sha={sha} decision={decision} average={avg:.2f} -->"


def parse_marker(body: str) -> dict[str, str] | None:
    m = re.search(re.escape(RATING_MARKER) + r"((?: \w+=[^\s]+)+) -->", body)
    if not m:
        return None
    return dict(part.split("=", 1) for part in m.group(1).split())


def comment_body(pr: dict[str, Any], rating: dict[str, Any], decision: str, vote_line: str | None) -> str:
    s = rating["scores"]
    avg = average(s)
    parts = [rating["message"].strip(), "", f"**What it does:** {rating['summary'].strip()}", "",
             "| " + " | ".join(c.capitalize() for c in CRITERIA) + " | Average |",
             "|" + " --- |" * (len(CRITERIA) + 1),
             "| " + " | ".join(str(s[c]) for c in CRITERIA) + f" | **{avg:.1f}** |", ""]
    if rating.get("area_answers"):
        parts += [f"- *{a['question']}* {a['answer']}" for a in rating["area_answers"]] + [""]
    if decision == "merge":
        parts.append("**Decision: merge.**" + (" Small things will be polished by Claude in a follow-up: "
                                               + "; ".join(rating["fixups"]) + "." if rating.get("fixups") else ""))
    elif decision == "changes":
        parts.append("**Decision: changes requested.** Push to this branch and it will be rated again:")
        for c in rating.get("change_requests", [])[:3]:
            where = f"`{c['file']}`" + (f" line {c['line']}" if c.get("line") else "") if c.get("file") else "General"
            parts.append(f"- {where}: {c['problem']} **Fix:** {c['fix']}")
    else:
        parts.append(f"**Decision: close.** {rating.get('close_reason', '').strip()}")
    if vote_line:
        parts += ["", f"**Community vote** (react 👍 or 👎 on the PR itself): {vote_line}"]
    parts += ["", "<sub>Rated by Claude, the project's AI maintainer. A script checks the hard rules again before "
              "anything merges. Questions? Reply here.</sub>", marker(pr["head"]["sha"], decision, avg)]
    return "\n".join(parts)


def prepare(cfg: config_mod.Config, number: int) -> dict[str, str]:
    pr = gh.api(f"repos/{cfg.repo}/pulls/{number}")
    subprocess.run(["git", "fetch", "--quiet", "origin", f"pull/{number}/head"], check=True)
    subprocess.run(["git", "worktree", "add", "--quiet", "--detach", "pr", pr["head"]["sha"]], check=True)
    labels = {label["name"] for label in pr["labels"]}
    prompt = (Path(".github/maintainer/rate.md").read_text()
              .replace("{{REPO}}", cfg.repo).replace("{{PR}}", str(number)).replace("{{SHA}}", pr["head"]["sha"])
              .replace("{{AUTHOR}}", pr["user"]["login"]).replace("{{AREA_QUESTIONS}}", area_questions(labels)))
    return {"prompt": prompt, "sha": pr["head"]["sha"]}


def post(cfg: config_mod.Config, number: int, rated_sha: str, rating: dict[str, Any]) -> str:
    pr = gh.api(f"repos/{cfg.repo}/pulls/{number}")
    if pr["head"]["sha"] != rated_sha:
        return f"#{number} changed while it was rated; it will be rated again tomorrow"
    decision = final_decision(rating)
    labels = {label["name"] for label in pr["labels"]}
    vote_line = None
    if decision == "merge" and votes.is_votable(labels):
        vote_line = ("Voting is open for 24 hours. The current count is shown here and updated daily. "
                     "Gameplay changes: please add a short GIF or video so voters can judge without building the game.")
    if rating.get("description") and len((pr.get("body") or "").strip()) < 20:
        gh.api(f"repos/{cfg.repo}/pulls/{number}", "-X", "PATCH",
               input={"body": f"{(pr.get('body') or '').strip()}\n\n*Description written by Claude:*\n\n"
                              f"{rating['description'].strip()}".strip()})
    gh.api(f"repos/{cfg.repo}/issues/{number}/comments", "-X", "POST",
           input={"body": comment_body(pr, rating, decision, vote_line)})
    if decision == "close":
        gh.api(f"repos/{cfg.repo}/pulls/{number}", "-X", "PATCH", input={"state": "closed"})
    if decision == "merge" and rating.get("fixups"):
        state.update(cfg, lambda s: s.setdefault("fixups", {}).__setitem__(str(number), rating["fixups"][:10]),
                     f"rate: fix-ups for #{number}")
    if rating.get("concerns"):
        print(f"concerns on #{number}: {rating['concerns']}")
    return f"Rated #{number}: {decision} (average {average(rating['scores']):.1f})"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("prepare").add_argument("--pr", type=int, required=True)
    p = sub.add_parser("post")
    p.add_argument("--pr", type=int, required=True)
    p.add_argument("--sha", required=True)
    args = ap.parse_args(argv)
    cfg = config_mod.load()
    if args.cmd == "prepare":
        out = prepare(cfg, args.pr)
        path = os.environ.get("GITHUB_OUTPUT")
        if path:
            with open(path, "a") as fh:
                fh.write(f"sha={out['sha']}\nprompt<<__END__\n{out['prompt']}\n__END__\n")
                schema = json.loads(Path(".github/maintainer/schemas/rate.json").read_text())
                fh.write(f"schema={json.dumps(schema, separators=(',', ':'))}\n")
        print(out["prompt"][:300])
    else:
        print(post(cfg, args.pr, args.sha, json.loads(os.environ["RATING"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
