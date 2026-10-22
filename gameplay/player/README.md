# Player

## Purpose

Wizard controller: move, dodge, cast, mana, health, downed and revive.

**Closed until M4.** Built in M1, opens for PRs in M4 (see "Gameplay sub-areas" in docs/PLAN.md and "Opens for PRs" in docs/ROADMAP.md). Until then Claude maintains it; an outside PR is a gamble.

Every player is an index 0–3 with their own device, mana, health and downed state. A downed player can be revived by a teammate; nobody ever waits for another player.

## Contract

- **Public entry script:** `gameplay/player/player.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. Move, dodge, health, mana, downed, revive and cast exist (M1 parts 9 and 10). Health and mana are `health` and `mana` (`MAX_HEALTH`, `MAX_MANA`, `MANA_REGEN`); `take_damage(amount)` (also reached by `damage_dealt` with the wizard as target), `is_downed()` and `revive(reviver)` (called by `coop` when a teammate has stayed beside the body long enough). Cast: while `cast` is held the wizard calls only `Spells.cast(index, active_slot, origin, direction, mana)` (the cooldowns live in `Spells`, per player and slot); it reads no spell field. The cast returns the mana spent or `Spells.REFUSED`; `spell_cast` carries the form id of the recipe.
- **Spells (M2 part 11):** two prepared spells, slot 0 (A) and 1 (B), each a recipe of component ids (`recipe_of(slot)` gives a copy) compiled and installed through `Spells`; `start_recipe_a` and `start_recipe_b` are built when the wizard enters the tree (flow sets them; both `{}` means no spell, `has_spell()` is false and nothing casts). `swap()` (also `spell_swap_requested` for this player) switches `active_slot` and does nothing when downed or when the other slot is empty. `build_change_requested(player, spell, slot, component_id)` for this player: `spell` is the path (`[0]` A, `[1]` B, `[0, 0]` the spell A's trigger holds, one level more for each `0`), `slot` is `SLOT_FORM` 0, `SLOT_ELEMENT` 1, `SLOT_FIRST_MODIFIER` 2 to 4 (a new modifier goes in the first free place; clearing one closes the gap) or `SLOT_TRIGGER` 5 (clearing it drops the held spell), and an empty `component_id` clears the slot. The change is made on a copy and checked: the id must be in the `bag`, its `kind()` must fit the slot, and `Spells.compile` must accept the whole recipe (complexity, depth, modifiers). If so the copy replaces the spell and `spell_changed(player, [slot of A or B], description)` is sent (always for the prepared spell, since a change below rebuilds the chain); if not `build_refused(player, reason)` is sent and nothing changes. `set_recipe(slot, recipe)` does the same for a whole recipe. The `bag` is the list of component ids the player may build with: every component in the registry until M3's rewards fill it per player. A rebuild leaves the shots already flying alone (`Spells` keeps their old numbers). Orbit shots circle the body: the wizard pushes `global_position + ORBIT_ANCHOR_OFFSET` to `Projectiles.set_anchor` each step and clears it when downed or when it leaves the tree. Nothing sends an event for a swap yet (part 18, the corner panel, needs one). The cast sound is `Registry.get_sound(&"cast")`, skipped on `null`.
- **Aim and look:** shots go along `aim`, not the walk direction (`facing` is only the last walk direction, used by a dodge with no direction). The right stick aims and holds `AIM_HOLD_TIME` (0.6 s) after release; the keyboard player aims at the mouse after it moves (the J key goes back); with no aim input the wizard aims the way it walks. The sprite turns toward the aim and a reticle in the player colour, with a ground shadow, is drawn by `_draw`. Shots start at the staff tip, `muzzle_position()` (hand height plus `STAFF_REACH` along the aim), and a staff is drawn there. A dodge stretches the sprite along its dominant axis, leans it, and leaves three ghosts where the wizard was (`DASH_STRETCH`, `GHOST_INTERVAL`, `GHOST_ALPHAS`). The staff and reticle are drawn by a child node above the sprite; the shadow and ghosts below it. A dodge or cast press made up to `INPUT_BUFFER` (0.15 s) before it is possible still counts (a press in an overlay does not); while the wizard cannot be hurt (a dodge, or join or revive protection) the sprite is 55% opaque and a ring in the player colour closes round it.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `player_downed`, `player_revived`, `player_stats_changed` (on appearing, on a health change and when mana crosses a whole number; for the HUD), `spell_cast`, `wizard_cast` (the wizard node, for the caster squash in `feel`), `spell_changed` and `build_refused` (for the builder), `recipe_changed(player, slot, recipe)` (right after `spell_changed`, a copy of the new recipe so the HUD can draw the chain) and `bag_changed(player, ids)` (when the wizard appears, and whenever the bag changes).
  - Listens to: `revive_progress` from `coop` (draws the revive ring over its own downed wizard: an arc sweeping clockwise from the top, a cross in the middle; `revive_progress()` answers the value), `damage_dealt` from `combat`, `build_change_requested` and `spell_swap_requested` (from the HUD; acted on only for its own player), and `device_joined`, `device_left` from `core/input`.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Not open yet. When it opens, follow the steps and test layout in [gameplay/README.md](../README.md).

## Physics layers

One plan for every part that adds bodies: layer 1 walls, 2 players, 3 enemies, 4 projectiles and hit boxes. Players collide only with walls (mask 1). `player.gd` sets its layer and mask in `_init`. `core/` owns `project.godot` and has not yet named the layers there: until it does, use these numbers.

## Example to copy

`gameplay/player/player.gd` with its scene `content/wizard/base/wizard.tscn`, and its tests `tests/gameplay/player/test_player_move.gd` and `test_player_health_cast.gd` (a stand-in spell runtime is in `tests/gameplay/player/fixtures/fake_spells.gd`; `test_player_build.gd` runs the real one). `gameplay/` has no scenes: the wizard scene lives in `content/wizard/base/`. The script is driven by `step(delta)`, so a test runs time with fixed deltas. Combat asks `is_invulnerable()` before it hurts a wizard.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Rating questions

A good PR here changes how one wizard moves, dodges, casts or recovers, works the same for player 0 and player 3, and keeps input responsive with full effects on screen. Besides the standard criteria:

- Does it work for 1 and for 4 players at once? Do moving, dodging and casting stay responsive with full effects on screen?
- Does it keep to the dependency direction, without calling another area directly?
