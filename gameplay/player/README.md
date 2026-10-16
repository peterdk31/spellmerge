# Player

## Purpose

Wizard controller: move, dodge, cast, mana, health, downed and revive.

**Built in M1. Opens for PRs in M4** (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

Every player is an index 0–3 with their own device, mana, health and downed state. A downed player can be revived by a teammate; nobody ever waits for another player.

## Contract

- **Public entry script:** `gameplay/player/player.gd`. Other code uses only this script and the events below; nothing else in the folder is public. The script arrives when the area is built (M1).
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and reads content data through the registry. `core/` never depends on it, and content never reaches into it.
- **Areas never call each other directly.** They talk through `core/events`; direct calls only in the documented directions. Events sent: `player_downed`, `player_revived`, `spell_cast`. Names are provisional until the event bus is built in M1.
- **Depends on:** input from `core/input`; hits from `combat` arrive as events.
- Every system takes a player index 0–3. Nothing assumes a single player.
- Performance: no per-frame allocations; use the pools and the projectile manager from `core/`; respect the particle limits.

## Allowed files

`.gd`, `.tres`, `.tscn`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only (types on every variable, parameter and return); no banned APIs. Tests mirror the tree in `tests/gameplay/player/`.

## Steps

1. Pick an issue labelled `now` in this area (only once the area is open) and comment `/claim`.
2. Read this contract and the events above; make one focused change.
3. Add or update tests in `tests/gameplay/player/`.
4. Run the checks below, then open a PR using the template. For gameplay changes, add a short GIF or video.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

Besides the standard criteria:

- Does it work for 1 and for 4 players at once? Do moving, dodging and casting stay responsive with full effects on screen?
- Does it keep to the dependency direction, without calling another area directly?
