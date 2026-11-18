class_name GroundGeometry
extends RefCounted
## A room's ground as it is worked out from its shape (connected biomes CB4): which pixels are land,
## how wide a crack is where it runs, which ground material each pixel of land is, and where the pits
## are. The twin of `Ground` in `tools/ground_shape.py`, line by line (content/rooms/README.md, "A
## room's ground from a shape", says what a shape holds). Always in the template's own frame:
## `GroundDrawing` mirrors it.
##
## A crack's width is single precision (`PackedFloat32Array`), as the tool's `array("f")`.

const N := preload("res://gameplay/feel/ground/ground_noise.gd")

## The size of a wall cell, in pixels.
const CELL: int = 8
## How far past a pin's end a frame's edge eases back to its noise, in pixels.
const PIN_EASE: float = 12.0

var width: int = 0
var height: int = 0
var land := PackedByteArray()
## The crack's width at each of its pixels (0: no crack).
var crack := PackedFloat32Array()
## The index of a pixel's ground material (0: the floor's own, then the shape's areas).
var material := PackedByteArray()
## 1 where a pit is (always a hole), and where open ground is a pit's side (a pit, a crack from one).
var pit := PackedByteArray()
var pit_side := PackedByteArray()
var shape: Dictionary = {}
## Where cracks keep clear of: x, y, radius, one after another.
var keep_clear := PackedFloat64Array()
var _side: int = 0


## The ground of `shape` (a shape file's data), its cracks kept clear of `placed` and its frame
## pushed out round `clear` (x, y, radius triples: `GroundShape.placements`, `clear_points`).
func _init(shape_data: Dictionary, placed: PackedFloat64Array = PackedFloat64Array(), clear: PackedFloat64Array = PackedFloat64Array()) -> void:
	shape = shape_data
	var size: Array = shape["size"]
	width = int(size[0])
	height = int(size[1])
	if width % CELL != 0 or height % CELL != 0:
		push_error("Ground: size %s is not whole %d px cells" % [size, CELL])
	var n: int = width * height
	land.resize(n)
	crack.resize(n)
	material.resize(n)
	pit.resize(n)
	pit_side.resize(n)
	for c: Array in shape.get("keep_clear", []):
		keep_clear.append_array(PackedFloat64Array([float(c[0]), float(c[1]), float(c[2])]))
	keep_clear.append_array(placed)
	for spec: Dictionary in shape.get("outlines", []):
		fill_polygon(land, width, height, outline_points(spec), 1)
	if shape.has("frame"):
		_frame(shape["frame"], clear)
	var areas: Array = shape.get("areas", [])
	for i in areas.size():
		var area_mask := PackedByteArray()
		area_mask.resize(n)
		fill_polygon(area_mask, width, height, outline_points(areas[i], 3.0), 1)
		for p in n:
			if area_mask[p] != 0 and land[p] != 0:
				material[p] = i + 1
	for spec: Dictionary in shape.get("pits", []):
		var mask := PackedByteArray()
		mask.resize(n)
		fill_polygon(mask, width, height, outline_points(spec), 1)
		for p in n:
			if mask[p] != 0:
				land[p] = 0
				pit[p] = 1
				pit_side[p] = 1
	for spec: Dictionary in shape.get("cracks", []):
		if spec.has("pit"):
			_crack_from_pit(spec)
		else:
			_crack(spec)


## An outline's points, clockwise on screen: a wavy, rough oval (`outline_points`), x then y.
static func outline_points(spec: Dictionary, step: float = 2.0) -> PackedFloat64Array:
	var centre: Array = spec["centre"]
	var radii: Array = spec["radii"]
	var cx: float = float(centre[0])
	var cy: float = float(centre[1])
	var rx: float = float(radii[0])
	var ry: float = float(radii[1])
	var seed: int = int(spec.get("seed", 0))
	var mean: float = (rx + ry) * 0.5
	var count: int = maxi(64, int(N.TURN * mean / step))
	var waves: Array = spec.get("waves", [])
	var rough: Array = spec.get("rough", [])
	var periods := PackedInt64Array()
	for j in rough.size():
		periods.append(maxi(1, N.round_even(N.TURN * mean / float(rough[j][0]))))
	var points := PackedFloat64Array()
	points.resize(count * 2)
	for i in count:
		var a: float = float(i) / float(count) * N.TURN
		var r: float = 1.0
		for wave: Array in waves:
			r += float(wave[1]) * sin(float(wave[0]) * a + float(wave[2]))
		for j in rough.size():
			var period: int = periods[j]
			r += float(rough[j][1]) * 2.0 * (N.noise1(a / N.TURN * float(period), seed + 17 * j, period) - 0.5)
		points[i * 2] = cx + cos(a) * rx * r
		points[i * 2 + 1] = cy + sin(a) * ry * r
	return points


