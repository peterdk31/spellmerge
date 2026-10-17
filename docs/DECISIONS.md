# Decisions

Why things were decided, so they aren't reversed by accident. Newest first.

## 2026-10-17: Pools and the projectile manager (M1 part 7)

**Decided by:** Claude (details the task left open).

- **Pool:** GDScript has no generics, so a pool is typed by its factory Callable and the caller casts `acquire()`. It makes all objects up front and never grows: at capacity `acquire()` returns `null` and the caller degrades. A growing pool would allocate mid-frame, which the budgets forbid.
- **Projectiles are rows in packed arrays** (struct of arrays), simulated in `_physics_process` and drawn by one `MultiMeshInstance2D`, tinted by player colour (STYLE.md base colours; enemy shots Fire). A texture can be set later for the real bolt art.
- **Targets are registered, not searched for:** `add_target(node, radius, layer)`. The manager reads their positions each step into a grid of 64 px cells, so it depends on no gameplay class and `core/` keeps its dependency direction. Hit layers (`LAYER_ENEMY`, `LAYER_PLAYER`) let enemy shots hit players and player shots hit enemies, and a shot's owner can be `NO_PLAYER`. Friendly fire (part 17) means a player shot with `LAYER_PLAYER` in its mask.
- **Hits test the path, not the point:** each step's segment against the target circle. The grid cells searched are those the segment touches, widened by the shot's radius and the largest target radius, so neither fast shots nor big targets (bosses) are missed. Among the targets a segment touches, the nearest along the path is hit first and the event carries the closest point on the path. A piercing shot remembers its last 3 hit targets, so overlapping enemies are hit once each (a fourth overlapping one could be hit again; accepted).
- **The cap degrades by dropping, never by refusing:** at the cap, the oldest projectile of whoever owns the most is dropped. A refused shot would feel like a broken button; dropping the oldest of the richest means a player who floods the screen loses only their own old shots, and nobody is starved (pillar 2). The default cap is the PLAN budget per platform (1,000 on the web, 3,000 on desktop); `set_cap` changes it. Dropping is O(1): each owner has a list of its slots in spawn order, so a flooding player cannot cause a scan. Projectiles deliberately do not use `core/pools`: they are rows with their own slot free list, and `Pool` is for nodes and effects (enemies, damage numbers).
- **A hit carries an opaque `tag`:** `spawn(..., pierce, tag)` stores an int per projectile and `projectile_hit(player, target, position, tag)` sends it back unread (the event changed from part 1 for this). The manager still knows nothing about damage: the spawner (the bolt, part 13) keeps its own table from tag to damage and effects, and `combat` (part 11) looks the tag up there. An int, not a Variant, so it stays a packed array row. Default 0 means "no tag".
- **Piercing shots hit up to 3 targets per step** (`HIT_MEMORY`), nearest first, so a fast piercing shot through a crowd hits all of them; a shot that would pierce more than 3 targets in one step (very rare) hits the rest on later steps only if they are still on its path. It remembers the last 3 targets hit and forgets the oldest after that.
- **Draw cost is unmeasured.** `step` and `update_draw` loop over all slots in GDScript and `update_draw` writes the whole cap-sized buffer. Part 22 must time `spawn` at the cap and `update_draw` with a full cap before these caps are relied on; if slow, upload only the first `drawn` instances and lower the web cap.
- Removing a target or spawning a projectile inside a `projectile_hit` handler is safe: removal waits for the next step and new shots start moving on the next step.

## 2026-10-17: Per-player focus (M1 part 6)

**Decided by:** Claude (details the task left open).

