# Spellmerge — Project Plan

Oct 16, 2026 · peterdk31

## Overview

Spellmerge is a 2D top-down roguelite about building deep, combinable spells, for 1–4 local co-op players. Claude writes the code, reviews and merges community PRs, and ships a new playable web build every day, all on GitHub's servers with no PC running.

**Tagline:** *Merge spells. Cause chaos. Together.* On GitHub and in developer communities, a second line: *Every spell is a merge request.*

- **Owner:** peterdk31 (sole admin and code owner). Claude acts as a bot, so AI changes are always visible as such.
- **Engine:** Godot 4.x (one pinned stable version), GDScript only.
- **Art:** 32×32 pixel art. AI-made and human-made assets are both allowed, and each asset's origin is tracked.
- **Platforms:** Daily web build (a free demo and showcase) plus daily full desktop builds for Windows and Linux; Steam later.
- **License:** GPL-3.0-or-later code, CC-BY-SA assets, CLA for contributors.
- **Budget:** Claude Pro (about $20/month). Everything else is free.
- **Autonomy:** Claude plans, builds and merges on its own. The owner only controls the vision in `DESIGN.md` and the protected infrastructure.

## Quality bar

Spellmerge must ship as a professional-looking game with very few bugs and genuinely good art, music and gameplay. Quality beats speed everywhere: a milestone that runs long is fine; a sloppy one is not.

### Principles

- **No deadlines.** Milestones end when their done-when criteria and the quality bar are met, never because time ran out.
- **Cut scope, never quality.** When a milestone grows, features move to the backlog; the remaining work is still finished properly.
- **"OK" is not done.** Work that merely functions gets revisited until it feels good to play and looks good on screen.

### Claude's self-critique loop (every task)

1. Implement the task with tests.
2. A separate Claude session with fresh context reviews it critically: bugs, edge cases, 1–4 player behaviour, performance, code clarity, and whether it is actually fun or good-looking.
3. Claude revises based on the critique. At least one revision round is expected; a first draft is rarely merged.
4. Only then do the checks run and the PR merge.

Weekly, Claude picks a recently finished feature and re-examines it critically (code, bot playtest data, player feedback). Anything that is only "OK" becomes a polish task.

### Bugs

- Every bug fix comes with a regression test that would have caught it.
- Each milestone ends with a **stabilisation phase**: no new features, only bug fixing, polish and performance, until open bugs in that milestone's scope reach zero known crashes and zero known blockers.
- A "Report a bug" issue form (with build version, steps and an optional screenshot); bug reports outrank new features in `NEXT.md`.
- Daily builds are labelled **nightly**. A build is promoted to **stable** (the default web demo and the itch.io/Steam default branch) only when it passes the quality gate: no known crashes, all tests green, benchmark within budget.

### Art and music

- `docs/STYLE.md` defines the art direction: palette, lighting direction, outline rules, animation frame counts, UI style, and a set of reference images for the intended look.
- Every asset has a quality tier in the manifest: `placeholder`, `good`, `final`. Nothing ships in Steam Early Access with `placeholder` in a player-facing spot.
- **Honest limit:** Claude's code-generated pixel art and chiptune are fine as placeholders and some final SFX, but professional-quality art and especially music need skilled humans. The plan is to attract artists and musicians through the contribute pages and, once there is income (Sponsors, itch.io, Steam), to commission key art, the main character, the tileset and the soundtrack.
- Claude reviews art critically against `STYLE.md` and asks for revisions rather than accepting "good enough"; music is judged by community votes plus technical checks.

### Making the art direction easy to see

- **Style Guide page** on the website, generated from `docs/STYLE.md` and linked from every art issue, the README and the Contribute page: an in-game screenshot of the look, palette swatches with downloads, sizes, the key rules (light from top-left, 1px dark outline, no gradients, max 3 shades per material), animated frame-count examples, do/don't comparisons, and the golden examples.
- **Golden examples:** a small set of approved `final` assets that are the official reference everything should match.
- **Starter kit** (one zip): palette files for Aseprite, LibreSprite, Photoshop and Krita; 32×32 grid templates and sprite sheet templates; golden examples as source files; a one-page checklist.
- **Art preview page** (runs in the browser, nothing uploaded): drop a PNG to see it in an in-game scene at real size next to the golden examples, with automatic palette, size and frame-count checks that highlight off-palette pixels. The same checks run on submission with the same messages.
- **Every art issue** shows the style guide link, the current placeholder, the 2–3 closest golden examples, size, frame count and the relevant rules.
- **Who sets the direction:** in M1 Claude drafts a provisional style and guide with code-generated assets. In M2 an art direction call in Discussions invites style samples (wizard, a tile, a spell icon); the community votes and the owner picks the winner, or commissions an artist. The chosen style becomes the golden examples and is locked in an owner-only part of `DESIGN.md` so it cannot drift.

### Gameplay

- Bot playtest data, player feedback and the fun rules in Game design decide whether something stays, gets reworked or gets cut.
- Features that don't earn their place are removed, even if they work.

## Security model

Security comes first: all outside input (PR code, PR text, issues, discussions) is treated as untrusted. Three rules make that hold.

1. **PR code never runs where secrets exist.** PR checks use the sandboxed `pull_request` trigger, with no secrets and a read-only token.
2. **The AI never holds the merge button.** Claude returns a verdict as data, and a plain script merges only if every hard rule also passes, pinned to the exact reviewed commit.
3. **Rules, not AI judgment, limit what can be merged.** Protected paths, banned APIs and file-type limits are enforced by a script, before and after the AI.

### Threats and defences

| Threat | Defence |
| --- | --- |
| PR steals the Claude token | Token lives in a protected GitHub Environment that only scheduled jobs on `main` can use. PR jobs never see it. |
| PR edits workflows, AI instructions or rules | Protected paths are rejected by the rules script; CODEOWNERS requires owner review, so the bot cannot merge them. The bot's GitHub App has no Workflows permission, so GitHub itself blocks it from changing workflow files. |
| Prompt injection in PR or issue text | Reviewer has read-only tools and no shell; verdict is advisory; issues only become work once Claude or the owner labels them. |
| Malware shipped to players | Banned in `.gd`, `.tscn` and `.tres`: `OS.execute`, `OS.create_process`, `OS.shell_open`, networking/HTTP, `JavaScriptBridge`, file access outside `user://`, GDExtension. Binaries banned. |
| PR changed after approval | Merge uses `--match-head-commit` with the reviewed SHA. |
| Supply chain | Actions pinned by commit SHA, Godot download hash-checked, no third-party addons unless the owner adds them, Dependabot for Actions. |
| Tampered downloads | Builds only from `main` in a clean job, SHA256 checksums, build attestations, immutable releases. |
| Spam and AI-slop PRs | Free rules filter first, size limit, per-author daily cap, capped AI reviews per day. |
| Owner account compromised | 2FA/passkey; no personal access token given to the AI; the bot acts through a custom GitHub App installed only on this repo, with only Contents, Issues and Pull requests access. |

