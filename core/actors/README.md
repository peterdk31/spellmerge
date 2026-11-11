# Actors

## Purpose

The actor table: the one place an actor's id, team, look and seat are known (actors G2, [docs/milestones/M2-actors.md](../../docs/milestones/M2-actors.md), "Core: the actor table and one caster number"). An actor is anything that acts, a player or an enemy, and its id is its row in every system, so core never infers who someone is from a number.

## Contract

- **Public entry script:** `core/actors/actors.gd`, the autoload `Actors`. Services that need it take it injected (a `var` tests set, else the autoload), like Spells' `actors`.
- **Ids:** `open(team, ramp, seat := NONE) -> int` gives the lowest free id, 0 to `ACTORS - 1` (1024), or `NONE` (-1) when every id is taken; `close(id)` frees it; `is_open(id)`, `open_count()`. The lowest free id first, so a run hands out the same ids every time. No code may assume an actor id is a seat.
- **What it is:** `team_of(id)` (`TEAM_WIZARDS`, `TEAM_ENEMIES`, `TEAM_WORLD`): whom it aims at, never whether a hit lands. **Aim's one rule** is `is_foe(us, them)` (static): another team is a foe, the world's never (props W4, docs/milestones/props.md: the props' team is nobody's foe, so nothing aims at a prop, touches it for damage or counts its death as an enemy's; it is hit only by accident), and every team is the world's foe, so a prop's spells go for everyone; a body of no team (`NONE`) is everyone's foe, and with no team of our own every team but the world's is ours to aim at. Every aim test follows it (homing, a chain's jump, a zap, the AI's target, a touch, a discharge, a foes-only pull, `enemy_died`); the projectile manager's per-target loops and Combat's touch write it out, since a call per target costs more than the test, and the native homing search has its copy (`TEAM_WORLD` is among the constants it checks). Shields, deflects and threats go by a shot's own team, not by aim: a prop's blast is stopped by anyone's shield and dodged by everyone. `ramp_of(id)`: the colour ramp of its spells, 0–3 the hat colours, `RAMP_ENEMY` (4) Blight. `seat_of(id)`: the human (0–3, `SEATS`) driving it, or `NONE`. `teams()`: the table's own array of every id's team (`team_of` of each, `NONE` for an id not open), always current and read only, for a system that reads hundreds of teams a step (the projectile target grid, Combat's step).
- **Drivers:** `set_driver(id, team, seat)` is a controller change (a possession, a controller going home). A seat drives one actor at a time: seating an actor takes the seat from the actor that held it, which is left unseated (the newer driver wins). A seat outside 0–3 is no seat. `actor_of_seat(seat)` is the actor a seat drives now.
- **Home bodies:** `set_home(id, seat)` names the seat whose own body an actor is (a player: the actor sets it from its home controller's seat when it opens its id; a seat has one, the newer takes it), and `home_of_seat(seat)` finds it while the seat drives another actor or another controller drives it (possess): the HUD shows the home body (owner, 2026-10-28). Closing the actor frees it.
- **Budgets:** `budget_of(id)` is the seat (0–3) while a seat drives the actor, else `SHARED` (4): every actor no seat drives shares one budget, so enemies never take a player's share.
- **Nodes:** `set_node(id, node)` keeps only the node's instance id; `node_of(id)` gives the node, or null once it is freed or the actor is closed.
- **Safe:** an id outside the table or not open answers `NONE` (`budget_of` `SHARED`, `node_of` null) and changes nothing. `clear()` closes everything (a new run, and tests).
- **Performance:** packed arrays sized `ACTORS`; nothing is allocated after start.
- **Who opens ids (G3b):** the bodies themselves: a player (`gameplay/player`, `actor_id`: the players' team, ramp and seat of its index), an enemy that casts a staff (`gameplay/ai`, `caster`: the enemies' team, `RAMP_ENEMY`, no seat) and every actor of the kit (`gameplay/actor`, `id`). Spells, the projectile manager, Combat, Entities and Feel key their arrays and events by actor id and ask the table for team (aim), ramp (looks), budget (limits) and seat (HUD events); none of them opens ids.

## Allowed files

**Local stops (melee I7):** `hold(id, seconds)` holds an actor where it stands (the longer stop stands), `held_left(id)` reads it and `spend_hold(id, delta)` is what `Actor.step` calls: it returns the seconds of the step that still run (0 while held). `held_count` is how many are held, so a step with none held costs one comparison. A closed actor loses its hold. Feel is the one that holds (gameplay/feel/README.md).

Claude only, like all of `core/`. Typed GDScript, no banned APIs. Tests in `tests/core/test_actors.gd`.

## Steps

Take the task from the work queue. The table only says who an actor is; rules about what an actor does live in the systems that use it.

## Example to copy

None: the table is its own pattern. Its tests are `tests/core/test_actors.gd`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests
```

## Review questions

- Does the change keep "an actor id is not a seat" (tests open players at ids other than 0–3)?
- Does it stay allocation-free and deterministic (lowest free id first)?