- One autoload, `UIFocus`. A panel is opened for one player with an ordered list of controls; only that player's input moves it. It reads `PlayerInput` by index, never `Input`, and never calls `grab_focus`, so Godot's single global focus plays no part and the mouse cannot steal a panel.
- Navigation uses the gameplay actions, no new ones: up/left and down/right step through the controls (wrapping), `cast` activates, `dodge` cancels. Cancel only sends `cancelled`; the panel decides whether to close. The `overlay` action that opens panels is handled by the overlay (M1 part 19).
- It detects presses with a press counter added to `PlayerInput` (`get_press_count`), compared with the value seen at the last poll. A first version compared `is_action_pressed` between polls and lost a tap released within one frame (bots do that with `send_virtual`); `is_action_just_pressed` is tied to one frame and also needs the caller in `_process`. The counter loses nothing and works from any call. Presses from before the panel opened (the button that opened it) are ignored.
- An open panel captures its owner's gameplay input: `PlayerInput.set_captured(player, true)` makes `get_move`, `get_strength`, `is_action_pressed` and `is_action_just_pressed` answer "nothing" for move, `cast` and `dodge` (not `overlay`, so the overlay can close itself). Gameplay needs no check, nothing is paused, and the other players are untouched. The alternative, separate `ui_*` actions, would need a second binding set for every device. Capture ends on close and when the device leaves.
- Focus is re-checked every frame and before each activation: a control that was disabled, hidden (also through a hidden parent, when in the tree) or freed loses focus to the next usable one, and the press that found it stale activates nothing. `focus_mode` is ignored, since Godot's focus is never used. A panel opens only for a joined player, and opening over an open panel sends `closed` then `opened`.
- Results are signals with the player first (`opened`, `closed`, `focus_changed`, `activated`, `cancelled`); widgets check that the player is their owner. A panel closes when its player's device leaves. Nothing is paused.

## 2026-10-17: Input devices and join (M1 part 5)

**Decided by:** Claude (details the task left open).

- One autoload, `PlayerInput`, routes every input event by device to a player index and keeps per-player action state. Gameplay asks it by index and never reads `Input` directly, so one global action map serves all four players.
- A gamepad takes the lowest free index. The keyboard and mouse count as one device that may only take index 0, matching "P1 keyboard or gamepad, P2–P4 gamepads"; if a gamepad already holds P1, the keyboard cannot join.
- `join` (Enter, Space, gamepad A or Start) and `leave` (Backspace, gamepad Back) are actions. An unplugged gamepad leaves; plugging one in never joins without a button press.
- Bots use virtual devices, ids 1000 + index. They send `InputEventAction`s through the same `handle_event` path as real events, so bot tests exercise the real input code.
- The device events are `device_joined(player, device)` and `device_left(player, device)`, sent by `core/input`; `coop` (M1 part 17) turns them into `player_joined` and `player_left`.

## 2026-10-17: The provisional palette and style rules (M1 part 3)

**Decided by:** Claude (details the plan left open).
**Decision:** `docs/STYLE.md` fixes a 31-colour palette: outline `#14121f` plus ten 3-shade materials (stone, bone, fire, spark, wood, skin and one ramp per player: blue, rose, green, purple). Player ramps are used only for players. Animations are horizontal strips of 32 px frames with fixed counts per animation type. Placeholder SVGs use only `<rect>`s with whole-number coordinates, palette fills and `shape-rendering="crispEdges"`.
**Reason:** Part 4 and outside Art PRs need concrete values to check against. Rects-only SVG guarantees no antialiasing. The style is provisional: the M2 art direction call may replace it (the plan already says so), and then the palette changes in one file.

## 2026-10-17: Event lists in the READMEs are final (M1 part 2)

**Decided by:** Claude (details the plan left open).
**Decision:** `core/events/events.gd` is the source of truth for event names and senders. The "Events at a glance" table in `gameplay/README.md` and every area's event list match it, and the "provisional" marks are gone. `play_requested` (sender: HUD, listener: `flow`) joins the HUD's player-intent requests, so the HUD sends five events. This completes the 2026-10-16 entry "Entry script names, event names and file types", which expected the marks to go once the bus was built.
**Reason:** The bus exists, so the lists can be checked against code and later parts can rely on the names.

## 2026-10-16: Event signatures and base class shapes (M1 part 1)

