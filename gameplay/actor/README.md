# Actor

## Purpose

The shared body kit: one kind of body for players and enemies ([docs/milestones/M2-actors.md](../../docs/milestones/M2-actors.md)). An actor is a `Node2D` with `actor.gd` on its root (no physics body) and components as children. A player and an enemy differ only in which components they have and which controller drives them.

## Contract

- **Public scripts:** every script here has a `class_name`; every area may use them (the one stated exception to "areas never call each other directly").
- **`Actor`** (`actor.gd`): `id` (actor table, `core/actors`), `team()`, `seat()`, `own_team()`, `ramp`; components found once in `_ready` (`stats`, `health`, `hurtbox`, `contact`, `mover`, `caster`, `inventory`, `footprint`, `state_triggers`; `Stats`, `Footprint`, `Inventory`, `DamageNumbers` added when the scene has none); `home_controller`, `controller`, `drive(controller)`, `release()`; `belongs_to`, `possessed_by`, `add_look`/`remove_look`, `is_leaving()`; body points `body_offset`, `aim_pivot()`, `muzzle_position()`, `butt_position()`, `aim`; `is_still()`, `rebuild_derived()`, `rest_leaf()`; `step(delta)` and `move(delta)` (through `tick_step`, by the Tick; `ticking = false` to step a body yourself); `data` (`EnemyBase`), `set_size`, `count_players`; `is_down()`/`set_down()`, `is_downed()`, `die(killer)`, `downable`; falls (`fall_left`, `ground`, `returns_from_falls`, `never_falls`, `fall_share()`; `HoleRules`); spawning (`spawn(seconds, style)`, `is_spawning()`, `spawn_share()`); `caster_number()`; its row of the actor table's body table (`write_row()`, and `Actor.gather_rows(table, ids, count)` for the Tick, `BodyKernel.gather` with the module, `gd_gather_rows` its twin: perf plan C1 and C2, core/actors/README.md, "The body table": the body is the row's one writer, so a change to a flag's or the radius's member, or a new way to move another body mid-step, writes the row too). Local signals `touched`, `status_gained`, `reacted`, `damaged`, `healed`.
- **`Actor.step` order:** presses spent, Health's protection, `controller.think`, aim, `caster.step`, `mover.step`, `hurtbox.step`, looks, `home_controller.watch_home`. A moving body slides by `RoomGrid.slide_body` (with holes, `RoomGrid.walk_body` / `BodyKernel.walk`); `Actor.move` asks the walk and the place it ends in (its `room`) in one call, `RoomGrid.walk_place` / `BodyKernel.walk_place` (perf plan C2), and asks `find_room` again only when its node stands elsewhere after (a boss put on ground).
- **Components:** `ActorComponent` (`setup`, `attach`, `detach`, `at_rest`); `Health` (`take`, `heal`, `reset`, `rescale`, `protect`; signals `changed`, `depleted`); `Hurtbox` (circle or box, registers with `Combat.register_actor`, `set_enabled`); `Contact` (`damage`); `Mover` (walk, dash, teleport, pull, swap, recoil; `crossing`, `held_up`, `is_dashing`); `Caster` (1-4 staffs, one mana pool each; `cast`, `set_staff`, `hold_staffs`, `replace_staffs`, `rebuild`, `fill_hand`, `empty_hand`, `cast_ready`, `next_cast_*`; signals `cast_done`, `staff_built`); `Stats` (`power`, `mass`, `spell_scale`, `resist`, `apply`); `Footprint` (a body that cannot move is solid ground, `RoomGrid.set_footprint`); `Inventory` (bags, staffs by number, hands, quick-use slots, `loadout()`/`take_loadout()`; refusals as `Inventory.Refusal`); `DamageNumbers` (tells `damage_number_shown`).
- **Controllers:** `ActorController` (`team`, `seat`, `think`, `started`, `stopped`, `set_aside`, `watch_home`, `is_telegraphing`, `telegraph_staff`, `phase_started`, `possessions`, `leader()`, `end_possessions`); `PuppetController`; `ActorIntent` (`move`, `aim`, `press`/`is_pressed`, `hold`/`is_held`, `copy_from`).
- **Possession** (`Possession.begin(by, target, seconds)`, `end`, `move_on`): the driver drives its oldest possession, a `PuppetController` the rest; sends `possess_started`/`possess_ended`; `PossessedLook` draws the timer.
- **Bosses and elites:** `Phases` (from `data.phases`; `begin`, `adds_key`, never starts while possessed), `BossPresence` (`boss_shown`, `boss_health_changed`, `boss_hidden`), `EliteLook`.
- **Props:** `PropBody.make(data)`/`fill`, `PropStateTriggers` (`states`, `state`, `enter(state_id)`, `keeps_time()`, `MAX_DEPTH`), `PropLook`.
- **Looks** (VIEW_ONLY): `ActorLook` (`setup`, `step`, `sync`, `pose_offset`, `pose_scale`, `apply_pose`), `BodyPose`, `BodyPart` (`parts_of`), `Face` (`style`, `resting_mood`, `glow`, `glance`, `show_mood`, `restyle`, `unstyle`, `wear_sheets`).
- **Services:** `events`, `combat`, `projectiles`, `spells`, `actors` on the actor; tests set them before adding it.
- **Events** (defined in `core/events/events.gd`; matches [gameplay/README.md](../README.md)):
  - Sends: `adds_requested`, `boss_shown`, `boss_health_changed`, `boss_hidden`, `caster_move_finished`, `staff_shown`, `prop_state_changed`, `cue_shown`.
  - Listens to: `caster_move_requested`, `target_move_requested`, `mana_refund_requested`, `cast_left`. Hits, statuses, reactions and touches come as the actor's own local signals, never from the bus.