## Set every pixel whose middle is inside `points` (x, y pairs; even-odd) to `value`.
static func fill_polygon(mask: PackedByteArray, w: int, h: int, points: PackedFloat64Array, value: int) -> void:
	var count: int = points.size() / 2
	if count == 0:
		return
	var low: float = INF
	var high: float = -INF
	for i in count:
		low = minf(low, points[i * 2 + 1])
		high = maxf(high, points[i * 2 + 1])
	var top: int = maxi(0, int(low))
	var bottom: int = mini(h - 1, int(high) + 1)
	var xs := PackedFloat64Array()
	for y in range(top, bottom + 1):
		var sy: float = float(y) + 0.5
		xs.clear()
		for i in count:
			var x1: float = points[i * 2]
			var y1: float = points[i * 2 + 1]
			var k: int = (i + 1) % count
			var x2: float = points[k * 2]
			var y2: float = points[k * 2 + 1]
			if (y1 <= sy and sy < y2) or (y2 <= sy and sy < y1):
				xs.append(x1 + (sy - y1) * (x2 - x1) / (y2 - y1))
		xs.sort()
		var row: int = y * w
		var k: int = 0
		while k < xs.size() - 1:
			var start: int = maxi(0, ceili(xs[k] - 0.5))
			var end: int = mini(w - 1, floori(xs[k + 1] - 0.5))
			for x in range(start, end + 1):
				mask[row + x] = value
			k += 2


## A room's floor inside walls (`_frame`): a rounded rectangle `inset` pixels in from the border, its
## edge wandering by noise, held to its `pins`, opened into `bays`, pushed back round `clear`; the
## outermost cell always wall.
func _frame(spec: Dictionary, clear: PackedFloat64Array) -> void:
	var w: int = width
	var h: int = height
	var inset: float = float(spec["inset"])
	var corner: float = float(spec.get("corner", 16))
	var wander: Array = spec["wander"]
	var wander_in: float = float(wander[0])
	var wander_out: float = float(wander[1])
	var scales := PackedFloat64Array()
	for v: Variant in spec.get("rough", [40, 14, 5]):
		scales.append(float(v))
	var seed: int = int(spec.get("seed", 0))
	var pins := PackedFloat64Array()
	for pin: Array in spec.get("pins", []):
		pins.append_array(PackedFloat64Array([float(pin[0]), float(pin[1]), float(pin[2]), float(pin[3])]))
	var bays := PackedFloat64Array()
	for bay: Array in spec.get("bays", []):
		bays.append_array(PackedFloat64Array([float(bay[0]), float(bay[1]), float(bay[2])]))
	var bay_scales := PackedFloat64Array([12.0, 5.0])
	var cx: float = float(w) / 2.0
	var cy: float = float(h) / 2.0
	var hw: float = float(w) / 2.0 - inset - corner
	var hh: float = float(h) / 2.0 - inset - corner
	var reach: float = maxf(wander_in, wander_out) + 2.0
	for y in h:
		for x in w:
			var p: int = y * w + x
			if x < CELL or y < CELL or x >= w - CELL or y >= h - CELL:
				land[p] = 0
				continue
			var px: float = float(x) + 0.5
			var py: float = float(y) + 0.5
			var qx: float = absf(px - cx) - hw
			var qy: float = absf(py - cy) - hh
			var inward: float = -(N.length_of(maxf(qx, 0.0), maxf(qy, 0.0)) + minf(maxf(qx, qy), 0.0) - corner)
			var pinned: float = 1.0
			for k in range(0, pins.size(), 4):
				var dx: float = maxf(maxf(pins[k] - px, 0.0), px - pins[k + 2])
				var dy: float = maxf(maxf(pins[k + 1] - py, 0.0), py - pins[k + 3])
				pinned = minf(pinned, N.length_of(dx, dy) / PIN_EASE)
			var inside: bool = inward > 0.0
			if absf(inward) < reach and pinned > 0.0:
				var n: float = maxf(-1.0, minf(1.0, (N.fbm2(px, py, scales, seed) - 0.5) * 2.6))
				inside = inward + (n * wander_out if n > 0.0 else n * wander_in) * minf(1.0, pinned) > 0.0
			if not inside and pinned >= 1.0:
				for k in range(0, bays.size(), 3):
					var br: float = bays[k + 2]
					if N.length_of(px - bays[k], py - bays[k + 1]) + (N.fbm2(px, py, bay_scales, seed + 7) - 0.5) * br * 0.6 < br:
						inside = true
						break
			if not inside and pinned >= 1.0:
				for k in range(0, clear.size(), 3):
					if N.length_of(px - clear[k], py - clear[k + 1]) < clear[k + 2]:
						inside = true
						break
			if inside:
				land[p] = 1