**Decided by:** Claude (details the plan left open).
**Decision:** `Events` signals take the player index as an `int` named `player`, first. Events with no player (`run_started(player_count)`, `run_ended(victory)`, `room_entered(room_id)`, `room_cleared(room_id)`, `difficulty_changed(level)`, `reward_rolled(reward_ids)`, `unlock_gained(unlock_id)`, `currency_changed(currency_id, amount)`) don't. `damage_dealt`, `status_applied`, `enemy_died` and `projectile_hit` name the source player, or `Events.NO_PLAYER` (-1) when an enemy is the source. `door_voted` and `reward_taken` carry the voting or picking player, as the results of the matching request events. Base resources use `PackedVector2Array` positions for spawns and doors and have only the M1 fields, plus `id: StringName` and `demo: bool`.
**Reason:** Typed signals with a fixed shape let tests and later parts rely on them; -1 avoids a fake player index for enemy damage. M2 and M3 may change the base fields and event arguments; part 2 and those milestones update the docs with them.

## 2026-10-16: M1 design choices the plan left open

**Decided by:** Claude (details the plan left open), in `docs/milestones/M1-core-loop.md`.
**Decision:**
- The ten `gameplay/` sub-areas, `content/spells` and `content/wizard` don't allow `.tscn` (`hud/`, `content/enemies` and `content/rooms` do), so M1 scenes live with their content (`content/wizard/base`, which gets `.tscn` in its README, `content/enemies`, `content/rooms`, `hud/`); `gameplay/` stays script-only and gets scenes through `core/registry`. Rejected: allowing `.tscn` in `gameplay/`, because the Areas table in `docs/PLAN.md` lists only `.gd` and `.tres` for it. The allowed-files paragraph of `gameplay/README.md`, which left this open for M1, is rewritten to say so (part 9).
- The main menu starts the arena only through a new HUD intent event, `play_requested(player)`, that `flow` listens to; areas never call each other.
- Sounds are the Audio contributors' job. Gameplay code asks `core/registry` for a sound by id; the registry (the one place that loads by a computed path) returns `null` for a missing one and nothing plays, so a missing sound is silent and the literal-path rule holds.
- M1 is 25 parts: input, the player, combat with the enemy, and the HUD are each split in two so a task fits one session.
- The player and bots only call one cast method and read no spell fields, so M2 can replace the fire bolt.
- The registry scans folders at start; the build-time manifest waits until content is large.
- The one spell is a fire bolt on a small base class that M2 replaces; nothing else may depend on its fields.
- A minimal slice of `flow` (load the room, spawn the wave, restart) is built in M1 instead of M3, so the loop is playable. M3 replaces it. There is no pause menu in M1.
- Placeholder art is hand-written SVG, since sessions have no image tools. The web 4-bot run and the Style Guide page and kit zip need small owner-only changes in `ci/smbot/`, which their tasks file in `docs/BACKLOG.md`.

**Reason:** each keeps M1 small, inside the path rules, and playable for the first checkpoint.

## 2026-10-16: M1 starts before M0's dry runs

**Decided by:** owner.
**Context:** All seven M0 parts are built, and the bot now develops, reviews and merges its own PRs. M0's done-when also asks for 3 daily releases in a row and 15 dry runs. GitHub hasn't fired the daily schedule yet (the catch-up in `develop.yml` covers it from now on), and most dry runs need a second GitHub account or a deliberately broken build, so the bot's queue was empty with nothing it could do.
**Decision:** M0 is closed early and M1 starts now. The dry runs and the 3-release streak are not dropped: they carry into M1 and are part of M1's done-when, so M1 can't finish without them. The first M1 task is the M1 design document, which goes through the normal review before any M1 code. Art and Audio open for PRs with M1, as planned.
**Consequence:** the pipeline's end-to-end checks (rule-breaking PRs auto-closed, CLA, votes, quarantine, kill switch, token alarm, revert of a broken build) are still unproven while M1 is built and Art and Audio take outside PRs. The owner runs them during M1.

## 2026-10-16: llms.txt uses relative links and lists maintainer prompts as Optional

**Decided by:** Claude (details the plan left open).
**Context:** The llms.txt convention expects absolute URLs, but the repo may be forked or renamed, and agents read it from a checkout.
**Decision:** `llms.txt` at the repo root uses repo-relative paths. The `.github/maintainer/` prompts go under "Optional" since contributors rarely need them. Any PR that adds or removes a doc updates `llms.txt`.

## 2026-10-16: Entry script names, event names and file types in the code-area READMEs

