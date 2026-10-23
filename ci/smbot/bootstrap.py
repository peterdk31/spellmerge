"""Starts a new game from this harness: a new repository, its own bot app, and the first session.

  ./new-game.sh            the wizard: a few questions, then every step with what to click

It asks for the idea, the name, the repository and the folder, shows the plan, then:
1. makes the folder: the harness from this checkout (ci/bootstrap/harness.json), a fresh
   ci/config.json, a Godot project that shows the name and the build version
   (ci/bootstrap/skeleton/), and docs whose queue starts by drafting docs/DESIGN.md from the idea;
2. creates the public repository, the automation-state branch and the protected environment;
3. opens and pins the Control panel;
4. creates the game's own bot app with GitHub's app-manifest flow (you click Create; its key goes
   straight into the environment's secrets and never touches the disk);
5. has you install it on the new repository only;
6. commits the bot and the panel into ci/config.json;
7. runs ./setup.sh (needs jq);
8. stores your Claude token (`claude setup-token`);
9. has you add the Discussions categories (no API) and starts the first development session.

Progress is kept in the new folder's .git/new-game.json: if a step fails or you stop, running
./new-game.sh again offers to carry on from there. For scripts and tests:

  PYTHONPATH=ci python3 -m smbot.bootstrap scaffold --name N --repo O/N --idea-file F --dest DIR
  PYTHONPATH=ci python3 -m smbot.bootstrap launch --dest DIR

Godot only for now: the skeleton is a Godot 4 project, and build.sh is Godot's.
"""

from __future__ import annotations

import argparse
import datetime as dt
import fnmatch
import getpass
import html
import http.server
import json
import re
import secrets
import shutil
import subprocess
import sys
import threading
import urllib.parse
import webbrowser
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from . import config as config_mod
from . import gh, rules

SOURCE = config_mod.CI_DIR.parent  # this checkout
BOOTSTRAP = config_mod.CI_DIR / "bootstrap"
GAME_SECTIONS = ("Overview", "Game design", "Codebase architecture and areas", "Performance", "Roadmap")
APP_PERMISSIONS = {"contents": "write", "issues": "write", "pull_requests": "write"}  # docs/SETUP-APP.md
DISCUSSION_CATEGORIES = ("Announcements", "Ideas", "Art submissions")


@dataclass(frozen=True)
class Game:
    name: str
    repo: str
    idea: str
    pitch: str
    description: str
    owner_login: str
    owner_id: int
    timezone: str

    @property
    def slug(self) -> str:
        return self.repo.split("/")[1].lower()


# --- Scaffold (local only) ------------------------------------------------------


def tracked_files(root: Path) -> list[str]:
    out = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], check=True, capture_output=True).stdout
    return [p for p in out.decode().split("\0") if p]


def selected(path: str, copy: list[str], skip: list[str]) -> bool:
    def hit(pattern: str) -> bool:
        return path.startswith(pattern) if pattern.endswith("/") else fnmatch.fnmatchcase(path, pattern)
    return any(hit(p) for p in copy) and not any(hit(p) for p in skip)


def renames(old: config_mod.Config, game: Game) -> list[tuple[str, str]]:
    """Old project's names to the new game's, longest first, for the harness's docs and templates."""
    pairs = [(old.pages, f"https://{game.owner_login.lower()}.github.io/{game.repo.split('/')[1]}"),
             (old.repo, game.repo), (old.game.name, game.name), (f"@{old.owner.login}", f"@{game.owner_login}"),
             (old.owner.login, game.owner_login), (old.game.slug, game.slug)]
    return sorted({a: b for a, b in pairs if a}.items(), key=lambda p: -len(p[0]))


def rename(text: str, pairs: list[tuple[str, str]]) -> str:
    for old, new in pairs:
        text = text.replace(old, new)
    return text


def fill(text: str, values: dict[str, str]) -> str:
    return config_mod.render(text, values)


