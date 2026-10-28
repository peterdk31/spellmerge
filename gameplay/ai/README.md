# AI

## Purpose

Shared enemy behaviours: steering, targeting and attack patterns.

Built across M1 to M3 (the plan gives the range, not one milestone; see "Gameplay sub-areas" in docs/PLAN.md).

Enemies in `content/enemies/` pick and configure behaviours from here instead of writing their own. Targeting chooses among all active players, never "the player". The decoys and familiars of the staffs' cards live here too (staffs B5).

## Contract

- **Public entry scripts:** `gameplay/ai/ai.gd` and the autoload `Entities` (`gameplay/ai/entities.gd`). Other code uses only these and the events they send and listen to; nothing else in the folder is public. It is the script on the root node of an enemy scene (a `CharacterBody2D`): the spawner sets `data` (the enemy's `EnemyBase` resource) before adding the node. M1 has one behaviour: chase the nearest player who is not downed (any of indices 0–3, found in the `players` group or in `targets`), then one telegraphed attack (WINDUP with a visible telegraph and a locked aim, a shot through `core/projectiles`, RECOVER). `step(delta)` does the work, so tests run time with fixed deltas.
- `Entities` (staffs B5) keeps the decoys and familiars cards make, in a fixed pool (four of each kind per player; one more ends the oldest). A decoy is a still copy of its caster's wizard, drawn by the shot shader in its player's colour, part fallen apart, with a glow (never see-through; the glow look, 2026-10-27), that every shot but its own wizard's hits (a `core/projectiles` target on `LAYER_PLAYER` owned by its player) and that enemies within 240 px chase before any wizard (`lure`, asked by `ai.gd`); it breaks after three hits or when its time runs out. A familiar (drawn as an orbit shot by the shot shader: a small white-hot core in its player's colours and a tail bending round its circle) circles its caster (`entity_spawn_requested`'s `caster`: its wizard; the shot whose trigger made it, followed while it flies; or the point it was made at, once that shot is gone) and, every second, asks for a cast at the nearest enemy within 200 px. `seconds` of INF (or 0 or less) lasts until `entity_end_requested`. A new room or the end of the run clears them all without `entity_ended`. `step(delta)` does the work. **Enemies' entities (F8d):** a spawn with NO_PLAYER and an enemy's tag belongs to that enemy's caster row (`SpellTag.caster_of`). Its decoy copies the enemy, in the enemy ramp, and is a target on `LAYER_ENEMY` owned by the row: every shot but its own enemy's hits it (three break it), wizards' homing and familiars pick it, and enemies never chase it (`lure` is for wizards' decoys only). Its familiar circles the enemy and casts at the nearest wizard (or wizard's decoy) within 200 px, as NO_PLAYER with its tag. Each enemy keeps two of a kind; enemies share 32 rows of their own after the players' 32, so a crowd never takes a wizard's (full, the oldest enemy entity ends). The AI names its body for its row when it opens it (`set_enemy`) and, as it closes it, ends its entities where they are with `entity_ended` (`enemy_gone`), so even a `hold` one goes with the enemy.
- **Staffs (staffs F8a, docs/milestones/M2-staffs.md "Enemy staffs"):** an enemy whose data has a `staff` and `cards` (`uses_staff`) opens a caster row in `Spells` in `_ready` (`caster`; the `Spells` autoload, or the `spells` var in tests), installs its staff (compiled once per enemy type) as staff 0, names its body its row's target (`Projectiles.set_target_owner`), and closes the row when it leaves the tree (`close_staff`). Every step it gets mana back (`data.mana_regen`, plus `Spells.take_refund`), sets its anchor and aim (the aim follows the target while it chases; the windup and the recovery lock it). In reach it winds up only when `cast_ready()` (the next cast's delay no longer than the windup, and its mana there), else it holds; at the end of the windup it casts (`Spells.cast_staff`) and pays. The telegraph line reaches `next_cast_reach()` and hides for a cast that is not aimed. The telegraph is drawn in the new style (F8b): the scene's `Telegraph` is a `Sprite2D` with `gameplay/ai/telegraph.gdshader` (the shot look, but its own small shader: the shot shader's cost per pixel was too much for a crowd winding up at once), its ramp (`ramp_base`, `ramp_light`) set in the scene and its material local to the scene; the AI sets `beam_length`, `telegraph_lane` (the next cast's radius, `Spells.next_cast_radius`, plus a margin) and `telegraph_progress`; `telegraph_reach()` says how far it shows. Caster-side cards (F8c): the enemy answers `caster_move_requested` for its own row (NO_PLAYER and a tag whose `SpellTag.caster_of` is its `caster`): dash (from its staff tip, over the card's time), hook and swap (to the point), recoil (a push back), all through `velocity`; teleport at once, short of a wall with its body clear; dash, hook and teleport answer `caster_move_finished` (NO_PLAYER, the tag) where they end. Decoys and familiars (F8d): see `Entities` above; the AI calls `Entities.set_enemy` and `enemy_gone`. **Enemies hurt each other (actors G3c):** an enemy's spells always hit the other enemies too, and its blasts hurt it; the Enemy fire setting (F10) is gone. An enemy without a staff (or without a free caster row) only chases (staffs F9b: the old shot, `ATTACK_TAG_BASE` and the attack exports are gone).
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `caster_move_finished` (an enemy's dash, hook or teleport ended; NO_PLAYER and its tag), `entity_ended` (a decoy broke or ran out, a familiar ended; for the end point) and `familiar_cast_requested` (Entities). An attack is a cast of the enemy's staff through `Spells` (its caster row); `gameplay/combat` turns its hits into damage from the spell's hit profile and sends `damage_dealt`. The AI also registers the enemy with `Combat` and adds its knockback to its velocity (the same autoload-by-node-path lookup `player.gd` uses for `Events`).
  - Listens to: `entity_spawn_requested`, `entity_end_requested`, `projectile_hit` (a shot on a decoy), `room_entered` and `run_ended` (Entities); `caster_move_requested` (each enemy that casts a staff, for its own row); `target_move_requested` (each enemy: a swap moves the enemy it names there at once); `player_downed` (enemies chasing that player retarget at once) and `damage_dealt` (a hit on this enemy shows its optional `hurt_texture` pose for 0.25 s; it never cancels the windup). With `windup_texture` set, the windup pose flashes faster and brighter as the shot gets close. When an enemy leaves the tree it unregisters from `Combat`; it is not registered again on re-entry, so spawn a new one.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

`gameplay/ai/ai.gd` is the example, used by the enemy `content/enemies/ember_imp/` (`ember_imp.tscn` and `ember_imp.tres`). Its test `tests/gameplay/ai/test_ai.gd` shows how to test it: a fake bus, `Combat`, projectile manager and `Spells` (with the real cards from a scanned registry: the imp casts its staff), up to four wizards, and `step(delta)` with fixed deltas, moving the body by `velocity` as `move_and_slide()` would.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

A good PR here adds or improves one reusable behaviour that several enemies can configure, targets any of the 1–4 players, and stays cheap with 100–200 enemies. Besides the general review:

- Are behaviours reusable by several enemies? Do 100–200 enemies stay within the frame budget?
- Does it keep to the dependency direction, without calling another area directly?
