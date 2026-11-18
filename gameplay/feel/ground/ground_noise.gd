class_name GroundNoise
extends RefCounted
## The ground drawing's hashes, noise and colour helpers (connected biomes CB4,
## docs/milestones/connected-biomes.md): the twins of `tools/ground_shape.py`'s, to the bit, so a
## room's ground drawn in the game is the art the tool baked. Static only.
##
## A GDScript `float` is a double, as a Python float is; the noise reads only `+ - * /`, `floor` and
## the hash. Python's `round` rounds a half to the even number (`round_even`), and a colour is a
## whole `0xRRGGBB`. The C++ twin is `native/src/ground_kernel.cpp`.

const TURN: float = TAU


## A 32-bit hash of whole numbers (FNV-1a over them, then mixed): `hash32` of ground_shape.py.
static func hash2(a: int, b: int) -> int:
	var x: int = 2166136261
	x = ((x ^ (a & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
	x = ((x ^ (b & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
	return _finish(x)


static func hash3(a: int, b: int, c: int) -> int:
	var x: int = 2166136261
	x = ((x ^ (a & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
	x = ((x ^ (b & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
	x = ((x ^ (c & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
	return _finish(x)


static func hash4(a: int, b: int, c: int, d: int) -> int:
	var x: int = 2166136261
	x = ((x ^ (a & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
	x = ((x ^ (b & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
	x = ((x ^ (c & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
	x = ((x ^ (d & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
	return _finish(x)


static func _finish(x: int) -> int:
	x ^= x >> 13
	x = (x * 0x5BD1E995) & 0xFFFFFFFF
	return x ^ (x >> 15)


## A number in [0, 1) from whole numbers (`unit`).
static func unit2(a: int, b: int) -> float:
	return float(hash2(a, b)) / 4294967296.0


static func unit3(a: int, b: int, c: int) -> float:
	return float(hash3(a, b, c)) / 4294967296.0


static func unit4(a: int, b: int, c: int, d: int) -> float:
	return float(hash4(a, b, c, d)) / 4294967296.0


static func smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## Smooth value noise along a line, in [0, 1); with `period`, it repeats every that many units.
static func noise1(s: float, seed: int, period: int = 0) -> float:
	var i: int = floori(s)
	var t: float = smooth(s - float(i))
	var a: int = i
	var b: int = i + 1
	if period > 0:
		a = posmod(a, period)
		b = posmod(b, period)
	return unit2(seed, a) * (1.0 - t) + unit2(seed, b) * t


## Smooth value noise over the plane, cells of `scale` pixels, in [0, 1).
static func noise2(x: float, y: float, scale: float, seed: int) -> float:
	var fx: float = x / scale
	var fy: float = y / scale
	var ix: int = floori(fx)
	var iy: int = floori(fy)
	var tx: float = smooth(fx - float(ix))
	var ty: float = smooth(fy - float(iy))
	var a: float = unit3(seed, ix, iy)
	var b: float = unit3(seed, ix + 1, iy)
	var c: float = unit3(seed, ix, iy + 1)
	var d: float = unit3(seed, ix + 1, iy + 1)
	return (a * (1.0 - tx) + b * tx) * (1.0 - ty) + (c * (1.0 - tx) + d * tx) * ty


## Several octaves of `noise2`, the first the strongest, in [0, 1).
static func fbm2(x: float, y: float, scales: PackedFloat64Array, seed: int) -> float:
	var total: float = 0.0
	var weight: float = 0.0
	var amp: float = 1.0
	for i in scales.size():
		total += noise2(x, y, scales[i], seed + i) * amp
		weight += amp
		amp *= 0.5
	return total / weight


## How long (dx, dy) is (`length_of`): the square root of the sum of its squares.
static func length_of(dx: float, dy: float) -> float:
	return sqrt(dx * dx + dy * dy)


## Python's `round` of a float: the nearest whole number, a half to the even one.
static func round_even(x: float) -> int:
	var low: float = floorf(x)
	var part: float = x - low
	if part > 0.5:
		return int(low) + 1
	if part < 0.5:
		return int(low)
	return int(low) if posmod(int(low), 2) == 0 else int(low) + 1


## `_mix`: each channel of `a` toward `b` by `t`, rounded as Python rounds.
static func mix(a: int, b: int, t: float) -> int:
	var ar: int = (a >> 16) & 0xFF
	var ag: int = (a >> 8) & 0xFF
	var ab: int = a & 0xFF
	var r: int = round_even(float(ar) + float(((b >> 16) & 0xFF) - ar) * t)
	var g: int = round_even(float(ag) + float(((b >> 8) & 0xFF) - ag) * t)
	var bl: int = round_even(float(ab) + float((b & 0xFF) - ab) * t)
	return (r << 16) | (g << 8) | bl


## A colour as data names it: `#rrggbb`, or a palette material's shade (`leaf.base`); -1 for one the
## palette does not have (`colour`).
static func colour(spec: String, palette: Dictionary) -> int:
	if spec.begins_with("#"):
		return spec.substr(1).hex_to_int()
	var name: String = spec.get_slice(".", 0)
	var shade: int = ["shadow", "base", "light"].find(spec.get_slice(".", 1))
	var shades: PackedInt32Array = palette.get(name, PackedInt32Array())
	if shade < 0 or shades.size() != 3 or spec.get_slice_count(".") != 2:
		push_error("Ground: unknown colour '%s': write #rrggbb or <material>.<shadow|base|light>" % spec)
		return -1
	return shades[shade]


## The palette's materials as the drawing reads them: name -> its shadow, base and light, each a
## whole `0xRRGGBB` (core/base/palette.gd).
static func palette() -> Dictionary:
	var found: Dictionary = {}
	for name: StringName in Palette.MATERIALS:
		var shades := PackedInt32Array()
		for shade: Color in Palette.MATERIALS[name]:
			shades.append((shade.r8 << 16) | (shade.g8 << 8) | shade.b8)
		found[String(name)] = shades
	return found
