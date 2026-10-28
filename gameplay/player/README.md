# Player

## Purpose

Wizard controller: move, dash, four staffs, mana, health, downed and revive.

Built in M1 (see "Gameplay sub-areas" in docs/PLAN.md).

Every player is an index 0–3 with their own device, mana, health and downed state. A downed player can be revived by a teammate; nobody ever waits for another player.

## Contract

- **Public entry script:** `gameplay/player/player.gd`. Other code uses only this script and the events it sends and listens to; nothing else in the folder is public. Health and mana are `health` and `mana` (`MAX_HEALTH`, `MAX_MANA`, `MANA_REGEN`); `take_damage(amount)` (also reached by `damage_dealt` with the wizard as target), `is_downed()` and `revive(reviver)` (called by `coop` when a teammate has stayed beside the body long enough). Cast: the four staff buttons `cast_a`, `cast_x`, `cast_y`, `cast_b` cast staffs 0 to 3 through `Spells.cast_staff(index, staff, origin, direction, mana)` (the delays live in `Spells`); `cast_staff(staff)` does the same from code. A held button casts whenever the staff is ready; a press while it is not is remembered for `INPUT_BUFFER` (0.15 s); while a staff has a sustained (`hold`) card on, only a new press casts (switching it off). The mana offered is `free_mana()`: what the wizard has minus what its sustained cards hold (`mana_reserved`). A cast takes the mana returned, sends `spell_cast` (the carrier, from `Spells.last_form`), `staff_cast` and `wizard_cast`; it reads no spell field.
- **Staffs (staffs A6a, docs/milestones/M2-staffs.md):** four staffs, each a row of card ids `staff.slots` long (`staff` is the `StaffBase` flow hands over; without one a staff has 4 slots and no delay of its own). `start_cards` (four lists, flow sets them) are built when the wizard enters the tree. `cards_of(staff)` gives a copy, `has_staff(staff)` says whether it can cast, `slot_count()` the slots, `set_staff(staff, cards)` builds a whole row. `staff_change_requested(player, staff, slot, card_id)` for this player puts one card in (an empty id clears the slot); `card_move_requested(player, from_staff, from_slot, to_staff, to_slot)` moves or swaps cards between slots and staffs (`BAG`, -1, is the bag: from it a card is put in, to it a slot is emptied); `staff_cards_requested(player, staff, cards)` sets a whole staff at once (fewer cards than slots empties the rest; the radial builder's push, undo and clear). Nothing is refused for what the cards do (every arrangement is legal); only a slot or staff that does not exist, or a card not in the `bag`, is refused with `build_refused(player, reason)`. Every build is announced with `staff_changed(player, staff, plan)`, the plain view of `Spells.staff_view`. The `bag` is every card in the registry until M3's rewards fill it per player. A rebuild leaves the shots already flying alone (`Spells` keeps their old numbers). Orbit shots circle the body: the wizard pushes `global_position + ORBIT_ANCHOR_OFFSET` to `Projectiles.set_anchor` each step and clears it when downed or when it leaves the tree. The cast sound is `Registry.get_sound(&"cast")`, skipped on `null`.
- **Aim and look:** shots go along `aim`, not the walk direction (`facing` is only the last walk direction, used by a dash with no direction). The right stick aims and holds `AIM_HOLD_TIME` (0.6 s) after release; the keyboard player aims at the mouse after it moves (the J key goes back); with no aim input the wizard aims the way it walks. The sprite turns toward the aim and a reticle in the player colour, with a ground shadow, is drawn by `_draw`. Shots start at the staff tip, `muzzle_position()` (hand height plus `STAFF_REACH` along the aim), and a staff is drawn there. A dash stretches the sprite along its dominant axis, leans it, and leaves three ghosts where the wizard was (`DASH_STRETCH`, `GHOST_INTERVAL`): solid copies drawn by the shot shader (the glow look, 2026-10-27), turned to the player's colour and falling apart pixel by pixel, the older the more (`GHOST_DISSOLVE`), with a glow (`GHOST_GLOW`), never see-through. The staff and reticle are drawn by a child node above the sprite; the shadow below it, and the ghosts are sprites of their own under it. **Dash:** a `dash` card makes `Spells` send `caster_move_requested(actor_id, &"dash", to, seconds, tag)`; the wizard dashes the way it walks (the way it faces when standing) as far and as long as asked, with no invulnerability, and answers `caster_move_finished(actor_id, &"dash", position, tag)` where it stops (`is_dashing()`); an overlay opening ends a dash. While the wizard cannot be hurt (`protect`: join or revive) the sprite is 55% opaque and a ring in the player colour closes round it.
- **Caster kit (staffs B4):** `caster_move_requested` for this player is acted on as it comes, except `recoil`. A `teleport` jumps (`to` is measured from the staff tip) and stops `TELEPORT_CLEARANCE` short of the first wall, then backs off along the path until the body (`BODY_RADIUS`) is clear of walls and inside the room, answering `caster_move_finished` at once; a `hook` or `swap` pulls the wizard to the world point `to` over `seconds` (stopped by walls; `is_dashing()` is true meanwhile; a swap sends no answer); a later dash, teleport, hook or swap replaces the one in progress, which is answered where the wizard stands. The `recoil` requests of a step are added up and applied by the next `step` over the longest time asked (a `mirror` recoil cancels); each push then runs on its own time (up to `MAX_RECOILS` at once), so pushes of different lengths move the sum of their distances. A dash, hook or swap lasts its whole time and is answered by the step after. Walking and dashing are multiplied by `Combat.wizard_speed_factor(index)` (chill slows, freeze stops; a hook, swap, recoil and the push are not), and `Combat.consume_wizard_knockback(index, delta)` is added to the velocity. `mana_refund_requested` adds mana up to `MAX_MANA`. `combat` is the `Combat` autoload (tests set it).
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/` and the registry. `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - **Actor (actors G3b):** the wizard opens its actor in `_ready` (`actor_id`: the wizards' team, ramp and seat `index`; closed when it is freed) and its caster in `Spells`. Everything it asks of `Spells` and `Projectiles`, and the caster-keyed events (`caster_move_requested`/`_finished`, `mana_refund_requested`), use `actor_id`; the seat's events (HUD, builder, stats, downed, `spell_cast`, `staff_cast`, `wizard_cast`, `mana_reserved`) keep `index`.
  - Sends: `player_downed`, `player_revived`, `player_stats_changed` (on appearing, on a health change and when mana crosses a whole number; for the HUD), `spell_cast`, `staff_cast`, `wizard_cast` (the wizard node, for the caster squash in `feel`), `caster_move_finished` (where a dash, teleport or hook ended, for `core/spells`), `staff_changed` and `build_refused` (for the builder), and `bag_changed(player, ids)` (when the wizard appears, and whenever the bag changes).
  - Listens to: `revive_progress` from `coop` (draws the revive ring over its own downed wizard: an arc sweeping clockwise from the top, a cross in the middle; `revive_progress()` answers the value), `damage_dealt` from `combat`, `staff_change_requested`, `card_move_requested` and `staff_cards_requested` (from the HUD), `caster_move_requested`, `mana_reserved` and `mana_refund_requested` (from `core/spells`), each acted on only for its own player, and `device_joined`, `device_left` from `core/input`.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Physics layers

One plan for every part that adds bodies: layer 1 walls, 2 players, 3 enemies, 4 projectiles and hit boxes. Players collide only with walls (mask 1). `player.gd` sets its layer and mask in `_init`. `core/` owns `project.godot` and has not yet named the layers there: until it does, use these numbers.

## Example to copy

`gameplay/player/player.gd` with its scene `content/wizard/base/wizard.tscn`, and its tests `tests/gameplay/player/test_player_move.gd` and `test_player_health_cast.gd` (a stand-in spell runtime is in `tests/gameplay/player/fixtures/fake_spells.gd`; `test_player_build.gd` runs the real one). `gameplay/` has no scenes: the wizard scene lives in `content/wizard/base/`. The script is driven by `step(delta)`, so a test runs time with fixed deltas. Combat asks `is_invulnerable()` before it hurts a wizard.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

A good PR here changes how one wizard moves, dashes, casts or recovers, works the same for player 0 and player 3, and keeps input responsive with full effects on screen. Besides the general review:

- Does it work for 1 and for 4 players at once? Do moving, dodging and casting stay responsive with full effects on screen?
- Does it keep to the dependency direction, without calling another area directly?