**Decided by:** Claude (details the plan left open).
**Context:** docs/PLAN.md gives `combat/combat.gd` as an example entry script but doesn't list the rest, and the event bus doesn't exist yet.
**Decision:** Each gameplay sub-area's entry script is `gameplay/<area>/<area>.gd`. `core/events` owns the event definitions; each README only lists the events its area sends (each event has one sender) and listens to, marked **provisional** until the event bus is built in M1, when the READMEs are updated. The HUD's sent events are the player-intent requests from "The HUD sends player-intent events": `build_change_requested` (listener `player`), `reward_pick_requested` (`rewards`), `door_vote_requested` (`flow`) and `pause_requested` (`run`), all in the table in `gameplay/README.md`. Text shared by all sub-areas lives in `gameplay/README.md`. Gameplay PRs allow `.gd` and `.tres` only, as in the plan's Areas table. `core/` services get their entry scripts and sections when built.

## 2026-10-16: The bot can merge its own approved PRs

**Decided by:** owner.
**Context:** The `main` ruleset had "Require approval of the most recent reviewable push", which needs an approving review from someone other than the last pusher. The bot pushes its own PRs and can't approve them, and the merge script never approves anything, so GitHub refused every automated merge ("the base branch policy prohibits the merge") and every bot PR waited for the owner.
**Decision:** `require_last_push_approval` is off (`ci/settings/rulesets/main.json`, and on GitHub). Owner-only paths still need the owner's code-owner review, and the merge script still merges only the exact reviewed commit, after the required checks and the hard rules pass.
**Consequence:** the bot's PRs merge the same day, as the plan intends. What contributor PRs may change is unaffected: the hard rules and the code-owner review still apply.

## 2026-10-16: develop also runs on every push to main

**Decided by:** owner.
**Context:** GitHub never fired this repository's schedule: no scheduled run of any workflow on its first day, through two cron changes and turning the workflow off and on. When a session chain stops (an error, a usage limit, an empty queue), nothing started it again.
**Decision:** a push to `main` (any merge, by the bot or the owner) runs a small `kick` job in `develop.yml`. If no develop run is running or queued, it starts one with `workflow_dispatch`; otherwise the running chain carries on by itself. The kick job runs no Claude step, because `claude-code-action` doesn't accept `push` events, and it sits outside the `develop` concurrency group, so it never waits behind a session. The hourly schedule stays for when GitHub does fire it.

## 2026-10-16: Sessions don't wait for each other or for the owner

**Decided by:** owner.
**Context:** The next session started only after a merge, and only within 2 hours of the first. Any PR that didn't merge (a failed review, a blocked task, a merge GitHub refused) ended the chain, and work waited for the next hourly check. A stuck task also stayed at the top of the queue, so the next session tried it again.
**Decision:**
- When a session ends, the next one starts right away if the session made progress (it merged, opened or updated a PR, or reported the task blocked), the budget allows it, and there is a task. There is no time cap; the pacing budget limits usage. The chain stops on an error, a usage limit, nothing to do, or paused merging, and the hourly check starts it again.
- A task that can't move without someone else is parked in the state's `task_failures` and skipped, so the next task goes first: for 7 days when it failed review twice or was reported blocked, and for 1 day when its approved PR wasn't merged. Afterwards it is picked up again, and its open PR is continued.
**Consequence:** Work only waits on the owner for things only the owner can do, and even then other tasks go ahead. A task that failed review once is still retried straight away, with the review's problems.

## 2026-10-16: The HUD sends player-intent events

**Decided by:** owner.
**Context:** The plan said "The HUD only listens." But the spell builder, reward picks, door votes and the pause menu are all HUD scenes whose choices must reach gameplay. With a listen-only HUD, that input would have to go through direct calls into gameplay, which principle 2 forbids.
**Decision:** The HUD may send events, but only player-intent events: a request carrying the player index (0–3), such as a builder change, a reward pick, a door vote or opening the pause menu. Gameplay owns all state. It checks each request, applies it or refuses it, and announces the result as a normal state event. The HUD shows only what those state events say, never its own guess of the outcome. It still never calls gameplay directly, and other areas never call into the HUD.
**Consequence:** Plan principle 2 now says this. Event names are settled when the event bus is built in M1; intent events are named as requests, so they can't be mistaken for state events.

