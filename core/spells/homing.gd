class_name Homing
extends RefCounted
## The homing of one thing that is not one of the projectile manager's own shots: a leg of a
## beam, a teleport, a wizard's dash (owner, 2026-10-27: one rule, easy to add a new form to).
## It holds what its spell's homing cards give (`start`), the target it keeps and the seed of
## its random pick; `steer` turns what moves over time, `point` and `aim` bend what is over at
## once (which ends at its target when that is within its distance: a beam ends on it, a
## teleport lands at its edge). A new kind of carrier that homes holds one of these and calls one of the three.
## The manager's shots keep the same numbers in its packed arrays, for speed, and pick the same
## way (`Projectiles.homing_point`).

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## Radians a second it turns (`CompiledSpell.homing_turn`), how far it looks
## (`homing_range`), and how far an instant carrier bends, in radians (`homing_angle`).
var turn: float = 0.0
var reach: float = 0.0
var bend: float = 0.0
## The instance id of the target it keeps (0 for none yet), and the seed of its random pick.
var keep: int = 0
var pick_seed: int = 0
## The hit radius of the target `point` last found (0 for none).
var target_radius: float = 0.0
## The id of a target to pick only when no other qualifies (one just reached), 0 for none.
var avoid: int = 0


## Takes `spell`'s homing, keeping no target yet; a spell that does not home stops it.
func start(spell: CompiledSpell, with_seed: int) -> void:
	if spell == null or spell.homing_range <= 0.0:
		stop()
		return
	turn = spell.homing_turn
	reach = spell.homing_range
	bend = deg_to_rad(spell.homing_angle)
	keep = 0
	avoid = 0
	pick_seed = with_seed


func stop() -> void:
	turn = 0.0
	reach = 0.0
	bend = 0.0
	keep = 0
	avoid = 0


func homes() -> bool:
	return reach > 0.0 and turn > 0.0


## `velocity` at `from` turned toward its target for `delta` seconds (a dash as it goes), or
## unchanged when it does not home or has nothing in reach.
func steer(projectiles: ProjectilesScript, player: int, from: Vector2, velocity: Vector2, delta: float) -> Vector2:
	if not homes() or projectiles == null:
		return velocity
	var turned: Vector2 = projectiles.home_velocity(player, from, velocity, turn, reach, delta, keep, pick_seed)
	keep = projectiles.homing_target
	return turned


## The centre of the target something at `from` going along `direction` bends to (a beam's
## leg), or INF when it does not home or has nothing in reach and in its bend.
func point(projectiles: ProjectilesScript, player: int, from: Vector2, direction: Vector2) -> Vector2:
	target_radius = 0.0
	if not homes() or projectiles == null:
		return Vector2.INF
	var goal: Vector2 = projectiles.homing_point(player, from, direction, bend, ProjectilesScript.LAYER_ENEMY, reach, keep, pick_seed, avoid)
	keep = projectiles.homing_target
	target_radius = projectiles.homing_target_radius
	return goal


## `direction` bent toward that target (a teleport), or unchanged.
func aim(projectiles: ProjectilesScript, player: int, from: Vector2, direction: Vector2) -> Vector2:
	var goal: Vector2 = point(projectiles, player, from, direction)
	return direction if not goal.is_finite() else from.direction_to(goal)