def plan_md(source: str, keep: list[str], drop: dict[str, str], game: Game, pairs: list[tuple[str, str]],
            today: dt.date) -> str:
    """docs/PLAN.md: the harness's sections, renamed; the game's sections left for the planning task."""
    parts = re.split(r"(?m)^(?=## )", source)
    sections = {p.split("\n", 1)[0][3:].strip(): p for p in parts[1:]}
    missing = [name for name in keep if name not in sections]
    if missing:
        raise SystemExit(f"docs/PLAN.md has no section {', '.join(missing)} (ci/bootstrap/harness.json)")
    out = [f"# {game.name} — Project Plan\n\n{today:%b} {today.day}, {today.year} · {game.owner_login}\n\n"]
    for name in GAME_SECTIONS:
        out.append(f"## {name}\n\nNot written yet: the second task in `docs/NEXT.md` writes it from `docs/DESIGN.md`.\n\n")
    for name in keep:
        text = sections[name]
        for title, note in drop.items():  # facts about the old game, e.g. its name check
            text = re.sub(rf"(?ms)^### {re.escape(title)}\n.*?(?=^#{{2,3}} |\Z)",
                          f"### {title}\n\n{fill(note, {'GAME': game.name})}\n\n", text)
        out.append(rename(text, pairs).rstrip() + "\n\n")
    return "".join(out).rstrip() + "\n"


def new_config(game: Game, state_branch: str) -> dict[str, Any]:
    return {
        "repo": game.repo,
        "game": {"name": game.name, "slug": game.slug, "pitch": game.pitch,
                 "tagline": game.description, "description": game.description, "itch": ""},
        "owner": {"login": game.owner_login, "id": game.owner_id},
        "bot": {"login": "", "id": 0, "client_id": ""},  # launch fills these in from the new app
        "dependency_bots": ["dependabot[bot]"],
        "issues": {"control_panel": 0},  # launch opens the panel
        "timezone": game.timezone,
        "state_branch": state_branch,
    }


def write_json(path: Path, data: Any) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def scaffold(game: Game, dest: Path, source: Path = SOURCE, today: dt.date | None = None) -> None:
    today = today or dt.date.today()
    if dest.exists() and any(dest.iterdir()):
        raise SystemExit(f"{dest} exists and isn't empty")
    old = config_mod.load(source / "ci" / "config.json")
    harness = json.loads((source / "ci" / "bootstrap" / "harness.json").read_text())
    pairs = renames(old, game)
    for path in tracked_files(source):
        if not selected(path, harness["copy"], harness["skip"]):
            continue
        target = dest / path
        target.parent.mkdir(parents=True, exist_ok=True)
        name = Path(path).name
        if Path(path).suffix in harness["rename_in"] or name in harness["rename_in"]:
            target.write_text(rename((source / path).read_text(), pairs))
        else:
            shutil.copy2(source / path, target)
    pages = f"https://{game.owner_login.lower()}.github.io/{game.repo.split('/')[1]}"
    values = {"GAME": game.name, "REPO": game.repo, "IDEA": game.idea.strip(), "DATE": today.isoformat(),
              "MARKER": rules.DESIGN_DRAFT_MARKER, "DESCRIPTION": game.description, "PAGES": pages}
    skeleton = source / "ci" / "bootstrap" / "skeleton"
    for path in sorted(p for p in skeleton.rglob("*") if p.is_file()):
        target = dest / path.relative_to(skeleton)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(fill(path.read_text(), values))
    (dest / "docs" / "PLAN.md").write_text(
        plan_md((source / "docs" / "PLAN.md").read_text(), harness["plan_sections"], harness["plan_replace"],
                game, pairs, today))
    write_json(dest / "ci" / "config.json", new_config(game, old.state_branch))
    git = ["git", "-C", str(dest)]
    subprocess.run([*git, "init", "-q", "-b", "main"], check=True)
    subprocess.run([*git, "add", "-A"], check=True)
    subprocess.run([*git, "commit", "-q", "-m", f"Start {game.name} from an idea\n\nThe harness from {old.repo} "
                    "(ci/bootstrap), a Godot project that shows the name and the build version, and "
                    "docs/DESIGN.md with the idea. The first task drafts the design."], check=True)


# --- Launch (GitHub) ----------------------------------------------------------------


