# M1: Core loop prototype

**Goal:** prove the core is fun before anything is scaled up (docs/PLAN.md, "Roadmap" and "Go/no-go checkpoints"). One spell, one enemy, one room and 1–4 players joining on their own devices, with game feel, pools and performance budgets built in from the start. Moving, dodging and casting must feel good alone and with four players, and nobody ever waits for another player (docs/DESIGN.md, pillar 2). M1 also gives Art and Audio contributors their first working ground: a provisional style, placeholder assets and examples to copy.

**Done when:**

1. The 4-bot smoke test passes on web, including one bot that idles in a per-player overlay while the others progress.
2. M0's carried-over dry runs all pass ([M0's list](M0-foundation.md#dry-runs); owner-run, results in `docs/LOG.md`).
3. 3 daily releases in a row work.
4. The stabilisation phase is over: no known crash or blocker in M1's scope.
5. Checkpoint C1 has a verdict (below).

**Opens for PRs:** Art and Audio, from the start of M1. All other areas stay closed; a good PR there may still merge, but it is a gamble.

## Who builds what

- **Claude** builds everything in bot-maintained and open paths: `core/`, `gameplay/`, `hud/`, `content/`, `art/`, `audio/`, `tests/`, `docs/`, `project.godot`, `export_presets.cfg`. One task is one session and one PR.
- **The owner** makes the changes that need owner-only paths, because sessions can't write to `.github/`, `ci/` or `tools/`: the web run of the 4-bot test (`ci/smbot/websmoke.py`), the Style Guide page and starter kit build (`ci/smbot/site.py`), the run of the carried-over dry runs, and the verdict at C1. Where a task needs one of these, the task says so and files it in "Needs an owner decision" in `docs/BACKLOG.md`; the rest of the queue goes on meanwhile. The owner is also told directly: when the part before an owner-only step starts (the web run, part 19; the kit page, part 20), Claude opens one issue labelled `owner` that lists the exact change and why it is needed, and the weekly run repeats the request in its report each Sunday until it is done. If the owner still hasn't acted when stabilisation (part 21) is reached, stabilisation goes on with bug fixing and polish, the C1 issue is opened anyway with the open owner items listed at the top, and done-when items 1 and 4 stay open; nothing is hidden or marked done.
- **The community** (Art and Audio) adds assets by the normal pipeline. The weekly planning run turns the art and sound needs of this milestone into issues labelled `now`, each with a "Brief for your AI".
- **Weekly owner playtest:** from the first Sunday after the HUD is in (part 15), when moving, dodging, casting, feel, the co-op camera and the HUD all exist (part 12 is only the first internal playable build), the weekly run opens a "Playtest of the week" issue with the build link and 3–5 specific questions about feel. The owner's answers outrank everything else on feel and fun. A skipped week blocks nothing.

## Design decisions for M1

These fill in what the plan leaves open (also recorded in `docs/DECISIONS.md`).

- **Events:** `core/events` is one autoload with a typed signal per event. Every per-player event carries the player index as its first argument. Event names follow `gameplay/README.md`, "Events at a glance"; when `core/events` exists it becomes the single source and the READMEs are fixed to match it.
- **Scenes:** the ten `gameplay/` sub-areas, `content/spells/` and `content/wizard/` do not allow `.tscn`; `hud/`, `content/enemies/` and `content/rooms/` already do. M1 scenes therefore live with their content: the wizard in `content/wizard/base/` (part 8 adds `.tscn` to that README's allowed files), the enemy in `content/enemies/`, the room in `content/rooms/`, HUD scenes in `hud/`. `gameplay/` stays script-only, and part 8 updates the allowed-files paragraph of `gameplay/README.md` to say so, since it promised that M1 would decide. Gameplay scripts get scenes through `core/registry`.
- **Registry:** in M1 it scans the content folders when the game starts. The build-time manifest the plan mentions is an optimisation for later, once content is large enough to need it.
- **The one spell** is a fire bolt, a `.tres` on a small base class in `core/base/`. M2 replaces it with the full component system and migrates this spell. To keep that true, the player and the bots only call one cast method and read none of the spell's fields (a done-when line of part 10); a test fails if a script outside `content/spells/` and `core/base/` reads them.
- **Arena glue:** a minimal slice of `flow` loads the room, spawns the wave, and announces `room_entered` and `room_cleared`; it restarts the room when all players are down. M3 replaces it with the real room sequence, door voting and run lifecycle. There is no pause menu in M1 (it belongs to `run`, M3).
- **Placeholder art** is hand-written SVG pixel art (rects on a 32×32 grid), because sessions have no image tools. It is listed in the manifest as `origin: "ai"`, tier `placeholder`, with tool and prompt.
- **Placeholder sounds** are not made by Claude sessions, which can't produce `.ogg`. Sounds are the Audio contributors' job: the weekly planning run opens `now` issues for the cast, hit and enemy-death sounds, with exact paths. Until a sound exists the code treats a missing sound as silent (the player, part 8, and feel, part 13, play nothing), and nothing may fail because of one. The Audio README's example is the first merged contributor sound.
- **First example paths** are fixed so no session has to guess: enemy `content/enemies/ember_imp/`, biome `content/rooms/crypt/` with the room `arena_01.tscn`, tiles `art/tilesets/crypt/`, effects `art/vfx/`, the wizard `content/wizard/base/`, the bolt `content/spells/forms/bolt/`, feel presets `gameplay/feel/presets/` (created by part 13, which then updates the README).
- **Player scaling** (enemy HP and count by player count) belongs to `difficulty` in M3. The M1 room has a fixed wave sized for four players, to be tuned at C1.

## Parts, in build order

Each part ends with tests and a green `tools/check.sh` and `ci/build/build.sh --quick`. `docs/NEXT.md` has them as sessions. Each is sized for one session and one PR, so a session that runs short stops at a part boundary and never leaves half-merged state.

| # | Part | Delivers |
| --- | --- | --- |
| 1 | **Event bus and base classes:** `core/events`, `core/base` | The events autoload with typed signals and the player index first; the small spell, enemy and room base resources; tests |
| 2 | **Event lists reconciled** (docs only) | `core/events` becomes the single source; the "Events at a glance" table and every area README's event list are fixed to match, "provisional" marks removed |
| 3 | **Style document** (Art and Audio are already open) | `docs/STYLE.md`: palette, light, outline, shades, frame counts and the 32×32 grid; listed in `llms.txt` |
| 4 | **Placeholder art:** `art/`, `content/wizard/base/`, `content/enemies/ember_imp/` | Floor and wall tiles, a wizard idle sprite in four player colours, the enemy sprite, the bolt and a hit spark as SVG, with manifest entries; the Art README's example filled in. No sounds (see decisions) |
| 5 | **Input and per-player focus:** `core/input`, `core/ui_focus` | Join by button press, one device per player (P1 keyboard and mouse or gamepad, P2–P4 gamepads), virtual devices for bots, and focus that each panel takes only from its owner |
| 6 | **Pools and projectiles:** `core/pools`, `core/projectiles` | Pools with no per-frame allocation, the bulk projectile manager with a spatial grid, a global projectile cap that degrades gracefully, and `projectile_hit` events |
| 7 | **Registry:** `core/registry` | Folder discovery, literal-path loading everywhere else |
| 8 | **Player:** `gameplay/player` and the wizard scene | Move, dodge, cast through one spell method, mana, health, downed and revive, for indices 0–3; the allowed-files updates in the wizard and gameplay READMEs |
| 9 | **Combat and the enemy:** `gameplay/combat`, `gameplay/ai`, `content/enemies/ember_imp` | The damage pipeline, hit and hurt boxes, knockback, `damage_dealt` and `enemy_died`, one telegraphed enemy |
| 10 | **The fire bolt and projectile hookup:** `content/spells/forms/bolt` | The bolt as a `.tres`, fired through the pools and the projectile manager, hitting through the damage pipeline; the player and bots call one cast method and read no spell fields |
| 11 | **The room:** `content/rooms/crypt` | One room with space for four, spawn points and doors, as a scene with layout only |
| 12 | **Arena glue:** the `flow` slice and a menu button | Load the room, spawn the wave, `room_entered` and `room_cleared`, restart in under 3 seconds, the first room within 10 seconds of start, a Play button; the first internal playable build (no owner playtest yet) |
| 13 | **Feel:** `gameplay/feel` | Hit-stop, screen shake, hit particles and optional sound on every hit; the per-effect particle limit constant with its test; a setting to turn shake off |
| 14 | **Co-op:** `gameplay/coop` | Join and leave mid-run, friendly fire option, the shared camera that zooms out to fit everyone |
| 15 | **Per-player HUD:** `hud/panels`, `hud/theme` | A corner panel in each player's colour (health, mana, an overlay that never pauses anyone) and the single theme; **the weekly owner playtest starts after this part** |
| 16 | **Bots and the 4-bot smoke test:** `tests/bots`, `tests/smoke` | Four bots on virtual devices play the room; one idles in its overlay; all others must still clear it. Runs in the editor |
| 17 | **The 4-bot test in the Linux export** | The same test run in the Linux export through `ci/build/build.sh`; any owner-only change is filed in `docs/BACKLOG.md` |
| 18 | **Performance probe and budgets:** `tests/benchmark` | A probe that logs frame time and node, projectile and memory counts in the 4-bot run and reads the particle limit from part 13. It gates nothing yet; the gating stress benchmark arrives in M2. Build size and load time are checked against the budgets |
| 19 | **The web 4-bot run** | The owner-only change to `ci/smbot/websmoke.py`, then the same test passing in headless Chrome |
| 20 | **Starter kit sources and Style Guide content** | The kit's source files (palette files, grid and sheet templates, golden-example candidates, checklist) in `art/`, and the owner-only build of the page and zip |
| 21 | **Stabilisation and C1** | Only bug fixing, polish and performance until no known crash or blocker remains; then the C1 issue with a build link, Claude's honest assessment and questions |

Parts 3 and 4 come early on purpose: outside Art and Audio PRs are possible from day one, and they need the style and the examples. The owner's work in parts 19 and 20 waits on the owner, so the queue never blocks on it.

## Checkpoint C1

The question is: do moving, dodging and casting feel good, alone and with 4 players? The owner decides, with Claude's assessment from bot logs, the weekly playtest answers and player feedback. Verdicts: **go** (M2 starts), **iterate** (rework the weak parts, at most 2 rounds) or **pivot**. The owner has 7 days to answer; if they don't, Claude defaults to iterate so nothing stalls (docs/PLAN.md, "Go/no-go checkpoints").

## Out of scope

The spell builder, spell components beyond the fire bolt and the spell limits (M2); the gating stress benchmark and the art direction call (M2); several rooms, door voting, the run lifecycle, rewards, relics, staffs, bosses and the pause menu (M3); enemy scaling by player count (M3); bot playtesting and balance reports (M3); HUD polish and cosmetics (M4); saving and the hub (M5). Cross-player spell linking stays in the backlog. Feedback links that open a browser need an owner decision first (`docs/BACKLOG.md`), so M1 has none.
