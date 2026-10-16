# Decisions

Why things were decided, so they aren't reversed by accident. Newest first.

## 2026-10-16: How the weekly planning run works

**Decided by:** Claude, within the plan.

- **`weekly.yml`** runs on Sundays at 06:00 UTC, in the same concurrency group as development, so the two never overlap.
- **Untrusted community text** (Discussions, spell ideas, bug reports) is read only by a digest session with read-only tools (`Read`, `Glob`, `Grep`; no shell) and no write token. Its structured output (verdicts, short replies, neutral bug restatements) is all the planning session sees, and only as data.
- **Replies to ideas** are posted by script with the workflow token, because the bot app has no Discussions permission and the plan keeps it to three. They are limited to about 1,200 characters, with no @mentions and no links outside this repository.
- **The planning session** is a normal work session (`session.yml`, mode `plan`), with the same critique, revision, final review and scripted merge as development. It edits the plan files, and writes the next milestone's design once the current milestone is done. Its structured output becomes the devlog post (Discussions, Announcements), contributor task issues (the fixed template with a "Brief for your AI", at most 10 open per area), owner issues (milestone start, checkpoints) and, from M1 on, the playtest of the week.
- **`session.yml`** holds the implement, critique, revise, final review, merge and finish chain for both `develop.yml` and `weekly.yml`.

## 2026-10-16: How the contribution pipeline works

**Decided by:** Claude, within the plan and the owner's CLA decision.

- **Triage** (daily, script): the hard rules are re-run from `main` against each PR head, with no PR code run. Closing comments list rule, file, line and fix. After 2 closed PRs in a day, an author's further PRs that day are closed. Unsigned authors get one CLA reminder, and the PR closes after 7 days. Area and skill labels come from the changed paths.
- **CLA records:** new signatures go into `docs/cla-signatures.json` through an `automated` bot PR that the merge step merges after checks. `automated` PRs may only change that file, or, for a quarantine, the reported asset and the manifests.
- **Rating:** one fresh Claude session per PR (matrix job, at most 8 a day, within about 30% of the window budget). It has read-only tools and a read-only token, and the PR's files are checked out without being run. A script holds Claude's decision to the plan's thresholds (merge needs an average of at least 3.5 and no criterion below 2) and posts the comment, with a marker recording the rated SHA. A push means a new rating.
- **Merging:** the rated SHA must still be the head. Votable PRs (art, audio, gameplay, spells) wait for the vote, and the rating comment's vote line is updated daily. Candidates are test-merged in score order on a local `staging` branch, with the quick build after each, in a job without secrets. Then the merge script merges each one (checks, hard rules, `--match-head-commit`). On a conflict, the higher-rated PR wins and the other gets a rebase request.
- **Follow-ups:** the rating's fix-ups for merged PRs become the next development session's task, crediting the contributor. They are treated as suggestions, not instructions.
- **Broken daily build:** in a job without secrets, the day's merges are reverted newest first until the build passes. The culprits are then reverted on `main` through bot PRs, with a comment on each, and the daily run starts again once (no second round of reverts).
- **Claims:** `/claim` (anyone) assigns an issue labelled `now`, hourly. A reminder comes after 1 day and the claim is released after 2 days without a PR that mentions the issue.
- **No-git submissions:** issue forms for art, sound and writing. In a job without secrets, the file is downloaded only from GitHub's attachment hosts. PNGs are fully decoded and re-encoded (only pixels survive) and OGG is re-encoded by ffmpeg. Then a privileged job checks that both agreement boxes were ticked and that only the author edited the issue, and opens a bot PR (label `submission`, contributor as co-author) that is rated like any outside PR.
- **Copyright reports:** the reported asset is replaced by a same-size placeholder (audio is removed) and marked `quarantined` in the manifest, through an `automated` PR merged before the build. The owner is notified.
- **Votes:** the thresholds, window, eligibility phases and coordinated-vote discount are implemented in `ci/smbot/votes.py`. They are dormant while there are 0–2 active voters.

## 2026-10-16: How a development session works

**Decided by:** Claude, within the plan.

- **The flow:** `develop.yml` runs hourly, as implement, critique, revise, final review, merge, finish. Each Claude step runs in its own job on a fresh runner, so a session with a shell can't tamper with its reviewers or with the merge script. The merge job runs no AI and uses only scripts from a clean checkout of `main`.
- **Reviewers** (`review.yml`) get a read-only app token and read-only tools (`gh pr view/diff`, `git diff/log/show`). Their verdict is structured JSON. A PR merges only with `approve` and no blocker or major problems, and only after the required checks and the hard rules (re-run from `main`) pass, pinned to the reviewed commit.
- **The implementer** gets a curated command list: git, `gh pr`, `gh issue view/comment`, `tools/check.sh`, `ci/build/build.sh --quick`, and basic file commands. No `curl`, `wget`, Python, web fetch or web search. Secrets are scrubbed from its subprocesses where the action supports it. Prompts are in owner-only `.github/maintainer/`.
- **One critique and one revision round** per session. If the final review rejects, the PR stays open, and the next session sees the problems and continues. After the second failed attempt, the task is marked blocked, with the reason, and work moves on.
- **Continuous work:** after a successful merge, the session starts the next one with `workflow_dispatch`, while there is a task and budget, for up to about 2 hours per chain. One session at a time, through the `develop` concurrency group.
- **Usage accounting** reads each step's execution file. Cache reads count a tenth, because they cost far less quota. A usage-limit message starts the back-off; a rejected token opens the token alarm, and the alarm closes after the next good run.