### Path tiers

| Tier | Paths | Who may change |
| --- | --- | --- |
| Owner only | `.github/` (incl. `.github/maintainer/` prompts), `ci/`, `.claude/`, `docs/DESIGN.md`, `LICENSE`, `CLA.md`, `setup.sh`, `REUSE.toml`, `docs/SECURITY-CHECKLIST.md`, `docs/SETUP-APP.md`, `addons/` | Owner review required |
| Bot maintained | `docs/ROADMAP.md`, `docs/NEXT.md`, `docs/BACKLOG.md`, `docs/DECISIONS.md`, `docs/LOG.md`, `docs/milestones/`, `docs/STYLE.md`, `docs/STORY.md`, area `README.md` files, `AGENTS.md`, `CLAUDE.md`, `llms.txt`, `docs/cla-signatures.json`, `core/`, `project.godot`, `export_presets.cfg` | Claude's own PRs only |
| Open | Content areas that are open in the current milestone | Anyone, through the rating pipeline |

**Kill switch:** set the repo variable `AUTOMATION_ENABLED=false`, or disable the workflow in the Actions tab. The Control panel issue also has a kill-switch checkbox usable from the GitHub mobile app. Every bot action is posted to a pinned "Daily log" issue, and every merge can be reverted.

## Automation pipeline

Everything runs as GitHub Actions on GitHub's servers, free for public repos; no owner PC needs to be on. There are three workflows.

### Per PR (`checks.yml`, seconds, no secrets)

Runs only the hard rules check (see PR filtering). There is no build per PR: results show up in the next daily release.

### Daily run (`daily.yml`, 03:00 UTC, `main` only, has the Claude token)

1. **Triage** (script): close PRs that break hard rules, with a reason; auto-label by area and skill.
2. **Claims** (script): release claims older than 2 days with no PR.
3. **Rate** (Claude, read-only tools): score up to about 8 eligible PRs; post scores as a PR comment.
4. **Merge** (script): in score order, test-merge approved PRs together on a throwaway `staging` branch and run content validators there; merge each passing PR into `main`, pinned to its reviewed commit; skip failures and conflicts with a comment. The bot is never a bypass actor on `main`.
5. **Develop** (Claude): take the top task from `docs/NEXT.md`, implement it with tests, update the plan files, open its own PR, which merges the same day after all checks plus an independent fresh-context review. Further adaptive development sessions start hourly whenever quota allows (see Self-driven progress).
6. **Build and smoke test** (script): export the web demo and the full Windows and Linux builds, run the 1-player and 4-bot smoke tests and the stress benchmark (a frame-time regression over 10% also counts as broken). If broken, revert the day's merges newest first (through bot revert PRs) until it passes and comment on the culprit.
7. **Release** (script): tag the tested `main` as `v0.YYYYMMDD`, attach build and checksums with attestation, deploy the web build to GitHub Pages and itch.io, regenerate the Contribute page.
8. **Log**: post a summary to the Daily log issue.

### Weekly planning run (Sundays)

Runs bot playtests for the balance report, reads player feedback, reviews milestone progress against its done-when criteria, reorders `NEXT.md`, triages Discussions ideas into `BACKLOG.md` and replies to each, syncs issues and their labels (the project board follows labels). When a milestone is done, it writes the next milestone's design document, which must pass an independent self-critique review before merging.

### Limits

Each Claude step has a turn cap. If the Pro usage limit is hit, the step stops cleanly and resumes the next day. The scripts never depend on Claude succeeding, so releases still ship.

### Running unattended (verified in Anthropic and GitHub docs)

- Claude runs in automation mode of `anthropics/claude-code-action` on a cron schedule, authenticated with the Pro subscription token. Nothing runs on the owner's PC.
- Scheduled runs are attributed to the user who last changed the cron schedule. Only the owner can edit `.github/`, so that is always the owner.
- Claude's commits and PRs use the custom app's token, not the default workflow token, whose commits do not trigger other workflows.
- GitHub disables schedules in public repos after 60 days without activity. Daily commits keep the repo active, and if no commit lands for 14 days, the workflow opens an issue that emails the owner.
- If the subscription token expires or is rejected, Claude's steps fail cleanly, an issue asks the owner to regenerate it, and the scripted merge, build and release steps keep running.
- The Pro quota is shared with the owner's own Claude use.

## PR filtering and rating

A PR merges only after passing three filters, each cheaper than the next: free rules, then Claude's rating, then a merge script that re-checks everything.

### Filter 1: hard rules (script, instant, free)

Auto-closed with a reason if the PR:

- touches owner-only or bot-maintained paths
- uses banned APIs, or adds binaries or native code
- adds a file type outside the allowed set (images, `.ogg`, Godot text files, `.gd`, `.json`) or a file over its size limit (1 MB per sprite sheet, 5 MB per music track)
- has no CLA signature (one comment on the PR; unsigned PRs get a comment explaining how to sign and are closed only if still unsigned after 7 days, and are never merged unsigned), or a file without license info (REUSE check; one line in the template)
- comes from an author who already had 2 PRs closed that day (spam limit)

Hard rules are kept to security and copyright only. Everything else (PR size, touching several areas, an area not yet open, a missing description) is guidance handled kindly in the review: Claude writes a missing description itself and may still merge a good PR for an area that isn't open yet.

### Filter 2: Claude's rating (1–5 per criterion)

| Criterion | Question |
| --- | --- |
| Fit | Matches `DESIGN.md`, the current milestone and the no-waiting co-op pillar? |
| Fun | Creates interesting decisions, interactions or satisfying feedback, not merely correct? |
| Quality | Clean, typed GDScript, follows area patterns, tests where sensible? |
| Value | Makes the game better for players? |
| Performance | Stays within budgets (pools, projectile manager, particle limits, no per-frame allocations)? |
| Risk | Safe to merge? (5 = safe) |
| Scope | One clear thing? |

Each area adds its own questions (see Areas). Art is judged by looking at the images; audio by technical checks plus votes.

- **Merge:** average ≥ 3.5 and no criterion below 2, as long as any remaining issues are ones Claude can fix itself.
- **Request changes:** fixable PRs get concrete feedback and are re-rated after updates.
- **Close:** off-direction or low-value, with a polite reason.
- PRs that advance the current milestone are rated first.

### Review stance: open and helpful

- **Idea first, polish second.** A good idea with rough edges is a merge, not a rejection.
- **Merge and polish:** small issues (naming, wrong folder, missing manifest line, untyped variables, missing tests, a dependency warning) don't block a merge; Claude fixes them in its own follow-up PR the same day and credits the contributor.
- **Never relaxed:** security rules, copyright rules, the smoke test and performance budgets.
- **Change requests are short:** at most 3 concrete points, never nitpicks alone.
- **First-time contributors** get extra help and a warm welcome.
- Every review thanks the contributor and explains the decision in plain words.

