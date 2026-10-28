# Player

## Purpose

The wizard's rules on the actor kit (actors G7, [docs/milestones/M2-actors.md](../../docs/milestones/M2-actors.md)): the seat that drives a wizard (input, the HUD's events, the builder), being downed and revived, and the wizard's look.

Built in M1 (see "Gameplay sub-areas" in docs/PLAN.md); since actors G7 a wizard is an actor of the shared body kit (`gameplay/actor`), and this area holds only the parts a wizard has that an enemy does not.

Every player is a seat 0–3 with their own device, and their own wizard. A downed wizard can be revived by a teammate; nobody ever waits for another player.

## Contract

- **The wizard** is the scene `content/wizard/base/wizard.tscn`, a floating staff (living staffs H3, docs/milestones/M2-living-staffs.md): an `Actor` root (group `wizards`, which coop reads; `hand_offset` (0, -12), the grip; `staff_reach` 14 for a staff with no tip) with `Health` (100), a hurtbox (radius 8 at (0, -12): the face and the grip), a mover (90 px/s), `Caster` (4 staffs, mana 100, regen 10), `Downed`, `PlayerController`, the `Sprite` (the body), `StaffLook` and a `Face` (anchor (-5, -20), 8 px above the grip). Its numbers live in the scene, not in code. Its ramp is its seat's (the player colour on the heads), its team the wizards'. `seat_wizard(body, seat, staff, cards, staffs)` gives it a staff per button (flow: the four starter heads). Health, mana, staffs, the moves (dash, teleport, hook, swap, recoil) and hits are the kit's (its README).
- **Public entry script:** `gameplay/player/player.gd`, `class_name PlayerController` (extends `ActorController`): the seat. Other code uses it, the area's other public scripts below and the events. It drives one actor at a time: its home wizard, or another actor that was handed to it (`Actor.drive`, possess in G9). **The HUD is always the player's own wizard** (owner, 2026-10-28): its home body (`home()`, the actor whose home controller it is) is bound once, when it first drives it (its Health, its Caster's `staff_built`, the builder's requests), and the driven actor only for its casts (`cast_done`, bound in `started`, let go in `stopped`).
  - **Input to intent** (`think`): the walk; the aim (the right stick, held `AIM_HOLD_TIME` (0.6 s) after release; the keyboard player aims at the mouse once it moves, `aim_at(actor, point)` measures from the hand, the J key goes back; with no aim input the walk direction); the staff buttons `staff_1` to `staff_4` (staffs 0–3): a button held is held, and a press (`get_press_count`, so no tap is lost) is pressed each step for `INPUT_BUFFER` (0.15 s) until a cast leaves. The Caster casts (a press, or a hold while no sustained card is on, then only a new press, switching it off). While an overlay captures the seat, the move in progress stops (`Mover.stop`), the intent is empty and presses made meanwhile do not count later; while the actor is down too.
  - **The panel's events,** always about the home wizard, also while the seat drives another actor or an enemy's AI drives the wizard: `player_stats_changed` (when it first drives the wizard and each time it comes home, on every Health change, and when mana crosses a whole number, looked at each step: in `think`, or in `watch_home` while it is away), `staff_changed(player, staff, plan)` on every `staff_built` (the plain view, `Caster.plan_of`), `bag_changed` and `build_refused`.
  - **The cast events,** about the actor it drives now (its buttons cast that actor's staffs): `spell_cast` (the carrier, `Caster.last_form`) and `staff_cast` on every `cast_done` (Feel's squash comes from the Caster's own `actor_cast`, for every actor), with the cast sound `Registry.get_sound(&"cast")` (skipped on null).
  - **The builder:** `staff_change_requested`, `card_move_requested` (`BAG`, -1, is the bag: from it a card is put in, to it a slot is emptied) and `staff_cards_requested` for this seat build the home wizard's staffs (`Caster.set_staff`), also during a possession. Nothing is refused for what the cards do; only a slot or staff that does not exist, or a card not in the `bag`, is refused with `build_refused(player, reason)`. The `bag` is every card in the registry until M3's rewards fill it per player.
  - **Possessed** (G9): `set_aside(actor, seconds)` when a possession takes the actor it drives: it drives nothing until `started` hands it an actor again (`is_set_aside()`); the panel goes on showing the wizard, and the time is drawn over the wizard (`PossessedLook`).
  - **The seat in the table:** the actor driven reports the controller's seat and team to `core/actors` (`Actor.seat`, `Actors.set_driver`), so budgets and `mana_reserved` (no HUD reads it yet) follow the seat; the wizard is its seat's home body there (`Actors.home_of_seat`, set by the actor from its home controller), which the HUD's `Spells.home_of_seat` finds.
  - `seat_wizard(body, seat, staff, cards)` (static) gets a wizard scene ready before it is added (its controller's seat, its ramp, its Caster's staff and start cards); `of(body)` (static) finds a body's PlayerController; `driven()`, `home()`, `bag`, `input`, `registry`, `mouse_world_override` (tests), `forget_presses()`, `announce_stats()`.
- **`downed.gd` (`Downed`, an `ActorComponent`):** makes its actor `downable`: at 0 health (`Health.depleted`) it is downed (`Actor.set_down`: it stands, casts nothing, its orbit and beam end, Combat takes its target off) and `player_downed(seat)` is sent; `revive(reviver)` (coop, flow) stands it up with `REVIVE_HEALTH` (50, `Health.reset`) and sends `player_revived(seat, reviver)`; `protect(seconds)` (`Health.protect`; `JOIN_PROTECTION`, 2 s, for a joiner and a new wave); `revive_progress()` from `coop`'s `revive_progress` for this seat. The seat is the home controller's (`seat()`), whoever drives the body. `of(body)` (static) finds it.
- **`staff_look.gd` (`StaffLook`, an `ActorLook`):** all the player's drawing, read from the actor: the head sheet of the staff on show (`Caster.current`'s `StaffBase.head`, `default_head` without one; 48 px frames, `DIRECTIONS` 16 columns from pointing right, clockwise, a row per ramp, the grip at `GRIP` on the hand), the hover bob (`HOVER_BOB`, per ramp out of step), down lying flat on the floor (`DOWN_LIFT`) the way it faced; it tells the `Face` where the body is (`body_offset`) and gives it the staff's personality (`face_style`, `resting_mood`); a dash, hook or swap (`Mover.is_moving`, `move_direction`; a standing actor dashes the way it aims) stretches and leans the sprite and leaves three ghosts drawn by the shot shader (`GHOST_DISSOLVE`, never see-through); a shadow on the floor; the reticle; the closing ring while protected (body and face 55% opaque); the revive ring while down (`Downed.revive_progress`). `shown_staff()`, `direction()`, `direction_of(aim)`. Colours are the ramp's light shade (`ProjectileManager.ramp_light(ramp)`, docs/STYLE.md, as Feel's flashes). It redraws only on a change and allocates nothing per step.
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area may use `core/`, the registry and the actor kit (`gameplay/actor`). `core/` never depends on it, and content never reaches into it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `player_stats_changed`, `spell_cast`, `staff_cast`, `staff_changed`, `bag_changed`, `build_refused` (PlayerController, for the seat), `player_downed`, `player_revived` (Downed).
  - Listens to: `staff_change_requested`, `card_move_requested` and `staff_cards_requested` from the HUD (PlayerController, for its seat), `revive_progress` from `coop` (Downed). Hits, heals, moves and mana refunds reach the wizard through the kit's components.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Physics layers

One plan for every part that adds bodies: layer 1 walls, 4 projectiles and hit boxes. An actor is on no body layer and collides only with walls (mask 1), so wizards walk through each other and never block a teammate; spells find it by its hurt circle (`core/projectiles`). `actor.gd` sets its layer and mask.

## Example to copy

The wizard scene `content/wizard/base/wizard.tscn` (`gameplay/` has no scenes) and its tests in `tests/gameplay/player/`: `wizard_fixture.gd` builds wizards from the scene with their own bus, input (virtual devices), projectile manager, Combat, actor table and spell runtime (the real one, or the stand-in `fixtures/fake_spells.gd`) and steps them by hand with fixed deltas; `test_player_move.gd`, `test_player_health_cast.gd` and `test_staff_look.gd` show the wizard, `test_player_build.gd` the seat and the builder. A new wizard rule is a new component (an `ActorComponent` found by the actor), a new drawing goes in `StaffLook`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

A good PR here changes how a seat drives, how a wizard is downed or revived, or how it looks, works the same for seat 0 and seat 3, and keeps input responsive with full effects on screen. Besides the general review:

- Does it work for 1 and for 4 players at once? Do moving, dashing and casting stay responsive with full effects on screen?
- Does the seat still work when it drives an actor that is not its home wizard (no cached body, no seat event from an undriven body)?
- Is all drawing in `StaffLook` (and the face in `Face`), and does nothing allocate per step?
