"""Bookkeeping around Claude's development sessions (docs/PLAN.md, "Self-driven progress").

  python3 -m smbot.session prepare            builds the implement prompt
  python3 -m smbot.session account --file F --kind dev|review
                                              records token usage, detects usage
                                              limits and a rejected token
  python3 -m smbot.session review-prompt --pr N --sha S --round critique|final
  python3 -m smbot.session revise-prompt --pr N
  python3 -m smbot.session finish             Daily log, task failures, next run

Outputs go to $GITHUB_OUTPUT. Prompt templates live in .github/maintainer/.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

from . import alarms, dailylog, gh, nexttask, pacing, state
from . import config as config_mod

MAINTAINER = Path(".github/maintainer")
MAX_FAILURES = 2

_LIMIT = re.compile(r"usage limit|limit reached|reached (?:your |the )?(?:\w+ )?limit|rate[ _-]?limit|\b429\b|"
                    r"quota|out of (?:extra )?usage|resets? (?:at|in)", re.IGNORECASE)
_WEEKLY = re.compile(r"weekly|7[- ]day", re.IGNORECASE)
_AUTH = re.compile(r"invalid (?:api key|bearer|token|x-api-key)|oauth token|authentication[_ ]error|\b401\b|"
                   r"unauthori[sz]ed|token (?:has )?expired|credit balance", re.IGNORECASE)


# --- Execution files -----------------------------------------------------------


def read_messages(path: Path) -> list[dict[str, Any]]:
    """The SDK messages in a claude-code-action execution file (JSON array or JSON lines)."""
    if not path.is_file():
        return []
    text = path.read_text()
    try:
        data = json.loads(text)
        return data if isinstance(data, list) else [data]
    except json.JSONDecodeError:
        return [json.loads(line) for line in text.splitlines() if line.strip().startswith("{")]


def tokens_used(result: dict[str, Any]) -> int:
    """An estimate of quota use: cache reads are cheap, so they count a tenth."""
    u = result.get("usage") or {}
    return int(u.get("input_tokens", 0) + u.get("output_tokens", 0) + u.get("cache_creation_input_tokens", 0)
               + 0.1 * u.get("cache_read_input_tokens", 0))


def classify(messages: list[dict[str, Any]], step_failed: bool) -> tuple[str, int, str]:
    """(status, tokens, detail): status is ok, limit, limit-weekly, auth or error."""
    results = [m for m in messages if m.get("type") == "result"]
    result = results[-1] if results else {}
    tokens = tokens_used(result)
    text = " ".join(str(result.get(k, "")) for k in ("result", "subtype", "error")) if result else ""
    if not result and not step_failed:
        return "error", 0, "no result in the execution file"
    if result.get("is_error") or step_failed or not result:
        if _AUTH.search(text):
            return "auth", tokens, text[:300]
        if _LIMIT.search(text):
            return ("limit-weekly" if _WEEKLY.search(text) else "limit"), tokens, text[:300]
        return "error", tokens, text[:300] or "the Claude step failed"
    return "ok", tokens, ""


# --- Prompts -------------------------------------------------------------------


def render(template: str, values: dict[str, str]) -> str:
    return re.sub(r"\{\{(\w+)\}\}", lambda m: values.get(m.group(1), m.group(0)), template)


def slug(text: str) -> str:
    words = re.sub(r"[^a-z0-9 ]+", " ", re.sub(r"\*\*|`", "", text.lower())).split()
    return "-".join(words[:6]) or "task"


def instructions_text(pending: list[dict[str, Any]]) -> str:
    if not pending:
        return "(none)"
    lines = []
    for p in pending:
        lines.append(f"- `/{p['kind']}` on #{p['number']} ({p['url']}): {p['text'] or '(no text)'}")
    return "\n".join(lines)


def prepare(cfg: config_mod.Config, st: dict[str, Any], focus: str, today: dt.date) -> dict[str, str]:
    task = nexttask.next_task()
    failures = st.get("task_failures", {}).get(task or "", {})
    previous = ""
    if failures:
        previous = (f"This task failed review {failures['count']} time(s) before. The last attempt is PR "
                    f"#{failures.get('pr')}; its problems were:\n\n{failures.get('problems', '(not recorded)')}\n\n"
                    + ("This is the last attempt: if it can't be done properly, mark the task blocked in "
                       "docs/NEXT.md with the reason, close the old PR, and report status `blocked`."
                       if failures["count"] >= MAX_FAILURES - 1 else
                       "Continue on that PR's branch if it is still useful, otherwise start fresh."))
    branch = f"claude/{today:%Y%m%d}-{slug(task or 'owner-instructions')}"
    template = (MAINTAINER / "develop.md").read_text()
    prompt = render(template, {
        "TASK": task or "(the queue is empty: only handle the owner instructions below)",
        "FOCUS": focus or "(none)",
        "INSTRUCTIONS": instructions_text(st.get("pending_instructions", [])),
        "PREVIOUS": previous or "(first attempt)",
        "BRANCH": branch,
        "REPO": cfg.repo,
    })
    return {"prompt": prompt, "branch": branch, "task": task or ""}


def review_prompt(cfg: config_mod.Config, pr: int, sha: str, round_: str) -> str:
    return render((MAINTAINER / "review.md").read_text(), {
        "PR": str(pr), "SHA": sha, "REPO": cfg.repo,
        "ROUND": ("This is the critique round: be demanding, the author will revise."
                  if round_ == "critique" else
                  "This is the final review: approve only if the PR can merge now as it is."),
    })


def revise_prompt(cfg: config_mod.Config, pr: int, review: dict[str, Any]) -> str:
    problems = "\n".join(
        f"- [{p.get('severity')}] {p.get('file', '')}{':' + str(p['line']) if p.get('line') else ''}: "
        f"{p.get('problem')} Fix: {p.get('fix')}" for p in review.get("problems", [])) or "(no specific problems)"
    return render((MAINTAINER / "revise.md").read_text(), {
        "PR": str(pr), "REPO": cfg.repo, "SUMMARY": review.get("summary", ""), "PROBLEMS": problems,
    })


def mergeable(review: dict[str, Any]) -> bool:
    return review.get("verdict") == "approve" and not any(
        p.get("severity") in ("blocker", "major") for p in review.get("problems", []))


# --- Workflow plumbing ---------------------------------------------------------


def write_outputs(values: dict[str, str]) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    for key, value in values.items():
        print(f"{key}: {value[:500]}")
    if path:
        with open(path, "a") as fh:
            for key, value in values.items():
                fh.write(f"{key}<<__END__\n{value}\n__END__\n")


def account(cfg: config_mod.Config, path: Path, kind: str, step_failed: bool) -> str:
    status, tokens, detail = classify(read_messages(path), step_failed)
    now = dt.datetime.now(dt.timezone.utc)

    def apply(s: dict[str, Any]) -> None:
        if tokens:
            pacing.record(s, now, tokens, kind)
        if status in ("limit", "limit-weekly"):
            pacing.limit_hit(s, now, weekly=status == "limit-weekly")
    state.update(cfg, apply, f"session: {kind} used {tokens} tokens ({status})")

    if status == "auth":
        st, _ = state.load(cfg)
        line = alarms.raise_alarm(cfg, st, "token")
        state.update(cfg, lambda s: s["alarms"].update(st["alarms"]), "session: token alarm")
        if line:
            dailylog.post(cfg, "Claude token rejected", [line], mention_owner=True)
    elif status == "ok":
        st, _ = state.load(cfg)
        if "token" in st["alarms"]:
            line = alarms.clear_alarm(cfg, st, "token")
            state.update(cfg, lambda s: s["alarms"].pop("token", None), "session: token works again")
            if line:
                dailylog.post(cfg, "Claude token works again", [line])
    print(f"{kind}: {status}, {tokens:,} tokens {detail}")
    return status


def finish(cfg: config_mod.Config, env: dict[str, str]) -> dict[str, str]:
    """Records the outcome, posts to the Daily log and decides on another session."""
    task, pr, merged = env.get("TASK", ""), env.get("PR", ""), env.get("MERGED") == "true"
    status = env.get("IMPLEMENT_STATUS", "")
    review = json.loads(env.get("FINAL_REVIEW") or "{}")
    lines: list[str] = []
    now = dt.datetime.now(dt.timezone.utc)

    def apply(s: dict[str, Any]) -> None:
        failures = s.setdefault("task_failures", {})
        if merged:
            failures.pop(task, None)
            s["pending_instructions"] = []
            s["last_own_merge"] = pacing.iso(now)
        elif pr and review and not mergeable(review):
            entry = failures.setdefault(task, {"count": 0})
            entry["count"] += 1
            entry["pr"] = pr
            entry["problems"] = "\n".join(f"- {p.get('problem')} Fix: {p.get('fix')}"
                                          for p in review.get("problems", []))[:4000]
        elif status == "blocked":
            failures.pop(task, None)
            s["pending_instructions"] = []
    state.update(cfg, apply, f"session: finished ({'merged' if merged else 'not merged'})")

    if merged:
        lines.append(f"Merged #{pr}: {task or 'owner instructions'}")
    elif status == "blocked":
        lines.append(f"Marked blocked: {task} ({env.get('IMPLEMENT_SUMMARY', '')[:300]})")
    elif pr:
        reason = env.get("MERGE_RESULT") or review.get("summary", "the final review did not approve it")
        lines.append(f"Not merged: #{pr} ({task}). {reason[:400]}")
    elif status and status != "ok":
        lines.append(f"Development session stopped: {status}. {env.get('IMPLEMENT_SUMMARY', '')[:300]}")
    settings = json.loads(env.get("SETTINGS") or "{}")
    st, _ = state.load(cfg)
    lines.append(pacing.usage_line(st, now, settings.get("dev_intensity", 90), settings.get("weekly_share", 90)))
    if env.get("RUN_URL"):
        lines.append(f"[Workflow run]({env['RUN_URL']})")
    dailylog.post(cfg, "Development session", lines)

    # Keep going while there is work and budget, up to about 2 hours per chain.
    started = env.get("CHAIN_STARTED") or pacing.iso(now)
    elapsed = now - pacing.parse_time(started)
    budget = pacing.budget(st, now, settings.get("dev_intensity", 90), settings.get("weekly_share", 90))
    again = merged and budget.allowed and elapsed < dt.timedelta(hours=2) and nexttask.next_task() is not None
    return {"again": str(again).lower(), "chain_started": started}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("prepare")
    acc = sub.add_parser("account")
    acc.add_argument("--file", type=Path, required=True)
    acc.add_argument("--kind", choices=("dev", "review", "rate", "plan"), required=True)
    acc.add_argument("--step-failed", action="store_true")
    rp = sub.add_parser("review-prompt")
    rp.add_argument("--pr", type=int, required=True)
    rp.add_argument("--sha", required=True)
    rp.add_argument("--round", dest="round_", choices=("critique", "final"), required=True)
    vp = sub.add_parser("revise-prompt")
    vp.add_argument("--pr", type=int, required=True)
    pi = sub.add_parser("pr-info")
    pi.add_argument("--pr", type=int, required=True)
    pi.add_argument("--require-own", action="store_true", help="fail unless the bot opened the PR")
    sub.add_parser("finish")
    args = ap.parse_args(argv)

    cfg = config_mod.load()
    if args.cmd == "prepare":
        st, _ = state.load(cfg)
        write_outputs(prepare(cfg, st, os.environ.get("FOCUS", ""), dt.datetime.now(dt.timezone.utc).date()))
    elif args.cmd == "account":
        write_outputs({"status": account(cfg, args.file, args.kind, args.step_failed)})
    elif args.cmd == "review-prompt":
        write_outputs({"prompt": review_prompt(cfg, args.pr, args.sha, args.round_)})
    elif args.cmd == "revise-prompt":
        review = json.loads(os.environ.get("REVIEW") or "{}")
        write_outputs({"prompt": revise_prompt(cfg, args.pr, review),
                       "needed": str(bool(review.get("problems")) or review.get("verdict") != "approve").lower()})
    elif args.cmd == "pr-info":
        pr = gh.api(f"repos/{cfg.repo}/pulls/{args.pr}")
        own = pr["user"]["login"] == cfg.bot.login and pr["head"]["repo"]["full_name"] == cfg.repo
        if args.require_own and not own:
            print(f"::error::PR #{args.pr} was not opened by the bot from this repository")
            return 1
        write_outputs({"sha": pr["head"]["sha"], "branch": pr["head"]["ref"], "own": str(own).lower()})
    else:
        write_outputs(finish(cfg, dict(os.environ)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