### Community voting (scales with the community)

Votes are 👍/👎 reactions on art, audio and core gameplay PRs (the `gameplay/` sub-areas and spell components), and on the art direction call. The number of 👍 needed grows automatically with the number of active voters, so early on a couple of votes are enough and later a real share of the community must agree.

**Who can vote** loosens or tightens with the size of the community, just like the number of votes needed:

| Phase | When | Who can vote |
| --- | --- | --- |
| Open | Fewer than 20 active contributors | Any GitHub account older than 30 days with some public activity, so playtesters and followers can vote from day 1 |
| Community | 20 or more active contributors | Accounts that have taken part in the project at least 7 days before the vote: a merged contribution, an accepted bug report, or feedback and discussion posts |

**Active voters (N):** eligible accounts with any activity in the project (vote, PR, bug report, discussion post) in the last 30 days, recounted daily. The phase switches back to Open if active contributors drop below 20.

**Anti-gaming:** Claude may discount votes that look coordinated (for example many accounts with no prior activity voting on the same PR within minutes) and says so openly in the PR comment.

| Active voters (N) | 👍 needed | Notes |
| --- | --- | --- |
| 0–2 | none | Votes are advisory; Claude decides with its normal bar |
| 3–13 | 2 | |
| 14–20 | 3 | 15% of N, rounded up |
| 50 | 8 | |
| 100 | 15 | |
| 167+ | 25 | Cap, so votes stay reachable in a large community |

- **Approval:** 👍 reaches the needed number **and** at least 60% of cast votes are 👍. Claude's rating must still pass; votes can block or confirm, never force in something that breaks the rules.
- **Window:** 24 hours. If the needed number isn't reached, it extends once by 24 hours; after 48 hours Claude decides alone with the stricter bar (average ≥ 3.8), so nothing stalls. With 0–2 active voters there is no waiting at all.
- **Gameplay PRs show what they do:** a short GIF or video (or a clear description) is requested so voters can judge without building the game; Claude adds a plain-language summary of the gameplay effect.
- **Claude's own gameplay changes** still merge the same day, but are listed in that day's "Try this today" thread. If voters reach the needed number of 👎 with at least 60% 👎, Claude reworks or reverts the change.
- **Transparent:** the PR comment always shows the state, e.g. "4 👍 / 1 👎, needs 3 👍 (15% of 18 active voters), 14 hours left".
- **Tunable settings (Control panel):** `VOTE_SHARE` (15%), `VOTE_MIN` (2), `VOTE_MAX` (25), `VOTE_APPROVAL` (60%).

### Filter 3: merge script

Merges only if the verdict is merge, rules still pass, the head commit is unchanged, and content validators pass on `staging`. On conflicts, the higher-rated PR wins and the other gets a rebase request. A PR that breaks the daily smoke test is reverted automatically, with a comment explaining why.

## Game design

Spellmerge is a 2D top-down action roguelite where the build comes from spells you assemble mid-run, in the spirit of Noita's wands and Ember Knights' co-op.

### Pillars

1. **Deep spell building:** few components, many combinations.
2. **Nobody waits for anybody:** 1–4 players act independently at all times.
3. **A mix of tones:** a self-aware, slightly comic magic world with real stakes.
4. **Readable chaos:** 32×32 pixel art, clear telegraphs, player colours.

### Build elements

| Element | Role |
| --- | --- |
| Wizard | One base character; cosmetics only (hat, robe, colours, staff look). |
| Staff | Chosen before a run; sets the basic attack and a small bonus. |
| Spells | Built from form → element → modifiers → trigger; a trigger holds another spell. Limited by a complexity budget. |
| Relics | Passives found in runs, some altering how components behave. |

Starting components: forms (bolt, beam, nova, rune, orbit), elements (fire, frost, storm, void), modifiers (split, pierce, homing, chain, bigger, faster), triggers (on hit, on expire, timer).

### No-waiting co-op rules

1. No player controls another player's choices; there is no leader and no shared menu.
2. Menus are per-player overlays and never pause the game for others.
3. Rewards are rolled per player.
4. Unpicked rewards carry over as an unspent icon.
5. Shared decisions are made by walking (the door rule).
6. Only the real pause menu stops the game, and any player can open it.

### Spell builder and UI

- Each player has a corner panel in their colour. It expands toward the centre for the builder or rewards, never covers another panel, and fills the screen in single player.
- The builder is a slot chain navigated with d-pad or stick, with a bag of collected components, live stats (damage, mana, cast time, complexity bar) and a live mini-preview.
- **Full builder:** cleared rooms and the hub, no time limit.
- **During combat:** quick actions only (swap prepared spells, drop a component into a free slot).
- Gamepad first; P1 can also use keyboard and mouse, and the mouse only acts on P1's panel.

### Door rule

- All players at one door: go now.
- Majority at one door: 5-second countdown.
- Tie: one tied door picked at random after 10 seconds.
- Players still building (hammer icon) are waited for up to 20 seconds, then carried along with choices preserved.

### Co-op rules

Downed players can be revived. Enemy HP and count scale with player count. Friendly fire is an option. The camera is a single shared view that zooms out to fit everyone. A later idea is cross-player spell linking (one player's frost plus another's storm), done asynchronously with no waiting.

### Fun

Fun comes from proven design rules, bot playtesting that catches what kills fun, and real player feedback, which outranks Claude's own judgement.

| Rule | Concretely |
| --- | --- |
| Game feel from day 1 | Every hit has hit-stop, screen shake, knockback, particles and sound, starting in M1. |
| Meaningful choices | Every reward offers 3 options with trade-offs; synergy hints such as "Works with: Split, Chain". |
| Surprising combos | Components interact across systems (frost + storm = shatter); every new component needs at least 2 interesting interactions. |
| Growing power fantasy | Weak at the start, overpowered by the end; strong builds may break the game a little. |
| Short loops | Runs of 20–30 minutes, under 3 seconds from death to a new run, first room within 10 seconds of start. |
| Fair difficulty | Every attack is telegraphed and every death is understandable. |
| Discovery | A codex of found combos, secret interactions, unlocks through play. |

**Bot playtesting:** simple AI bots play hundreds of headless runs at high speed. A weekly balance report shows run length, win rate, death causes, dominant combos, dead content and damage spikes; the weekly planning run turns problems into tasks.

**Player feedback:** the end-of-run screen has a thumbs up/down and "What was fun?" button that opens a pre-filled GitHub Discussion (no tracking or network code in the game). Each daily release names a "Try this today" focus with a feedback thread.

## Codebase architecture and areas

The codebase is split into self-contained areas that talk only through `core/`, so contributors can add content by adding files, without touching shared code.

### Principles