BOLD, DIM, GREEN, YELLOW, RED, OFF = "\033[1m", "\033[2m", "\033[32m", "\033[33m", "\033[31m", "\033[0m"


def say(text: str) -> None:
    print(f"\n{BOLD}{text}{OFF}")


def panel_body(cfg: config_mod.Config) -> str:
    return f"""**{cfg.game.name.upper()} CONTROL PANEL**

- [x] Automation enabled (untick = full stop, the kill switch)
- [ ] Pause development (still review PRs and release, build nothing new)
- [ ] Pause PR merging

DEV_INTENSITY: 90%
WEEKLY_SHARE: 90%
QUIET_HOURS:
FOCUS:

---

**How to use:** tick or untick a box, or edit a value, and save. Every run reads this issue first, so changes apply from the next run (at most an hour later).

- `DEV_INTENSITY`: share of each ~5-hour Claude usage window the bot may use (0–100%).
- `WEEKLY_SHARE`: share of the weekly Claude usage cap the bot may use (0–100%).
- `QUIET_HOURS`: hours with no development sessions, in {cfg.timezone} time, e.g. `07-17`. Empty means none.
- `FOCUS`: an optional instruction for Claude, e.g. `fix bugs before new features this week`.

Only edits by {cfg.owner.login} count; the bot never edits this issue, and edits by anyone else make the bot pause and notify you. Every applied change is noted in the Daily log.
"""


def manifest(cfg: config_mod.Config, redirect: str) -> dict[str, Any]:
    url = f"https://github.com/{cfg.repo}"
    return {"name": f"{cfg.game.name} Bot"[:34], "url": url, "description": f"Claude's maintainer bot for {cfg.repo}.",
            "hook_attributes": {"url": url, "active": False}, "redirect_url": redirect, "public": False,
            "default_permissions": APP_PERMISSIONS, "default_events": []}


def manifest_page(cfg: config_mod.Config, redirect: str, state: str) -> str:
    owner = cfg.repo.split("/")[0]
    action = ("https://github.com/settings/apps/new" if owner == cfg.owner.login
              else f"https://github.com/organizations/{owner}/settings/apps/new") + f"?state={state}"
    value = html.escape(json.dumps(manifest(cfg, redirect)))
    return (f'<!doctype html><meta charset="utf-8"><title>Create the bot app</title>'
            f'<form id="f" method="post" action="{html.escape(action)}"><input type="hidden" name="manifest" '
            f'value="{value}"><p>Sending you to GitHub to create the bot app for {html.escape(cfg.repo)}...</p>'
            '<button>Continue</button></form><script>document.getElementById("f").submit()</script>')


def create_app(cfg: config_mod.Config) -> dict[str, Any]:
    """GitHub's app-manifest flow; returns the conversion (id, slug, client_id, pem, html_url)."""
    state, result = secrets.token_urlsafe(16), {}
    done = threading.Event()

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args: Any) -> None:
            pass

        def do_GET(self) -> None:
            url = urllib.parse.urlparse(self.path)
            query = urllib.parse.parse_qs(url.query)
            if url.path == "/":
                body = manifest_page(cfg, f"http://127.0.0.1:{self.server.server_port}/done", state)
            elif url.path == "/done" and query.get("state") == [state] and query.get("code"):
                result.update(gh.api(f"app-manifests/{query['code'][0]}/conversions", "-X", "POST"))
                body = ("<!doctype html><meta charset='utf-8'><p>The app is created. Back in the terminal, "
                        "install it on the new repository.</p>")
                done.set()
            else:
                self.send_response(404)
                self.end_headers()
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(body.encode())

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    start = f"http://127.0.0.1:{server.server_port}/"
    print(f"  Opening {start} : it sends you to GitHub with the app's settings (Contents, Issues and Pull "
          "requests only). Check them, change the name if it's taken, and click Create.")
    webbrowser.open(start)
    done.wait()
    server.shutdown()
    return result


def run_gh(*args: str, input: str | None = None) -> str:
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True, input=input).stdout


