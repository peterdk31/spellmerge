# Player

## Purpose

Wizard controller: move, dodge, cast, mana, health, downed and revive.

**Closed until M4.** Built in M1, opens for PRs in M4 (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

Every player is an index 0–3 with their own device, mana, health and downed state. A downed player can be revived by a teammate; nobody ever waits for another player.

## Contract

- **Public entry script:** `gameplay/player/player.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. Move, dodge, health, mana, downed, revive and cast exist (M1 parts 9 and 10). Health and mana are `health` and `mana` (`MAX_HEALTH`, `MAX_MANA`, `MANA_REGEN`); `take_damage(amount)` (also reached by `damage_dealt` with the wizard as target), `is_downed()` and `revive(reviver)` (called by whoever decides a revive happened, e.g. `coop`; it is not automatic yet). Cast: the wizard holds a `spell: SpellBase` and, while `cast` is held, calls only `spell.cast(index, origin, direction, mana)` and `spell.tick(index, delta)`; it reads no spell field (`spell_id()` is a method). The cast returns the mana spent or `SpellBase.REFUSED`. The cast sound is `Registry.get_sound(&"cast")`, skipped on `null`. Aim: shots go along `aim`, not the walk direction (`facing` is only the last walk direction, used by a dodge with no direction). The right stick aims and holds `AIM_HOLD_TIME` (0.6 s) after release; the keyboard player aims at the mouse after it moves (the J key goes back); with no aim input the wizard aims the way it walks. The sprite turns toward the aim and a reticle in the player colour, with a ground shadow, is drawn by `_draw`. Shots start at the staff tip, `muzzle_position()` (hand height plus `STAFF_REACH` along the aim), and a staff is drawn there. A dodge stretches the sprite along its dominant axis, leans it, and leaves three ghosts where the wizard was (`DASH_STRETCH`, `GHOST_INTERVAL`, `GHOST_ALPHAS`). The staff and reticle are drawn by a child node above the sprite; the shadow and ghosts below it. The spell to set is the fire bolt, `content/spells/forms/bolt/bolt.tres`; nothing sets `spell` yet, the flow glue (part 15) does.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `player_downed`, `player_revived`, `player_stats_changed` (on appearing, on a health change and when mana crosses a whole number; for the HUD), `spell_cast`, `wizard_cast` (the wizard node, for the caster squash in `feel`).
  - Listens to: `damage_dealt` from `combat`, `build_change_requested` (from the HUD), and `device_joined`, `device_left` from `core/input`.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Not open yet. When it opens, follow the steps and test layout in [gameplay/README.md](../README.md).

## Physics layers

One plan for every part that adds bodies: layer 1 walls, 2 players, 3 enemies, 4 projectiles and hit boxes. Players collide only with walls (mask 1). `player.gd` sets its layer and mask in `_init`. `core/` owns `project.godot` and has not yet named the layers there: until it does, use these numbers.

## Example to copy

`gameplay/player/player.gd` with its scene `content/wizard/base/wizard.tscn`, and its tests `tests/gameplay/player/test_player_move.gd` and `test_player_health_cast.gd` (a fixture spell is in `tests/gameplay/player/fixtures/`). `gameplay/` has no scenes: the wizard scene lives in `content/wizard/base/`. The script is driven by `step(delta)`, so a test runs time with fixed deltas. Combat asks `is_invulnerable()` before it hurts a wizard.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

A good PR here changes how one wizard moves, dodges, casts or recovers, works the same for player 0 and player 3, and keeps input responsive with full effects on screen. Besides the standard criteria:

- Does it work for 1 and for 4 players at once? Do moving, dodging and casting stay responsive with full effects on screen?
- Does it keep to the dependency direction, without calling another area directly?
