# Difficulty

## Purpose

Scaling by player count, depth and setting.

Built in M3 (see "Gameplay sub-areas" in docs/PLAN.md).

A run with 1 player and a run with 4 players should both feel fair.

## Contract

- **Public entry script:** `gameplay/difficulty/difficulty.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. The script arrives when the area is built.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `difficulty_changed`.
  - Listens to: `run_started`, `player_joined`, `player_left` and `room_entered`.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

Arrives with Claude's first code for this area. Do not guess its layout before then.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

A good PR here tunes how enemy count, health or rewards scale with players, depth or the chosen setting. Besides the general review:

- Does it feel fair from 1 to 4 players?
- Does it keep to the dependency direction, without calling another area directly?