class StepFailed(Exception):
    """A step that couldn't finish; the message says what to do before running the wizard again."""

    def __init__(self, message: str, started: bool = True) -> None:
        super().__init__(message)
        self.started = started  # False: nothing was made yet, so there is nothing to carry on


# --- Launch: resumable steps ---------------------------------------------------------
#
# Progress is kept in the new folder's .git/new-game.json (never committed), so running the wizard
# again skips what is done. The bot app's private key is stored as a secret the moment GitHub hands it
# over, because GitHub never shows it again.

PROGRESS = Path(".git") / "new-game.json"


def progress(dest: Path) -> dict[str, Any]:
    try:
        return json.loads((dest / PROGRESS).read_text())
    except (OSError, ValueError):
        return {"done": []}


def save_progress(dest: Path, data: dict[str, Any]) -> None:
    write_json(dest / PROGRESS, data)


def step_repo(dest: Path, cfg: config_mod.Config, data: dict[str, Any]) -> None:
    git = ["git", "-C", str(dest)]
    if subprocess.run(["gh", "repo", "view", cfg.repo], capture_output=True).returncode != 0:
        run_gh("repo", "create", cfg.repo, "--public", "--description", cfg.game.description,
               "--source", str(dest), "--remote", "origin", "--push")
    subprocess.run([*git, "push", "-q", "origin", f"HEAD:refs/heads/{cfg.state_branch}"], check=True,
                   capture_output=True)
    # setup.sh converges it later; the bot app's key needs somewhere to go before that.
    run_gh("api", "-X", "PUT", f"repos/{cfg.repo}/environments/automation")
    print(f"  https://github.com/{cfg.repo}")


def step_panel(dest: Path, cfg: config_mod.Config, data: dict[str, Any]) -> None:
    url = run_gh("issue", "create", "--repo", cfg.repo, "--title", "Control panel", "--body", panel_body(cfg))
    data["control_panel"] = int(url.strip().rsplit("/", 1)[1])
    run_gh("issue", "pin", str(data["control_panel"]), "--repo", cfg.repo)
    print(f"  {url.strip()} (pinned; tick and untick its boxes to steer the bot)")


def step_app(dest: Path, cfg: config_mod.Config, data: dict[str, Any]) -> None:
    print("  Your browser opens GitHub's \"Create GitHub App\" page, already filled in: three permissions "
          "(Contents, Issues, Pull requests) and no webhook.")
    print("  If the name is taken, change it there. Then click the green Create button.")
    input(f"  {DIM}Press Enter to open the browser...{OFF}")
    app = create_app(cfg)
    env = ["--env", "automation", "--repo", cfg.repo]
    try:
        run_gh("secret", "set", "BOT_APP_ID", *env, "--body", str(app["id"]))
        run_gh("secret", "set", "BOT_APP_PRIVATE_KEY", *env, input=app["pem"])
    except subprocess.CalledProcessError as e:  # GitHub never shows the key again: start this app over
        raise StepFailed(f"The app was created, but its key couldn't be stored ({(e.stderr or '').strip()}). "
                         f"Delete the app ({app['html_url']}, Advanced, Delete GitHub App), then run the wizard "
                         "again to create a fresh one.") from e
    login = f"{app['slug']}[bot]"
    data["bot"] = {"login": login, "id": int(run_gh("api", f"users/{login}", "--jq", ".id")),
                   "client_id": app["client_id"]}
    data["app_url"] = app["html_url"]
    print(f"  Created {login}; its key went straight into the repository's protected secrets.")


def step_install(dest: Path, cfg: config_mod.Config, data: dict[str, Any]) -> None:
    url = f"{data['app_url']}/installations/new"
    print(f"  Now give the app access to {cfg.repo}, and nothing else. On the page that opens:")
    print("    1. choose \"Only select repositories\"")
    print(f"    2. pick {cfg.repo.split('/')[1]}")
    print("    3. click Install")
    webbrowser.open(url)
    input(f"  {DIM}({url}){OFF}\n  Press Enter when it's installed... ")