1. **New content = new files.** A content registry discovers content by folder (from a manifest generated at build time), so no central lists need editing.
2. **Areas never call each other directly.** They communicate through an event bus (`spell_cast`, `enemy_died`, `player_downed`, `room_cleared`, ...). The HUD shows state from events and sends only player-intent events (a builder or menu choice, with the player index); gameplay decides what happens.
3. **Data-driven content.** Content is a `.tres` resource on a base class; code is needed only for new behaviour.
4. **No single "the player".** Every system takes a player index 0–3.
5. **Written contracts.** Each area's `README.md` states what it may depend on, what it must provide, and its file rules.

### Folder layout

```
spellmerge/
├─ core/             closed to outside PRs
│  └─ events/ registry/ input/ ui_focus/ save/ base/ projectiles/ pools/
├─ gameplay/         code systems, one sub-area each (see below)
│  └─ run/ flow/ player/ combat/ rewards/ difficulty/ coop/ ai/ feel/ progression/
├─ content/          one folder per item; its own art and sound live inside it
│  ├─ spells/        forms/ elements/ modifiers/ triggers/ + reactions.tres
│  ├─ relics/  enemies/  bosses/
│  ├─ wizard/        cosmetics/ staffs/
│  ├─ rooms/         one folder per biome
│  └─ story/         lore/ dialogue/ events/
├─ hud/
│  └─ panels/ builder/ menus/ widgets/ theme/
├─ art/              shared art only: tilesets/ ui/ vfx/ palette
├─ audio/            shared audio only: music/ sfx/
├─ tests/            mirrors the tree, plus smoke/ benchmark/ bots/
├─ tools/            asset generators, local check script
└─ docs/             design, plan and style files
```

### Areas

| Area | Contributors add | Allowed files | Extra rating questions |
| --- | --- | --- | --- |
| Spells | Forms, elements, modifiers, triggers | `.tres`, `.gd`, icon, SFX | Creative interactions, power budget |
| Relics | Passive items | `.tres`, `.gd`, icon | Build diversity, balance |
| Wizard | Cosmetics, staffs | `.tres`, `.gd`, sprites | Distinct look/playstyle, style guide |
| Enemies | Enemies, attack patterns | `.tres`, `.gd`, `.tscn`, sprites | Readable telegraphs, co-op scaling |
| Bosses | Bosses with phases | `.tres`, `.gd`, `.tscn`, sprites | Fairness, spectacle, 1–4 scaling |
| Rooms | Room templates | `.tscn` (tilemap), `.tres` | Space for 4, valid doors and spawns |
| Gameplay | Changes to one of the 10 gameplay sub-areas (below) | `.gd`, `.tres` | No-waiting pillar, no regressions |
| HUD | Widgets, menus, accessibility | `.gd`, `.tscn`, UI art | Readable with 4 players, gamepad navigation |
| Art | Sprites, tilesets, VFX | `.png`, `.svg` | `STYLE.md` palette, readability at 1× |
| Audio | Music, SFX | `.ogg` only | Format, loudness, length, plus votes |
| Story | Dialogue, lore, descriptions | `.json` | Fits `STORY.md` canon and tone |
| Core | (no outside PRs) | – | Outside PRs closed with "open an issue" |

### Structure rules

Code gets structure; content and assets stay flat and simple. Structure exists to keep the codebase tidy, not to make contributing harder: contributors get guidance, and Claude does the tidying.

| Folder | Structure | Why |
| --- | --- | --- |
| `core/` | Sub-folders per service | Closed to outside PRs; only Claude needs to navigate it |
| `gameplay/` | 10 sub-areas, each with a public entry script, README and mirrored tests | The most code, and the most likely to tangle |
| `hud/` | panels, builder, menus, shared widgets, theme | Widgets are reused across panels; one theme keeps 4-player UI consistent |
| `content/` | Flat: one folder per item, copied from an example | Easiest possible contribution: add a folder, done |
| `art/`, `audio/` | Shared assets only; item-specific assets live with the item | Contributors find an item's files in one place |
| `tests/` | Mirrors the tree | Easy to find the tests for anything |

### Gameplay sub-areas

| Sub-area | Job | Built | Open for PRs |
| --- | --- | --- | --- |
| `player` | Wizard controller: move, dodge, cast, mana, health, downed/revive | M1 | M4 |
| `combat` | Damage pipeline, hit/hurt boxes, knockback, status effects, applying element reactions | M1 | M4 |
| `feel` | Hit-stop, screen shake, juice presets | M1 | M4 |
| `coop` | Join/leave mid-run, friendly fire, shared camera | M1 | M4 |
| `ai` | Shared enemy behaviours: steering, targeting, attack patterns | M1–M3 | M3 |
| `run` | Run lifecycle: start, seed, end, summary screen | M3 | M5 |
| `flow` | Room sequence, door voting, transitions, waiting for builders | M3 | M5 |
| `rewards` | Per-player rolls from loot tables, unspent rewards, shops | M3 | M5 |
| `difficulty` | Scaling by player count, depth and setting | M3 | M5 |
| `progression` | Hub, unlocks, currency, codex | M5 | M6 |

- **Public interface:** each sub-area has one entry script (e.g. `combat/combat.gd`) plus the events it sends and listens to; other code uses only those.
- **One dependency direction:** `core` ← `gameplay` ← `content` data via the registry; sub-areas talk through events, with direct calls only in documented directions.
- **Data apart from rules:** element reactions and loot tables are content data, so contributors can add them without touching gameplay code.
- **Checked, but kindly:** the rules check reports dependency violations as warnings on outside PRs; Claude fixes them after merging. Claude's own code must follow them strictly.

### Asset origin manifest

`art/manifest.json` and `audio/manifest.json` list every asset with origin (`placeholder`, `ai`, `human`), author and license. Validators reject assets missing from the manifest. It drives Steam's AI disclosure and the auto-generated replacement issues.

### Co-op technology (built in M1)

- **Player manager:** devices join with a button press and each player gets their own device; P1 can use keyboard/mouse or a gamepad, P2–P4 gamepads (browsers support gamepads).
- **Per-player UI focus:** Godot has one global UI focus, so `core/` provides a focus system in which each panel takes input only from its owner. All UI widgets build on it.
- **Shared camera** fits all players.
- **4-bot smoke test**, including one bot that idles in the builder while the others must still progress.

## Performance

Performance is designed in from M1, with hard budgets checked every day, because spell chaos with 4 players is the game's heaviest load.

### Budgets

| Budget | Web demo | Full desktop build |
| --- | --- | --- |
| Frame rate | 60 FPS on a mid-range laptop in Chrome or Firefox | 60 FPS on a mid-range PC with a \~5-year-old GPU |
| Stress scenario | 4 players, 100 enemies, 1,000 projectiles, full effects | 4 players, 200 enemies, 3,000 projectiles, full effects |
| Load time | Under 10 s on normal broadband | Under 5 s from SSD |
| Download | Under 40 MB compressed | Under 300 MB |
| Memory | Under 512 MB | Under 1.5 GB |

### Architecture for speed