## Rules

- Every rule holds for every actor, player and enemy alike; never assume an actor id is a seat.
- Dependency direction: `core` ← `gameplay` ← `content`. The kit uses only `core/`, `Combat.STATUSES`/`STATUS_COUNT` and Combat's actor API (`register_actor`, `unregister_actor`, `pace`, `consume_knockback`, `own_pace`, `own_knockback`).
- Components reach each other only through the actor, never by node path.
- No process callback but the actor's (a look may animate in `_process` only while it plays frames); nothing allocates in `step`; a component is called only when it has something to do and sends only what changed.
- A controller's `think` writes `actor.intent`, nothing else.
- One controller never drives two bodies (`drive` takes it off the last).
- A body with no Mover never moves; a still body is never stepped.
- Spawning and falling bodies are down to everything that asks (`is_down`) but not downed (`is_downed`).
- Looks are view only and never state; every other member follows the simulation rules ([core/sim/README.md](../../core/sim/README.md)).

## Allowed files

`.gd`, plus `.uid` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md). A new kind of component extends `ActorComponent` (or `ActorLook` for a look) and is found by the actor as a child; the actor steps only the kinds it names, so a component that needs a step is added to `Actor.step` in its place in the order.

## Example to copy

`tests/gameplay/actor/actor_fixture.gd` puts actors together in code from the components, with a scripted controller (`Scripted`), its own bus, projectile manager, Spells, Combat and actor table, and steps them by hand. Its tests (`test_actor.gd`, `test_actor_health.gd`, `test_actor_mover.gd`, `test_actor_caster.gd`, `test_face.gd`) show each component alone.

## Tests

`tests/gameplay/actor/` (`test_spawn.gd`, `test_actor_stats.gd`, `test_prop_state_triggers.gd`, `test_prop_look.gd`, `test_damage_numbers.gd`, `test_inventory.gd`, `test_inventory_hands.gd`, `test_possess.gd`), `tests/gameplay/ai/test_ai_phases.gd`, `tests/gameplay/ai/test_ai_poses.gd`, `tests/gameplay/feel/test_remnants.gd`, `tests/screenshots/shot_possess.gd`, `tests/screenshots/shot_damage_numbers.gd`, `tests/core/test_body_walk.gd`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests
```

## Review questions

Besides the general review:

- Does it hold for every actor, player and enemy alike, by one rule? Does nothing assume an actor id is a seat?
- Does a step stay free of allocations, with 200 actors in a room?
- Do components reach each other only through the actor, never by node path?

History and reasons: [docs/history/gameplay-actor-README.md](../../docs/history/gameplay-actor-README.md).