def step_config(dest: Path, cfg: config_mod.Config, data: dict[str, Any]) -> None:
    git = ["git", "-C", str(dest)]
    path = dest / "ci" / "config.json"
    conf = json.loads(path.read_text())
    conf["bot"], conf["issues"]["control_panel"] = data["bot"], data["control_panel"]
    write_json(path, conf)
    subprocess.run([*git, "add", "ci/config.json"], check=True)
    if subprocess.run([*git, "diff", "--cached", "--quiet"]).returncode != 0:
        subprocess.run([*git, "commit", "-q", "-m", "Record the bot app and the Control panel"], check=True)
    subprocess.run([*git, "push", "-q", "origin", "main"], check=True, capture_output=True)
    print("  ci/config.json now names the bot and the Control panel")


def step_settings(dest: Path, cfg: config_mod.Config, data: dict[str, Any]) -> None:
    print(f"  {DIM}(./setup.sh: branch rules, the read-only workflow token, Pages, labels, variables){OFF}")
    out = subprocess.run(["./setup.sh"], cwd=dest, capture_output=True, text=True)
    failed = re.findall(r"✗ (.*)", out.stdout)
    if out.returncode != 0 and (failed or not out.stdout):
        tail = "\n    ".join(failed or (out.stderr or out.stdout).strip().splitlines()[-5:])
        raise StepFailed(f"setup.sh reported problems:\n    {tail}\n  The full output: run ./setup.sh in {dest}.")
    print("  done")


def step_claude(dest: Path, cfg: config_mod.Config, data: dict[str, Any]) -> None:
    print("  The bot uses your Claude subscription. In another terminal, run:")
    print(f"    {BOLD}claude setup-token{OFF}")
    print("  and paste the token it prints here (it isn't shown while you paste).")
    while True:
        token = getpass.getpass("  Token: ").strip()
        if token:
            break
        print(f"  {YELLOW}Nothing pasted; try again (Ctrl+C stops, and the wizard continues here next time).{OFF}")
    run_gh("secret", "set", "CLAUDE_CODE_OAUTH_TOKEN", "--env", "automation", "--repo", cfg.repo, input=token)
    print("  stored as a protected secret")


def step_start(dest: Path, cfg: config_mod.Config, data: dict[str, Any]) -> None:
    print("  One thing GitHub has no API for: Discussions categories. On the page that opens, add "
          f"{', '.join(DISCUSSION_CATEGORIES)}, and delete GitHub's defaults.")
    url = f"https://github.com/{cfg.repo}/discussions/categories"
    webbrowser.open(url)
    input(f"  {DIM}({url}){OFF}\n  Press Enter when that's done (or to do it later)... ")
    run_gh("workflow", "run", "develop.yml", "--repo", cfg.repo, "--ref", "main")
    print("  The first development session has started.")


STEPS = (
    ("repo", "Create the GitHub repository", step_repo),
    ("panel", "Open the Control panel", step_panel),
    ("app", "Create the game's bot app", step_app),
    ("install", "Install the bot app on the repository", step_install),
    ("config", "Save the bot and the panel in the repository", step_config),
    ("settings", "Apply the repository's security settings", step_settings),
    ("claude", "Connect Claude", step_claude),
    ("start", "Start the first session", step_start),
)


def launch(dest: Path, first_step: int = 1, total: int = len(STEPS)) -> None:
    data = progress(dest)
    for n, (key, title, run) in enumerate(STEPS, first_step):
        if key in data["done"]:
            print(f"{GREEN}✓{OFF} [{n}/{total}] {title}")
            continue
        say(f"[{n}/{total}] {title}")
        cfg = config_mod.load(dest / "ci" / "config.json")
        try:
            run(dest, cfg, data)
        except (subprocess.CalledProcessError, gh.GhError, StepFailed) as e:
            save_progress(dest, data)
            detail = e.stderr.strip() if isinstance(e, subprocess.CalledProcessError) and e.stderr else str(e)
            raise StepFailed(f"{title} didn't work:\n  {detail}") from e
        data["done"].append(key)
        save_progress(dest, data)
    cfg = config_mod.load(dest / "ci" / "config.json")
    say(f"{GREEN}{cfg.game.name} is running.{OFF}")
    print(f"""
  What happens now:
  - In about half an hour the bot opens a pull request that drafts docs/DESIGN.md from your idea.
    GitHub asks for your review: approve and merge it, or ask for changes in a review and comment /retry.
  - Then it plans the game and starts building. A new build is published every day:
    https://github.com/{cfg.repo}/releases
  - Steer it from the Control panel: https://github.com/{cfg.repo}/issues/{cfg.control_panel_issue}

  Later, when you want to: an itch.io page (docs/SETUP-APP.md, step 6), and docs/SECURITY-CHECKLIST.md.
""")


