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
- **The owner** makes the changes that need owner-only paths, because sessions can't write to `.github/`, `ci/` or `tools/`: the web run of the 4-bot test (`ci/smbot/websmoke.py`), the Style Guide page and starter kit build (`ci/smbot/site.py`), the run of the carried-over dry runs, and the verdict at C1. Where a task needs one of these, the task says so and files it in "Needs an owner decision" in `docs/BACKLOG.md`; the rest of the queue goes on meanwhile.
- **The community** (Art and Audio) adds assets by the normal pipeline. The weekly planning run turns the art and sound needs of this milestone into issues labelled `now`, each with a "Brief for your AI".
- **Weekly owner playtest:** from the first Sunday after the room is playable (part 8), the weekly run opens a "Playtest of the week" issue with the build link and 3–5 specific questions about feel. The owner's answers outrank everything else on feel and fun. A skipped week blocks nothing.

## Design decisions for M1

These fill in what the plan leaves open (also recorded in `docs/DECISIONS.md`).

- **Events:** `core/events` is one autoload with a typed signal per event. Every per-player event carries the player index as its first argument. Event names follow `gameplay/README.md`, "Events at a glance"; when `core/events` exists it becomes the single source and the READMEs are fixed to match it.
- **Scenes:** the gameplay folders allow `.gd` and `.tres` only, so M1 scenes live with their content: the wizard in `content/wizard/`, the enemy in `content/enemies/`, the room in `content/rooms/`, HUD scenes in `hud/`. Gameplay scripts get them through `core/registry`.
- **Registry:** in M1 it scans the content folders when the game starts. The build-time manifest the plan mentions is an optimisation for later, once content is large enough to need it.
- **The one spell** is a fire bolt, a `.tres` on a small base class in `core/base/`. M2 replaces it with the full component system and migrates this spell, so nothing else may depend on its fields.
- **Arena glue:** a minimal slice of `flow` loads the room, spawns the wave, and announces `room_entered` and `room_cleared`; it restarts the room when all players are down. M3 replaces it with the real room sequence, door voting and run lifecycle. There is no pause menu in M1 (it belongs to `run`, M3).
- **Placeholder art** is hand-written SVG pixel art (rects on a 32×32 grid), because sessions have no image tools. It is listed in the manifest as `origin: "ai"`, tier `placeholder`, with tool and prompt.
- **Player scaling** (enemy HP and count by player count) belongs to `difficulty` in M3. The M1 room has a fixed wave sized for four players, to be tuned at C1.

## Parts, in build order

Each part ends with tests and a green `tools/check.sh` and `ci/build/build.sh --quick`. `docs/NEXT.md` has them as sessions.

| # | Part | Delivers |
| --- | --- | --- |
| 1 | **Event bus and base classes:** `core/events`, `core/base` | Typed events with player index; the base resources; the event lists in the READMEs reconciled |
| 2 | **Style and starter assets** (Art and Audio are already open) | `docs/STYLE.md`, the placeholder palette, the first placeholder tiles, sprites, vfx and sounds with manifest entries, and the examples named in the Art and Audio READMEs |
| 3 | **Input and per-player focus:** `core/input`, `core/ui_focus` | Join by button press, one device per player (P1 keyboard and mouse or gamepad, P2–P4 gamepads), virtual devices for bots, and focus that each panel takes only from its owner |
| 4 | **Pools and projectiles:** `core/pools`, `core/projectiles` | Pools with no per-frame allocation, the bulk projectile manager with a spatial grid, a global projectile cap that degrades gracefully, and `projectile_hit` events |
| 5 | **Registry:** `core/registry` | Folder discovery, literal-path loading everywhere else |
| 6 | **Player:** `gameplay/player` and the wizard scene | Move, dodge, cast the fire bolt, mana, health, downed and revive, for indices 0–3 |
| 7 | **Combat, the enemy and the spell:** `gameplay/combat`, `gameplay/ai`, `content/spells`, `content/enemies` | The damage pipeline, knockback, one telegraphed enemy, the fire bolt |
| 8 | **The room and arena glue:** `content/rooms`, the `flow` slice | One room with space for four, spawns and doors, the wave, win and restart in under 3 seconds; the first playable build, which starts the weekly playtest |
| 9 | **Feel:** `gameplay/feel` | Hit-stop, screen shake, hit particles and sound on every hit, with player-count-safe limits and a setting to turn shake off |
| 10 | **Co-op:** `gameplay/coop` | Join and leave mid-run, friendly fire option, the shared camera that zooms out to fit everyone |
| 11 | **Per-player HUD:** `hud/panels`, `hud/theme` | A corner panel in each player's colour (health, mana, an overlay that never pauses anyone) and the single theme |
| 12 | **Bots and the 4-bot smoke test:** `tests/bots`, `tests/smoke` | Four bots on virtual devices play the room; one idles in its overlay; all others must still clear it. Runs in the editor and the Linux export first |
| 13 | **Performance budgets:** `tests/benchmark` | A probe that logs frame time and node, projectile and memory counts in the 4-bot run. It gates nothing yet; the gating stress benchmark arrives in M2. Build size and load time are checked against the budgets |
| 14 | **The web 4-bot run** | The owner-only change to `ci/smbot/websmoke.py`, then the same test passing in headless Chrome |
| 15 | **Style Guide page and starter kit** | The kit's source files (palette files, grid and sheet templates, golden-example candidates, checklist) in `art/`, and the owner-only build of the page and zip |
| 16 | **Stabilisation and C1** | Only bug fixing, polish and performance until no known crash or blocker remains; then the C1 issue with a build link, Claude's honest assessment and questions |

Part 2 comes early on purpose: outside Art and Audio PRs are possible from day one, and they need the style and the examples. Part 14 and the owner's work in 15 wait on the owner, so the queue never blocks on them.

## Checkpoint C1

The question is: do moving, dodging and casting feel good, alone and with 4 players? The owner decides, with Claude's assessment from bot logs, the weekly playtest answers and player feedback. Verdicts: **go** (M2 starts), **iterate** (rework the weak parts, at most 2 rounds) or **pivot**. The owner has 7 days to answer; if they don't, Claude defaults to iterate so nothing stalls (docs/PLAN.md, "Go/no-go checkpoints").

## Out of scope

The spell builder, spell components beyond the fire bolt and the spell limits (M2); the gating stress benchmark and the art direction call (M2); several rooms, door voting, the run lifecycle, rewards, relics, staffs, bosses and the pause menu (M3); enemy scaling by player count (M3); bot playtesting and balance reports (M3); HUD polish and cosmetics (M4); saving and the hub (M5). Cross-player spell linking stays in the backlog. Feedback links that open a browser need an owner decision first (`docs/BACKLOG.md`), so M1 has none.
