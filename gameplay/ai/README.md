# AI

## Purpose

Shared enemy behaviours: steering, targeting and attack patterns.

Built across M1 to M3 (the plan gives the range, not one milestone; see "Gameplay sub-areas" in docs/PLAN.md).

Enemies in `content/enemies/` pick and configure behaviours from here instead of writing their own. Targeting chooses among all active players, never "the player". The decoys and familiars of the staffs' cards live here too (staffs B5).

## Contract

- **Public entry scripts:** `gameplay/ai/ai.gd` and the autoload `Entities` (`gameplay/ai/entities.gd`). Other code uses only these and the events they send and listen to; nothing else in the folder is public. It is the script on the root node of an enemy scene (a `CharacterBody2D`): the spawner sets `data` (the enemy's `EnemyBase` resource) before adding the node. M1 has one behaviour: chase the nearest player who is not downed (any of indices 0–3, found in the `players` group or in `targets`), then one telegraphed attack (WINDUP with a visible telegraph and a locked aim, a shot through `core/projectiles`, RECOVER). `step(delta)` does the work, so tests run time with fixed deltas.
- `Entities` (staffs B5) keeps the decoys and familiars cards make, in a fixed pool (four of each kind per player; one more ends the oldest). A decoy is a still copy of its caster's wizard, drawn by the shot shader in its player's colour, part fallen apart, with a glow (never see-through; the glow look, 2026-10-27), that enemy shots hit (a `core/projectiles` target on `LAYER_PLAYER` owned by its player) and that enemies within 240 px chase before any wizard (`lure`, asked by `ai.gd`); it breaks after three enemy hits or when its time runs out. A familiar (drawn as an orbit shot by the shot shader: a small white-hot core in its player's colours and a tail bending round its circle) circles its caster (`entity_spawn_requested`'s `caster`: its wizard; the shot whose trigger made it, followed while it flies; or the point it was made at, once that shot is gone) and, every second, asks for a cast at the nearest enemy within 200 px. `seconds` of INF (or 0 or less) lasts until `entity_end_requested`. A new room or the end of the run clears them all without `entity_ended`. `step(delta)` does the work.
- **Staffs (staffs F8a, docs/milestones/M2-staffs.md "Enemy staffs"):** an enemy whose data has a `staff` and `cards` (`uses_staff`) opens a caster row in `Spells` in `_ready` (`caster`; the `Spells` autoload, or the `spells` var in tests), installs its staff (compiled once per enemy type) as staff 0, names its body its row's target (`Projectiles.set_target_owner`), and closes the row when it leaves the tree (`close_staff`). Every step it gets mana back (`data.mana_regen`, plus `Spells.take_refund`), sets its anchor and aim (the aim follows the target while it chases; the windup and the recovery lock it). In reach it winds up only when `cast_ready()` (the next cast's delay no longer than the windup, and its mana there), else it holds; at the end of the windup it casts (`Spells.cast_staff`) and pays. The telegraph line reaches `next_cast_reach()` and hides for a cast that is not aimed. Coming: the telegraph drawn by the shot shader (F8b) and caster-side cards (F8c). `ATTACK_TAG_BASE` and its hit-profile table, for an enemy without a staff, go in part F9.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `entity_ended` (a decoy broke or ran out, a familiar ended; for the end point) and `familiar_cast_requested` (Entities). An attack is a shot spawned in `core/projectiles` for `Events.NO_PLAYER`; `gameplay/combat` turns its hit into damage (the hit profile for `attack_tag` in `ai.gd`: `ATTACK_TAG_BASE` plus a number from the enemy id and `attack_damage`, which the AI sets; the exports such as `attack_damage` belong to the enemy scene, not to a spawn) and sends `damage_dealt`. The AI also registers the enemy with `Combat` and adds its knockback to its velocity (the same autoload-by-node-path lookup `player.gd` uses for `Events`).
  - Listens to: `entity_spawn_requested`, `entity_end_requested`, `projectile_hit` (an enemy's shot on a decoy), `room_entered` and `run_ended` (Entities); `target_move_requested` (each enemy: a swap moves the enemy it names there at once); `player_downed` (enemies chasing that player retarget at once) and `damage_dealt` (a hit on this enemy shows its optional `hurt_texture` pose for 0.25 s; it never cancels the windup). With `windup_texture` set, the windup pose flashes faster and brighter as the shot gets close. When an enemy leaves the tree it unregisters from `Combat`; it is not registered again on re-entry, so spawn a new one.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

`gameplay/ai/ai.gd` is the example, used by the enemy `content/enemies/ember_imp/` (`ember_imp.tscn` and `ember_imp.tres`). Its test `tests/gameplay/ai/test_ai.gd` shows how to test it: a fake bus, `Combat` and projectile manager, up to four wizards, and `step(delta)` with fixed deltas, moving the body by `velocity` as `move_and_slide()` would.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

A good PR here adds or improves one reusable behaviour that several enemies can configure, targets any of the 1–4 players, and stays cheap with 100–200 enemies. Besides the general review:

- Are behaviours reusable by several enemies? Do 100–200 enemies stay within the frame budget?
- Does it keep to the dependency direction, without calling another area directly?