# --- The wizard ------------------------------------------------------------------------


def ask(question: str, default: str = "", check: Any = None) -> str:
    hint = f" {DIM}[{default}]{OFF}" if default else ""
    while True:
        answer = input(f"{question}{hint}: ").strip() or default
        problem = check(answer) if check else ("" if answer else "please answer")
        if not problem:
            return answer
        print(f"  {YELLOW}{problem}{OFF}")


def ask_idea() -> str:
    print("Describe the game: what you do, what makes it fun, who it's for. A few lines is enough;")
    print(f"the bot turns it into a design you approve. {DIM}Finish with an empty line.{OFF}")
    lines: list[str] = []
    while True:
        line = input("> " if not lines else "  ")
        if not line.strip() and lines:
            return "\n".join(lines).strip() + "\n"
        if line.strip():
            lines.append(line)


def slugify(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "game"


def preflight() -> dict[str, Any]:
    """The tools and the GitHub login the wizard needs; StepFailed says how to get each."""
    missing = [(cmd, fix) for cmd, fix in (
        ("git", "https://git-scm.com/downloads"), ("gh", "https://cli.github.com"),
        ("jq", "sudo apt install jq   (macOS: brew install jq)"),
        ("claude", "https://claude.com/claude-code")) if not shutil.which(cmd)]
    if missing:
        raise StepFailed("Install these first, then run the wizard again:\n"
                         + "\n".join(f"    {cmd}: {fix}" for cmd, fix in missing), started=False)
    if subprocess.run(["gh", "auth", "status"], capture_output=True).returncode != 0:
        raise StepFailed("Log in to GitHub first:  gh auth login", started=False)
    for key in ("user.name", "user.email"):
        if subprocess.run(["git", "config", key], capture_output=True).returncode != 0:
            raise StepFailed(f"Tell git who you are first:  git config --global {key} \"...\"", started=False)
    return json.loads(run_gh("api", "user"))


def unfinished() -> list[Path]:
    try:
        paths = json.loads((SOURCE / PROGRESS).read_text())
    except (OSError, ValueError):
        return []
    return [Path(p) for p in paths if (Path(p) / PROGRESS).exists()
            and len(progress(Path(p))["done"]) < len(STEPS)]


def remember(dest: Path, keep: bool) -> None:
    paths = {str(p) for p in unfinished()} - {str(dest)}
    if keep:
        paths.add(str(dest))
    write_json(SOURCE / PROGRESS, sorted(paths))


def wizard() -> None:
    print(f"\n{BOLD}New game{OFF}: a new GitHub repository with its own bot, which Claude starts building today.")
    print(f"{DIM}About 10 minutes. You'll need a browser for two clicks on GitHub and a Claude token.{OFF}")
    user = preflight()
    for dest in unfinished():
        name = config_mod.load(dest / "ci" / "config.json").game.name
        if ask(f"\nContinue setting up {name} in {dest}? (y/n)", "y").lower().startswith("y"):
            remember(dest, True)
            launch(dest, first_step=2, total=len(STEPS) + 1)
            remember(dest, False)
            return

    say("About the game")
    idea = ask_idea()
    name = ask("\nThe game's name", check=lambda a: "" if 2 <= len(a) <= 40 else "2 to 40 characters")

    def free(repo: str) -> str:
        if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo):
            return "write it as OWNER/NAME"
        if subprocess.run(["gh", "repo", "view", repo], capture_output=True).returncode == 0:
            return f"{repo} already exists on GitHub; pick another name"
        return ""
    repo = ask("GitHub repository", f"{user['login']}/{slugify(name)}", free)
    dest = Path(ask("Folder on this computer", str(SOURCE.parent / repo.split("/")[1]),
                    lambda a: f"{a} exists and isn't empty" if Path(a).exists() and any(Path(a).iterdir()) else ""))
    first = idea.strip().splitlines()[0].strip().rstrip(".")
    pitch = ask("One line about it, for the bot's prompts", first[:200])
    zone = config_mod.load().timezone

    say("The plan")
    print(f"  {name}, at https://github.com/{repo} (public), in {dest}")
    print(f"  1. Make the project folder: the automation from {config_mod.load().repo}, an empty Godot project, "
          "and your idea")
    for n, (_, title, _) in enumerate(STEPS, 2):
        print(f"  {n}. {title}")
    if not ask("\nGo ahead? (y/n)", "y").lower().startswith("y"):
        print("Nothing was changed.")
        return

    say(f"[1/{len(STEPS) + 1}] Make the project folder")
    game = Game(name=name, repo=repo, idea=idea, pitch=pitch, description=first[:300],
                owner_login=user["login"], owner_id=int(user["id"]), timezone=zone)
    scaffold(game, dest.resolve())
    print(f"  {dest.resolve()}")
    remember(dest.resolve(), True)
    launch(dest.resolve(), first_step=2, total=len(STEPS) + 1)
    remember(dest.resolve(), False)


