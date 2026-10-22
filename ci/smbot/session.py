"""Bookkeeping around Claude's development sessions (docs/PLAN.md, "Self-driven progress").

  python3 -m smbot.session prepare            builds the implement prompt
  python3 -m smbot.session account --file F --kind dev|review
                                              records token usage, detects usage
                                              limits and a rejected token
  python3 -m smbot.session usage --file F     the same detection, without writing
                                              anything (on a runner where Claude had a shell)
  python3 -m smbot.session record --kind K    writes $STATUS and $TOKENS to the state
  python3 -m smbot.session package            bundles Claude's local commits as data
  python3 -m smbot.session publish --bundle B --mode new|update
                                              on a fresh runner: pushes the bundled
                                              commits and opens or updates the PR
  python3 -m smbot.session review-prompt --pr N --sha S --round critique|final
  python3 -m smbot.session revise-prompt --pr N
  python3 -m smbot.session answers            posts the answers to /ask in $RESULT
  python3 -m smbot.session finish             Daily log, task failures, next run

Outputs go to $GITHUB_OUTPUT. Prompt templates live in .github/maintainer/.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from . import alarms, checkpoint, dailylog, gh, intake, nexttask, pacing, state, weekly
from . import merge as merge_mod
from . import config as config_mod

MAINTAINER = Path(".github/maintainer")
FENCE = "`" * 3
MAX_FAILURES = 2
PARK_BLOCKED = dt.timedelta(days=7)  # blocked or failed too often: revisited by the weekly planning run
PARK_WAITING = dt.timedelta(days=1)  # approved, but the merge waits on GitHub or the owner

_LIMIT = re.compile(r"usage limit|limit reached|reached (?:your |the )?(?:\w+ )?limit|hit (?:your |the )?(?:\w+ )?limit|"
                    r"session limit|rate[ _-]?limit|\b429\b|quota|out of (?:extra )?usage|resets? (?:at |in )?\d",
                    re.IGNORECASE)
# e.g. "You've hit your session limit · resets 12am (UTC)" or "resets at 3:30pm (Europe/Copenhagen)"
_RESETS = re.compile(r"resets?\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:\(([^)]+)\))?", re.IGNORECASE)
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
    # The action fails the step when Claude finishes successfully but used more turns than
    # --max-turns allows; the work is still done, so it counts (see structured_result).
    if step_failed and result and not result.get("is_error") and result.get("subtype") == "success":
        return "ok", tokens, f"finished after {result.get('num_turns', '?')} turns (over the turn cap)"
    if result.get("is_error") or step_failed or not result:
        if _AUTH.search(text):
            return "auth", tokens, text[:300]
        if _LIMIT.search(text):
            return ("limit-weekly" if _WEEKLY.search(text) else "limit"), tokens, text[:300]
        return "error", tokens, text[:300] or "the Claude step failed"
    return "ok", tokens, ""


def reset_time(text: str, now: dt.datetime) -> dt.datetime | None:
    """When a usage limit resets, from the message: the next such time of day after now."""
    m = _RESETS.search(text)
    if not m:
        return None
    hour, minute, ampm, zone = int(m.group(1)), int(m.group(2) or 0), (m.group(3) or "").lower(), m.group(4)
    if ampm:
        hour = hour % 12 + (12 if ampm == "pm" else 0)
    if hour > 23 or minute > 59:
        return None
    try:
        tz = ZoneInfo(zone.strip()) if zone else dt.timezone.utc
    except (ZoneInfoNotFoundError, ValueError):
        tz = dt.timezone.utc
    local = now.astimezone(tz)
    reset = local.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if reset <= local:
        reset += dt.timedelta(days=1)
    return reset.astimezone(dt.timezone.utc)


def structured_result(messages: list[dict[str, Any]]) -> str:
    """Claude's structured output from the execution file, as compact JSON ("" if there is none).

    The action only sets its structured_output when the step succeeds, so a session that
    finished over the turn cap would otherwise lose its finished work.
    """
    results = [m for m in messages if m.get("type") == "result"]
    if not results or results[-1].get("is_error") or results[-1].get("subtype") != "success":
        return ""
    data = results[-1].get("structured_output")
    if not isinstance(data, dict):
        try:
            data = json.loads(str(results[-1].get("result", "")))
        except json.JSONDecodeError:
            return ""
    return json.dumps(data, separators=(",", ":")) if isinstance(data, dict) and "status" in data else ""


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


def queue(cfg: config_mod.Config, st: dict[str, Any], strict: bool = False) -> list[str]:
    """The scheduled issues, which go before docs/NEXT.md."""
    return intake.queue_tasks(cfg, st, strict)


def open_checkpoint(cfg: config_mod.Config) -> int | None:
    try:
        return checkpoint.open_issue(cfg)
    except gh.GhError:
        return None


def close_checkpoint(cfg: config_mod.Config, number: int, pr: str) -> list[str]:
    """A merged plan carried out the owner's answer to checkpoint #number: close it if it's still open.

    Usually the PR's `Closes #N` closed it already; a checkpoint closed by any other means is left alone.
    """
    try:
        if gh.api(f"repos/{cfg.repo}/issues/{number}").get("state") != "open":
            return []
        gh.api(f"repos/{cfg.repo}/issues/{number}/comments", "-X", "POST",
               input={"body": f"Carried out in #{pr}. Development continues."})
        gh.api(f"repos/{cfg.repo}/issues/{number}", "-X", "PATCH",
               input={"state": "closed", "state_reason": "completed"})
    except gh.GhError as e:
        return [f"Couldn't close checkpoint #{number} after #{pr}: {dailylog.shorten(str(e), 200)}"]
    return [f"Checkpoint #{number} carried out in #{pr}; development continues."]


def checkpoint_not_carried_out(cfg: config_mod.Config, number: int, summary: str) -> list[str]:
    """Planning ended with nothing to do on the owner's answer: hand the checkpoint back to the owner."""
    text = dailylog.shorten(summary, 600) or "No reason given."
    try:
        gh.api(f"repos/{cfg.repo}/issues/{number}/comments", "-X", "POST", input={"body": (
            f"@{cfg.owner.login}, planning couldn't turn your answer into changes. Claude's summary: {text}\n\n"
            "The checkpoint is waiting again: answer with `/go`, `/iterate <what>` or `/pivot <how>`, "
            "with more detail if needed.")})
    except gh.GhError:
        pass
    return [f"Checkpoint #{number}: planning couldn't carry out your answer, so it waits for you again. {text}"]


