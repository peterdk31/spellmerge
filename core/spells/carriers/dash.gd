class_name CarrierDash
extends CarrierMove
## Moves its caster `ray_length` along the move direction, striking every body it passes once
## (`&"dash"`). Homing turns it as it goes; its shield guards what it moves.


## Modifier cards that do nothing on a dash, with the sentence the builder shows after
## "<Card> does nothing on a Dash: ". Every card not listed does something here.
const DOES_NOTHING: Dictionary = {
	B.HOLD: "nothing keeps it on: a dash moves its caster and hits what it passes, once each",
	B.BOUNCE: "it turns a shot or a beam at walls, and a dash moves its caster and hits what it passes, once each",
	B.LINGER: "it only changes a moving shot, and a dash moves its caster and hits what it passes, once each",
	B.STICKY: "it only changes a moving shot, and a dash moves its caster and hits what it passes, once each",
	B.MAGNET: "it needs a shot or a beam that stays in the world, and a dash moves its caster and hits what it passes, once each",
	B.GHOST: "it only takes a flying shot or a line through walls, and a dash moves its caster and hits what it passes, once each",
	B.SPIRAL: "it only changes a moving shot, and a dash moves its caster and hits what it passes, once each",
	B.MIRROR: "a move and its mirror cancel",
	B.GROWTH: "it grows a shot in the world or a beam, and a dash moves its caster and hits what it passes, once each",
	B.RETURN: "it does not fly out",
	B.ARC: "it is not a shot that stays in the air",
}
## Trigger cards that never go off on a dash, with the sentence the builder shows.
const NEVER_FIRES: Dictionary = {
	E.WALL: "it stops before walls",
}


## A dash under way (rules R4c, `_start_pass`): it strikes every body its mover passes, once each.
class MovePass:
	extends RefCounted
	var tag: int = 0
	var spell: CompiledSpell = null
	var actor: int = 0
	## The shot it moves and that shot's seq, or -1 for the actor's own body.
	var shot: int = -1
	var seq: int = 0
	## Where the mover was at the last step (where it started, before the first), and the seconds left.
	var last: Vector2 = Vector2.INF
	var left: float = 0.0
	## The chain jumps its hits carry, the body before them, and what it hits with when not its
	## spell's own `hit` (an echo's), as a swing's.
	var chain: int = 0
	var prev: int = 0
	var hit: HitProfile = null
	var struck: Array[Node] = []
## Per actor, the homing of the wizard's last dash; the actor steers with it (`move_homing`).
var _dash_homing: Array[Homing] = []
## The homing of a dash that does not home (`move_homing` for an actor out of range).
var _no_homing: Homing = Homing.new()
## The dashes under way (`_start_pass`), and spare records for the next ones.
var _passes: Array[MovePass] = []
var _passes_free: Array[MovePass] = []


func id() -> StringName:
	return &"dash"


func noun() -> String:
	return "dash"


func what() -> String:
	return "a dash moves its caster and hits what it passes, once each"


func traits() -> int:
	return HITS | LASTS | REACHES | STEERS | SPEED | HOLDS_STAFF


func does_nothing() -> Dictionary:
	return DOES_NOTHING


func never_fires() -> Dictionary:
	return NEVER_FIRES


func bind(runtime: SpellRuntime, staff_poses: StaffPoses) -> void:
	super(runtime, staff_poses)
	for i in SpellRuntime.ACTORS:
		_dash_homing.append(Homing.new())


## Every dash under way ends quietly (`Spells.clear`).
func clear() -> void:
	for dash in _passes:
		dash.spell = null
		dash.hit = null
		dash.struck.clear()
		_passes_free.append(dash)
	_passes.clear()


func _move_seconds(spell: CompiledSpell) -> float:
	return CasterMoves.move_seconds(spell.ray_length, spell.speed, spell.lifetime)


## The body dashes: its owner picks the way (where it walks) and may home with `move_homing`; its
## way is drawn where it really goes, and it strikes every body it passes (`_start_pass`).
func _move_body(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, offset: Vector2, seconds: float, chain: int, prev: int) -> void:
	_dash_homing[actor].start(spell, hash(Vector2i(actor, tag)))
	rt.events.caster_move_requested.emit(actor, &"dash", origin + offset, seconds, tag)
	var reach: float = origin.distance_to(rt.projectiles.clip_to_walls(origin, origin + offset))
	rt.events.form_shown.emit(actor, &"dash", origin, _way, reach, spell.tint, spell.look)
	rt.projectiles.follow_caster(actor, spell.tint, spell.look, seconds)
	_start_pass(spell, tag, actor, -1, seconds, chain, prev)
	rt._lc_join(spell, tag, SpellRuntime.LC_ACTOR, actor, 0, false, seconds, origin, _way)


