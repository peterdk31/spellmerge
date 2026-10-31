class_name CarrierTeleport
extends CarrierMove
## Blinks its caster `ray_length` along the aim, stopping before walls, and strikes the bodies where
## it lands (`&"teleport"`). Over at once: homing bends its way.


## Its homing, and actor -> the target its last teleport landed at (so the next one picks another).
var _teleport_homing: Homing = Homing.new()
var _landed_at: PackedInt64Array = PackedInt64Array()


func id() -> StringName:
	return &"teleport"


func traits() -> int:
	return HITS | REACHES | STEERS | INSTANT_HOMING | MOVES_CASTER | MEETS_SHOTS


## It strikes what is where it landed (rules R4c): each body within SpellLimits.LAND_REACH
## (`Spells._strike_round`), and with `deflect` turns the shots within MOVE_GUARD_REACH.
func on_move_end(spell: CompiledSpell, tag: int, actor: int, at: Vector2, heading: Vector2) -> void:
	if spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0:
		kit.guard(kit.projectiles.shots_on_segment(actor, at, at, SpellLimits.MOVE_GUARD_REACH), actor, tag, true, 0, at, at, id())
	kit.strike_round(spell, tag, actor, at, heading, SpellLimits.LAND_REACH, spell.echo_hit if kit.is_echo(spell) else null)


func bind(runtime_kit: CarrierKit, staff_poses: StaffPoses) -> void:
	super(runtime_kit, staff_poses)
	_landed_at.resize(SpellRuntime.ACTORS)


## The swarm promoted a body (`Carrier.replace_body`): a teleport that landed at `old` landed at
## `new`.
func replace_body(old: Node, new: Node) -> void:
	_replace_in_rows(old, new, [], _landed_at)


func clear() -> void:
	_landed_at.fill(0)


func reset_actor(actor: int) -> void:
	_landed_at[actor] = 0


## A teleport is over at once: like a beam it bends its way toward a target, and like a beam it
## ends there when the target is within its distance, at the target's edge.
func _aim_move(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, way: Vector2, distance: float) -> Vector3:
	_teleport_homing.start(spell, hash(Vector3i(actor, tag, roundi(kit.clock() * 1000.0))))
	_teleport_homing.avoid = _landed_at[actor] if actor >= 0 and actor < _landed_at.size() else 0
	var goal: Vector2 = _teleport_homing.point(kit.projectiles, actor, origin, way)
	if goal.is_finite() and not goal.is_equal_approx(origin):
		way = origin.direction_to(goal)
		var gap: float = origin.distance_to(goal) - _teleport_homing.target_radius - SpellLimits.LAND_CLEARANCE
		if gap <= distance and actor >= 0 and actor < _landed_at.size():
			_landed_at[actor] = _teleport_homing.keep
		distance = minf(distance, maxf(gap, 0.0))
	return Vector3(way.x, way.y, distance)


func _move_body(_spell: CompiledSpell, tag: int, actor: int, _origin: Vector2, _way: Vector2, offset: Vector2, _seconds: float, _chain: int, _prev: int) -> void:
	kit.events.caster_move_requested.emit(actor, &"teleport", offset, 0.0, tag)