def checkpoint_allows_milestone_work(cfg: config_mod.Config, st: dict[str, Any]) -> bool:
    """False while a checkpoint issue waits for the owner: then only scheduled issues run."""
    number = open_checkpoint(cfg)
    return not number or checkpoint.answer(st, number) is not None


def nothing_queued(cfg: config_mod.Config, now: dt.datetime) -> bool:
    """No task a session could take now: no scheduled issue and nothing unparked in docs/NEXT.md.

    When GitHub can't be read it says False: an API error is not a reason to call development idle.
    """
    st, _ = state.load(cfg)
    try:
        scheduled = queue(cfg, st, strict=True)
    except gh.GhError:
        return False
    return nexttask.next_task(skip=nexttask.parked(st, now), first=scheduled) is None


def open_pr_for(cfg: config_mod.Config, task_slug: str) -> dict[str, Any] | None:
    """An open bot PR whose branch is for this task (any date), if there is one."""
    try:
        prs = gh.api(f"repos/{cfg.repo}/pulls?state=open&per_page=100")
    except gh.GhError:
        return None
    for pr in prs:
        ref = pr["head"]["ref"]
        if pr["user"]["login"] == cfg.bot.login and ref.startswith(BRANCH_PREFIX) and ref.endswith("-" + task_slug):
            return pr
    return None


def sync_with_main(branch: str) -> str:
    """Checks out a PR's branch and merges origin/main into it, before Claude starts.

    This runs outside Claude's sandbox, which keeps .github/, ci/ and tools/ read-only, so a
    merge that updates those files can't happen inside a session. Conflicts can only be in files
    the PR changed, which Claude may edit; they are left for Claude to resolve. Returns a note
    for the prompt.
    """
    if not valid_branch(branch):
        return ""
    git = ["git", "-c", "core.hooksPath=/dev/null"]
    fetched = subprocess.run([*git, "fetch", "--quiet", "origin", "main", branch], capture_output=True, text=True)
    if fetched.returncode != 0:
        return ""
    subprocess.run([*git, "switch", "--quiet", "--force", "-C", branch, f"origin/{branch}"], check=True)
    merged = subprocess.run([*git, "merge", "--no-edit", "origin/main"], capture_output=True, text=True)
    if merged.returncode == 0:
        return (f"The session has checked out `{branch}` for you and merged `origin/main` into it, so it's up "
                "to date. Stay on this branch and don't merge or rebase yourself.")
    conflicts = subprocess.run(["git", "diff", "--name-only", "--diff-filter=U"], capture_output=True,
                               text=True).stdout.split()
    if not conflicts:
        subprocess.run([*git, "merge", "--abort"], capture_output=True)
        return ""
    return (f"The session has checked out `{branch}` for you and started merging `origin/main` into it. The merge "
            f"has conflicts in {', '.join(f'`{c}`' for c in conflicts)}. Before anything else, resolve them (in "
            "plan files, keep both sides' entries), `git add` the files and `git commit` to finish the merge. "
            "Don't merge, rebase or abort yourself.")