## 2026-10-16: Content READMEs name no field or file layout before the example exists

**Decided by:** Claude, within the plan.
**Decision:** The content area READMEs describe the contract as "the base class (arrives in milestone X)" and point to an example that arrives with Claude's first content, instead of inventing field names. Sub-folder `.gitkeep` files (spells, wizard, story) stay because those sub-folders have no README.
**Reason:** The base classes don't exist yet; documenting invented names would contradict the code later. Each README gets the real example path when its area opens.

## 2026-10-16: Claude never holds a write token where it has a shell

**Decided by:** Claude, after reviewing the session design.
**Context:** The implementing and revising sessions can effectively run code: through git, file commands, or Godot running scripts they wrote. If a prompt injection ever reached them (say, from a merged contribution's comments), a write token on that runner could be stolen and used to merge.
**Decision:**
- Those sessions get a read-only app token and commit only locally. Their commits leave the runner as a git bundle, which is plain data.
- A `publish` job on a fresh runner fetches the bundle into a clean checkout of `main` (with git hooks disabled), pushes only to a `claude/...` branch, and opens or updates the PR from Claude's structured output. It also records usage and posts `/ask` answers, only on issues where the owner asked.
- Claude is also denied edits under `.git/`, `.github/`, `ci/` and `tools/`, and gets only specific `git` subcommands.
- Sessions without shell or file-writing tools (rating, review, digest) still mint a write token after Claude finishes, because they can't run code.
**Residual risk:** a session could still leak its read-only token or its Claude token over the network. The next hardening step would be an egress firewall on those runners (see `docs/BACKLOG.md`).

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
- **Continuous work:** after every session that made progress, the next one starts with `workflow_dispatch` while there is a task and budget (see "Sessions don't wait for each other or for the owner"). One session at a time, through the `develop` concurrency group.
- **Usage accounting** reads each step's execution file. Cache reads count a tenth, because they cost far less quota. A usage-limit message starts the back-off; a rejected token opens the token alarm, and the alarm closes after the next good run.

## 2026-10-16: How the control gate, owner commands and pacing work

**Decided by:** Claude, within the plan.

- **The gate:** every run starts with `ci/smbot/control.py`. Nothing runs unless the `AUTOMATION_ENABLED` variable is `true` and the Control panel (issue #4) allows it.
- **Panel trust:** values come from GitHub's edit history (each `userContentEdits` entry holds the full body of that revision), from the newest revision whose editor is the owner's numeric ID. A newer edit by anyone else is ignored and reported in the Daily log with a mention of the owner. If no owner revision exists, the gate fails closed.
- **Owner commands:** processed only by the hourly run, so two runs never act on one command. `/pause` pauses development and PR merging; releases continue, because only the kill switch stops releases. `/merge` refuses if the PR head was pushed after the command, judged by when GitHub started that commit's checks run, since commit dates can be faked. `/priority`, `/claude` and `/ask` are queued for the next Claude session.
- **Merge method:** squash for every merge, so each PR is one commit that one `git revert` undoes. The PR author stays the commit author.
- **State:** bookkeeping lives in `state.json` on the `automation-state` branch: token usage, learned limits, back-off, processed commands and alarm issues. Writes use the file's SHA, so concurrent runs can't silently overwrite each other. It is never trusted for security decisions.
- **Pacing:** each run records its tokens. When a usage limit is hit, the tokens used in the last 5 hours (or 7 days) become the learned window (or week) size, and runs back off until the reset. After that, runs stop at `DEV_INTENSITY`% of a window and at `WEEKLY_SHARE`% of a week, spread evenly at a seventh per day.
- **Schedule:** the hourly run starts at minute 35, away from the busy top of the hour.
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
- Only GitHub-owned actions plus `anthropics/claude-code-action` and `oven-sh/setup-bun` are allowed, all pinned by SHA (`ci/settings/allowed-actions.json`). claude-code-action uses `oven-sh/setup-bun` internally, pinned by SHA in its own `action.yml`.
