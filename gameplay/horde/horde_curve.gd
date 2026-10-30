class_name HordeCurve
extends Resource
## The horde's curve (docs/milestones/horde.md, "Spawning"): points of (seconds, spawns per
## second, cap alive, weights by enemy id), in time order. Between two points every number is
## interpolated in a straight line; before the first and after the last the end point holds.
##
## `prepare()` lays the weights out once (every enemy id any point names, and a table of their
## weights per point), so asking for a weight while the run plays allocates nothing:
##
##     curve.prepare()
##     var rate: float = curve.rate_at(seconds)
##     var weight: float = curve.weight_at(seconds, curve.ids.find(&"ember_imp"))

@export var points: Array[HordeCurvePoint] = []

## Every enemy id any point names, sorted; filled by `prepare()`.
var ids: Array[StringName] = []
## Weight of id `i` at point `p` is `_weights[p * ids.size() + i]`; filled by `prepare()`.
var _weights: PackedFloat32Array = PackedFloat32Array()
## Stands in for a null point.
static var _empty: HordeCurvePoint = HordeCurvePoint.new()


## Lays out `ids` and the weight table. Call it once after loading or changing the points.
func prepare() -> void:
	ids.clear()
	for point: HordeCurvePoint in points:
		if point == null:
			continue
		for id: StringName in point.weights:
			if not ids.has(id):
				ids.append(id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	_weights.resize(points.size() * ids.size())
	for p in points.size():
		var point: HordeCurvePoint = points[p]
		for i in ids.size():
			_weights[p * ids.size() + i] = maxf(point.weights.get(ids[i], 0.0), 0.0) if point != null else 0.0


## Enemies that appear a second at `seconds`.
func rate_at(seconds: float) -> float:
	var at: int = _segment(seconds)
	if at < 0:
		return 0.0
	var mix: float = _mix(at, seconds)
	return maxf(lerpf(_point(at).spawns_per_second, _point(at + 1).spawns_per_second, mix), 0.0)


## The most horde enemies alive at once at `seconds`.
func cap_at(seconds: float) -> int:
	var at: int = _segment(seconds)
	if at < 0:
		return 0
	var mix: float = _mix(at, seconds)
	return maxi(roundi(lerpf(float(_point(at).cap_alive), float(_point(at + 1).cap_alive), mix)), 0)


## The weight of `ids[index]` at `seconds` (0 for an index outside `ids`). Needs `prepare()`.
func weight_at(seconds: float, index: int) -> float:
	var at: int = _segment(seconds)
	var count: int = ids.size()
	if at < 0 or index < 0 or index >= count or _weights.size() != points.size() * count:
		return 0.0
	var next: int = mini(at + 1, points.size() - 1)
	return lerpf(_weights[at * count + index], _weights[next * count + index], _mix(at, seconds))


## The point a segment starts at: the last point at or before `seconds` (0 before the first),
## or -1 for a curve with no points.
func _segment(seconds: float) -> int:
	if points.is_empty():
		return -1
	var at: int = 0
	for p in range(1, points.size()):
		if points[p] != null and points[p].seconds <= seconds:
			at = p
	return at


## How far `seconds` is from point `at` towards the next (0 to 1; 0 after the last point).
func _mix(at: int, seconds: float) -> float:
	if at + 1 >= points.size():
		return 0.0
	var start: float = _point(at).seconds
	var span: float = _point(at + 1).seconds - start
	if span <= 0.0:
		return 0.0
	return clampf((seconds - start) / span, 0.0, 1.0)


## Point `at`, the last one past the end; a null point counts as an empty one.
func _point(at: int) -> HordeCurvePoint:
	var point: HordeCurvePoint = points[mini(at, points.size() - 1)]
	return point if point != null else _empty