## 2026-10-16: How the control gate, owner commands and pacing work

**Decided by:** Claude, within the plan.

- **The gate:** every run starts with `ci/smbot/control.py`. Nothing runs unless the `AUTOMATION_ENABLED` variable is `true` and the Control panel (issue #4) allows it.
- **Panel trust:** values come from GitHub's edit history (each `userContentEdits` entry holds the full body of that revision), from the newest revision whose editor is the owner's numeric ID. A newer edit by anyone else is ignored and reported in the Daily log with a mention of the owner. If no owner revision exists, the gate fails closed.
- **Owner commands:** processed only by the hourly run, so two runs never act on one command. `/pause` pauses development and PR merging; releases continue, because only the kill switch stops releases. `/merge` refuses if the PR head was pushed after the command, judged by when GitHub started that commit's checks run, since commit dates can be faked. `/priority`, `/claude` and `/ask` are queued for the next Claude session.
- **Merge method:** squash for every merge, so each PR is one commit that one `git revert` undoes. The PR author stays the commit author.
- **State:** bookkeeping lives in `state.json` on the `automation-state` branch: token usage, learned limits, back-off, processed commands and alarm issues. Writes use the file's SHA, so concurrent runs can't silently overwrite each other. It is never trusted for security decisions.
- **Pacing:** each run records its tokens. When a usage limit is hit, the tokens used in the last 5 hours (or 7 days) become the learned window (or week) size, and runs back off until the reset. After that, runs stop at `DEV_INTENSITY`% of a window and at `WEEKLY_SHARE`% of a week, spread evenly at a seventh per day.
- **Schedule:** the hourly run starts at minute 17, away from the busy top of the hour.
- **Alarms:** each alarm is an issue labelled `alarm` that mentions the owner, opened once and closed automatically when the problem is resolved.
- The bot app's token is minted with `app-id`, which is deprecated in favour of `client-id` (see `docs/BACKLOG.md`).

## 2026-10-16: How builds and releases work

**Decided by:** Claude, within the plan.

- **Engine:** Godot 4.7.2-stable is pinned in `ci/build/godot.env`. The editor and export templates are checked against Godot's own SHA-512 sums. Only the checked downloads are cached; Godot is unpacked fresh on every run, so a tampered cache can't supply a binary.
- **Display:** a 640×360 viewport with integer scaling for crisp 32×32 pixel art, the Compatibility renderer, and a single-threaded web export (no special server headers needed on GitHub Pages or itch.io).
- **Smoke tests every build must pass:** the main scene in the editor, the exported Linux binary, and the exported web build in headless Chrome (`ci/smbot/websmoke.py`). Any engine or script error in the logs fails the build. Windows builds can't be run on Linux runners.
- **Channel:** decided before the build. A build that passes every test is stable unless an issue labelled `crash` or `blocker` is open, in which case it is nightly. Failing tests stop the release entirely. The benchmark joins the gate in M2.
- **Releases:** tagged `v0.YYYYMMDD` (`.2`, `.3` for extra runs on the same day). The assets are attached to a draft, which is then published, so the immutable release is complete. Nightlies are pre-releases; stable releases are marked latest.
- **Pages:** `/play/` serves the latest stable web build, `/nightly/` today's build, and `/` a landing page until the Contribute page exists.
- **itch.io:** pushed with butler 15.31.0 (hash-pinned) once the `ITCH_TARGET` variable (for example `peterdk31/spellmerge`) is set. Stable builds go to the `web`, `windows` and `linux` channels, nightlies to `*-nightly`.
- Only `core/` and `tests/` may load files dynamically. Tests are never exported.

## 2026-10-16: How the hard rules check works

**Decided by:** Claude, within the plan's rules.

- The check is `ci/smbot/rules.py`, Python 3 standard library only, so nothing is installed in jobs that hold secrets. `tools/check.sh` runs the same code locally.
- The owner-only paths are read from `.github/CODEOWNERS`, so there is one list. `addons/` was added, because the plan allows third-party addons only from the owner. `project.godot` and `export_presets.cfg` are bot-maintained, because they can register autoload scripts and change export settings.
- In CI, the rules and `ci/config.json` come from a checkout of `main`, never from the PR. The fixed identities (owner and bot, with numeric IDs) live in owner-only `ci/config.json` rather than in repository variables, because the check must also work for fork PRs.
- Untyped GDScript is a warning for outside contributors, since the review stance has Claude fix it after merging, and an error for the bot's own PRs. `project.godot` therefore reports untyped code as a warning, not an error, so a contributor's untyped code can't break the build.
- Size limits: 1 MB for `.png` and `.svg`, 5 MB for `.ogg`, as in the plan, and 1 MB for any other file, against abuse.
- Banned in `.gd`, `.tscn` and `.tres`, beyond the plan's list, because each can hide a banned call: calling singletons by name (`OS.call`, `Engine.get_singleton`), creating code at runtime (`GDScript.new`, `Expression`, `set_script`), `@tool` and editor plugins, and loading from a computed or `user://` path outside `core/`.
- Also rejected: symbolic links, submodules, binaries disguised as `.png` or `.ogg` (the magic bytes are checked), and SVGs with scripts or external links. Dependabot PRs may only change GitHub Actions files.
- The owner's own PRs get warnings only.
- The required `rules` status alone is never trusted, because a PR could rewrite `checks.yml`. Such a PR needs the owner's review, and the merge script re-runs the check from `main` before merging.

## 2026-10-16: Own CLA check instead of CLA Assistant; no lawyer review

**Decided by:** owner.
**Context:** cla-assistant.io keeps an OAuth token for the owner's account with `repo:status`, `write:repo_hook` and `gist` scopes on all repos. The owner account is what the whole security model protects.
**Decision:**
- `CLA.md` is adapted from the Apache Individual CLA v2.2, because a standard, widely used text is the safest choice without a lawyer.
- Contributors sign by commenting `I have read the CLA and I agree to it.` on their PR. For no-git submissions, the issue-form checkbox counts.
- The daily run records signatures in the bot-maintained `docs/cla-signatures.json` by numeric user ID and CLA version.
- Unsigned PRs get a how-to-sign comment and are closed only if still unsigned after 7 days, because a signature is only seen at the next daily run. They are never merged unsigned.
- The plan's "short lawyer review before selling" item is dropped entirely.

## 2026-10-16: PRs merge into `main`; `staging` is only a test branch

**Decided by:** owner.
**Context:** The plan had approved PRs merged into `staging`, with `main` fast-forwarded at release. A `main` ruleset that requires PRs and code-owner review would only allow that if the bot were a bypass actor, and then the bot could also push owner-only paths past CODEOWNERS.
**Decision:** The bot is never a bypass actor. The merge script merges candidates together on a throwaway `staging` branch and runs the content validators there, then merges each passing PR into `main` with `gh pr merge --match-head-commit <reviewed SHA>`. A broken daily build is fixed with revert PRs that the bot opens and merges itself. The release tags `main`.
**Consequence:** Every protection that GitHub enforces stays in place for the bot. `main` can briefly hold a merge that the daily smoke test later reverts, but releases are cut only from a tested `main`.

## 2026-10-16: Code license is GPL-3.0-or-later

**Decided by:** owner. Assets stay CC-BY-SA-4.0. Recorded in `REUSE.toml` and `LICENSE`.

## 2026-10-16: Setup, security docs and REUSE.toml are owner-only

**Decided by:** owner. `setup.sh`, `REUSE.toml`, `docs/SECURITY-CHECKLIST.md` and `docs/SETUP-APP.md` join the owner-only tier, so the bot can't weaken the security setup or its checklist, or change the license that every file falls under. Repository settings data lives in `ci/settings/`, which is owner-only already.

## 2026-10-16: The project board is user-owned and follows labels

**Decided by:** owner.
**Context:** GitHub Apps can't access projects owned by a personal account; that needs a classic personal access token, which the plan rules out.
**Decision:** The board stays under `peterdk31`. GitHub's built-in auto-add workflow fills it, and views filter by label. The bot keeps issue labels correct and never edits the board itself.

## 2026-10-16: Names chosen during setup

**Decided by:** Claude (details the plan left open).

- The protected environment is called `automation`. Its secrets are `BOT_APP_ID`, `BOT_APP_PRIVATE_KEY`, `CLAUDE_CODE_OAUTH_TOKEN` and `BUTLER_API_KEY` (the name itch.io's `butler` tool reads).
- The repository variables are `AUTOMATION_ENABLED` (the kill switch), `OWNER_ID` (the owner's numeric user ID) and `BOT_LOGIN`.
- The required PR status check is the `checks.yml` job named `rules`, pinned to the GitHub Actions app.
- Only GitHub-owned actions plus `anthropics/claude-code-action` are allowed, all pinned by SHA (`ci/settings/allowed-actions.json`).