def prepare(cfg: config_mod.Config, st: dict[str, Any], focus: str, today: dt.date,
            now: dt.datetime | None = None, sync: Callable[[str], str] | None = None) -> dict[str, str]:
    now = now or dt.datetime.now(dt.timezone.utc)
    task, kind = nexttask.next_task(skip=nexttask.parked(st, now), first=queue(cfg, st),
                                    milestone=checkpoint_allows_milestone_work(cfg, st)), "next"
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
    existing = open_pr_for(cfg, branch.split("-", 1)[1]) if task else None
    if existing:
        branch = existing["head"]["ref"]
        synced = sync(branch) if sync else ""
        how = synced or (f"`git fetch origin {branch} && git switch {branch}`, then bring it up to date with "
                         "`git fetch origin main && git merge origin/main` and resolve any conflicts (never rebase: "
                         "the PR's history must stay).")
        previous = (f"PR #{existing['number']} is already open for this task, on branch `{branch}`. Continue it. "
                    f"{how} Read its review comments with `gh pr view {existing['number']} --comments`, and "
                    "improve it rather than starting over. " + (previous or ""))
    template = (MAINTAINER / "develop.md").read_text()
    prompt = render(template, {
        "TASK": task or "(the queue is empty: only handle the owner instructions below)",
        "FOCUS": focus or "(none)",
        "INSTRUCTIONS": instructions_text(st.get("pending_instructions", [])),
        "PREVIOUS": previous or "(first attempt)",
        "BRANCH": branch,
        "REPO": cfg.repo,
    })
    return {"prompt": prompt, "branch": branch, "task": task or "", "kind": kind}


def prepare_plan(cfg: config_mod.Config, st: dict[str, Any], focus: str, today: dt.date,
                 weekly_run: bool = False) -> dict[str, str]:
    backlog = weekly.backlog_text(cfg, st)
    # Planning runs weekly, when the queue runs empty and after a checkpoint answer, so the branch
    # carries the time. A planning PR that didn't merge is continued instead of opening another.
    existing = open_pr_for(cfg, "planning")
    branch = existing["head"]["ref"] if existing else f"claude/{dt.datetime.now(dt.timezone.utc):%Y%m%d-%H%M}-planning"
    prompt = render((MAINTAINER / "plan.md").read_text(), {
        "BACKLOG": backlog.replace(FENCE, "` ` `"),  # keep it inside its code block
        "CHECKPOINT": checkpoint.prompt_text(st, open_checkpoint(cfg)),
        "RUN": ("This is the weekly run on Sunday: do every step." if weekly_run else
                "This run started because the work queue is empty. Do steps 1 to 5 only: leave `progress_post` "
                "empty and omit `playtest`; the Sunday run writes those."),
        "FOCUS": focus or "(none)",
        "INSTRUCTIONS": instructions_text(st.get("pending_instructions", [])),
        "BRANCH": branch,
        "REPO": cfg.repo,
    })
    if existing:
        prompt += (f"\n\nPR #{existing['number']} from an earlier planning session didn't merge. Continue it on "
                   f"`{branch}`: `git fetch origin {branch} && git switch {branch}`, merge `origin/main`, read its "
                   f"review with `gh pr view {existing['number']} --comments`, and fix what it says.")
    return {"prompt": prompt, "branch": branch, "task": "Planning", "kind": "plan"}


def review_prompt(cfg: config_mod.Config, pr: int, sha: str, round_: str) -> str:
    return render((MAINTAINER / "review.md").read_text(), {
        "PR": str(pr), "SHA": sha, "REPO": cfg.repo,
        "ROUND": ("This is the critique round: be demanding, the author will revise."
                  if round_ == "critique" else
                  "This is the final review: approve only if the PR can merge now as it is."),
    })