- **Projectile manager:** spell projectiles are not individual nodes; one manager simulates them in bulk and draws them in one batch.
- **Object pools** for enemies, effects and damage numbers.
- **Spatial grid** for collision lookups.
- **Spell limits double as performance limits:** caps on projectiles per cast, trigger depth and a global projectile cap; at the cap, effects degrade gracefully instead of lagging.
- **Typed GDScript required** (faster in Godot 4); the rules check rejects untyped code.
- **Web-friendly rendering:** Compatibility renderer, texture atlases, CPU particles with per-effect limits.
- **Settings:** effect quality, screen shake toggle, FPS display.

### Automatic checks (daily run)

- The stress scenario runs headless on GitHub's servers and measures game-logic frame time (the usual bottleneck).
- Frame time more than 10% worse than the 7-day average: the culprit PR is reverted, as with a broken build.
- Build size and load size are checked against budgets; content validators enforce particle counts and sprite sheet sizes.
- A trend chart is published on the Contribute page.
- GPU performance can't be measured on free runners; fixed draw limits and player-reported FPS cover it.

### Web demo and full build

Every daily release ships two builds from the same code:

| Build | Content | Where |
| --- | --- | --- |
| Web demo | A curated subset that fits the web budgets: first biome, a selection of spells and enemies | GitHub Pages and itch.io, playable in the browser |
| Full build | Everything | Windows and Linux downloads on GitHub Releases and itch.io; later Steam |

Each content item carries a `demo` flag, and Godot export presets with feature tags include or exclude it. Both builds are produced from M1, so the switch is ready before it's needed. The demo stays complete content while web budgets hold; when the full game exceeds them, the weekly planning run curates the demo subset automatically. Windows builds are unsigned at first, so Windows shows a SmartScreen warning until signing is added for Steam.

## Planning system

Claude has no memory between runs, so the repo is its memory: a fixed set of plan files means there is always exactly one clear next task.

| File | Holds | Changed by |
| --- | --- | --- |
| `docs/DESIGN.md` | Vision and pillars | Owner only |
| `docs/ROADMAP.md` | Linear milestones with done-when criteria | Claude |
| `docs/milestones/Mx-*.md` | Detailed design of the current milestone, written before any code | Claude (self-critiqued) |
| `docs/NEXT.md` | Ordered task queue; the top item is next | Claude |
| `docs/BACKLOG.md` | Ideas and future work outside the milestone | Claude |
| `docs/DECISIONS.md` | Why things were decided, so they aren't reversed by accident | Claude |
| `docs/LOG.md` | What each run did | Claude |

### Linear rules

- One milestone at a time; nothing from later milestones is built early.
- Each milestone goes design document → tasks → code.
- Discoveries go to the backlog unless they block the current milestone.
- Community PRs for future milestones are closed with thanks and saved as backlog issues.

### Autonomy

Claude runs fully on its own, including starting milestones. The safeguard is an independent self-critique: a second Claude review with fresh context checks each new milestone design against `DESIGN.md` for contradictions, scope creep and breaks of the no-waiting pillar. The owner gets a notification issue when a milestone starts and only acts to change direction.

## Self-driven progress

Claude's own development is the main engine and outside PRs are a bonus, so the game progresses at full speed even with zero contributors.

### Capacity

- **Adaptive sessions:** an hourly check starts a development session when `NEXT.md` has a task and no session is running; it costs nothing when there is nothing to do.
- **A session keeps working** while quota and tasks remain: when one session ends, the next starts right away, whether or not its PR merged. It stops on an error, a usage limit or paused merging, and the hourly check picks up from there.
- **Back-off:** when a usage limit is hit, it is recorded and hourly checks pause until the usage window resets (about 5 hours).
- **One session at a time** to avoid conflicts; parallel sessions in clearly separate areas are a later option.
- **Reviews are capped** at about 30% of the quota; unused review quota goes to development. PR reviews and the release run once a day at 03:00 UTC.
- **Pacing:** each run records its token usage. Each time a limit is hit, the bot learns how many tokens a full window and a full week hold, and stops at its DEV\_INTENSITY percentage of the window. The week is not gated by estimate: the bot just runs, and a weekly limit backs it off until the reset time the limit names. The daily log reports usage as percentages, e.g. "used \~62% of window budget, 41% of weekly share". These are estimates, since the exact remaining quota isn't available to automation.
- **More quota, more speed:** upgrading to Claude Max is used automatically with no changes.

| Control panel setting | Default | Effect |
| --- | --- | --- |
| `DEV_INTENSITY` | `90%` | Share of each \~5-hour usage window the bot may use; the rest stays free for the owner |
| `QUIET_HOURS` | Unset (no quiet hours) | Hours with no development sessions, e.g. `07-17` Danish time; set later by the owner |
| `WEEKLY_SHARE` | `90%` | Reported only: the Daily log shows usage as a share of this part of the learned weekly cap |

### Flow

- **Same-day merge of Claude's own PRs:** rules, tests, smoke test and benchmark, plus an independent review by a separate Claude session with fresh context. If all pass, it merges immediately and the next session builds on it.
- **Tasks sized to one session;** the weekly planning run splits larger ones.
- **Never stuck:** a task that fails twice or is reported blocked is set aside for a week with the reason logged, and work moves on to the next task; blocked tasks are revisited weekly. A task whose approved PR waits on GitHub or the owner is set aside for a day the same way.
- **Never waiting for humans:** unclear points are decided by Claude and recorded in `DECISIONS.md`; only `DESIGN.md` needs the owner.
- **Milestones never depend on contributors:** all content targets are planned as Claude's work, and a contribution simply removes a task.

### Measurement and alarms

- The daily log shows tasks done, PRs merged and progress against done-when criteria.
- No own PR merged for 3 days: an issue opens and the owner is emailed.
- A milestone running over twice its estimate: the weekly run cuts scope to the backlog rather than letting it drag.
- A weekly progress post in Discussions doubles as a devlog.
- About every 5th task is cleanup or polish (refactoring, docs, tests, game feel).

**Expected pace:** roughly 2–5 small-to-medium tasks a day including self-critique and revision. Speed is measured but never optimised at the cost of quality, and no timeline is promised.

## Owner control from the phone

Everything day-to-day can be controlled from the GitHub Android app; no PC is needed after setup.

### GitHub app

Push notifications (daily log, stall alarm, token alarm, copyright reports); read, comment on, approve, merge or close PRs and issues; see and re-run workflow runs; download releases or open the web build.

### Control panel issue

A pinned issue that every run reads before starting. Edits take effect from the next run (at most an hour later).

```
SPELLMERGE CONTROL PANEL

- [x] Automation enabled     (untick = full stop, the kill switch)
- [ ] Pause development      (still review PRs and release, build nothing new)
- [ ] Pause PR merging

DEV_INTENSITY: 90%
WEEKLY_SHARE: 90%
QUIET_HOURS:
VOTE_SHARE: 15%   VOTE_MIN: 2   VOTE_MAX: 25   VOTE_APPROVAL: 60%
FOCUS: (optional, e.g. "fix bugs before new features this week")
```

