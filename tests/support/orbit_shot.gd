extends RefCounted
## Orbit shots for the projectile tests (orbit as a modifier, part 5A): the manager has no
## `spawn_orbit` any more; the Orbit card turns a live straight shot onto its circle with
## `set_orbit(slot, orbit_radius, angle, drift, centre)`, and the shot turns by its drift plus its
## own speed over the radius. `start` makes the shot the old `spawn_orbit` made: one with no speed
## of its own, put on the circle, so it turns by `turn` radians a second exactly (its drift).
##
##     const OrbitShot := preload("res://tests/support/orbit_shot.gd")
##     var slot: int = OrbitShot.start(mgr, caster, 40.0, 0.0, 3.0, 5.0)

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")


## A shot of `caster` circling its anchor (or `centre` when finite) `orbit_radius` pixels out from
## `angle`, turning `turn` radians a second; the rest are `spawn`'s. Returns its slot, or -1 where
## `spawn` or `set_orbit` would refuse it (an invalid caster, bad numbers, an origin in a room wall,
## no centre), having taken no slot.
static func start(mgr: Node2D, caster: int, orbit_radius: float, angle: float, turn: float, lifetime: float, radius: float = 4.0, hit_layers: int = ManagerScript.LAYER_ENEMY, pierce: int = 0, tag: int = 0, centre: Vector2 = Vector2.INF) -> int:
	var around: Vector2 = centre if centre.is_finite() else mgr.get_anchor(caster) as Vector2
	if not around.is_finite() or not is_finite(orbit_radius) or not is_finite(angle) or not is_finite(turn):
		return -1
	var slot: int = mgr.spawn(caster, around + DMath.from_angle(angle) * maxf(orbit_radius, 0.0), Vector2.ZERO, lifetime, radius, hit_layers, pierce, tag) as int
	if slot < 0:
		return -1
	if not mgr.set_orbit(slot, orbit_radius, angle, turn, centre):
		push_error("OrbitShot.start: set_orbit refused a shot spawn took")
		return -1
	return slot
