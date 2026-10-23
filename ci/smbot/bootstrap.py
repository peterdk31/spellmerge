"""Starts a new game from this harness: a new repository, its own bot app, and the first session.

  PYTHONPATH=ci python3 -m smbot.bootstrap new --name "Bee Keeper" --repo OWNER/bee-keeper \\
      --idea-file idea.md --dest ../bee-keeper
  PYTHONPATH=ci python3 -m smbot.bootstrap scaffold ...   the local folder only (same arguments)
  PYTHONPATH=ci python3 -m smbot.bootstrap launch --dest ../bee-keeper   the GitHub part, for a scaffolded folder

`scaffold` copies the harness (ci/bootstrap/harness.json: .github/, ci/, tools/, setup.sh, the
licences, the security docs) from this checkout, writes a fresh ci/config.json, a Godot project that
only shows the name and the build version (ci/bootstrap/skeleton/), and docs whose queue starts with
two tasks: draft docs/DESIGN.md from the idea (the owner approves that PR), then plan the game.

`launch`, from the scaffolded folder, run by the owner with `gh` logged in:
1. creates the public repository and pushes main and the automation-state branch;
2. opens the Control panel issue;
3. creates the game's own bot app with GitHub's app-manifest flow (a page on 127.0.0.1 posts the
   manifest; you click Create, then Install on the new repository only), so its key never touches
   the disk;
4. writes the app and the panel into ci/config.json, commits and pushes;
5. runs ./setup.sh (rulesets, environment, variables, Pages, labels; needs jq);
6. stores BOT_APP_ID, BOT_APP_PRIVATE_KEY and CLAUDE_CODE_OAUTH_TOKEN in the protected environment;
7. lists what has no API (Discussions categories, itch.io) and starts the first development session.

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
        "build": {"ready": "main menu ready", "runs": []},
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


def say(text: str) -> None:
    print(f"\n\033[1m{text}\033[0m")


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


def launch(dest: Path) -> None:
    cfg_path = dest / "ci" / "config.json"
    cfg = config_mod.load(cfg_path)
    git = ["git", "-C", str(dest)]
    for cmd in ("gh", "git", "jq"):
        if not shutil.which(cmd):
            raise SystemExit(f"'{cmd}' is not installed")
    login = run_gh("api", "user", "--jq", ".login").strip()
    if login != cfg.owner.login:
        raise SystemExit(f"gh is logged in as {login}, not {cfg.owner.login}")

    say(f"1. Repository {cfg.repo}")
    if subprocess.run(["gh", "repo", "view", cfg.repo], capture_output=True).returncode != 0:
        run_gh("repo", "create", cfg.repo, "--public", "--description", cfg.game.description,
               "--source", str(dest), "--remote", "origin", "--push")
        subprocess.run([*git, "push", "-q", "origin", f"HEAD:refs/heads/{cfg.state_branch}"], check=True)
    print("  created and pushed")

    data = json.loads(cfg_path.read_text())
    say("2. Control panel")
    if not data["issues"]["control_panel"]:
        url = run_gh("issue", "create", "--repo", cfg.repo, "--title", "Control panel", "--body", panel_body(cfg))
        data["issues"]["control_panel"] = int(url.strip().rsplit("/", 1)[1])
        run_gh("issue", "pin", str(data["issues"]["control_panel"]), "--repo", cfg.repo)
    print(f"  #{data['issues']['control_panel']}")

    say("3. The bot app")
    app: dict[str, Any] = {}
    if not data["bot"]["client_id"]:
        app = create_app(cfg)
        login = f"{app['slug']}[bot]"
        data["bot"] = {"login": login, "id": int(run_gh("api", f"users/{login}", "--jq", ".id")),
                       "client_id": app["client_id"]}
        input(f"  Now install it on {cfg.repo} only: {app['html_url']}/installations/new\n"
              "  (\"Only select repositories\", pick the new repository). Press Enter when it's installed. ")
    print(f"  {data['bot']['login']}")

    say("4. ci/config.json")
    write_json(cfg_path, data)
    subprocess.run([*git, "add", "ci/config.json"], check=True)
    if subprocess.run([*git, "diff", "--cached", "--quiet"]).returncode != 0:
        subprocess.run([*git, "commit", "-q", "-m", "Record the bot app and the Control panel"], check=True)
        subprocess.run([*git, "push", "-q", "origin", "main"], check=True)
    print("  committed and pushed")

    say("5. Repository settings (./setup.sh)")
    subprocess.run(["./setup.sh"], cwd=dest, check=False)

    say("6. Secrets in the protected environment")
    env = ["--env", "automation", "--repo", cfg.repo]
    if app:
        run_gh("secret", "set", "BOT_APP_ID", *env, "--body", str(app["id"]))
        run_gh("secret", "set", "BOT_APP_PRIVATE_KEY", *env, input=app["pem"])
        print("  BOT_APP_ID and BOT_APP_PRIVATE_KEY")
    token = getpass.getpass("  Paste a Claude token from `claude setup-token` (Enter to skip): ").strip()
    if token:
        run_gh("secret", "set", "CLAUDE_CODE_OAUTH_TOKEN", *env, input=token)
        print("  CLAUDE_CODE_OAUTH_TOKEN")

    say("7. By hand (no API)")
    print(f"  - Discussions categories {', '.join(DISCUSSION_CATEGORIES)}; delete GitHub's defaults: "
          f"https://github.com/{cfg.repo}/discussions/categories")
    print("  - Optional: an itch.io page, then BUTLER_API_KEY in the environment and the ITCH_TARGET variable "
          "(docs/SETUP-APP.md, step 6), and .game.itch in ci/config.json")
    print("  - docs/SECURITY-CHECKLIST.md")
    if token and input("\n  Start the first development session now? [Y/n] ").strip().lower() in ("", "y", "yes"):
        run_gh("workflow", "run", "develop.yml", "--repo", cfg.repo, "--ref", "main")
        print(f"  Started: https://github.com/{cfg.repo}/actions. Its PR drafts docs/DESIGN.md for your review.")


# --- CLI ---------------------------------------------------------------------------


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
    sub = parser.add_subparsers(dest="cmd", required=True)
    for name in ("new", "scaffold"):
        p = sub.add_parser(name)
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
    sub.add_parser("launch").add_argument("--dest", required=True, type=Path)
    args = parser.parse_args(argv)
    if args.cmd in ("new", "scaffold"):
        scaffold(game_from(args), args.dest)
        print(f"Scaffolded {args.dest}")
    if args.cmd in ("new", "launch"):
        launch(args.dest)


if __name__ == "__main__":
    main()
