class_name CarrierTeleport
extends CarrierMove
## Blinks its caster `ray_length` along the aim, stopping before walls, and strikes the bodies where
## it lands (`&"teleport"`). Over at once: homing bends its way, recoil shortens it.


## Each modifier behaviour (`ModifierBase.Behaviour`) on the teleport, every one (keys: see `Carrier`).
const BEHAVIOURS: Dictionary = {
	B.NONE: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a teleport is over at once and draws nothing of its own: its cards show only in its hits"},
	B.HOMING: {"works": Works.OWN_WAY, "shows": Shows.NOTHING, "why_nothing_shows": "a teleport is over at once and draws nothing of its own: its cards show only in its hits"},
	B.CHAIN: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a teleport is over at once and draws nothing of its own: its cards show only in its hits"},
	B.SHIELD: {"works": Works.OWN_WAY, "shows": Shows.NOTHING, "why_nothing_shows": "a teleport is over at once and draws nothing of its own: its cards show only in its hits"},
	B.BLAST: {"works": Works.YES, "shows": Shows.AS_EFFECT},
	B.HOLD: {"works": Works.NO, "why_not": "nothing keeps it on: a teleport moves its caster at once and hits where it lands"},
	B.RECOIL: {"works": Works.OWN_WAY, "shows": Shows.NOTHING, "why_nothing_shows": "a teleport is over at once and draws nothing of its own: its cards show only in its hits"},
	B.BOUNCE: {"works": Works.NO, "why_not": "it turns a shot or a beam at walls, and a teleport moves its caster at once and hits where it lands"},
	B.ECHO: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a teleport is over at once and draws nothing of its own: its cards show only in its hits"},
	B.LINGER: {"works": Works.NO, "why_not": "it only changes a moving shot, and a teleport moves its caster at once and hits where it lands"},
	B.HEAVY: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a teleport is over at once and draws nothing of its own: its cards show only in its hits"},
	B.SIPHON: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a teleport is over at once and draws nothing of its own: its cards show only in its hits"},
	B.STICKY: {"works": Works.NO, "why_not": "it only changes a moving shot, and a teleport moves its caster at once and hits where it lands"},
	B.MAGNET: {"works": Works.NO, "why_not": "it needs a shot or a beam that stays in the world, and a teleport moves its caster at once and hits where it lands"},
	B.GHOST: {"works": Works.NO, "why_not": "it only takes a flying shot or a line through walls, and a teleport moves its caster at once and hits where it lands"},
	B.SPIRAL: {"works": Works.NO, "why_not": "it only changes a moving shot, and a teleport moves its caster at once and hits where it lands"},
	B.MIRROR: {"works": Works.NO, "why_not": "a move and its mirror cancel"},
	B.GROWTH: {"works": Works.NO, "why_not": "it grows a shot in the world or a beam, and a teleport moves its caster at once and hits where it lands"},
	B.RELAY: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a teleport is over at once and draws nothing of its own: its cards show only in its hits"},
	B.RETURN: {"works": Works.NO, "why_not": "it does not fly out"},
	B.ARC: {"works": Works.NO, "why_not": "it is not a shot that stays in the air"},
	B.POSSESS: {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a teleport is over at once and draws nothing of its own: its cards show only in its hits"},
	B.DEFLECT: {"works": Works.OWN_WAY, "shows": Shows.NOTHING, "why_nothing_shows": "a teleport is over at once and draws nothing of its own: its cards show only in its hits"},
}
## Each trigger (`TriggerBase.Event`) on the teleport: "fires" (does it ever go off here?) and, when it
## never does, "why_not".
const EVENTS: Dictionary = {
	E.HIT: {"fires": true},
	E.EXPIRE: {"fires": true},
	E.TIMER: {"fires": false, "why_not": "it is over at once"},
	E.BLOCK: {"fires": true},
	E.KILL: {"fires": true},
	E.CAST: {"fires": true},
	E.WALL: {"fires": false, "why_not": "it stops before walls"},
	E.HURT: {"fires": false, "why_not": "it is over at once"},
	E.REACTION: {"fires": true},
}
## An infusion (an element card) on the teleport, with the same keys as a behaviour.
const INFUSIONS: Dictionary = {"works": Works.YES, "shows": Shows.NOTHING, "why_nothing_shows": "a teleport is over at once and draws nothing of its own: its cards show only in its hits"}


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
	return HITS | REACHES | STEERS | INSTANT_HOMING


func behaviours() -> Dictionary:
	return BEHAVIOURS


func events() -> Dictionary:
	return EVENTS


func infusions() -> Dictionary:
	return INFUSIONS



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
