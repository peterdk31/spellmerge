class_name GroundMaterial
extends RefCounted
## One ground material ready to draw (connected biomes CB4; content/grounds/README.md): its colours
## looked up once, its patches' noise worked out on a coarse grid over the room and read back. The
## twin of `Material` in `tools/ground_materials.py`, line by line; a colour is a whole `0xRRGGBB`.

const N := preload("res://gameplay/feel/ground/ground_noise.gd")

## The patches' noise is worked out every this many pixels and read back between.
const STEP: int = 4

var base: int = 0
var cols: int = 0
var patch_map := PackedFloat64Array()
var has_patches: bool = false
var patch_colour: int = 0
var patch_above: float = 2.0
var speckle_colours := PackedInt32Array()
var speckle_shares := PackedFloat64Array()
var seed: int = 0
var has_slabs: bool = false
var slab_size: float = 0.0
var slab_jitter: float = 0.8
var slab_squash: float = 1.0
var slab_tone: int = 0
var slab_vary: float = 0.0
var joint: int = 0
var joint_width: float = 1.2
var has_light: bool = false
var light: int = 0
var light_width: float = 1.0
var has_edge: bool = false
var edge_colour: int = 0
var edge_reach: float = 0.0
var edge_most: float = 0.6
var edge_scales := PackedFloat64Array([10.0, 4.0])
var has_strokes: bool = false
var stroke_colour: int = 0
var stroke_spacing: float = 10.0
var stroke_share: float = 0.4
var stroke_inner: float = 24.0
var centre_x: float = 0.0
var centre_y: float = 0.0


## The material `spec` (a `ground.json`'s data), the `index`th of the shape's (0 its floor's), in a
## room of `size` seeded `room_seed`; its strokes go round (`middle_x`, `middle_y`).
func _init(spec: Dictionary, index: int, room_seed: int, size: Vector2i, middle_x: float, middle_y: float, palette: Dictionary) -> void:
	base = N.colour(spec["base"], palette)
	cols = size.x / STEP + 2
	var rows: int = size.y / STEP + 2
	if spec.has("patches"):
		var patches: Dictionary = spec["patches"]
		has_patches = true
		var patch_seed: int = room_seed * 13 + index * 101 + int(patches.get("seed", 0))
		var scales := PackedFloat64Array()
		for v: Variant in patches["scales"]:
			scales.append(float(v))
		patch_map.resize(rows * cols)
		for cy in rows:
			for cx in cols:
				patch_map[cy * cols + cx] = N.fbm2(float(cx * STEP), float(cy * STEP), scales, patch_seed)
		patch_colour = N.colour(patches["colour"], palette)
		patch_above = float(patches.get("above", 0.5))
	for pair: Array in spec.get("speckle", []):
		speckle_colours.append(N.colour(pair[0], palette))
		speckle_shares.append(float(pair[1]))
	seed = room_seed * 7 + index * 31
	if spec.has("slabs"):
		var slabs: Dictionary = spec["slabs"]
		has_slabs = true
		slab_size = float(slabs["size"])
		slab_jitter = float(slabs.get("jitter", 0.8))
		slab_squash = float(slabs.get("squash", 1.0))
		slab_tone = N.colour(slabs["tone"], palette) if slabs.has("tone") else base
		slab_vary = float(slabs.get("vary", 0.0))
		joint = N.colour(slabs["joint"], palette)
		joint_width = float(slabs.get("joint_width", 1.2))
		has_light = slabs.has("light")
		light = N.colour(slabs["light"], palette) if has_light else 0
		light_width = float(slabs.get("light_width", 1.0))
	if spec.has("toward_edge"):
		var edge: Dictionary = spec["toward_edge"]
		has_edge = true
		edge_colour = N.colour(edge["colour"], palette)
		edge_reach = float(edge["reach"])
		edge_most = float(edge.get("most", 0.6))
		if edge.has("scales"):
			edge_scales = PackedFloat64Array()
			for v: Variant in edge["scales"]:
				edge_scales.append(float(v))
	if spec.has("strokes"):
		var strokes: Dictionary = spec["strokes"]
		has_strokes = true
		stroke_colour = N.colour(strokes["colour"], palette)
		stroke_spacing = float(strokes.get("spacing", 10.0))
		stroke_share = float(strokes.get("share", 0.4))
		stroke_inner = float(strokes.get("inner", 24.0))
		centre_x = middle_x
		centre_y = middle_y


