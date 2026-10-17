# Co-op

## Purpose

Join and leave mid-run, friendly fire and the shared camera.

**Closed until M4.** Built in M1, opens for PRs in M4 (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

Players join with a button press on their own device and can leave at any time. The shared camera fits all players. Nobody ever waits for another player.

## Contract

- **Public entry script:** `gameplay/coop/coop.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. The script arrives when the area is built.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `player_joined`, `player_left`.
  - Listens to: device events from `core/input` (defined in M1 part 5, not in `events.gd` yet), and `player_downed`.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Not open yet. When it opens, follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

Arrives with Claude's first code for this area. Do not guess its layout before then.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

A good PR here improves joining or leaving mid-run, the friendly-fire rules or the shared camera, and is checked with 1, 2, 3 and 4 players. Besides the standard criteria:

- Does it work for any join order of 1–4 players, and does the camera keep everyone on screen?
- Does it keep to the dependency direction, without calling another area directly?
