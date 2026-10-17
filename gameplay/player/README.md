# Player

## Purpose

Wizard controller: move, dodge, cast, mana, health, downed and revive.

**Closed until M4.** Built in M1, opens for PRs in M4 (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

Every player is an index 0–3 with their own device, mana, health and downed state. A downed player can be revived by a teammate; nobody ever waits for another player.

## Contract

- **Public entry script:** `gameplay/player/player.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. Move and dodge exist (M1 part 9); health, mana, downed and cast follow in part 10.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `player_downed`, `player_revived`, `spell_cast`.
  - Listens to: `damage_dealt` from `combat`, `build_change_requested` (from the HUD), and `device_joined`, `device_left` from `core/input`.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Not open yet. When it opens, follow the steps and test layout in [gameplay/README.md](../README.md).

## Physics layers

One plan for every part that adds bodies: layer 1 walls, 2 players, 3 enemies, 4 projectiles and hit boxes. Players collide only with walls (mask 1). `player.gd` sets its layer and mask in `_init`. `core/` owns `project.godot` and has not yet named the layers there: until it does, use these numbers.

## Example to copy

`gameplay/player/player.gd` (move and dodge so far) with its scene `content/wizard/base/wizard.tscn`, and its test `tests/gameplay/player/test_player_move.gd`. `gameplay/` has no scenes: the wizard scene lives in `content/wizard/base/`. The script is driven by `step(delta)`, so a test runs time with fixed deltas. Combat asks `is_invulnerable()` before it hurts a wizard.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

A good PR here changes how one wizard moves, dodges, casts or recovers, works the same for player 0 and player 3, and keeps input responsive with full effects on screen. Besides the standard criteria:

- Does it work for 1 and for 4 players at once? Do moving, dodging and casting stay responsive with full effects on screen?
- Does it keep to the dependency direction, without calling another area directly?
