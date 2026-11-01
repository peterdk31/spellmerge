class_name AISight
extends RefCounted
## What an AI sees of walls (owner, 2026-11-01: "handle walls better ... also useful for
## enemies"): shared by the enemy AI (`ai.gd`) and the test bots (`tests/bots/bot.gd`), so every
## AI reads walls one way. It asks the projectile manager's wall grid, which holds the room's
## walls and every live solid shot (a Wall card's, whoever cast it): the same grid shots stop on,
## so "clear" means a shot along the line would get through. Static, nothing allocated per call.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## The eight ways a detour is probed, clockwise from right.
const DIRECTIONS: Array[Vector2] = [
	Vector2(1, 0), Vector2(0.70710678, 0.70710678), Vector2(0, 1), Vector2(-0.70710678, 0.70710678),
	Vector2(-1, 0), Vector2(-0.70710678, -0.70710678), Vector2(0, -1), Vector2(0.70710678, -0.70710678)]
## A probe end the goal is in view from beats any end it is not, whatever the distance.
const IN_VIEW_BONUS: float = 100000.0


## True when no wall (room or spell) lies between `from` and `to`. Without a projectile manager
## nothing blocks.
static func line_clear(projectiles: ProjectilesScript, from: Vector2, to: Vector2) -> bool:
	return projectiles == null or projectiles.line_clear(from, to)


## The way (unit length) to walk round a wall between `from` and `goal`: of the eight ways whose
## first `probe` pixels are free, one from whose end `goal` is in view, the nearest to `goal`;
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
		if not projectiles.line_clear(from, end):
			continue
		var score: float = end.distance_to(goal)
		if projectiles.line_clear(end, goal):
			score -= IN_VIEW_BONUS
		if score < best_score:
			best_score = score
			best = way
	return best


## The way (unit length) to cover from `threat`: of the eight ways whose first `probe` pixels are
## free, one whose end has a wall (any wall: a room's, a Wall card's, whoever cast it) between it
## and `threat`, the end farthest from `threat`; ZERO when no such end is near, or with no
## projectile manager. It asks nothing about what the wall is or who made it.
static func cover(projectiles: ProjectilesScript, from: Vector2, threat: Vector2, probe: float) -> Vector2:
	if projectiles == null:
		return Vector2.ZERO
	var best: Vector2 = Vector2.ZERO
	var best_distance: float = -1.0
	for way: Vector2 in DIRECTIONS:
		var end: Vector2 = from + way * probe
		if not projectiles.line_clear(from, end) or projectiles.line_clear(end, threat):
			continue
		var distance: float = end.distance_squared_to(threat)
		if distance > best_distance:
			best_distance = distance
			best = way
	return best
