class_name AISight
extends RefCounted
## What an AI sees of walls (owner, 2026-11-01: "handle walls better ... also useful for
## enemies"): shared by the enemy AI (`ai.gd`) and the test bots (`bench/bots/bot.gd`), so every
## AI reads walls one way. It asks the projectile manager's wall grid, which holds the room's
## walls and every live solid shot (a Wall card's, whoever cast it): the same grid shots stop on,
## so "clear" means a shot along the line would get through. A walk also asks of the ground of the
## bodies that cannot move (a pillar's footprint; boss plan OB14, decision 36: `walk_clear`), so
## the ways round (`detour`, `cover`) go round a blocking prop as round a wall. Two checks are kept
## apart (hub rework HR-H2, docs/milestones/hub-rework.md, "Holes" 6): **walking** sees a room's
## holes as it sees a prop's ground (`walk_clear`, `detour`, the run-up), so an AI walks round a
## crack; **the line of fire and cover** do not (`line_clear`, `ground_clear`, `shot_clear`, and
## `cover`'s wall), so it shoots across a crack and never hides behind one. The line of fire
## (`fire_clear`) also minds a prop's whole hit shape, which a shot stops on: a pillar's tall body
## hides a wizard behind it from a shot that would pass over its ground. Static, nothing
## allocated per call.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## The eight ways a detour is probed, clockwise from right.
const DIRECTIONS: Array[Vector2] = [
	Vector2(1, 0), Vector2(0.70710678, 0.70710678), Vector2(0, 1), Vector2(-0.70710678, 0.70710678),
	Vector2(-1, 0), Vector2(-0.70710678, -0.70710678), Vector2(0, -1), Vector2(0.70710678, -0.70710678)]
## A probe end the goal is in view from beats any end it is not, whatever the distance.
const IN_VIEW_BONUS: float = 100000.0
## How many probes out a flank looks (`flank`): its probe, then twice it.
const FLANK_REACH: int = 2
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
	return projectiles == null or projectiles.grid().line_clear(from, to)


## True when a shot from `from` to `to` (body to body) would get there: no wall (room or spell) and
## no prop's hit shape (a pillar's whole body, not only its ground: a shot is spent on it) within
## `width` of the line (its shot's hit width either side) before the shot meets its target, `short`
## pixels before `to` (the target's reach plus `width`: a wizard hugging a pillar is still hit by a
## shot from its open side). What an AI's line of fire asks before an aimed cast. Without a
## projectile manager nothing blocks.
static func fire_clear(projectiles: ProjectilesScript, from: Vector2, to: Vector2, width: float = 0.0, short: float = 0.0) -> bool:
	if projectiles == null:
		return true
	var length: float = from.distance_to(to)
	var end: Vector2 = to
	if short > 0.0 and length > 0.0:
		end = from + (to - from) * maxf(1.0 - short / length, 0.0)
	return projectiles.line_clear(from, end) and projectiles.props_clear(from, end, width)


## True when no ground of a body that cannot move (a pillar's footprint) lies between `from` and
## `to`: a body's feet to another's. Without a projectile manager nothing blocks.
static func ground_clear(projectiles: ProjectilesScript, from: Vector2, to: Vector2) -> bool:
	return projectiles == null or projectiles.grid().ground_clear(from, to)


## True when a body could walk from `from` to `to` in a line: no wall (room or spell), no ground
## of a body that cannot move and no hole (HR-H2) on it.
static func walk_clear(projectiles: ProjectilesScript, from: Vector2, to: Vector2) -> bool:
	return projectiles == null or (projectiles.grid().line_clear(from, to) and projectiles.grid().walk_clear(from, to))


## True when a walk's feet from `from` to `to` meet no ground of a body that cannot move and no hole
## (HR-H2), walls aside: `ground_clear` for walking.
static func feet_clear(projectiles: ProjectilesScript, from: Vector2, to: Vector2) -> bool:
	return projectiles == null or projectiles.grid().walk_clear(from, to)


## True when nothing a shot would stop at lies from `from` to `to`: no wall and no blocking body's
## ground; a hole is no cover (HR-H2). What `cover` looks for between an end and the threat.
static func shot_clear(projectiles: ProjectilesScript, from: Vector2, to: Vector2) -> bool:
	return projectiles == null or (projectiles.grid().line_clear(from, to) and projectiles.grid().ground_clear(from, to))


## How far a body of `radius` at `from` could run along `way` before its rim meets a wall or a
## blocking body's ground, at most `most` (pixels; `most` with no projectile manager): a move's
## line (boss plan OB14, the run-up).
static func run_along(projectiles: ProjectilesScript, from: Vector2, way: Vector2, most: float, radius: float) -> float:
	if projectiles == null:
		return most
	return clampf(projectiles.grid().clear_run(from, way, most + radius) - radius, 0.0, most)


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
		var back: float = minf(projectiles.grid().clear_run(target, way, reach) - radius - RUN_UP_MARGIN, reach * RUN_UP_NEAR)
		if back <= radius:
			continue
		var spot: Vector2 = target + way * back
		if projectiles.grid().circle_blocked(spot, radius, true):
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


## The way (unit length) to a place its target can be shot from: of the eight ways whose first
## `probe` pixels can be walked, one from whose end a shot `width` either side would reach `aim` (the
## target's body, `short` of it; `fire_clear`, from the end's body, `eye` above its feet) and no blocking body's
## ground lies on to `goal` (the target's feet; `ground_clear`), as the brain's line of fire asks;
## the end whose distance to `aim` is nearest its own now (a step round, not a walk past the prop
## into the target). With none, the same `FLANK_REACH` times as far (a wizard right behind a pillar
## is hidden in a wide shadow); ZERO when none is near, or with no projectile manager.
static func flank(projectiles: ProjectilesScript, from: Vector2, goal: Vector2, aim: Vector2, eye: Vector2, probe: float, width: float = 0.0, short: float = 0.0) -> Vector2:
	if projectiles == null:
		return Vector2.ZERO
	var now: float = (from + eye).distance_to(aim)
	for ring in FLANK_REACH:
		var length: float = probe * float(ring + 1)
		var best: Vector2 = Vector2.ZERO
		var best_change: float = INF
		for way: Vector2 in DIRECTIONS:
			var end: Vector2 = from + way * length
			if not walk_clear(projectiles, from, end) or not ground_clear(projectiles, end, goal) or not fire_clear(projectiles, end + eye, aim, width, short):
				continue
			var change: float = absf((end + eye).distance_to(aim) - now)
			if change < best_change:
				best_change = change
				best = way
		if best != Vector2.ZERO:
			return best
	return Vector2.ZERO


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
		if not walk_clear(projectiles, from, end) or shot_clear(projectiles, end, threat):
			continue
		var distance: float = end.distance_squared_to(threat)
		if distance > best_distance:
			best_distance = distance
			best = way
	return best