func _moved_shot(spell: CompiledSpell, tag: int, actor: int, shot: int, seconds: float, chain: int, prev: int) -> void:
	_start_pass(spell, tag, actor, shot, seconds, chain, prev)


## A dash under way (rules R4c): for its `seconds` (and SpellLimits.PASS_GRACE more, as its mover
## is moved and told a step later) it strikes every body its mover passes, once each, with its hit
## (`_pass_step`): the actor's own body (`shot` -1, its anchor) or the shot it moves. A new dash of
## the same body ends the one before (its mover replaces the move). Its echo hits as an echo.
func _start_pass(spell: CompiledSpell, tag: int, actor: int, shot: int, seconds: float, chain: int, prev: int) -> void:
	for other in _passes:
		if other.actor == actor and other.shot == shot:
			other.left = 0.0
	if _passes_free.is_empty():
		_passes_free.append(MovePass.new())
	var dash: MovePass = _passes_free.pop_back()
	dash.tag = tag
	dash.spell = spell
	dash.actor = actor
	dash.shot = shot
	dash.seq = rt.projectiles.get_seq_of(shot) if shot >= 0 else 0
	dash.last = rt.projectiles.get_anchor(actor) if shot < 0 else rt.projectiles.get_position_of(shot)
	dash.left = seconds + SpellLimits.PASS_GRACE
	dash.chain = chain
	dash.prev = prev
	dash.hit = spell.echo_hit if rt._echo_spell == spell else null
	dash.struck.clear()
	_passes.append(dash)
	rt.shot_started(tag)


## Runs the dashes under way on by `delta` (`Spells.step`): each strikes what its mover passed since the last step
## (and deflects the shots it passed, with `deflect`), then ends when its time is up, its mover is
## gone or its build is forgotten.
func step(delta: float) -> void:
	var i: int = 0
	while i < _passes.size():
		var dash: MovePass = _passes[i]
		var at: Vector2 = Vector2.INF
		if dash.shot < 0:
			at = rt.projectiles.get_anchor(dash.actor)
		elif rt.projectiles.is_alive(dash.shot) and rt.projectiles.get_seq_of(dash.shot) == dash.seq:
			at = rt.projectiles.get_position_of(dash.shot)
		if dash.left > 0.0 and at.is_finite() and rt._profiles.get(dash.tag) == dash.spell:
			_pass_step(dash, dash.last if dash.last.is_finite() else at, at)
			dash.last = at
			dash.left -= delta
		else:
			dash.left = 0.0
		if dash.left > 0.0:
			i += 1
			continue
		_passes.remove_at(i)
		var tag: int = dash.tag
		dash.spell = null
		dash.hit = null
		dash.struck.clear()
		_passes_free.append(dash)
		rt.shot_ended(tag)


## The dash `dash` moved from `from` to `to`: it strikes each body within SpellLimits.PASS_REACH of that
## way that it has not struck yet (`Projectiles.sweep` all round points PASS_REACH apart, so a
## fast dash misses nothing), and with `deflect` turns the shots within MOVE_GUARD_REACH of it.
func _pass_step(dash: MovePass, from: Vector2, to: Vector2) -> void:
	var spell: CompiledSpell = dash.spell
	var reach: float = SpellLimits.PASS_REACH
	var way: Vector2 = from.direction_to(to) if not from.is_equal_approx(to) else rt._moves.move_heading[dash.actor]
	if spell.behaviour(ModifierBase.Behaviour.DEFLECT) > 0.0:
		rt._guard(rt.projectiles.shots_on_segment(dash.actor, from, to, SpellLimits.MOVE_GUARD_REACH), dash.actor, dash.tag, true, 0, from, to)
	var samples: int = maxi(ceili(from.distance_to(to) / reach), 1)
	for n in samples:
		var point: Vector2 = from.lerp(to, float(n + 1) / samples)
		var found: int = rt.projectiles.sweep(dash.actor, point, way, 1, -PI, PI, reach, SpellRuntime.HITS)
		if found > 0:
			rt._strike_bodies(spell, dash.tag, dash.actor, found, dash.struck, point, way, dash.chain, dash.prev, dash.hit)
		if dash.left <= 0.0 or rt._profiles.get(dash.tag) != spell:
			return


## The homing of `actor`'s last dash, for the wizard to turn it as it goes (`Homing.steer`); one
## that does not home when the dash does not, or `actor` is out of range.
func move_homing(actor: int) -> Homing:
	return _dash_homing[actor] if actor >= 0 and actor < _dash_homing.size() else _no_homing
