class_name CarrierMove
extends Carrier
## A carrier that moves its caster `ray_length` pixels (a dash, a teleport): a card's distance is
## fixed, and its speed only says how long a dash takes (`CasterMoves.move_seconds`), so `faster`
## arrives sooner, not farther. What it moves is its caster (`CasterMoves.moved_by`): a body is
## asked through its owner (`caster_move_requested`: the wizard's for its own cast, whose player
## picks a dash's way, the way it walks, and answers where it stops, staffs A6a; a decoy's for a
## payload its body fired, owner 2026-11-06); a shot that cast it is moved along `direction` itself,
## and its end point comes when the move is over (`CasterMoves.track`). A dash the wizard casts
## itself takes the way its body walks in place of the aim (`Spells.cast_staff`'s `walk`), so a
## mirrored one goes back the other way. A point cannot move, so a move cast by one moves the wizard
## to it (rules R4c, F1). Its `shield` guards what it moves (`CasterMoves.shield`). The subclasses
## say what is their own: the way and distance (`_aim_move`), how long it takes (`_move_seconds`)
## and what starts with it (`_move_body`, `_moved_shot`). A move's way and distance are its
## launch's own: what it emits may launch another move of the same carrier (a payload on the end of
## the move it replaces) before it is done.


func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, _source: Node, _lifetime: float, chain: int, prev: int) -> int:
	var distance: float = CasterMoves.move_distance(spell.ray_length, spell.speed, spell.lifetime)
	var way: Vector2 = direction
	var caster: int = kit.caster()
	var moved: int = CasterMoves.moved_by(caster, actor)
	var body: int = SpellRuntime.body_of(moved, actor)
	if caster == SpellRuntime.CASTER_BODY and _walks():
		# Turned as far as the walk is off the aim (staffs A6a), so a mirrored one goes the other way.
		way = way.rotated(kit.walk_turn(actor))
	if moved != caster:
		var anchor: Vector2 = kit.projectiles.get_anchor(body)
		if not anchor.is_finite() or anchor.is_equal_approx(origin):
			return 0
		# Cast by a point: its wizard goes to the point, from where its body is.
		way = anchor.direction_to(origin)
		distance = anchor.distance_to(origin)
		origin = anchor
	# Where what it moves is now: its way and distance are measured from there (the body's anchor,
	# the shot's place), not from the staff tip it is cast from.
	var from: Vector2 = kit.projectiles.get_anchor(body) if body >= 0 else kit.projectiles.get_position_of(moved)
	if not from.is_finite():
		from = origin
	var aimed: Vector3 = _aim_move(spell, tag, actor, origin, from, way, distance)
	if aimed.z < 0.0:
		return 0
	way = Vector2(aimed.x, aimed.y)
	distance = aimed.z
	var offset: Vector2 = way * distance
	var seconds: float = _move_seconds(spell)
	if body >= 0:
		if kit.events != null:
			kit.moves().move_heading[body] = way
			kit.moves().asked(body, tag)
			_move_body(spell, tag, actor, body, origin, way, offset, seconds, chain, prev)
			kit.moves().shield(spell, tag, body, -1, seconds)
		return 1
	var shot: int = moved
	# The move turns on the homing curve at its own speed.
	var turn: float = offset.length() / seconds / spell.homing_curve if spell.homing_range > 0.0 and spell.homing_curve > 0.0 and seconds > 0.0 else 0.0
	if not kit.projectiles.move_shot(shot, offset, seconds, turn, spell.homing_range):
		return 0
	kit.moves().shield(spell, tag, -1, shot, seconds)
	_moved_shot(spell, tag, actor, shot, seconds, chain, prev)
	kit.moves().track(shot, tag, seconds, way)
	kit.live_join(spell, tag, SpellRuntime.LC_SLOT, shot, kit.projectiles.get_seq_of(shot), false, seconds, kit.projectiles.get_position_of(shot), way)
	return 1


## Its strikes (a dash's pass, a teleport's landing) are what it moves: a payload their hit fires is
## cast by that body or shot (`Carrier.hit_caster`).
func hit_caster(caster: int, actor: int) -> int:
	return CasterMoves.moved_by(caster, actor)


## True when the wizard's own cast of it goes the way its body walks (a dash).
func _walks() -> bool:
	return false


## The way (x, y) and distance (z) of the move about to start, cast from `origin`, of what is at
## `from` (the body's anchor, the shot), along `way` for `distance` (a teleport's homing changes
## them); a distance below 0: it does not move at all (a homing teleport with nothing in reach).
func _aim_move(_spell: CompiledSpell, _tag: int, _actor: int, _origin: Vector2, _from: Vector2, way: Vector2, distance: float) -> Vector3:
	return Vector3(way.x, way.y, distance)


## How long the move takes (0: at once).
func _move_seconds(_spell: CompiledSpell) -> float:
	return 0.0


## Asks the body of `body` (the card's `actor`'s own, or one that fired its payload) to make the
## move `offset` along `way` (`caster_move_requested`), and starts what goes with it.
func _move_body(_spell: CompiledSpell, _tag: int, _actor: int, _body: int, _origin: Vector2, _way: Vector2, _offset: Vector2, _seconds: float, _chain: int, _prev: int) -> void:
	pass


## What starts with a move of the shot `shot` that cast it.
func _moved_shot(_spell: CompiledSpell, _tag: int, _actor: int, _shot: int, _seconds: float, _chain: int, _prev: int) -> void:
	pass