def revise_prompt(cfg: config_mod.Config, pr: int, review: dict[str, Any], branch: str = "", synced: str = "") -> str:
    problems = "\n".join(
        f"- [{p.get('severity')}] {p.get('file', '')}{':' + str(p['line']) if p.get('line') else ''}: "
        f"{p.get('problem')} Fix: {p.get('fix')}" for p in review.get("problems", [])) or "(no specific problems)"
    return render((MAINTAINER / "revise.md").read_text(), {
        "PR": str(pr), "REPO": cfg.repo, "SUMMARY": review.get("summary", ""), "PROBLEMS": problems,
        "BRANCH": branch or "the PR's head branch",
        "SYNC": synced or (f"Switch to it with `git fetch origin {branch} && git switch {branch}`. If GitHub reports "
                           "the PR as conflicting, or `main` has moved on, run `git fetch origin main && git merge "
                           "origin/main` and resolve the conflicts (never rebase: the PR's history must stay)."),
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


def resets_at(status: str, detail: str) -> str:
    """The reset time of a usage limit as an ISO time, or "" when it isn't a limit or isn't given."""
    reset = reset_time(detail, dt.datetime.now(dt.timezone.utc)) if status.startswith("limit") else None
    return pacing.iso(reset) if reset else ""


def account(cfg: config_mod.Config, path: Path, kind: str, step_failed: bool) -> str:
    status, tokens, detail = classify(read_messages(path), step_failed)
    print(f"{kind}: {status}, {tokens:,} tokens {detail}")
    return record(cfg, kind, status, tokens, resets_at(status, detail))


def record(cfg: config_mod.Config, kind: str, status: str, tokens: int, reset: str = "") -> str:
    """Records usage and limits in the state, and raises or clears the token alarm."""
    now = dt.datetime.now(dt.timezone.utc)

    def apply(s: dict[str, Any]) -> None:
        if tokens:
            pacing.record(s, now, tokens, kind)
        if status in ("limit", "limit-weekly"):
            pacing.limit_hit(s, now, weekly=status == "limit-weekly",
                             resets_at=pacing.parse_time(reset) if reset else None)
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
    return status


# --- Moving Claude's work off its runner ---------------------------------------

BRANCH_PREFIX = "claude/"


def package(out: Path, expected: str = "") -> dict[str, str]:
    """Bundles the commits Claude made on top of origin/main (runs where Claude had a shell).

    If Claude's commits ended up on a branch outside claude/ (say `pr19` from `gh pr checkout`,
    or a detached HEAD), they are bundled under the branch the session expected.
    """
    out.mkdir(parents=True, exist_ok=True)
    branch = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True).stdout.strip()
    ahead = subprocess.run(["git", "rev-list", "--count", "origin/main..HEAD"], capture_output=True,
                           text=True).stdout.strip() or "0"
    if int(ahead) > 0 and not branch.startswith(BRANCH_PREFIX) and valid_branch(expected):
        subprocess.run(["git", "branch", "--force", expected, "HEAD"], check=True)
        branch = expected
    if branch.startswith(BRANCH_PREFIX) and int(ahead) > 0:
        subprocess.run(["git", "bundle", "create", str(out / "work.bundle"), f"origin/main..{branch}"], check=True)
    return {"branch": branch, "commits": ahead}


def valid_branch(name: str) -> bool:
    return bool(re.fullmatch(r"claude/[a-z0-9][a-z0-9./-]{0,100}", name)) and ".." not in name


UNFINISHED = ("**Unfinished:** the session stopped before it was done ({reason}). Its commits are kept here, "
              "and the next session for this task continues from them. Not reviewed or merged until then.")


def task_title(task: str) -> str:
    m = re.match(r"\*\*(.+?)\*\*", task.strip())
    return (m.group(1) if m else task.strip()).rstrip(".")[:150] or "Claude's work"


def workflow_changes(tip: str, bases: list[str]) -> list[str]:
    """Files under .github/ whose version at `tip` matches none of `bases` (main, the branch as pushed).

    The point where `tip` left main counts too: a branch that started before main changed a workflow
    still has the old version, and merging it keeps main's, so it changes nothing.
    """
    fork = subprocess.run(["git", "merge-base", bases[0], tip], check=True, capture_output=True,
                          text=True).stdout.strip()
    bases = [*bases, fork]
    changed: set[str] | None = None
    for base in bases:
        names = set(subprocess.run(["git", "diff", "--name-only", "--no-renames", base, tip, "--", ".github/"],
                                   check=True, capture_output=True, text=True).stdout.split())
        changed = names if changed is None else changed & names
    return sorted(changed or ())


def publish(cfg: config_mod.Config, bundle: Path, branch: str, mode: str, result: dict[str, Any],
            pr_number: int | None, token: str, unfinished: str = "", task: str = "") -> dict[str, str]:
    """Pushes Claude's bundled commits from a clean checkout of main and opens or updates the PR.

    With `unfinished` (why the session stopped: a usage limit, an error, a timeout), the commits
    are kept on the branch in a draft PR (or the PR is updated) so the next session continues
    them; nothing is returned that would start a review.
    """
    if not valid_branch(branch):
        raise ValueError(f"refusing to push branch {branch!r}")
    remote = f"https://x-access-token:{token}@github.com/{cfg.repo}.git"
    git = ["git", "-c", "core.hooksPath=/dev/null"]
    subprocess.run([*git, "fetch", "--quiet", str(bundle), f"+refs/heads/{branch}:refs/remotes/work/{branch}"],
                   check=True)
    if mode == "update":
        pr = gh.api(f"repos/{cfg.repo}/pulls/{pr_number}")
        if pr["head"]["ref"] != branch or pr["user"]["login"] != cfg.bot.login or pr["state"] != "open":
            raise ValueError(f"PR #{pr_number} is not the bot's open PR for {branch}")
        # A revision must build on the PR's current head, so the force push below can't drop its commits.
        subprocess.run([*git, "fetch", "--quiet", remote, f"+refs/heads/{branch}:refs/remotes/current/{branch}"],
                       check=True)
        if subprocess.run(["git", "merge-base", "--is-ancestor", f"refs/remotes/current/{branch}",
                           f"refs/remotes/work/{branch}"]).returncode != 0:
            raise ValueError(f"the revision doesn't build on PR #{pr_number}'s current head; not overwriting it")
    # The push token may change workflows, so that a branch can take in main's workflow changes (GitHub
    # refuses such a merge otherwise); the bot's own commits must never change one.
    subprocess.run([*git, "fetch", "--quiet", remote, "+refs/heads/main:refs/remotes/current/main"], check=True)
    on_remote = subprocess.run([*git, "fetch", "--quiet", remote, f"+refs/heads/{branch}:refs/remotes/current/{branch}"],
                               capture_output=True).returncode == 0
    changed = workflow_changes(f"refs/remotes/work/{branch}",
                               ["refs/remotes/current/main"] + ([f"refs/remotes/current/{branch}"] if on_remote else []))
    if changed:
        raise ValueError(f"refusing to push {branch}: it changes {', '.join(changed)} (owner-only), "
                         "which is neither main's version nor the branch's")
    pushed = subprocess.run(["git", "rev-parse", f"refs/remotes/work/{branch}"], check=True, capture_output=True,
                            text=True).stdout.strip()
    subprocess.run([*git, "push", "--quiet", "--force", remote, f"refs/remotes/work/{branch}:refs/heads/{branch}"],
                   check=True)
    if unfinished:
        note = UNFINISHED.format(reason=unfinished)
        if mode == "new":
            existing = gh.api(f"repos/{cfg.repo}/pulls?state=open&head={cfg.repo.split('/')[0]}:{branch}")
            if existing:
                pr_number = existing[0]["number"]
            else:
                pr_number = gh.api(f"repos/{cfg.repo}/pulls", "-X", "POST", input={
                    "title": f"Unfinished: {task_title(task)}", "head": branch, "base": "main", "draft": True,
                    "body": f"{note}\n\nTask: {task[:3000]}"})["number"]
                return {"saved_pr": str(pr_number), "branch": branch}
        gh.api(f"repos/{cfg.repo}/issues/{pr_number}/comments", "-X", "POST",
               input={"body": f"{note}\n\nPushed {pushed[:7]}."})
        return {"saved_pr": str(pr_number), "branch": branch}
    if mode == "new":
        existing = gh.api(f"repos/{cfg.repo}/pulls?state=open&head={cfg.repo.split('/')[0]}:{branch}")
        if existing:
            pr_number = existing[0]["number"]
            gh.api(f"repos/{cfg.repo}/pulls/{pr_number}", "-X", "PATCH",
                   input={"title": result.get("pr_title") or existing[0]["title"],
                          "body": result.get("pr_body") or existing[0]["body"]})
            if existing[0].get("draft"):  # an unfinished PR the session has now finished
                gh.run("pr", "ready", str(pr_number), "--repo", cfg.repo)
        else:
            created = gh.api(f"repos/{cfg.repo}/pulls", "-X", "POST", input={
                "title": (result.get("pr_title") or result.get("summary", "Claude's work"))[:200],
                "head": branch, "base": "main",
                "body": result.get("pr_body") or result.get("summary", ""),
            })
            pr_number = created["number"]
    elif result.get("comment"):
        gh.api(f"repos/{cfg.repo}/issues/{pr_number}/comments", "-X", "POST",
               input={"body": f"**Revised after the critique.**\n\n{result['comment']}"})
    # The commit we pushed, not the API's view of the PR head, which can lag right after a push.
    return {"pr": str(pr_number), "sha": pushed, "branch": branch}


def pr_title(cfg: config_mod.Config, pr: str) -> str:
    """The PR's title for the log, "" if it can't be read."""
    if not pr:
        return ""
    try:
        return gh.api(f"repos/{cfg.repo}/pulls/{pr}")["title"]
    except (gh.GhError, KeyError, TypeError):
        return ""


def open_pr(cfg: config_mod.Config, branch: str) -> dict[str, str]:
    """The bot's open PR for a branch, for a session that continued it without new commits."""
    if not valid_branch(branch):
        return {}
    prs = gh.api(f"repos/{cfg.repo}/pulls?state=open&head={cfg.repo.split('/')[0]}:{branch}")
    own = [p for p in prs if p["user"]["login"] == cfg.bot.login and p["head"]["repo"]["full_name"] == cfg.repo]
    if not own:
        print(f"no open bot PR for {branch}")
        return {}
    return {"pr": str(own[0]["number"]), "sha": own[0]["head"]["sha"], "branch": branch}


def post_answers(cfg: config_mod.Config, answers: list[dict[str, Any]], allowed: set[int]) -> None:
    """Posts answers to /ask, only on issues the owner actually asked in."""
    for a in answers:
        if a.get("issue") in allowed and a.get("body"):
            gh.api(f"repos/{cfg.repo}/issues/{a['issue']}/comments", "-X", "POST",
                   input={"body": a["body"][:10000]})


def finish(cfg: config_mod.Config, env: dict[str, str]) -> dict[str, str]:
    """Records the outcome, posts to the Daily log and decides on another session."""
    task, pr, merged = env.get("TASK", ""), env.get("PR", ""), env.get("MERGED") == "true"
    status = env.get("IMPLEMENT_STATUS", "")
    review = json.loads(env.get("FINAL_REVIEW") or "{}")
    lines: list[str] = []
    now = dt.datetime.now(dt.timezone.utc)

    # The merge job sets MERGED to "true" or "false"; it's empty when the job didn't run.
    conflict = bool(pr) and env.get("MERGED") == "false" and merge_mod.CONFLICT in env.get("MERGE_RESULT", "")
    merge_refused = bool(pr) and mergeable(review) and env.get("MERGED") == "false" and not conflict
    merge_skipped = bool(pr) and mergeable(review) and not env.get("MERGED")
    # A queue task with nothing to do now (it waits on the owner, or another PR) must not stop
    # development: it's set aside like a refused merge and the next task goes first.
    idle_task = status == "nothing_to_do" and bool(task) and env.get("TASK_KIND") == "next" and not pr
    planning = env.get("TASK_KIND") == "plan"
    progressed = merged or bool(pr) or status == "blocked" or idle_task
    # Planning that found nothing to do while the queue is empty: development has run out of work.
    # (Not while a checkpoint waits: then an empty queue is expected.)
    plan_idle = (planning and status == "nothing_to_do" and not pr and not open_checkpoint(cfg)
                 and nothing_queued(cfg, now))
    # A usage limit backs off until its reset and a rejected token raises its own alarm; any other
    # session that ends without progress is an error, retried a few times before the owner is told.
    failed = (not progressed and not plan_idle and status not in ("nothing_to_do", "limit", "limit-weekly", "auth"))

    def park(entry: dict[str, Any], span: dt.timedelta, reason: str) -> None:
        entry["parked_until"] = pacing.iso(now + span)
        entry["parked_reason"] = reason[:500]

    # Answers to the open checkpoint: carried out by a merged plan, or handed back when planning did nothing.
    checkpoint_now = open_checkpoint(cfg) if planning else None
    carried: list[str] = []
    handed_back: list[str] = []
    was_idle: list[bool] = []

    def apply(s: dict[str, Any]) -> None:
        failures = s.setdefault("task_failures", {})
        if planning:
            s["last_plan"] = pacing.iso(now)
            if env.get("WEEKLY") == "true" and (progressed or status == "nothing_to_do"):
                s["last_weekly"] = pacing.iso(now)  # it ran; a limit or an error leaves it due
        if failed:
            s["errors_in_a_row"] = s.get("errors_in_a_row", 0) + 1
        elif progressed:
            s["errors_in_a_row"] = 0
        was_idle[:] = [bool(s.get("idle"))]
        if plan_idle:
            s["idle"] = s.get("idle") or pacing.iso(now)
        elif progressed:
            s.pop("idle", None)
        answers = s.setdefault("checkpoint_answers", {})
        if planning and merged:
            # The open checkpoint's answer, and answers to checkpoints that are closed by now.
            carried[:] = [n for n in answers if checkpoint_now is None or n == str(checkpoint_now)]
        elif planning and status == "nothing_to_do" and not pr and str(checkpoint_now) in answers:
            handed_back[:] = [str(checkpoint_now)]
        for n in carried + handed_back:
            answers.pop(n, None)
        # Instructions are carried out by development sessions (planning can't answer /ask).
        if not planning and status == "nothing_to_do" and not pr:
            s["pending_instructions"] = []  # handled: answered, or nothing to do for them
        if merged:
            failures.pop(task, None)
            if not planning:
                s["pending_instructions"] = []
            s["last_own_merge"] = pacing.iso(now)
        elif pr and review and not mergeable(review):
            entry = failures.setdefault(task, {"count": 0})
            entry["count"] += 1
            entry["pr"] = pr
            entry["problems"] = "\n".join(f"- {p.get('problem')} Fix: {p.get('fix')}"
                                          for p in review.get("problems", []))[:4000]
            if entry["count"] >= MAX_FAILURES and task:
                park(entry, PARK_BLOCKED, f"failed review {entry['count']} times")
        elif conflict and task:
            # Like a failed review: the next session continues the PR and merges main into it.
            entry = failures.setdefault(task, {"count": 0})
            entry["count"] += 1
            entry["pr"] = pr
            entry["problems"] = (f"- Approved, but PR #{pr} conflicts with main, so it couldn't merge. Fix: "
                                 "`git fetch origin main && git merge origin/main`, resolve the conflicts, "
                                 "and keep both sides' entries in the plan files.")
            if entry["count"] >= MAX_FAILURES:
                park(entry, PARK_BLOCKED, f"conflicted with main {entry['count']} times")
        elif merge_refused and task:
            entry = failures.setdefault(task, {"count": 0})
            entry["pr"] = pr
            park(entry, PARK_WAITING, env.get("MERGE_RESULT") or "the merge was refused")
        elif idle_task:
            park(failures.setdefault(task, {"count": 0}), PARK_WAITING,
                 env.get("IMPLEMENT_SUMMARY", "nothing to do on it now"))
        elif status == "blocked":
            if task:
                park(failures.setdefault(task, {"count": 0}), PARK_BLOCKED, env.get("IMPLEMENT_SUMMARY", "blocked"))
            s["pending_instructions"] = []
    state.update(cfg, apply, f"session: finished ({'merged' if merged else 'not merged'})")

    what = (pr_title(cfg, pr) or task_title(task)) if (pr or task) else "owner instructions"
    said = dailylog.shorten(env.get("IMPLEMENT_SUMMARY", ""), 300)
    if merged:
        lines.append(f"Merged #{pr}: {what}")
    elif env.get("TASK_KIND") == "plan" and status == "nothing_to_do":
        lines.append("Planning: no plan changes needed")
    elif status == "blocked":
        lines.append(f"Blocked, set aside for a week: {what}. {said}")
    elif idle_task:
        lines.append(f"Nothing to do on it now, set aside for a day: {what}. {said}")
    elif merge_refused:
        lines.append(f"Approved but not merged, set aside for a day: #{pr} {what}. "
                     f"{dailylog.shorten(env.get('MERGE_RESULT', ''), 300)}")
    elif pr:
        reason = env.get("MERGE_RESULT") or review.get("summary", "the final review did not approve it")
        lines.append(f"Not merged yet: #{pr} {what}. {dailylog.shorten(reason, 300)}")
    elif status and status != "ok":
        lines.append(f"Session stopped ({status}): {what}. {said}")
    st, _ = state.load(cfg)
    if env.get("RUN_URL"):
        lines.append(f"[Workflow run]({env['RUN_URL']})")
    dailylog.post(cfg, "Development session", lines)

    # Development flows: after progress, after an empty queue (the next run plans) and after an
    # error (retried) the next session starts at once. It stops for the owner's pauses, a usage
    # limit (resume.yml restarts it at the reset), a rejected token, repeated errors, an open
    # checkpoint, and when planning finds nothing left to do. Each stop that needs the owner
    # mentions them, once.
    started = env.get("CHAIN_STARTED") or pacing.iso(now)
    errors = st.get("errors_in_a_row", 0)
    backing_off = pacing.backing_off_until(st, now)
    empty_queue = env.get("TASK_KIND") == "next" and not task and status == "nothing_to_do"
    # Planning with nothing to change while work remains (a weekly run mid-milestone, say): carry on.
    planned_nothing = planning and status == "nothing_to_do" and not plan_idle
    again = (not backing_off and not merge_skipped and not plan_idle and status != "auth"
             and (progressed or empty_queue or planned_nothing or (failed and errors < state.MAX_ERRORS_IN_A_ROW)))
    for number in carried:
        if lines_cp := close_checkpoint(cfg, int(number), pr):
            dailylog.post(cfg, "Checkpoint", lines_cp)
    for number in handed_back:
        dailylog.post(cfg, "Checkpoint", checkpoint_not_carried_out(cfg, int(number), env.get("IMPLEMENT_SUMMARY", "")),
                      mention_owner=True)
    stop: list[str] = []
    if failed and errors >= state.MAX_ERRORS_IN_A_ROW:
        stop.append(alarms.raise_alarm(cfg, st, "stopped", errors=errors, run=env.get("RUN_URL", "the Actions tab"))
                    or "")  # None while the alarm is already open: no new post
    elif progressed and "stopped" in st.get("alarms", {}):
        stop.append(alarms.clear_alarm(cfg, st, "stopped") or "")
    if plan_idle and not (was_idle and was_idle[0]):
        stop.append("Development is idle: planning found no more tasks. It plans again on Sunday, and works "
                    "again as soon as there is a scheduled issue or an instruction from you (`/claude`).")
    stop = [line for line in stop if line]
    if stop:
        number = st["alarms"].get("stopped")

        def keep_alarm(s: dict[str, Any]) -> None:
            if number:
                s["alarms"]["stopped"] = number
            else:
                s["alarms"].pop("stopped", None)
        state.update(cfg, keep_alarm, "session: stop alarm")
        dailylog.post(cfg, "Development stopped" if not progressed else "Development running again", stop,
                      mention_owner=not progressed)
    resume_at = backing_off if not plan_idle else ""
    return {"again": str(again).lower(), "chain_started": started, "resume_at": resume_at}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("prepare").add_argument("--mode", choices=("develop", "plan"), default="develop")
    acc = sub.add_parser("account")
    acc.add_argument("--file", type=Path, required=True)
    acc.add_argument("--kind", choices=("dev", "review", "intake", "plan"), required=True)
    acc.add_argument("--step-failed", action="store_true")
    us = sub.add_parser("usage")
    us.add_argument("--file", type=Path, required=True)
    us.add_argument("--step-failed", action="store_true")
    sub.add_parser("record").add_argument("--kind", choices=("dev", "review", "intake", "plan"), required=True)
    pk = sub.add_parser("package")
    pk.add_argument("--out", type=Path, default=Path("work"))
    pk.add_argument("--branch", default="", help="the branch the session expected Claude to commit on")
    pb = sub.add_parser("publish")
    pb.add_argument("--bundle", type=Path, required=True)
    pb.add_argument("--branch", required=True)
    pb.add_argument("--mode", choices=("new", "update"), required=True)
    pb.add_argument("--pr", type=int)
    pb.add_argument("--unfinished", default="", help="why the session stopped; keeps the commits without review")
    rp = sub.add_parser("review-prompt")
    rp.add_argument("--pr", type=int, required=True)
    rp.add_argument("--sha", required=True)
    rp.add_argument("--round", dest="round_", choices=("critique", "final"), required=True)
    vp = sub.add_parser("revise-prompt")
    vp.add_argument("--pr", type=int, required=True)
    vp.add_argument("--branch", default="")
    sub.add_parser("open-pr").add_argument("--branch", required=True)
    sub.add_parser("answers")
    sub.add_parser("finish")
    args = ap.parse_args(argv)

    cfg = config_mod.load()
    if args.cmd == "prepare":
        st, _ = state.load(cfg)
        today = dt.datetime.now(dt.timezone.utc).date()
        out = (prepare_plan(cfg, st, os.environ.get("FOCUS", ""), today, os.environ.get("WEEKLY") == "true")
               if args.mode == "plan" else
               prepare(cfg, st, os.environ.get("FOCUS", ""), today, sync=sync_with_main))
        schema = MAINTAINER / "schemas" / ("plan.json" if args.mode == "plan" else "session.json")
        out["schema"] = json.dumps(json.loads(schema.read_text()), separators=(",", ":"))
        write_outputs(out)
    elif args.cmd == "account":
        write_outputs({"status": account(cfg, args.file, args.kind, args.step_failed)})
    elif args.cmd == "usage":
        messages = read_messages(args.file)
        status, tokens, detail = classify(messages, args.step_failed)
        print(f"{status}, {tokens:,} tokens {detail}")
        write_outputs({"status": status, "tokens": str(tokens), "resets_at": resets_at(status, detail),
                       "result": structured_result(messages) if status == "ok" else ""})
    elif args.cmd == "record":
        status = os.environ.get("STATUS") or "error"
        write_outputs({"status": record(cfg, args.kind, status, int(os.environ.get("TOKENS") or 0),
                                        os.environ.get("RESETS_AT", ""))})
    elif args.cmd == "package":
        write_outputs(package(args.out, args.branch))
    elif args.cmd == "publish":
        result = json.loads(os.environ.get("RESULT") or "{}")
        write_outputs(publish(cfg, args.bundle, args.branch, args.mode, result, args.pr, os.environ["GH_TOKEN"],
                              args.unfinished, os.environ.get("TASK", "")))
    elif args.cmd == "answers":
        st, _ = state.load(cfg)
        post_answers(cfg, json.loads(os.environ.get("RESULT") or "{}").get("answers", []),
                     {p["number"] for p in st.get("pending_instructions", []) if p["kind"] == "ask"})
    elif args.cmd == "review-prompt":
        write_outputs({"prompt": review_prompt(cfg, args.pr, args.sha, args.round_)})
    elif args.cmd == "revise-prompt":
        review = json.loads(os.environ.get("REVIEW") or "{}")
        write_outputs({"prompt": revise_prompt(cfg, args.pr, review, args.branch, sync_with_main(args.branch)),
                       "needed": str(bool(review.get("problems")) or review.get("verdict") != "approve").lower()})
    elif args.cmd == "open-pr":
        write_outputs(open_pr(cfg, args.branch))
    else:
        write_outputs(finish(cfg, dict(os.environ)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