## The colour of this material at pixel (x, y); `edge_distance` is how far the pixel is from the
## floor's edge (only `toward_edge` reads it).
func at(x: int, y: int, edge_distance: float = 1e9) -> int:
	var rgb: int = base
	if has_slabs:
		rgb = _slab(x, y)
	if has_patches and _bilinear(float(x) / float(STEP), float(y) / float(STEP)) > patch_above:
		rgb = patch_colour
	if has_strokes:
		rgb = _stroke(x, y, rgb)
	var roll: float = N.unit3(x, y, 4041)
	for i in speckle_shares.size():
		if roll < speckle_shares[i]:
			rgb = speckle_colours[i]
			break
		roll -= speckle_shares[i]
	if has_edge and edge_distance < edge_reach:
		var near: float = 1.0 - edge_distance / edge_reach
		var grit: float = N.fbm2(float(x), float(y), edge_scales, seed + 77)
		var share: float = minf(edge_most, maxf(0.0, near * 1.6 * grit - 0.25))
		if share > 0.08:
			rgb = N.mix(rgb, edge_colour, share)
	return rgb


func _slab(x: int, y: int) -> int:
	var s: float = slab_size
	var sq: float = slab_squash
	var fx: float = (float(x) + 0.5) / s
	var fy: float = (float(y) + 0.5) / (s * sq)
	var cx0: int = floori(fx)
	var cy0: int = floori(fy)
	var best: float = 1e18
	var second: float = 1e18
	var best_cx: int = 0
	var best_cy: int = 0
	var best_dy: float = 0.0
	for cy in range(cy0 - 1, cy0 + 2):
		# Every other row is offset half a slab, so the joints never line up into a grid.
		var shift: float = 0.5 if cy % 2 != 0 else 0.0
		for cx in range(cx0 - 1, cx0 + 2):
			var px: float = (float(cx) + shift + 0.5 + (N.unit4(seed, cx, cy, 1) - 0.5) * slab_jitter) * s
			var py: float = (float(cy) + 0.5 + (N.unit4(seed, cx, cy, 2) - 0.5) * slab_jitter) * s * sq
			var dx: float = float(x) + 0.5 - px
			var dy: float = (float(y) + 0.5 - py) / sq
			var d: float = dx * dx + dy * dy
			if d < best:
				second = best
				best = d
				best_cx = cx
				best_cy = cy
				best_dy = dy
			elif d < second:
				second = d
	var edge: float = sqrt(second) - sqrt(best)
	if edge < joint_width:
		return joint
	var rgb: int = N.mix(base, slab_tone, N.unit4(seed, best_cx, best_cy, 3) * slab_vary)
	# The upper edge of a slab (its middle lies below the pixel) catches the light.
	if has_light and edge < joint_width + light_width and best_dy < 0.0:
		rgb = light
	return rgb


func _stroke(x: int, y: int, rgb: int) -> int:
	var dx: float = float(x) + 0.5 - centre_x
	var dy: float = float(y) + 0.5 - centre_y
	var r: float = sqrt(dx * dx + dy * dy)
	if r < stroke_inner:
		return rgb
	var turn: float = fposmod(atan2(dy, dx) / N.TURN, 1.0)
	r += (N.noise1(turn * 6.0, seed + 9, 6) - 0.5) * stroke_spacing * 0.8
	var ring: int = floori(r / stroke_spacing + 0.5)
	if absf(r - float(ring) * stroke_spacing) >= 0.5:
		return rgb
	var pieces: int = maxi(3, N.round_even(N.TURN * float(ring) * stroke_spacing / 40.0))
	if N.noise1(turn * float(pieces), seed + 31 * ring, pieces) < 1.0 - stroke_share:
		return rgb
	return N.mix(rgb, stroke_colour, 0.5)


func _bilinear(fx: float, fy: float) -> float:
	var ix: int = int(fx)
	var iy: int = int(fy)
	var tx: float = fx - float(ix)
	var ty: float = fy - float(iy)
	var i: int = iy * cols + ix
	return (patch_map[i] * (1.0 - tx) + patch_map[i + 1] * tx) * (1.0 - ty) + (patch_map[i + cols] * (1.0 - tx) + patch_map[i + cols + 1] * tx) * ty