## Carve a crack out from the edge of pit `pit` (`_crack_from_pit`).
func _crack_from_pit(spec: Dictionary) -> void:
	var pit_spec: Dictionary = (shape["pits"] as Array)[int(spec["pit"])]
	var centre: Array = pit_spec["centre"]
	var a: float = float(spec["angle"]) * N.TURN
	var x: float = float(centre[0])
	var y: float = float(centre[1])
	while x >= 0.0 and x < float(width) and y >= 0.0 and y < float(height) and land[int(y) * width + int(x)] == 0:
		x += cos(a)
		y += sin(a)
	var seed: int = int(spec.get("seed", 0))
	var heading: float = a + (N.unit2(seed, 3) - 0.5) * 0.4
	_side = 1
	_walk(x - cos(a) * 4.0, y - sin(a) * 4.0, heading, float(spec["width"]), int(spec["length"]), seed, 0)
	_side = 0


func _near_keep_clear(x: float, y: float) -> bool:
	for k in range(0, keep_clear.size(), 3):
		if N.length_of(x - keep_clear[k], y - keep_clear[k + 1]) < keep_clear[k + 2]:
			return true
	return false


## Carve a crack in from the edge of outline `outline` (`_crack`).
func _crack(spec: Dictionary) -> void:
	var outline: Dictionary = (shape["outlines"] as Array)[int(spec.get("outline", 0))]
	var centre: Array = outline["centre"]
	var radii: Array = outline["radii"]
	var rx: float = float(radii[0])
	var ry: float = float(radii[1])
	var a: float = float(spec["angle"]) * N.TURN
	var x: float = float(centre[0])
	var y: float = float(centre[1])
	while x >= 0.0 and x < float(width) and y >= 0.0 and y < float(height) and land[int(y) * width + int(x)] != 0:
		x += cos(a)
		y += sin(a) * ry / rx
	var seed: int = int(spec.get("seed", 0))
	var heading: float = a + PI + (N.unit2(seed, 3) - 0.5) * 0.4
	_walk(x - cos(a) * 4.0, y - sin(a) * 4.0, heading, float(spec["width"]), int(spec["length"]), seed, 0)


func _walk(x: float, y: float, heading: float, crack_width: float, steps: int, seed: int, depth: int) -> void:
	for i in steps:
		heading += sin(float(i) * 0.37 + float(seed)) * 0.22 + (N.unit2(seed, i) - 0.5) * 0.25
		x += cos(heading) * 3.0
		y += sin(heading) * 3.0
		if _near_keep_clear(x, y) or not (x >= 0.0 and x < float(width) and y >= 0.0 and y < float(height)):
			return
		var at: int = int(y) * width + int(x)
		if i > 6 and land[at] == 0 and crack[at] == 0.0:
			return
		var w: float = crack_width * pow(maxf(0.0, 1.0 - float(i) / float(steps)), 1.6)
		if w < 1.5:
			return
		_stamp(x, y, w)
		if depth < 2 and i > 4 and N.hash3(seed, i, 7) % 26 == 0:
			var turn: float = 0.7 if N.hash3(seed, i, 8) % 2 != 0 else -0.7
			_walk(x, y, heading + turn, w * 0.9, int(float(steps - i) * 0.6), seed * 31 + i, depth + 1)


func _stamp(x: float, y: float, w: float) -> void:
	var r: float = w * 0.5
	var reach: int = int(r + 6.0)
	var seed: int = int(shape.get("seed", 0))
	var wide_scales := PackedFloat64Array([12.0, 6.0])
	var fine_scales := PackedFloat64Array([4.0, 2.0])
	for py in range(maxi(0, int(y) - reach), mini(height, int(y) + reach + 1)):
		for px in range(maxi(0, int(x) - reach), mini(width, int(x) + reach + 1)):
			var d: float = N.length_of(float(px) + 0.5 - x, float(py) + 0.5 - y)
			if d > r + 5.0:
				continue
			var edge: float = r
			if w > 6.0:
				# A wide crack's walls are as rough as the coast's; a thin one is a clean line.
				edge += minf(r * 0.9, 4.0) * 2.0 * (N.fbm2(float(px), float(py), wide_scales, seed + 310) - 0.5)
				edge += 1.5 * (N.fbm2(float(px), float(py), fine_scales, seed + 311) - 0.5)
			if d <= edge:
				var p: int = py * width + px
				if land[p] != 0 or crack[p] > 0.0:
					land[p] = 0
					if w > crack[p]:
						crack[p] = w
					if _side != 0:
						pit_side[p] = 1
