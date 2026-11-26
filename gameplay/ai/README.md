# AI

## Purpose

Shared enemy behaviours: one AI that plays whatever staffs an actor holds, steering, targeting, the looks, and the decoys and familiars of the staffs' cards. Enemies in `content/enemies/` configure behaviours from here instead of writing their own. Targeting chooses among every actor of another team, never "the player".

## Contract

- **Public entry scripts:** `ai.gd` (`AIController`), `brain.gd` (`AIBrain`), `behaviour.gd` (`AIBehaviour`), `behaviours.gd` (`AIBehaviours`), `team_board.gd` (`TeamBoard`), `sight.gd` (`AISight`), `creature_look.gd` (`CreatureLook`), `dummy_look.gd` (`DummyLook`), `decoy_controller.gd` (`DecoyController`), `decoy_look.gd` (`DecoyLook`), and the autoload `Entities` (`entities.gd`). Nothing else in the folder is public.
- **Enemies are actors:** the scene root is an `Actor` with Health, Hurtbox, Contact, Mover and Caster, filled from its `data` (`EnemyBase`, set by the spawner before it enters the tree). Every enemy has an actor id (enemies' team, no seat). The components walk, cast and get hurt; this area only decides and draws.
- **`AIController`** (an `ActorController`) writes the actor's intent and nothing else, through its `brain`. Profile: `profile`, else `EnemyBase.profile_or_fallback()`. It hears only its own actor's `Actor.damaged` and its Caster's `staff_built`; **nothing listens on the bus per enemy.** API: `state`, `target`, `grudge`, `grudge_left()`, `windup_time`, `recover_time`, `is_telegraphing()`, `telegraph_progress()`, `telegraph_staff()`, `started(actor)`, `stopped(actor)`, `phase_started`. Team board: `Entities.board`, or `board` set by a test. All timing runs in `think(actor, delta)`, called by `Actor.step`. A minion is an `AIController` of the players' team handed the actor (`Actor.drive`).
- **`AIBrain`** is the AI every enemy, minion, boss and test bot plays by. It perceives on its profile's `reaction` timer (target: nearest standing actor of another team, `nearest_foe`, `can_target`; grudges for `GRUDGE_TIME`), and reads **what each staff casts next as a `CastSense`** (`Caster.next_cast_sense`); **it never names a card id** (`tests/core/test_ai_names_no_card.gd`). The range band comes from its harmful casts' reach. It decides by asking every behaviour's `want` and runs the winner's `act`, which writes the plan (`plan_staff`, `plan_move`: STAND, TOWARD, AWAY, WAY, POINT; `plan_way`, `plan_urgent`, `plan_point`, `plan_target`). States: CHASE, WINDUP, CHANNEL, RECOVER, REPOSITION, TRANSITION, CALL. Helpers for behaviours: `reaches`, `hurt_mate`, `slot_off`, `slot_way`, `spread_bonus`, `run_here`, `run_up`, `can_fire`, `fire_pick`, `downed_mate`, `foe_within`.
- **Enemies telegraph, allies don't:** a wind-up is the staff's data (`CastSense.wind_up`); only a brain that `warns()` (an actor not on the players' team) shows it. `aim_lock` stops the aim in the wind-up and sends `aim_locked`. A new driver cancels winding casts.
- **No move of its own ends over a hole;** walking stops at a lip. Harmful floor is asked through the bus (`look_harm`, `cover_danger_looked`, `CoverSight`), never by calling the cover area. Items are seen through `ground_looked` (`GroundSight`) and taken by `actor_take_requested`, never by calling Items. Revive reads no coop rule.
- **No pathfinder:** steering plus `AISight.detour`. Every room template is played spawn by spawn by the crypt mite (crypt rework rules CR5, CR6): it must reach a wizard from each enemy spawn, never falling.
- **`AISight`** (static, allocates nothing): `line_clear`, `ground_clear`, `walk_clear`, `feet_clear`, `fire_clear`, `shot_clear`, `detour`, `cover`, `flank`, `run_along`, `run_up_spot`, `DIRECTIONS`. Walking sees holes and props' ground as blocked; the line of fire and cover do not see holes; the line of fire minds a prop's tall body (`fire_clear`). It asks nothing about who made a wall or what the AI's staffs cast.
- **Behaviours** (`behaviours/`): each one stateless file (`name()`, `want(brain)`, `act(brain)`), one copy shared by every AI; per-AI memory goes in the brain's `picks` and `memo` at the behaviour's `index`. Now: chase, keep range (`position.gd`), fight, flank, close in, dodge, guard, evade, open, run up, heal ally, pick up, revive.
- **`TeamBoard`**: one per team, stepped by `Entities`, cleared on a new room: `started`, `beat`, `report`, `mate`, `mate_place`, `mate_health`, `note_attack`, `attackers`, `slot_angle`, `call_attack`, `is_calling`, `can_call`, `called_at`, `nearest_mate`. Fixed packed arrays; nothing allocated after it is made.
- **`CreatureLook`** (an `ActorLook`) draws an enemy: windup/hurt poses, flash, hop (`lift()`), staff pose, layered bodies (`BodyPose`, `body_pose()`, `parts()`), phase looks (`PhaseLook.parts`, `sync`). All of an enemy's drawing is here, none in the AI. A step sets nothing on nodes that did not change. One body of one sprite and the shared face share a `TexturePage` per kind. The telegraph lane is the card's `wind_cue` (Feel), not the look's.
- **`DummyLook`**: the training dummy's `dps()`, `status_text()`, `total_damage`.
- **`Entities`**: decoys and familiars in a fixed pool (four of each kind a player; enemies two each in 32 rows of their own after the players' 32; one more ends the oldest). A decoy is a regular actor (`DecoyController` aims it by `AIBrain.nearest_foe`; no lure; winds up nothing). A spawn belongs to its `caster` actor id; the body is `Actors.node_of` or the one named by `set_enemy`; no group or player index is read. `enemy_gone` ends an enemy's entities as it leaves. `step(delta)`, `decoy_of(caster)`. A new room or the run's end clears all without `entity_ended`.
- **Everything hurts everything:** an enemy's spells hit other enemies and its blasts hurt it; teams only aim.
- **Nothing allocates per step.** Timers slow by `Combat.pace`. Stay cheap with 100-200 enemies (`tests/benchmark/ai_step.gd`).
- **Dependency direction:** `core` ← `gameplay` ← `content`. Areas never call each other directly; they talk through events ([gameplay/README.md](../README.md)).
- **Events** (defined in `core/events/events.gd`):
  - Sends: `cover_danger_looked`, `aim_locked`, `ground_looked`, `actor_take_requested`, `entity_ended`.
  - Listens to: `entity_spawn_requested`, `entity_end_requested`, `room_entered`, `run_ended` (Entities); `damage_dealt`, `reaction_triggered` (`DummyLook`).

## Aim

An attack leads a moving target by its profile's `lead` and errs by a seeded error drawn once a cast, up to `AIM_ERROR` × (1 − `accuracy`). An enemy's (a brain that `warns()`) is tuned by `AimTuning` (`content/enemies/profiles/aim_tuning.tres`, `AIBrain.AIM_TUNING`; a test sets `aim_tuning`): its sharpness (`aim_sharpness()`) follows the room's depth level (`Actor.room_level`), never the player count; elites are sharper (`elite_sharpness`); `start_lead`, `start_error`, `sharp_level`, and the global `lead_scale`, `error_scale`. It aims by `aim_lead()` and `aim_error_most()`. Test bots are not tuned. Test: `tests/gameplay/ai/test_ai_aim.gd`.

## Allowed files

`.gd` and `.tres`, plus `.uid`, `.import` and `.license` files. 1 MB per file. Typed GDScript only; no banned APIs.

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md). **A new behaviour is one file in `behaviours/` and one line in `behaviours.gd`.** A new enemy configures a profile (`AIProfile`) and its staff in its content folder; it writes no AI code.

## Example to copy

`ai.gd` and `creature_look.gd`, put together in `content/enemies/ember_imp/` (`ember_imp.tscn`, `ember_imp.tres`). Test it on `tests/gameplay/ai/ai_fixture.gd` (its own world, real cards, up to four players, stepped by hand with fixed deltas), as `test_ai.gd`, `test_ai_telegraph.gd` and `test_ai_actors.gd` do.

## Tests

`tests/gameplay/ai/`: `test_ai_brain.gd`, `test_ai_combos.gd` (every combo played by an enemy), `test_ai_team.gd`, `test_ai_staff.gd`, `test_ai_sight.gd`, `test_ai_run_up.gd`, `test_ai_holes.gd`, `test_ai_pit_rooms.gd`, `test_ai_prop_cover.gd`, `test_ai_cover.gd`, `test_ai_pick_up.gd`, `test_ai_revive.gd`, `test_ai_poses.gd`, `test_enemy_page.gd`, `test_ai_aim.gd`; `tests/core/test_ai_names_no_card.gd`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

- Is the behaviour reusable by several enemies, targeting any of 1–4 players? Do 100–200 enemies stay within the frame budget?
- Does it keep to the dependency direction, without calling another area directly?

History and reasons: [docs/history/gameplay-ai-README.md](../../docs/history/gameplay-ai-README.md).