- **Verified by user ID:** runs only trust panel values from a revision whose editor is the owner's fixed numeric GitHub user ID (not the username). The bot never edits the panel.
- **Trusted values come from GitHub's own edit history** (the owner's latest revision), never from storage the bot could change.
- **Fail closed:** if no owner revision can be verified (history deleted, API error), automation pauses and the owner is notified.
- **Strict parsing:** numbers are capped to valid ranges, unknown fields are ignored, unreadable values fall back to the owner's last verified revision.
- **Locked issue:** only the owner can comment on the panel; the panel holds only harmless settings, never secrets.
- **Audit:** every applied change is written to the daily log, e.g. "DEV_INTENSITY 90% → 50% (by peterdk31)".
- **Worst case** of a successful attack on the panel: the bot pauses or changes pace; it cannot touch code, secrets or releases.

### Owner commands in comments

Comments by the owner's user ID on any issue or PR are carried out by the next run, but only if the comment was never edited by anyone else. Commands from anyone else are ignored and never treated as instructions. `/merge` cannot merge PRs that touch protected paths; those still need the owner's approval in GitHub itself.

| Command | Effect |
| --- | --- |
| `/merge`, `/close` | Override Claude's decision on a PR |
| `/revert` | Roll back a merged PR |
| `/priority` | Put this issue at the top of `NEXT.md` |
| `/claude <text>` | Free-text instruction, e.g. "make frost slow enemies a little more" |
| `/ask <question>` | Claude replies in the thread |
| `/pause`, `/resume` | Same as the panel checkboxes |

`/claude` instructions follow the same rules as all of Claude's work: they cannot change protected paths or override security, copyright or quality rules.

### Claude app

The Claude Android app (private account) is for discussing ideas and design. Recent versions can also start cloud Claude Code sessions on the repo for larger interactive work.

## Roadmap

The game is built in eight strictly sequential milestones. Art and Audio open to contributors from M1, and every area is open by M6.

| # | Milestone | Content | Done when | Opens for PRs |
| --- | --- | --- | --- | --- |
| M0 | Foundation | Full infrastructure: security, releases, autonomy, owner control, contribution pipeline, voting, onboarding; empty game | 3 daily releases in a row work and every pipeline part passes its dry run | No areas yet |
| M1 | Core loop prototype | 1 spell, 1 enemy, 1 room, 4-player join, game feel, pools | 4-bot smoke test passes on web | Art, Audio |
| M2 | Spell system | Components, spell builder, spell limits, stress benchmark | Validators pass, 20+ combos work | Spells, Story |
| M3 | Run structure | 5 rooms, 3 enemies, boss, relics, staffs, bot playtests | A full run can be completed | Rooms, Enemies, Bosses, Relics, AI |
| M4 | Polish and variety | HUD polish, cosmetics, story intro, more content | Polished enough to show off | HUD, Wizard, core gameplay systems |
| M5 | Meta-progression | Hub, unlocks, saving | Runs give lasting progression | Run, flow, rewards, difficulty |
| M6 | Content expansion | 2 more biomes, more bosses, Steam Coming Soon page | 3 biomes, 3 bosses, Steam page | All areas |
| M7 | Early Access ready | Desktop exports, Steamworks, settings, polish | Ready to launch on Steam | Steam Early Access launch |

An area that is not yet open still has folders, contracts and Claude's example content from M1, so contributors can study it before it opens.

## Infrastructure, checkpoints and playtests

The full infrastructure is built first, because it is what makes an AI-run community project work; the core must then prove it is fun before content is scaled up, and the owner's weekly playtest supplies the human taste Claude cannot.

### Infrastructure first (M0)

M0 builds the complete infrastructure before any gameplay, in this order:

1. **Security:** rules check, protected paths, custom app, protected environment, REUSE license check.
2. **Build and release:** CI, daily release (web demo + desktop), smoke test, nightly/stable channels.
3. **Autonomy:** plan files, hourly adaptive development sessions, Daily log issue, stall and token alarms.
4. **Owner control:** full Control panel and owner commands.
5. **Contribution pipeline:** PR rating and merge pipeline, CLA, PR template, issue templates and no-git submission forms, claims, labels and project board.
6. **Community:** scaling community voting (dormant until there are voters), Discussions categories, copyright report form and quarantine, bug report form.
7. **Onboarding:** AGENTS.md, CLAUDE.md, llms.txt, CONTRIBUTING.md, area READMEs, local check script, Contribute page.

Every part is verified end to end with dry runs (for example a fake PR that breaks a rule, a fake vote, a fake copyright report) before M0 counts as done. Only the parts that need a working game come later:

| When | What |
| --- | --- |
| M1 | Provisional Style Guide page and starter kit (first art exists); weekly owner playtest starts |
| M2 | Stress benchmark (spells exist), art direction call |
| M3 | Bot playtesting and balance report (full runs exist) |
| M6 | Steam page, trademark search |

### Go/no-go checkpoints

| Checkpoint | Question | Decided by |
| --- | --- | --- |
| C1: end of M1 | Do moving, dodging and casting feel good, alone and with 4 players? | Owner, with Claude's assessment |
| C2: end of M2 | Is building spells fun and deep, with surprising combos? | Owner, with bot data and player feedback |
| C3: end of M3 | After one full run, do you want to play another? | Owner, with player feedback |
| C4: before the Steam page | Is the art, sound and polish good enough to show the world? | Owner |

- Possible verdicts: **go** (next milestone), **iterate** (rework the weak parts, at most 2 rounds), or **pivot** (change the core mechanic or cut scope).
- After 2 failed iteration rounds the answer is a pivot, not a third round of the same thing.
- Claude prepares each checkpoint as an issue with a build link, its own honest assessment and the questions. If the owner doesn't answer within 7 days, Claude defaults to **iterate** so nothing stalls.
- Content expansion (M6) only starts after C3 says the core is great.

### Owner's weekly playtest

- Every Sunday the weekly planning run opens a "Playtest of the week" issue: the build link, what changed, and 3–5 specific questions (for example "does the new dodge feel responsive?").
- About 30 minutes of play, answered in a few lines from the phone.
- The owner's feedback is the highest-priority input on feel, fun and direction; community votes decide on individual contributions.
- A skipped week blocks nothing.

### Scope

Small and excellent beats big and mediocre. The first real target is one biome, a great spell system and solid 1–4 player co-op. Everything beyond that is earned by passing the checkpoints.

## Contributor experience

Contributors always see what is wanted now, what is coming next, and who is working on what, through issues, a project board and a Contribute page that are all kept up to date automatically.

**Principle: contributing must stay easy.** Hard rules exist only for security; everything else is guidance, and Claude polishes good-but-imperfect PRs itself.

### Contributing without git

