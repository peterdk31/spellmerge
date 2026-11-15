class_name MoveCurve
extends RefCounted
## A move's speed over its time (boss plan OB10; a card's `ModifierBase.move_start`, `move_end` and
## `move_ease`, multiplied into `CompiledSpell`): the factor on its speed at `u`, the share of its
## time gone (0 to 1), is
##
##     f(u) = 1 - (1 - start) (1 - u)^ease - (1 - end) u^ease
##
## so it starts at `start` times its speed, ends at `end` times it, and is near full speed between
## (an ease above 1 gets there sooner and leaves it later). Start and end below 1 make a lurch and a
## drag (Lumber); above 1, a burst. The move still goes its whole distance in its whole time: each
## step goes the share of the way the curve's area over that step is of its whole area
## (`share`, worked out exactly from the area's formula, so the steps add up to the whole way
## however long each is). A curve is a Vector3 (start, end, ease); NONE keeps the speed even, and a
## move with it is stepped as before, to the bit. Pure functions, the same on every machine (`DMath`).

## The curve of a move that keeps its speed.
const NONE: Vector3 = Vector3.ONE
## The least ease a curve takes (`ModifierBase` holds its cards there too): below 1 the curve can
## turn below zero.
const MIN_EASE: float = 1.0
## A curve whose whole area is below this is taken as NONE (it would hardly move).
const MIN_AREA: float = 0.01


## The curve of `spell`'s moves (NONE when its cards give it none).
static func of(spell: CompiledSpell) -> Vector3:
	if spell == null:
		return NONE
	return Vector3(spell.move_start, spell.move_end, spell.move_ease)


## True when `curve` changes a move's speed (and is one a move can take).
static func shapes(curve: Vector3) -> bool:
	if curve == NONE or not curve.is_finite() or curve.x < 0.0 or curve.y < 0.0:
		return false
	return _area(curve, 1.0) >= MIN_AREA


## The factor on the move's speed at `u`, the share of its time gone (for the looks and the tests).
static func factor(curve: Vector3, u: float) -> float:
	if not shapes(curve):
		return 1.0
	var at: float = clampf(u, 0.0, 1.0)
	var ease_power: float = maxf(curve.z, MIN_EASE)
	var whole: float = _area(curve, 1.0)
	return (1.0 - (1.0 - curve.x) * DMath.pow(1.0 - at, ease_power) - (1.0 - curve.y) * DMath.pow(at, ease_power)) / whole


## The share of a move's whole way it goes in a step that takes it from `left` seconds left to
## `left - delta` (no less than 0), of `total` seconds in all: the curve's area over that part of its
## time over its whole area. The shares of every step add up to 1.
static func share(curve: Vector3, total: float, left: float, delta: float) -> float:
	if not (total > 0.0):
		return 1.0
	var u0: float = clampf(1.0 - left / total, 0.0, 1.0)
	var u1: float = clampf(1.0 - maxf(left - delta, 0.0) / total, 0.0, 1.0)
	return (_area(curve, u1) - _area(curve, u0)) / _area(curve, 1.0)


## The area under f from 0 to `u` (before dividing by the whole): u + (1 - start) ((1 - u)^(e+1) - 1)
## / (e + 1) - (1 - end) u^(e+1) / (e + 1).
static func _area(curve: Vector3, u: float) -> float:
	var ease_power: float = maxf(curve.z, MIN_EASE)
	var up: float = ease_power + 1.0
	return u + (1.0 - curve.x) * (DMath.pow(1.0 - u, up) - 1.0) / up - (1.0 - curve.y) * DMath.pow(u, up) / up
