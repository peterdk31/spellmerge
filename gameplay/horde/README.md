# Horde

## Purpose

The horde director: a separate game mode where the players hold out against a growing horde, to try the spell rules, the carriers and the engine on hundreds of enemies at once.

Built as part H3 of [docs/milestones/horde.md](../../docs/milestones/horde.md), an exception to the milestone order. It is easy to remove: delete this folder and the `Horde` autoload line (the milestone's "Removing it" lists the rest).

## Contract

- **Public entry script:** `gameplay/horde/horde.gd` (autoload `Horde`). Other code uses only this script and its events; nothing else in the folder is public. It runs a horde run's world from `horde_started(world)` until `horde_ended` or the next `horde_started` (a restart: it forgets the old world, takes its own nodes out of it and starts over). All timing is in `step(delta)` (`_process` calls it), so tests drive it with fixed deltas; the services (`events`, `registry`, `actors`), the `curve`, `view_size`, `rng` and `web` are set by tests before the node is added. The node is PROCESS_MODE_ALWAYS (the build break pauses the tree), but `_process` steps only while the tree is not paused or a break is on, so the pause menu still stops it.
  - **Spawning:** who and how many comes from the curve, `horde_curve.tres`, a `HordeCurve` (`horde_curve.gd`) of `HordeCurvePoint`s (`horde_curve_point.gd`): seconds, spawns per second, cap alive and weights by enemy id; between points every number is interpolated, past the ends the end point holds. Enemies appear on a ring `SPAWN_RING_MARGIN` past the edge of the camera's view (the world's `Camera2D`, its limits applied, `view_size` / zoom) around the middle of the standing wizards, clamped to the floor, never closer than `SPAWN_MIN_DISTANCE` to a wizard; up to `SPAWN_TRIES` directions are tried, and when the view shows the whole floor the spawn lands at the floor's edge. At most `SPAWN_PER_FRAME` a step, and never more alive than `max_alive()`: the curve's cap clamped to `MAX_ALIVE_DESKTOP` (200), or `MAX_ALIVE_WEB` (100) when `web` (`OS.has_feature("web")`). The floor is the box round the world's wall bodies (static bodies on layer 1), else the camera's limits, else the registry room `horde`'s spawns, else `FALLBACK_ARENA`; then `WALL_MARGIN` in (44: the 32-pixel wall and a 12-pixel body radius; in the horde arena, 1280×720 walled 32 px thick, the floor enemies stand on is Rect2(44, 44, 1192, 632)). The enemies come from the registry (`enemies`), are added under one `Horde` Node2D in the world (an `Actor` gets its `data`), and an id the registry lacks is skipped with one warning.
  - **Kills and experience:** an `enemy_died` whose enemy stands under the `Horde` node counts a kill, takes one off the alive count and drops a gem worth `GEM_XP` there. Every gem is one instance in one draw node (`horde_gems.gd`, a MultiMeshInstance2D, glow style; packed arrays sized `MAX_GEMS`). A standing wizard within `PICKUP_RADIUS` pulls a gem in; its experience is the party's: one shared level, next at `xp_next(level)` (5, 10, 17, 26, ...).
  - **Level-up:** every joined seat gets `horde_picks_offered(seat, OFFER_SIZE card ids)`, drawn from the spell cards (`spells`, `SpellComponent`) not in that seat's bag (the bag the director gave it). One open offer per seat; a level-up while one is open waits behind it and comes after the pick. With every card owned, no offer. `horde_pick_requested(seat, choice)` adds the card (`bag_set_requested`) and sends `horde_pick_taken`; a seat that leaves, a stop or a restart drops its open offer (`horde_pick_taken(seat, &"")`).
  - **Bags:** `bag_set_requested(seat, START_BAG)` (`dash`, `swing`: the cards of Flow's `HORDE_START_CARDS`) for every seat with a wizard on start, and for a joiner on the next step after its `player_joined` (Flow adds the joiner's wizard in its own handler of that event, and the player hears the request only once its wizard is in the tree).
  - **Build break** (owner, 2026-10-31: in Horde only, the game waits for every player): a level-up pauses the tree (`get_tree().paused`) and sends `horde_break_changed(true)` and `horde_ready_changed(seat, false)` for every joined seat; nothing spawns, the clock and the gems stand still, shots are not cleared. `horde_ready_requested(seat)` makes the seat ready (`horde_ready_changed(seat, true)`) only when it has no open or queued offer; earlier it is ignored. A seat with no offer still says ready. When every joined seat is ready the break ends: the tree is un-paused first, then `horde_break_changed(false)` (so the pause menu, if open, can pause again). A seat that leaves no longer counts (its leaving can end the break); one that joins in a break is ready at once (its start bag still goes out on the next step, which runs in a break). A level-up in a break adds offers and un-readies the seats that got one. `horde_over`, a stop (`horde_ended`) and a restart end it. `in_break()`, `is_ready(seat)`.
  - **Status:** `horde_status(seconds, kills, alive, level, xp, xp_next)` every `STATUS_INTERVAL` (0.25 s).
  - **The end:** when every joined wizard is down (`player_downed`, `player_revived`, `player_joined`, `player_left`), `horde_over(seconds, kills, level)` once; it is final until the next `horde_started` (Flow's restart is never cancelled), and nothing spawns after it.
  - **Wizards:** a seat's wizard is its home body in the actor table (`Actors.home_of_seat`, `node_of`) when it stands in the run's world.
  - **Cost:** no per-frame allocations; the alive count is a counter, a death is checked by its parent, nobody connects to an enemy; the only pass that grows is the gems' (at most `MAX_GEMS` against four wizards).
- **Dependency direction:** `core` ← `gameplay` ← `content`. This area uses `core/` (events, registry, actors), the base classes and the actor kit's `Actor`. Nothing depends on it.
- **Events** (`core/events/events.gd` owns the definitions; this list matches it and the table in [gameplay/README.md](../README.md)):
  - Sends: `horde_status`, `horde_picks_offered`, `horde_pick_taken`, `horde_break_changed`, `horde_ready_changed`, `horde_over`, `bag_set_requested`.
  - Listens to: `horde_started`, `horde_ended`, `horde_pick_requested`, `horde_ready_requested`, `enemy_died`, `player_downed`, `player_revived`, `player_joined`, `player_left`.
- Areas never call each other directly; they talk through events. [gameplay/README.md](../README.md) has the rules every sub-area shares.

## Allowed files

`.gd`, `.tres` and the swarm look's shader (`swarm_look.gdshader`, warmed by `horde.gd`), plus `.uid` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs. The text shared by all sub-areas is in [gameplay/README.md](../README.md).

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md). To tune the horde, edit the points of `horde_curve.tres`; the numbers are a first guess, tuned by playing (H6).

## Example to copy

`gameplay/horde/horde.gd`, with its test `tests/gameplay/horde/test_horde.gd` and its fixture `horde_fixture.gd` (a walled world out of the tree, a stand-in registry). Run it with `godot --headless --path . --script res://tests/gameplay/horde/test_horde.gd`.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick --tests
```

## Review questions

Besides the general review:

- Does it stay cheap with 600+ enemies alive (nothing per enemy per frame, no allocation in a step)?
- Does it work for any 1–4 seats, joining and leaving mid-run (also in a build break), with nobody waiting for anyone outside the build break?
- Can it still be removed by deleting the folder and the autoload line?
