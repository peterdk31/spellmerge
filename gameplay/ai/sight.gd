class_name AISight
extends RefCounted
## What an AI sees of walls (owner, 2026-11-01: "handle walls better ... also useful for
## enemies"): shared by the enemy AI (`ai.gd`) and the test bots (`tests/bots/bot.gd`), so every
## AI reads walls one way. It asks the projectile manager's wall grid, which holds the room's
## walls and every live solid shot (a Wall card's, whoever cast it): the same grid shots stop on,
## so "clear" means a shot along the line would get through. A walk also asks of the ground of the
## bodies that cannot move (a pillar's footprint; boss plan OB14, decision 36: `walk_clear`), so
## the ways round (`detour`, `cover`) go round a blocking prop as round a wall. Static, nothing
## allocated per call.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## The eight ways a detour is probed, clockwise from right.
const DIRECTIONS: Array[Vector2] = [
	Vector2(1, 0), Vector2(0.70710678, 0.70710678), Vector2(0, 1), Vector2(-0.70710678, 0.70710678),
	Vector2(-1, 0), Vector2(-0.70710678, -0.70710678), Vector2(0, -1), Vector2(0.70710678, -0.70710678)]
## A probe end the goal is in view from beats any end it is not, whatever the distance.
const IN_VIEW_BONUS: float = 100000.0
## The run-up (boss plan OB14): the ways round its target a start is looked for along, and how far
## clear of the wall behind it the body stands there (pixels past its own radius).
const RUN_UP_WAYS: int = 16
const RUN_UP_MARGIN: float = 4.0
## A run-up's start is no farther from the target than this share of the move's reach, so the
## target is met well inside the run (the rest of it carries on past).
const RUN_UP_NEAR: float = 0.7
## Each pixel walked to a start costs this many pixels of run: a nearer start that runs a little
## shorter is the better one.
const RUN_UP_WALK_COST: float = 0.5


## True when no wall (room or spell) lies between `from` and `to`. Without a projectile manager
## nothing blocks.
static func line_clear(projectiles: ProjectilesScript, from: Vector2, to: Vector2) -> bool:
	return projectiles == null or projectiles.line_clear(from, to)


## True when no ground of a body that cannot move (a pillar's footprint) lies between `from` and
## `to`: a body's feet to another's. Without a projectile manager nothing blocks.
static func ground_clear(projectiles: ProjectilesScript, from: Vector2, to: Vector2) -> bool:
	return projectiles == null or projectiles.ground_clear(from, to)


## True when a body could walk from `from` to `to` in a line: no wall (room or spell) and no ground
## of a body that cannot move on it.
static func walk_clear(projectiles: ProjectilesScript, from: Vector2, to: Vector2) -> bool:
	return projectiles == null or (projectiles.line_clear(from, to) and projectiles.ground_clear(from, to))


## How far a body of `radius` at `from` could run along `way` before its rim meets a wall or a
## blocking body's ground, at most `most` (pixels; `most` with no projectile manager): a move's
## line (boss plan OB14, the run-up).
static func run_along(projectiles: ProjectilesScript, from: Vector2, way: Vector2, most: float, radius: float) -> float:
	if projectiles == null:
		return most
	return clampf(projectiles.clear_run(from, way, most + radius) - radius, 0.0, most)


## Where a body of `radius` at `from` should stand to run a move `reach` long at `target` (boss
## plan OB14, the run-up: "a wall's foot facing the open room"): of RUN_UP_WAYS ways round the
## target, the start back along each, at the foot of what stands behind it but no farther than
## RUN_UP_NEAR of the reach, where the body can stand; scored by how long the run from there through
## the target goes (`run_along`, at most `reach`) less RUN_UP_WALK_COST for each pixel walked to it,
## a start it could not walk to in a line costing it twice. Vector2.INF when none can be stood on
## (or with no projectile manager).
static func run_up_spot(projectiles: ProjectilesScript, from: Vector2, target: Vector2, reach: float, radius: float) -> Vector2:
	if projectiles == null or reach <= 0.0:
		return Vector2.INF
	var best: Vector2 = Vector2.INF
	var best_score: float = -INF
	for k in RUN_UP_WAYS:
		var way: Vector2 = DMath.from_angle(float(k) * TAU / float(RUN_UP_WAYS))
		var back: float = minf(projectiles.clear_run(target, way, reach) - radius - RUN_UP_MARGIN, reach * RUN_UP_NEAR)
		if back <= radius:
			continue
		var spot: Vector2 = target + way * back
		if projectiles.circle_blocked(spot, radius):
			continue
		var run: float = minf(back + run_along(projectiles, target, -way, reach, radius), reach)
		var walk: float = from.distance_to(spot)
		if not walk_clear(projectiles, from, spot):
			walk *= 2.0
		var score: float = run - walk * RUN_UP_WALK_COST
		if score > best_score:
			best_score = score
			best = spot
	return best


## The way (unit length) to walk round a wall (or a blocking body's ground) between `from` and
## `goal`: of the eight ways whose first `probe` pixels can be walked (`walk_clear`), one from whose
## end `goal` can be walked to in a line, the nearest to `goal`;
## else the free one ending nearest `goal`; straight at `goal` when none is free or there is no
## projectile manager.
static func detour(projectiles: ProjectilesScript, from: Vector2, goal: Vector2, probe: float) -> Vector2:
	var straight: Vector2 = (goal - from).normalized()
	if projectiles == null:
		return straight
	var best: Vector2 = straight
	var best_score: float = INF
	for way: Vector2 in DIRECTIONS:
		var end: Vector2 = from + way * probe
		if not walk_clear(projectiles, from, end):
			continue
		var score: float = end.distance_to(goal)
		if walk_clear(projectiles, end, goal):
			score -= IN_VIEW_BONUS
		if score < best_score:
			best_score = score
			best = way
	return best


## The way (unit length) to cover from `threat`: of the eight ways whose first `probe` pixels can
## be walked, one whose end has a wall (any wall: a room's, a Wall card's, whoever cast it; or a
## blocking body's ground, a pillar) between it and `threat`, the end farthest from `threat`; ZERO when no such end is near, or with no
## projectile manager. It asks nothing about what the wall is or who made it.
static func cover(projectiles: ProjectilesScript, from: Vector2, threat: Vector2, probe: float) -> Vector2:
	if projectiles == null:
		return Vector2.ZERO
	var best: Vector2 = Vector2.ZERO
	var best_distance: float = -1.0
	for way: Vector2 in DIRECTIONS:
		var end: Vector2 = from + way * probe
		if not walk_clear(projectiles, from, end) or walk_clear(projectiles, end, threat):
			continue
		var distance: float = end.distance_squared_to(threat)
		if distance > best_distance:
			best_distance = distance
			best = way
	return best
