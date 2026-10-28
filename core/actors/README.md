# Actors

## Purpose

The actor table: the one place an actor's id, team, look and seat are known (actors G2, [docs/milestones/M2-actors.md](../../docs/milestones/M2-actors.md), "Core: the actor table and one caster number"). An actor is anything that acts, a wizard or an enemy, and its id is its row in every system, so core never infers who someone is from a number.

## Contract

- **Public entry script:** `core/actors/actors.gd`, the autoload `Actors`. Services that need it take it injected (a `var` tests set, else the autoload), like Spells' `actors`.
- **Ids:** `open(team, ramp, seat := NONE) -> int` gives the lowest free id, 0 to `ACTORS - 1` (512), or `NONE` (-1) when every id is taken; `close(id)` frees it; `is_open(id)`, `open_count()`. The lowest free id first, so a run hands out the same ids every time. No code may assume an actor id is a seat.
- **What it is:** `team_of(id)` (`TEAM_WIZARDS`, `TEAM_ENEMIES`): whom it aims at, never whether a hit lands. `ramp_of(id)`: the colour ramp of its spells, 0–3 the hat colours, `RAMP_ENEMY` (4) Blight. `seat_of(id)`: the human (0–3, `SEATS`) driving it, or `NONE`.
- **Drivers:** `set_driver(id, team, seat)` is a controller change (a possession, a controller going home). A seat drives one actor at a time: seating an actor takes the seat from the actor that held it, which is left unseated (the newer driver wins). A seat outside 0–3 is no seat. `actor_of_seat(seat)` is the actor a seat drives now.
- **Budgets:** `budget_of(id)` is the seat (0–3) while a seat drives the actor, else `SHARED` (4): every actor no seat drives shares one budget, so enemies never take a player's share.
- **Nodes:** `set_node(id, node)` keeps only the node's instance id; `node_of(id)` gives the node, or null once it is freed or the actor is closed.
- **Safe:** an id outside the table or not open answers `NONE` (`budget_of` `SHARED`, `node_of` null) and changes nothing. `clear()` closes everything (a new run, and tests).
- **Performance:** packed arrays sized `ACTORS`; nothing is allocated after start.
- **Who opens ids (G3b):** the bodies themselves: a wizard (`gameplay/player`, `actor_id`: the wizards' team, ramp and seat of its index), an enemy that casts a staff (`gameplay/ai`, `caster`: the enemies' team, `RAMP_ENEMY`, no seat) and every actor of the kit (`gameplay/actor`, `id`). Spells, the projectile manager, Combat, Entities and Feel key their arrays and events by actor id and ask the table for team (aim), ramp (looks), budget (limits) and seat (HUD events); none of them opens ids.

## Allowed files

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

- Does the change keep "an actor id is not a seat" (tests open wizards at ids other than 0–3)?
- Does it stay allocation-free and deterministic (lowest free id first)?
