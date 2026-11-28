extends RefCounted
## Which rooms' cover each body found can walk (perf plan F3, docs/milestones/perf-plan.md): Feel's
## `cover_rooms.gd` sorts the first view's bodies once a frame (`sort`), and each view walks only its
## own (`cover.gd`'s `walk_only`), not every body found. A biome's 28 views each tested the 32 bodies
## a frame (the box of the 32 nearest spans most of a biome's rooms): 0.18 ms a frame, at rest.
##
## Each view's reach is its walk box (`CoverScript.walk_low` to `walk_high`: where a body's footprint may touch
## its cells, the test `_walk_bodies` makes), kept in buckets of `BUCKET` pixels so a body looks at
## the few views whose box shares its bucket; worked out again whenever a view is laid (`lay`, by
## the views' `flats_version`). A view's bodies keep the order they were found in.
##
## Nothing is allocated a frame: the lists are one array of `CoverScript.BODIES` a view, sized when
## a view is added. Pure view: nothing here is the game's.

const CoverScript := preload("res://gameplay/feel/cover.gd")

## A bucket's side (px): a room is a few of them.
const BUCKET: float = 512.0

## The bodies each view walks: view `v`'s from `v * CoverScript.BODIES`, `counts[v]` of them.
var bodies: PackedVector2Array = PackedVector2Array()
var counts: PackedInt32Array = PackedInt32Array()

## Each view's walk box (`lows[v]` to `highs[v]`; none for a view with no cell).
var _lows: PackedVector2Array = PackedVector2Array()
var _highs: PackedVector2Array = PackedVector2Array()
## The views whose box shares each bucket, by the bucket's corner (`_key`).
var _buckets: Dictionary[Vector2i, PackedInt32Array] = {}


## The views' walk boxes, from `views` (Feel's rooms' views, by number), anew.
func lay(views: Array[CoverScript]) -> void:
	_buckets.clear()
	var size: int = views.size()
	if counts.size() != size:
		counts.resize(size)
		bodies.resize(size * CoverScript.BODIES)
		_lows.resize(size)
		_highs.resize(size)
	counts.fill(0)
	for v in size:
		var view: CoverScript = views[v]
		if view.layout == null or view.layout.cells.is_empty():
			continue
		_lows[v] = view.walk_low()
		_highs[v] = view.walk_high()
		var first: Vector2i = _key(_lows[v])
		var last: Vector2i = _key(_highs[v])
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var key := Vector2i(x, y)
				var list: PackedInt32Array = _buckets.get(key, PackedInt32Array())
				list.append(v)
				_buckets[key] = list


## The first `count` of `found` sorted to the views whose walk box holds them (into `bodies`, `counts`).
func sort(found: PackedVector2Array, count: int) -> void:
	counts.fill(0)
	for at in mini(count, found.size()):
		var body: Vector2 = found[at]
		var list: PackedInt32Array = _buckets.get(_key(body), PackedInt32Array())
		for v in list:
			var low: Vector2 = _lows[v]
			var high: Vector2 = _highs[v]
			if body.x < low.x or body.y < low.y or body.x > high.x or body.y > high.y:
				continue
			var n: int = counts[v]
			if n < CoverScript.BODIES:
				bodies[v * CoverScript.BODIES + n] = body
				counts[v] = n + 1


static func _key(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / BUCKET), floori(at.y / BUCKET))