Artists, musicians and writers can contribute through GitHub issue forms ("Submit art", "Submit sound", "Submit writing", "Spell idea") by uploading a file and filling in a few fields, including a CLA checkbox. A script validates and re-encodes the file (type, size, PNG/OGG only), and Claude opens the PR with the contributor credited as co-author.

### Issues as the task list

Every task is an issue with the same template: milestone, area, skill, size, what, where (exact path), specs, an example file to copy, the current placeholder, and done-when criteria.

| Label group | Values |
| --- | --- |
| Status | `now` (PRs welcome) · `soon` (next milestone, discuss) · `later` |
| Area | `area:spells`, `area:art`, ... |
| Skill | `code` · `pixel-art` · `music` · `sfx` · `writing` · `level-design` |
| Size | `good first issue` · `S` · `M` · `L` |

### Tasks generated from the game

- Each placeholder asset in the manifest becomes a "Replace placeholder" issue with preview and specs.
- Each event without sound becomes an SFX issue.
- Each item without lore or a description becomes a writing issue.
- Content the milestone document asks for that doesn't exist yet becomes an issue.
- At most about 10 open issues per area; new ones are created as others close.

### Claims

- Comment `/claim` and a script assigns the issue.
- Claims last **2 days** without a PR (reminder after 1 day).
- Expired claims reopen, or Claude takes the task if it has capacity that day.
- Claude's own tasks are labelled `claude:working`; Claude never takes a claimed task.

### Project board views

Now · one view per skill (artists, musicians, writers, coders) · Good first issues · Roadmap timeline · In progress.

The board is owned by `peterdk31`, and GitHub Apps can't edit user-owned projects, so GitHub's built-in auto-add workflow fills it and the views filter by label. The bot keeps labels correct and never edits the board directly.

### Contribute page

The GitHub Pages site is rebuilt daily and shows: play today's build, current milestone progress, wanted-now counts per skill, coming-next with links to design docs, recently merged, and top contributors. The game's main menu has a Contribute button and a credits screen.

### Discussions

GitHub Discussions has Ideas, Spell combos and Art feedback categories. The weekly run triages ideas into the backlog and replies to each. Discussion text is treated as suggestions only and never triggers actions.

## AI-friendly onboarding

Many contributors will point their own AI agent at the repo, so every doc is written to be read by both people and agents, and agents can check their work locally against the same rules CI uses.

| File | Purpose |
| --- | --- |
| `AGENTS.md` | The contributor guide for any coding agent (the cross-tool convention): project summary, hard rules, how to find a task, how to validate, PR format, what gets rejected. |
| `CLAUDE.md` | One line that imports `AGENTS.md`, so Claude Code picks it up automatically. |
| `llms.txt` | Index of all docs with one-line descriptions, for agents and LLM tools. |
| Area `README.md` | Same fixed sections in every area: Purpose · Contract · Allowed files · Steps · Example to copy · Validate · Rating questions. |
| `docs/STYLE.md` | Machine-checkable specs: palette hex list, sprite sizes, frame counts, audio format and loudness targets. |
| `CONTRIBUTING.md` | Human-friendly version: rules, rating, CLA, AI disclosure. |

### Making agent PRs succeed the first time

- **Local check:** `tools/check.sh` runs the same rules and content validators as CI, with error messages that say exactly what to fix and where.
- **Typed content:** every content type has a base class with documented fields; validators reject missing or out-of-range values.
- **Copy-paste task brief:** every issue ends with a "Brief for your AI" block containing the task spec, paths, constraints and done-when criteria.
- **PR template:** required fields for issue link, area, asset origin (`ai` or `human`), and "ran `tools/check.sh`".
- **Godot gotchas spelled out:** commit `.uid` files, scenes as text (`.tscn`), no editor-only plugins.
- **Guidance:** keep PRs focused, no refactors outside the task, no `core/` changes, small PRs are reviewed fastest. These are guidance, not hard rules.
- **Actionable rejections:** rejection and change-request comments follow a fixed format (rule, file, line, fix) so an agent can iterate on them.

### Security

`AGENTS.md`, `CLAUDE.md`, `llms.txt` and area READMEs are bot-maintained, so outside PRs cannot change them. The maintainer's own instructions live separately in owner-only `.github/maintainer/`. Instructions inside a PR are never followed by the reviewer.

## Monetization and licensing

The plan follows the Mindustry model: free and open source on GitHub and the web, paid on Steam for convenience and to support development. The brand, not the code, is what protects the income.

### Revenue path

| Phase | When | What | Income |
| --- | --- | --- | --- |
| Free web | From M1 | Daily web build on GitHub Pages and itch.io | itch.io name-your-price, Ko-fi, GitHub Sponsors |
| Steam page | M6 | "Coming Soon" page to collect wishlists | – |
| Early Access | M7 | Steam Early Access at about $5–8; nightly beta branch, weekly stable default branch | Main income |
| Full release | Later | Soundtrack, supporter pack DLC | Extra |

The web demo stays free, and daily desktop builds stay free on GitHub Releases, as with Mindustry; Steam sells convenience, automatic updates, achievements and supporting the project. No ads or microtransactions. The "built and maintained by an AI with community PRs" story is the marketing hook.

### Protection

- **Code: GPL-3.0.** Anyone selling a fork must publish its source.
- **Assets: CC-BY-SA 4.0.** Music or key art can be kept proprietary if commissioned.
- **CLA** (`CLA.md`, adapted from the Apache Individual CLA, checked in Filter 1): lets the owner also license contributions under other terms, which a future console port needs. No third-party CLA service is used, so no outside service holds a token for the owner's account.
  - **Signing:** the contributor comments `I have read the CLA and I agree to it.` on their PR once; for no-git submissions, the CLA checkbox in the issue form counts.
  - **Record:** the daily run stores each signature in the bot-maintained `docs/cla-signatures.json` (numeric user ID, login, CLA version, link to the comment or issue, date). A new CLA version needs a new signature.
- **Trademark "Spellmerge"** once there is traction (EU trademark about €850). It is the real moat, since mostly AI-generated code has weak copyright protection.

### Fair deal for contributors

The README states "Free on the web forever; the Steam version funds development." Every merged contributor gets a free Steam key, a place on the in-game credits screen, and top contributors may name a spell.

### Checks before selling (not legal or tax advice)

- [ ] Employment contract: side-business and IP clauses
- [ ] Tax registration once revenue starts (e.g. a Danish sole proprietorship)
- [ ] Steam AI-content disclosure (generated from the asset manifest)
- [ ] Anthropic's current terms for commercial use of output

## Copyright and licensing

Copyright infringement is treated like a security risk: when in doubt, leave it out. Rules are strict but cost contributors one line, and disputed content never ships.

### Rules (hard, checked automatically)

