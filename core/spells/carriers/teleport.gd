class_name CarrierTeleport
extends CarrierMove
## Blinks its caster `ray_length` along the aim, stopping before walls, and strikes the bodies where
## it lands (`&"teleport"`). Over at once: homing bends its way, recoil shortens it.


## Its homing, and actor -> the target its last teleport landed at (so the next one picks another).
var _teleport_homing: Homing = Homing.new()
var _landed_at: PackedInt64Array = PackedInt64Array()


func id() -> StringName:
	return &"teleport"


func noun() -> String:
	return "teleport"


func what() -> String:
	return "a teleport moves its caster at once and hits where it lands"


func traits() -> int:
	return HITS | REACHES | STEERS | INSTANT_HOMING | MOVES_CASTER | MEETS_SHOTS


## It strikes what is where it landed (rules R4c): each body within SpellLimits.LAND_REACH, pushed
## outward from there, and with `deflect` turns the shots within MOVE_GUARD_REACH.
func on_move_end(spell: CompiledSpell, tag: int, actor: int, at: Vector2, heading: Vector2) -> void:
	if spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0:
		rt._guard(rt.projectiles.shots_on_segment(actor, at, at, SpellLimits.MOVE_GUARD_REACH), actor, tag, true, 0, at, at)
	var found: int = rt.projectiles.sweep(actor, at, heading, 1, -PI, PI, SpellLimits.LAND_REACH, SpellRuntime.HITS)
	if found > 0:
		var struck: Array[Node] = []
		rt._strike_bodies(spell, tag, actor, found, struck, at, heading, spell.chain_jumps, 0, spell.echo_hit if rt._echo_spell == spell else null)


func bind(runtime: SpellRuntime, staff_poses: StaffPoses) -> void:
	super(runtime, staff_poses)
	_landed_at.resize(SpellRuntime.ACTORS)


func clear() -> void:
	_landed_at.fill(0)


func reset_actor(actor: int) -> void:
	_landed_at[actor] = 0


func _moves_from_a_point() -> bool:
	return true


## A teleport is over at once: like a beam it bends its way toward a target, and like a beam it
## ends there when the target is within its distance, at the target's edge. Its recoil is taken
## off its distance (past it, it goes backwards).
func _aim_move(spell: CompiledSpell, tag: int, actor: int, origin: Vector2) -> void:
	_teleport_homing.start(spell, hash(Vector3i(actor, tag, roundi(rt._clock * 1000.0))))
	_teleport_homing.avoid = _landed_at[actor] if actor >= 0 and actor < _landed_at.size() else 0
	var goal: Vector2 = _teleport_homing.point(rt.projectiles, actor, origin, _way)
	if goal.is_finite() and not goal.is_equal_approx(origin):
		_way = origin.direction_to(goal)
		var gap: float = origin.distance_to(goal) - _teleport_homing.target_radius - SpellLimits.LAND_CLEARANCE
		if gap <= _distance and actor >= 0 and actor < _landed_at.size():
			_landed_at[actor] = _teleport_homing.keep
		_distance = minf(_distance, maxf(gap, 0.0))
	_distance -= spell.behaviour(ModifierBase.Behaviour.RECOIL)


func _move_body(_spell: CompiledSpell, tag: int, actor: int, origin: Vector2, offset: Vector2, _seconds: float, _chain: int, _prev: int) -> void:
	rt.events.caster_move_requested.emit(actor, &"teleport", rt.projectiles.clip_to_walls(origin, origin + offset), 0.0, tag)


## Its recoil is taken off its distance (`_aim_move`), not pushed.
func handles_recoil() -> bool:
	return true
