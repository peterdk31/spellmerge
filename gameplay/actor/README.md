# Actor

## Purpose

The shared body kit: one kind of body for wizards and enemies (actors G4, [docs/milestones/M2-actors.md](../../docs/milestones/M2-actors.md)).

An actor is a `CharacterBody2D` with `actor.gd` on its root and components as children: Health, Hurtbox, Contact, Mover, Caster, its looks and the controller that drives it. A wizard and an enemy differ only in which components they have and which controller drives them. Built in phase G of M2: the kit lands in G4, enemies move onto it in G6 and wizards in G7; until then no scene uses it.

## Contract

- **Public scripts:** every script in this folder (the layering exception below). Each has a `class_name`, so scenes and other areas use them by type.
- **`actor.gd` (`Actor`):** identity (`id` in the actor table `core/actors`, opened when ready and on every re-entry, closed when it leaves the tree; `ramp`; `team()` and `seat()` from the controller driving it, `idle_team` with none). Components are found once in `_ready` (the first child of each kind; none is required) and reached as `health`, `hurtbox`, `contact`, `mover`, `caster`. `home_controller` (the first `ActorController` child) and `controller` (the one driving now); `drive(controller)` hands the body to a guest (or to nobody with null), `release()` gives it back, and each change updates the table's team and seat at once. Body points: `body_offset` (hurt circle and orbit anchor), `aim_pivot()` (`hand_offset`), `muzzle_position()` (`staff_reach` along the aim), `aim` (unit length). `step(delta)` in a fixed order: the intent's presses are spent, Health's protection counts down, `controller.think`, the aim follows the intent, `caster.step`, `mover.step`, `hurtbox.step`, the looks; `_physics_process` then calls `move_and_slide()`. `data` (an `EnemyBase`) sets health, speed, contact damage, staff, cards and mana before the components are set up (no staff or no cards: no caster). `is_down()`/`set_down(on)` (the Downed component, G7), `die(killer)` (the local `died`, then freed), `downable`. `caster_number()` and `open_caster_number()`/`close_caster_number()`: the one seam to Spells' numbering (a seat's 0-3 or an enemy row until G3, the actor id after).
- **`actor_intent.gd` (`ActorIntent`):** what a controller wants this step: `move` (length ≤ 1), `aim` (zero keeps the aim), per staff `press(staff)`/`is_pressed` (this step only) and `hold(staff, on)`/`is_held`. Made once per actor.
- **`actor_controller.gd` (`ActorController`):** `team`, `seat` (-1 for none), `think(actor, delta)` (writes `actor.intent`, nothing else), `started(actor)`, `stopped(actor)`.
- **`actor_component.gd` (`ActorComponent`):** the components' base: `actor`, `setup(actor)` once, `attach()` on entering the tree, `detach()` on leaving.
- **`health.gd` (`Health`):** `max_health`, `health`, `take(amount, killer)`, `heal(amount)`, `reset(amount)`, `protect(seconds)`, `is_protected()`, `is_depleted()`; local signals `changed(health, max_health)` and `depleted(killer)`. Fed by `damage_dealt`/`heal_dealt` with the actor as target until Combat calls it (G5).
- **`hurtbox.gd` (`Hurtbox`):** `radius`, `offset`; registers the actor with `Combat.register_actor` (health, circle, Contact's damage) on attach, `unregister_actor` on detach and while the actor is down; `is_on()`.
- **`contact.gd` (`Contact`):** `damage`, handed to Combat by the Hurtbox.
- **`mover.gd` (`Mover`):** `speed`, `body_radius`; walking (`speed` × the intent's move × `Combat.pace`) plus `Combat.consume_knockback`, and the caster kit, one implementation for every actor: dash, teleport, hook, swap, recoil from `caster_move_requested` whose tag's caster is the actor's caster number; `caster_move_finished` for a dash, hook or teleport; `target_move_requested` naming the actor moves it at once. `is_moving()`, `move_mode()`, `move_direction()`, `stop()`. The rules are in docs/DECISIONS.md ("The actor kit").
- **`caster.gd` (`Caster`):** `staff_count` (1-4), `staff` (`StaffBase`), `start_cards`, `max_mana`, `regen`, `mana`, `number`; `cast(staff)`, `set_staff(staff, cards)`, `cards_of`, `slot_count`, `plan_of`, `last_form`, `has_staff`, `is_holding`, `free_mana`, `next_cast_mana`/`_reach`/`_radius`, `cast_ready(within, staff)`; local signals `cast_done(staff, origin, direction)` and `staff_built(staff)`. Each step: mana back (regen, `Spells.take_refund`; a seat's `mana_refund_requested`), the anchor and aim to the projectile manager and Spells, the casts the intent asks for (a press, or a hold while no sustained card is on). Compiled staffs are cached for every caster by Spells, staff and cards.
- **`actor_look.gd` (`ActorLook`):** a look's base (a `Node2D`): `setup(actor)`, `step(delta)`, read only.
- **Services:** `events`, `combat`, `projectiles`, `spells`, `actors` on the actor; tests set them before adding it, otherwise the autoloads are found by node path when it enters the tree.
- **Dependency direction:** `core` ← `gameplay` ← `content`. The kit may use `core/` and the Combat autoload's actor API (`register_actor`, `unregister_actor`, `pace`, `consume_knockback`). It is the one stated exception to "areas never call each other directly": every area may use the kit's public scripts. `gameplay/player` and `gameplay/ai` build on it (their controllers, Downed, the looks), and `content/` scenes put the components together.
- **Events** (`core/events/events.gd` owns the definitions; this list matches the table in [gameplay/README.md](../README.md)):
  - Sends: `caster_move_finished` (Mover).
  - Listens to: `caster_move_requested`, `target_move_requested` (Mover), `mana_refund_requested` (Caster), `damage_dealt`, `heal_dealt` (Health, until G5).
- **Performance:** no process callback but the actor's; nothing allocates in `step` (the intent is made once, the recoils are packed arrays).

## Allowed files

`.gd`, plus `.uid` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md). A new kind of component extends `ActorComponent` (or `ActorLook` for a look) and is found by the actor as a child; the actor steps only the kinds it names, so a component that needs a step is added to `Actor.step` in its place in the order.

## Example to copy

`tests/gameplay/actor/actor_fixture.gd` puts actors together in code from the components, with a scripted controller (`Scripted`), its own bus, projectile manager, Spells, Combat and actor table, and steps them by hand. Its tests (`test_actor.gd`, `test_actor_health.gd`, `test_actor_mover.gd`, `test_actor_caster.gd`) show each component alone.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests
```

## Review questions

Besides the general review:

- Does it hold for every actor, wizard and enemy alike, by one rule? Does nothing assume an actor id is a seat?
- Does a step stay free of allocations, with 200 actors in a room?
- Do components reach each other only through the actor, never by node path?
