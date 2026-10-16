# Gameplay

## Purpose

The rules of the game, in 10 sub-areas: `player`, `combat`, `feel`, `coop`, `ai`, `run`, `flow`, `rewards`, `difficulty` and `progression`. Each has its own README with its job, when it is built and when it opens for PRs (docs/PLAN.md, "Gameplay sub-areas"). This file holds the text they share.

**All sub-areas are closed for now.** The first to open is `ai` in M3 (docs/ROADMAP.md, "Opens for PRs"). A PR to a closed area may still be merged, but it's a gamble.

## Contract shared by every sub-area

- **Entry script:** `gameplay/<area>/<area>.gd`. Other code uses only that script and the area's events.
- **Dependency direction:** `core` ← `gameplay` ← `content`. A sub-area may use `core/` and the registry. Areas never call each other directly; they talk through events.
- **Events:** `core/events` owns the event definitions. A sub-area README only lists which events the area sends and which it listens to, and each event has exactly one sender. The names in those lists are **provisional** until the event bus is built in M1.
- **Players:** everything that acts per player takes a player index 0–3. Nothing assumes a single player, and nobody ever waits for another player.
- **Performance:** no per-frame allocations; use the pools and the projectile manager from `core/`; respect the particle limits.

## Allowed files

`.gd`, `.tres`, `.tscn`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only (types on every variable, parameter and return); no banned APIs (see AGENTS.md, hard rules).

## Steps (once the area is open)

1. Pick an issue labelled `now` in the area and comment `/claim`.
2. Read the area's README and make one focused change.
3. Add or update tests in `tests/gameplay/<area>/`. The test runner and file naming are documented in `tests/README.md`, which is written by a later task; until it exists, don't invent a layout.
4. Run the checks below, then open a PR using the template. For gameplay changes, add a short GIF or video.

## Validate

```sh
tools/check.sh                   # hard rules, on your changes
ci/build/build.sh --quick        # import and smoke test in Godot
```
