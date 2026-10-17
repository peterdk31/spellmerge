# AI

## Purpose

Shared enemy behaviours: steering, targeting and attack patterns.

**Closed until M3.** Built across M1 to M3 (the plan gives the range, not one milestone), opens for PRs in M3 (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

Enemies in `content/enemies/` pick and configure behaviours from here instead of writing their own. Targeting chooses among all active players, never "the player".

## Contract

- **Public entry script:** `gameplay/ai/ai.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. It is the script on the root node of an enemy scene (a `CharacterBody2D`): the spawner sets `data` (the enemy's `EnemyBase` resource) before adding the node. M1 has one behaviour: chase the nearest player who is not downed (any of indices 0–3, found in the `players` group or in `targets`), then one telegraphed attack (WINDUP with a visible telegraph and a locked aim, a shot through `core/projectiles`, RECOVER). `step(delta)` does the work, so tests run time with fixed deltas.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: none. An attack is a shot spawned in `core/projectiles` for `Events.NO_PLAYER`; `gameplay/combat` turns its hit into damage (the hit profile for `attack_tag` in `ai.gd`: `ATTACK_TAG_BASE` plus a number from the enemy id and `attack_damage`, which the AI sets; the exports such as `attack_damage` belong to the enemy scene, not to a spawn) and sends `damage_dealt`. The AI also registers the enemy with `Combat` and adds its knockback to its velocity (the same autoload-by-node-path lookup `player.gd` uses for `Events`).
  - Listens to: `player_downed` (enemies chasing that player retarget at once). When an enemy leaves the tree it unregisters from `Combat`; it is not registered again on re-entry, so spawn a new one. `room_entered` is not used yet.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Not open yet. When it opens, follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

`gameplay/ai/ai.gd` is the example, used by the enemy `content/enemies/ember_imp/` (`ember_imp.tscn` and `ember_imp.tres`). Its test `tests/gameplay/ai/test_ai.gd` shows how to test it: a fake bus, `Combat` and projectile manager, up to four wizards, and `step(delta)` with fixed deltas, moving the body by `velocity` as `move_and_slide()` would.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

A good PR here adds or improves one reusable behaviour that several enemies can configure, targets any of the 1–4 players, and stays cheap with 100–200 enemies. Besides the standard criteria:

- Are behaviours reusable by several enemies? Do 100–200 enemies stay within the frame budget?
- Does it keep to the dependency direction, without calling another area directly?