# --- CLI -------------------------------------------------------------------------------


def game_from(args: argparse.Namespace) -> Game:
    idea = Path(args.idea_file).read_text() if args.idea_file else args.idea
    if not idea or not idea.strip():
        raise SystemExit("give the idea with --idea or --idea-file")
    owner = json.loads(run_gh("api", "user")) if not args.owner else {"login": args.owner, "id": args.owner_id}
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", args.repo):
        raise SystemExit(f"--repo must be OWNER/NAME, not {args.repo}")
    first = idea.strip().splitlines()[0].strip().rstrip(".")
    return Game(name=args.name, repo=args.repo, idea=idea, pitch=args.pitch or first[:200],
                description=args.description or first[:300], owner_login=owner["login"], owner_id=int(owner["id"]),
                timezone=args.timezone)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="smbot.bootstrap", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd")
    p = sub.add_parser("scaffold", help="only the local folder, without questions (for scripts and tests)")
    p.add_argument("--name", required=True, help="the game's name, e.g. 'Bee Keeper'")
    p.add_argument("--repo", required=True, help="OWNER/NAME of the repository to create")
    p.add_argument("--idea", help="the idea, a few lines to a page")
    p.add_argument("--idea-file", help="or a file with the idea")
    p.add_argument("--pitch", help="one line for Claude's prompts (default: the idea's first line)")
    p.add_argument("--description", help="the repository description (default: the idea's first line)")
    p.add_argument("--timezone", default="Europe/Copenhagen", help="for quiet hours and the Daily log")
    p.add_argument("--dest", required=True, type=Path, help="the new local folder")
    p.add_argument("--owner", help=argparse.SUPPRESS)  # tests: skip the gh lookup
    p.add_argument("--owner-id", type=int, default=0, help=argparse.SUPPRESS)
    sub.add_parser("launch", help="the GitHub part, for a scaffolded folder").add_argument("--dest", required=True,
                                                                                          type=Path)
    args = parser.parse_args(argv)
    try:
        if args.cmd == "scaffold":
            scaffold(game_from(args), args.dest)
            print(f"Scaffolded {args.dest}")
        elif args.cmd == "launch":
            launch(args.dest.resolve())
        else:
            wizard()
    except StepFailed as e:
        then = "it carries on from this step" if e.started else "nothing was changed yet"
        print(f"\n{RED}✗{OFF} {e}\n\nFix that and run ./new-game.sh again ({then}).")
        sys.exit(1)
    except (KeyboardInterrupt, EOFError):
        print("\n\nStopped. Run ./new-game.sh again to carry on where you left off.")
        sys.exit(130)


if __name__ == "__main__":
    main()
