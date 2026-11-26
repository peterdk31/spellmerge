# Player

## Purpose

The player's rules on the actor kit ([docs/milestones/M2-actors.md](../../docs/milestones/M2-actors.md)): the seat that drives a player (input, the HUD's events, the builder), being downed and revived, and the player's look. A player is an actor of `gameplay/actor`; this area holds only what a player has that an enemy does not. Every player is a seat 0–3 with its own device and body; a downed player can be revived; nobody ever waits for another player.

## Contract

- **The player scene:** `content/wizard/base/wizard.tscn`, a floating staff: `Actor` root (group `wizards`), `Health`, hurtbox, mover, `Caster` (4 staffs), `Downed`, `PlayerController`, `Sprite`, `StaffLook`, `Face`. Its numbers live in the scene, not in code. Health, mana, staffs, moves and hits are the kit's.
- **Public entry script:** `gameplay/player/player.gd`, `class_name PlayerController` (extends `ActorController`): the seat. It drives one actor at a time: its home body or one handed to it (`Actor.drive`, possession).
- **The HUD is the body the seat drives:** `shown()` is the driven actor (the oldest possession), else `home()`. The shown body's Health, Caster (`staff_built`) and Inventory are watched while shown, reconnected in `rebuild_derived` after a snapshot.
- **Input:** `think` reads only the seat's `InputFrame` (`Frames.frame_of(seat)`), never a device; devices become frames in `LocalInput` (core/input). The press buffer (`INPUT_BUFFER`) stays here. While captured or down: `Mover.stop`, empty intent, buffer forgotten.
- **Panel events** (about the shown body): `player_stats_changed`, `staff_mana_changed`, `staff_changed`, `build_refused`, `inventory_announced(player, body)` then `bag_changed`, `owned_staff_changed`, `hands_changed` each time the shown body changes and on each change.
- **Cast events** (about the driven actor): `spell_cast`, `staff_cast` on every `cast_done`. Cast sounds are Feel's, never played here.
- **Commands** (heard at the next tick's start via `Events.listen`), all on the shown body's `Inventory`:
  - `staff_change_requested`, `staff_cards_requested` (`set_card`, `set_cards`); refused with `build_refused` (NO_STAFF, NO_SLOT, NO_CARD). Never refused for what the cards do. A card given back to a full bag drops at the body's feet.
  - `staff_hand_requested`, `bag_drop_requested` (`set_hand`, `drop_staff`, `drop`); refused with `inventory_refused` (NO_STAFF, NO_HAND, NO_ROOM, NO_ITEM, NO_DROP).
  - `bag_use_requested` (`ItemKinds.use_of`, `ItemUse`; heals via `health_gift_requested`; kept uses recharge via `Inventory.start_recharge`, told as `item_recharging`); refused NO_ITEM, NO_USE, NO_CHARGE, NO_NEED.
  - `quick_bind_requested`, `quick_use_requested` (`Inventory.bind_quick`; `quick_bound` tells the HUD).
  - **While the shown body is down every request is refused (NO_DOWN)**; each request names the body its menu showed (`body`, `Actor.key`), and one for a body no longer shown is refused (NO_BODY).
- **Card bag:** the run mode's (card id to copies), handed by flow via `seat_wizard` (`Inventory.give_cards`); a wizard seated with none gets `Inventory.DEV_COPIES` of every card. Currency is a bag like any other; everything is droppable.
- **Possessed:** `set_aside(actor, seconds)`; drives nothing until `started` (`is_set_aside()`); `PossessedLook` draws the time.
- **The seat in the table:** the driven actor reports seat and team to `core/actors` (`Actor.seat`, `Actors.set_driver`, `Actors.home_of_seat`); the HUD uses `Spells.shown_of_seat`.
- **API:** `seat_wizard(body, seat, staff, cards, staffs, bag)` (static, before the body is added), `of(body)` (static), `driven()`, `home()`, `shown()`, `forget_presses()`, `announce_stats()`; tests: `frames`, `registry`, `input`, `mouse_world_override`.
- **`downed.gd` (`Downed`, an `ActorComponent`):** at 0 health downs the actor (`Actor.set_down`) and sends `player_downed(seat)`; `revive(reviver)` (`REVIVE_HEALTH`) sends `player_revived(seat, reviver)` and `cue_shown` `revive` (`REVIVE_CUE`); `protect(seconds)` (`JOIN_PROTECTION`); `revive_progress()`; `is_down()` (a fall is no down); `stands()`; `seat()` is the home controller's; `of(body)`.
- **`staff_look.gd` (`StaffLook`, an `ActorLook`):** all the player's drawing, read from the actor: the shown staff's head sheet (`StaffBase.head`, 16 `DIRECTIONS`, a row per ramp), hover bob, the poof on a staff change (`is_poofing()`), lying down, the `Face`'s offset and mood, move stretch and ghosts (never see-through), shadow, reticle, protection and revive rings, carrier poses (`Spells.poses()`, `tip_position()`; docs/CARRIERS.md, "Lining a staff animation up with its look"). Colours: `ProjectileManager.ramp_light(ramp)`. It redraws only on a change and allocates nothing per step.
- **Dependency direction:** `core` ← `gameplay` ← `content`. Use `core/`, the registry and `gameplay/actor` only.
- **Events** (defined in `core/events/events.gd`; matches [gameplay/README.md](../README.md)):
  - Sends: `player_stats_changed`, `spell_cast`, `staff_cast`, `staff_changed`, `inventory_announced`, `bag_changed`, `owned_staff_changed`, `hands_changed`, `build_refused`, `inventory_refused`, `health_gift_requested`, `player_downed`, `player_revived`, `cue_shown`.
  - Listens to: `staff_change_requested`, `staff_cards_requested`, `staff_hand_requested`, `bag_drop_requested`, `bag_use_requested`, `quick_bind_requested`, `quick_use_requested` (HUD), `revive_progress` (coop).
- Areas never call each other directly; they talk through events. Shared rules: [gameplay/README.md](../README.md).

## Physics layers

Layer 1 walls, 4 projectiles and hit boxes. An actor is on no body layer and collides only with walls (mask 1): players never block each other; spells find it by its hurt circle. `actor.gd` sets layer and mask.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs.

## Example to copy

The scene `content/wizard/base/wizard.tscn` and `tests/gameplay/player/` (`wizard_fixture.gd` builds players with their own bus, input, projectile manager, Combat, actor table and spells, stepped by hand). A new player rule is a new `ActorComponent`; new drawing goes in `StaffLook`. Steps and test layout: [gameplay/README.md](../README.md).

## Tests

`tests/gameplay/player/`: `test_player_move.gd`, `test_player_health_cast.gd`, `test_staff_look.gd`, `test_staff_alignment.gd`, `test_player_build.gd`, `test_player_potions.gd`, `test_player_card_bag.gd`; also `tests/gameplay/actor/test_inventory_hands.gd`, `tests/hud/test_inventory_menu.gd`.

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

- Does it work for 1 and 4 players, seat 0 as seat 3? Do moving, dashing and casting stay responsive with full effects on screen?
- Does the seat still work when it drives an actor that is not its home body (no cached body, no seat event from an undriven body)?
- Is all drawing in `StaffLook` (and the face in `Face`), and does nothing allocate per step?

History and reasons: [docs/history/gameplay-player-README.md](../../docs/history/gameplay-player-README.md).
