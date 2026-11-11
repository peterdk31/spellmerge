extends RefCounted
## Where a mote leaves from: one place class for each of `MoteSource.From` (a point, a line, a box,
## an oval's rim, a mask's lit pixels), and the places within an oval that the still cards' motes
## share (`still_motes.gd`). A new kind of place is a value of `MoteSource.From`, a class here and a
## line in `make`; `source_motes.gd` knows none of them by name.
##
## A place is read once (`read`: where its source's node is in the world, as numbers of its own) and
## then picked from as often as its source gives off (`pick`: a point and the way a mote leaves it,
## into `at` and `way`, so a pick makes no object). View only: each pick takes the caller's own dice
## and uses the engine's trig, never the simulation's.

## How far from a line a mote is born, at most, either way (px).
const JITTER: float = 1.5


## A place a source's motes leave from, read from its node. The base is a point.
class Place:
	## The last pick: where a mote leaves from and the way it goes, in the world.
	var at: Vector2 = Vector2.ZERO
	var way: Vector2 = Vector2.UP
	## The world box its motes leave from (before what they fly).
	var bounds: Rect2 = Rect2()
	## Its middle in the world, its half-size there, and the way its source throws.
	var _middle: Vector2 = Vector2.ZERO
	var _half: Vector2 = Vector2.ZERO
	var _throw: Vector2 = Vector2.UP

	## Read where `look` leaves from, its node `node` at `to_world`; `mask` the world middles of its
	## art's lit pixels (a mask's; empty for the others). False when there is nowhere to leave from.
	func read(look: MoteSource, node: Node2D, to_world: Transform2D, mask: PackedVector2Array) -> bool:
		_throw = to_world.basis_xform(look.way).normalized() if not look.way.is_zero_approx() else Vector2.UP
		_middle = to_world * look.at
		_half = look.size * 0.5 * to_world.get_scale().abs()
		return _read(look, node, to_world, mask)

	func _read(_look: MoteSource, _node: Node2D, _to_world: Transform2D, _mask: PackedVector2Array) -> bool:
		bounds = Rect2(_middle, Vector2.ZERO)
		return true

	## Pick where the next mote leaves from and its way (`at`, `way`), with `rng`.
	func pick(_rng: RandomNumberGenerator, _look: MoteSource) -> void:
		at = _middle
		way = _throw

	## The fixed points a standing source puts a mote on, one each (empty: it has none).
	func spots() -> PackedVector2Array:
		return PackedVector2Array()

	## True when it leaves from its art's lit pixels (`read` is handed them).
	func wants_mask() -> bool:
		return false

	# The geometry every place shares (on the base class, so each place calls it as its own).

	## The box round `points` (at least one).
	static func box_of(points: PackedVector2Array) -> Rect2:
		var box := Rect2(points[0], Vector2.ZERO)
		for point in points:
			box = box.expand(point)
		return box


	## A point anywhere in the oval of half-axes `half` round its middle, at most `inside` of the way to
	## its rim (a pool's surface; `rng` the caller's own dice).
	static func in_oval(rng: RandomNumberGenerator, half: Vector2, inside: float = 1.0) -> Vector2:
		var b: float = rng.randf() * TAU
		return Vector2(cos(b), sin(b)) * half * sqrt(rng.randf()) * inside


	## A point on the rim of the oval of half-axes `half` round its middle, in whole pixels; with
	## `spacing`, only at that many pixels apart round it (a rune's ring).
	static func on_oval(rng: RandomNumberGenerator, half: Vector2, spacing: float = 0.0) -> Vector2:
		var a: float = rng.randf() * TAU
		if spacing > 0.0:
			var steps: float = maxf(roundf(TAU * maxf(half.x, half.y) / spacing), 1.0)
			a = roundf(a / TAU * steps) / steps * TAU
		return (Vector2(cos(a), sin(a)) * half).round()


	## `along` (a place on a line `w` from the world's origin along it) put on the world's grid of
	## `spacing` pixels, so pieces of a row and sources side by side line up (0: as it is).
	static func on_grid(along: float, w: float, spacing: float) -> float:
		if spacing <= 0.0:
			return along
		return roundf((w + along) / spacing) * spacing - w