| Kind | Allowed | Never allowed |
| --- | --- | --- |
| Code | Original, or MIT, BSD, Apache-2.0, GPL-3.0-compatible | Unknown origin, incompatible licenses, closed-source code |
| Art, audio, text | Original, or CC0, CC-BY 4.0, CC-BY-SA 4.0 | Non-commercial, no-derivatives, personal-use-only, ripped game assets, fan art of other IP |
| Fonts | OFL | Any other font license unless the owner approves |
| AI assets | Tools whose terms allow commercial use; tool and prompt recorded | Prompts naming living artists or existing franchises |
| Names and text | Generic names (Fireball, Frost Nova) | Names from other works (Hadouken, Avada Kedavra) |

- **Every file carries license info** following the REUSE standard; `reuse lint` runs in the rules check. For contributors it is one line in the PR template or issue form; Claude fills it in for its own files.
- **The origin manifest records** author, license, source link, and for AI assets the tool and prompt.
- **The CLA includes a statement** that the contributor has the right to submit the work.

### Checks in review

- **Code:** ScanCode finds license texts and known copied code; Claude flags code that looks pasted from elsewhere.
- **Images:** Claude inspects every image for known characters, logos or game sprites.
- **Names and text:** checked against well-known brands and works.
- **Audio:** license rules and community votes; audio fingerprinting (e.g. AcoustID) only if its terms allow commercial use, to be confirmed.
- No automated check catches everything, which is why fast response matters.

### Response to a concern

- A "Report a copyright concern" issue form, plus a contact address in the README and the game; GitHub's DMCA process also applies.
- On a report, the asset is quarantined automatically: replaced by a placeholder and excluded from the next build while it is investigated.
- If copying is confirmed, the asset is removed, the contributor's other submissions are re-reviewed, and the contributor may be blocked.

### Third-party parts and credits

- Dependencies come only from an allowlist of licenses compatible with GPL-3 and Steam; adding one needs owner approval (protected paths).
- A credits screen and `LICENSES/` folder are generated from the manifest, including the license notices Godot requires.
- Claude's own assets are generated from code (procedural pixel art, synthesised sound), and its own code is written fresh, not copied in.
- The weekly report includes license status: files without license info must always be 0.

### Name check

A first web search (October 2026) found no game or trademark named "Spellmerge"; the name exists only as an unrelated [GemStone IV player script](https://gstowncrier.com/knowledge-base/repospotlight-for-spellmerge/) and a [Stata utility](http://fmwww.bc.edu/RePEc/bocode/s/spellmerge.html). "Spell merging" is also a generic mechanic description used by other games.

- [ ] Formal trademark search in EUIPO and USPTO registers before the Steam page (M6)

No lawyer review is planned; the CLA uses a widely used standard text instead.

## Costs and owner setup

Running costs are about $20/month (Claude Pro), and setup takes about 20 minutes, done once.

| Item | Cost |
| --- | --- |
| Public repo, Actions, Releases, Pages, Discussions, Projects | Free |
| Godot, GUT tests, export templates | Free |
| Claude Pro | About $20/month |
| Steam Direct (at M6–M7) | $100 once, recouped after $1,000 revenue |
| EU trademark (optional, later) | About €850 |

### Hosting limits (verified October 2026)

| Service | Free terms for public repos | Design choice |
| --- | --- | --- |
| Actions | Standard hosted runners free, no minute cap; larger runners always billed | Workflows pinned to `ubuntu-latest` only |
| Releases | Under 2 GiB per file, 1,000 files per release, no total size or bandwidth limit | Builds published only as Releases; temporary Actions artifacts deleted after 1 day |
| Pages | 1 GB site, soft limit of 100 GB bandwidth/month (about 2,500–10,000 plays); not for sites primarily facilitating commercial transactions | Web build published to both Pages and itch.io from day 1; if bandwidth grows, play moves to itch.io and Pages keeps the Contribute page; no sales on Pages |
| Git LFS | Small free quotas, consumed by CI checkouts | Not used: assets live in the repo with per-file size limits and `.ogg`-only audio |

Actions artifact and cache storage terms for public repos were not confirmed in the docs; the 1-day artifact cleanup avoids depending on them.

### Setup steps

1. Turn on 2FA or a passkey on GitHub account `peterdk31`.
2. Buy Claude Pro and install Claude Code.
3. Run `gh auth login`.
4. Run `./setup.sh` (written by Claude). It creates `peterdk31/spellmerge` and applies all settings as code: rulesets, CODEOWNERS enforcement, read-only default workflow token, protected environment, Pages, Discussions, labels, project board and immutable releases. Discussions categories and project views have no API and are created by hand once (setup.sh lists them); `./setup.sh --check` verifies the live settings at any time.
5. Create the custom "Spellmerge Bot" GitHub App following `docs/SETUP-APP.md` (about 5 minutes): permissions Contents, Issues and Pull requests only, with no Workflows permission. Store its app ID and private key as secrets in the protected environment.
6. Run `claude setup-token` and store the token as the `CLAUDE_CODE_OAUTH_TOKEN` secret in the protected environment.
7. Create a free itch.io page with an API key stored as a secret in the protected environment.
8. Check the settings against `docs/SECURITY-CHECKLIST.md`.

After that, the first daily run starts M0 automatically.

## Risks and open questions

The biggest risks are Pro usage limits and slow quality drift; both have fallbacks that need no redesign.

| Risk | Mitigation |
| --- | --- |
| Pro limits too tight for daily dev plus reviews | Cap reviews per day; prioritise milestone work; switch to a pay-per-use API budget if needed. |
| Subscription token expires, is rejected in CI, or terms change | Failure opens an issue to regenerate the token; scripted steps keep shipping; check Anthropic's terms at setup; switching to an API key is a one-line change. |
| Code quality drifts over months | Tests and validators for every content type, weekly self-review of `DECISIONS.md`, refactor tasks added to `NEXT.md` when needed. |
| Residual prompt injection gets a weak PR merged | Hard rules limit the damage to game content; daily smoke test; one-click revert. |
| Players or contributors dislike AI-made games | Full transparency in README and on Steam; human assets credited. |
| Web export limits (single-threaded build, browser gamepad quirks, performance) | Web build becomes a curated demo via content flags; the full game ships as daily desktop builds; performance budgets checked daily. |
| Spam waves | Rules filter, per-author caps, and GitHub's option to limit PRs to prior contributors. |

### Open questions

- [ ] Start date for M0 (the day `setup.sh` runs)
- [ ] Steam Early Access price, decided at M6

## Sources

- [GitHub: 2026 pricing changes for GitHub Actions](https://github.com/resources/insights/2026-pricing-changes-for-github-actions)
- [GitHub Docs: GitHub Pages limits](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits)
- [GitHub Docs: About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)

* [Claude Code Docs: GitHub Actions](https://code.claude.com/docs/en/github-actions)
* [GitHub Docs: Disabling and enabling a workflow](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-workflow-runs/disabling-and-enabling-a-workflow)
* [claude-code-action setup guide](https://github.com/anthropics/claude-code-action/blob/main/docs/setup.md)
