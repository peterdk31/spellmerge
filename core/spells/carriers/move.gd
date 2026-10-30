class_name CarrierMove
extends Carrier
## A carrier that moves its caster `ray_length` pixels (a dash, a teleport): a card's distance is
## fixed, and its speed only says how long a dash takes (`CasterMoves.move_seconds`), so `faster`
## arrives sooner, not farther. The body is asked through its owner (`caster_move_requested`: a
## wizard's player picks a dash's way, the way it walks, and answers where it stops, staffs A6a); a
## shot that cast it is moved along `direction` itself, and its end point comes when the move is
## over (`CasterMoves.track`). A point cannot move: a carrier that `moves_from_a_point` blinks the
## wizard to it instead (rules R4c); any other, cast by a point, does nothing. Its `shield` guards
## what it moves (`CasterMoves.shield`). The subclasses say what is their own: the way and distance
## (`_aim_move`), how long it takes (`_move_seconds`) and what starts with it (`_move_body`,
## `_moved_shot`).

## The way and distance of the move being launched, which `_aim_move` may change.
var _way: Vector2 = Vector2.ZERO
var _distance: float = 0.0


func launch(spell: CompiledSpell, tag: int, actor: int, origin: Vector2, direction: Vector2, _source: Node, _lifetime: float, chain: int, prev: int) -> int:
	_distance = CasterMoves.move_distance(spell.ray_length, spell.speed, spell.lifetime)
	_way = direction
	var shot: int = rt._caster_shot()
	var wizard: bool = rt._caster == SpellRuntime.CASTER_WIZARD
	if not wizard and shot < 0:
		var anchor: Vector2 = rt.projectiles.get_anchor(actor)
		if not _moves_from_a_point() or not anchor.is_finite() or not rt._aim_origin[actor].is_finite() or anchor.is_equal_approx(origin):
			return 0
		# Its wizard blinks to the point: from its staff tip, as far as its body is from the point.
		_way = anchor.direction_to(origin)
		_distance = anchor.distance_to(origin)
		origin = rt._aim_origin[actor]
		wizard = true
	_aim_move(spell, tag, actor, origin)
	var offset: Vector2 = _way * _distance
	var seconds: float = _move_seconds(spell)
	if wizard:
		if rt.events != null:
			rt._moves.move_heading[actor] = _way
			_move_body(spell, tag, actor, origin, offset, seconds, chain, prev)
			rt._moves.shield(spell, tag, actor, -1, seconds)
		return 1
	var turn: float = spell.homing_turn if spell.homing_range > 0.0 else 0.0
	if not rt.projectiles.move_shot(shot, offset, seconds, turn, spell.homing_range):
		return 0
	rt._moves.shield(spell, tag, actor, shot, seconds)
	_moved_shot(spell, tag, actor, shot, seconds, chain, prev)
	rt._moves.track(shot, tag, seconds, _way)
	rt._lc_join(spell, tag, SpellRuntime.LC_SLOT, shot, rt.projectiles.get_seq_of(shot), false, seconds, rt.projectiles.get_position_of(shot), _way)
	return 1


## True when, cast by a point, it moves the wizard to that point (a teleport).
func _moves_from_a_point() -> bool:
	return false


## Changes `_way` and `_distance` of the move about to start from `origin` (a teleport's homing).
func _aim_move(_spell: CompiledSpell, _tag: int, _actor: int, _origin: Vector2) -> void:
	pass


## How long the move takes (0: at once).
func _move_seconds(_spell: CompiledSpell) -> float:
	return 0.0


## Asks `actor`'s body to make the move (`caster_move_requested`), and starts what goes with it.
func _move_body(_spell: CompiledSpell, _tag: int, _actor: int, _origin: Vector2, _offset: Vector2, _seconds: float, _chain: int, _prev: int) -> void:
	pass


## What starts with a move of the shot `shot` that cast it.
func _moved_shot(_spell: CompiledSpell, _tag: int, _actor: int, _shot: int, _seconds: float, _chain: int, _prev: int) -> void:
	pass