## A line: its points (the source's own, else its node's `Line2D`), thrown outward: the left of the
## way the points run, so a line drawn clockwise on screen throws out of its shape.
class LinePlace extends Place:
	var _points: PackedVector2Array = PackedVector2Array()
	## The length up to each point (the first 0), and its whole length.
	var _running: PackedFloat32Array = PackedFloat32Array()
	var _length: float = 0.0

	func _read(look: MoteSource, node: Node2D, to_world: Transform2D, _mask: PackedVector2Array) -> bool:
		var local: PackedVector2Array = look.points
		var closed: bool = look.closed
		if local.is_empty() and node is Line2D:
			local = (node as Line2D).points
			closed = (node as Line2D).closed
		for point in local:
			_points.append(to_world * point)
		if closed and _points.size() > 1:
			_points.append(_points[0])
		_running.append(0.0)
		for i in range(1, _points.size()):
			_length += _points[i - 1].distance_to(_points[i])
			_running.append(_length)
		if _points.size() < 2 or _length <= 0.0:
			return false
		bounds = box_of(_points)
		return true

	func pick(rng: RandomNumberGenerator, look: MoteSource) -> void:
		var along: float = clampf(on_grid(rng.randf() * _length, 0.0, look.spacing), 0.0, _length)
		# The segment `along` falls in: the last point whose running length is at most it.
		var i: int = clampi(_running.bsearch(along, true) - 1, 0, _points.size() - 2)
		var on: Vector2 = (_points[i + 1] - _points[i]).normalized()
		way = Vector2(on.y, -on.x)
		at = _points[i] + on * (along - _running[i]) + way * rng.randf_range(-JITTER, JITTER)


## Anywhere in a box `size` across round `at`, on the world's grid of `spacing`.
class AreaPlace extends Place:
	func _read(_look: MoteSource, _node: Node2D, _to_world: Transform2D, _mask: PackedVector2Array) -> bool:
		bounds = Rect2(_middle - _half, _half * 2.0)
		return true

	func pick(rng: RandomNumberGenerator, look: MoteSource) -> void:
		at = _middle + Vector2(rng.randf_range(-1.0, 1.0) * _half.x, rng.randf_range(-1.0, 1.0) * _half.y)
		if look.spacing > 0.0:
			at = (at / look.spacing).round() * look.spacing
		way = _throw


## On the rim of an oval `size` across round `at`, thrown out from its middle.
class RimPlace extends AreaPlace:
	func pick(rng: RandomNumberGenerator, look: MoteSource) -> void:
		var off: Vector2 = on_oval(rng, _half, look.spacing)
		at = _middle + off
		way = off.normalized() if not off.is_zero_approx() else _throw


## The lit pixels of its art (`mote_art`): a crystal's facets, a grid's `*` points.
class MaskPlace extends Place:
	var _spots: PackedVector2Array = PackedVector2Array()

	func _read(_look: MoteSource, _node: Node2D, _to_world: Transform2D, mask: PackedVector2Array) -> bool:
		_spots = mask
		if _spots.is_empty():
			return false
		bounds = box_of(_spots)
		return true

	func pick(rng: RandomNumberGenerator, _look: MoteSource) -> void:
		at = _spots[rng.randi() % _spots.size()]
		way = _throw

	func spots() -> PackedVector2Array:
		return _spots

	func wants_mask() -> bool:
		return true


## A new place of the kind `from` (`MoteSource.From`).
static func make(from: MoteSource.From) -> Place:
	match from:
		MoteSource.From.LINE:
			return LinePlace.new()
		MoteSource.From.AREA:
			return AreaPlace.new()
		MoteSource.From.RIM:
			return RimPlace.new()
		MoteSource.From.MASK:
			return MaskPlace.new()
	return Place.new()


## The places within an oval and on the world's grid, for the still cards' motes (`Place`'s own).
static func in_oval(rng: RandomNumberGenerator, half: Vector2, inside: float = 1.0) -> Vector2:
	return Place.in_oval(rng, half, inside)


static func on_oval(rng: RandomNumberGenerator, half: Vector2, spacing: float = 0.0) -> Vector2:
	return Place.on_oval(rng, half, spacing)


static func on_grid(along: float, w: float, spacing: float) -> float:
	return Place.on_grid(along, w, spacing)
