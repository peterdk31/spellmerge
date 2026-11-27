class_name GroundDrawing
extends RefCounted
## A room's ground drawn from its shape (connected biomes CB4, docs/milestones/connected-biomes.md,
## decision 6): the floor, the rock face under it, the glow, the walls' own art and the edges' mote
## lines, as `tools/ground_shape.py` draws them (its `Drawing`, line by line), from the shape as it is
## placed: **mirrored** either way or not. View only: nothing in the simulation reads it.
##
## **Mirrored, never flipped.** The ground's outline (its land, cracks, pits, areas and which floor
## pixels a body stands on) is worked out in the template's own frame, exactly as the tool does,
## then mirrored; everything drawn on it (the flagstones, the lip, the rock face under the south
## edges, the walls' faces above the floor, the rims and drips) is drawn again on the mirrored
## outline, so the light still comes from the upper left. Unmirrored, every pixel is the baked art's
## (tests/gameplay/feel/test_ground_drawing.gd); mirrored, the floor a body stands on is the exact
## mirror of the unmirrored one, pixel for pixel. (Which edge style a pixel near a pit takes, `side`, is
## worked out again on the mirrored outline too: where two open grounds are as near, the walk's first
## comer wins, so it may differ from the mirror at a tie. A look only.)
##
## `draw(spec)` is the whole of it, a pure function of `spec` (`GroundShape.spec`): the native twin,
## `GroundKernel.draw` (native/src/ground_kernel.cpp), gives the same bytes, and is what the game
## calls when the module is loaded (`GroundShape.draw`); this is the reference and the fallback.
##
## **At 2x** (`DETAIL`, ArtDetail): the floor, the rock face and the walls' art are drawn again on the
## same outline, every pixel `DETAIL` by `DETAIL` art pixels, by the same rules at that detail (`_fine`;
## the tool's `Drawing._fine`). The glow, the rims and the drips are drawn once.
##
## A crack's width and an edge's share of it (`crack`, `t`) and the glow's sums are single precision,
## as the tool's `array("f")`; everything else is a double, as a Python float.

const N := preload("res://gameplay/feel/ground/ground_noise.gd")
const GeometryScript := preload("res://gameplay/feel/ground/ground_geometry.gd")
const MaterialScript := preload("res://gameplay/feel/ground/ground_material.gd")
const WallsScript := preload("res://gameplay/feel/ground/ground_walls.gd")

const CELL: int = 8
## How far round a trimmed ledge cell's middle its floor is cleared (`TRIM_ROUND`).
const TRIM_ROUND: int = 5
## How far from open ground a pixel still takes its edge style's side, in pixels.
const SIDE_REACH: int = 130
## Art pixels a world pixel of the fine art (ArtDetail.DETAIL).
const DETAIL: int = 2

## Art pixels a world pixel of what this drawing draws (1; its fine twin's `DETAIL`), and the 1x
## drawing a fine one is drawn on (null for the 1x one).
var detail: int = 1
var coarse: GroundDrawing = null
## The fine twin (`_fine`), drawn after this one.
var fine: GroundDrawing = null
## Where the 1x drawing put its pebbles (x, y a pair) and its rubble (x, y, size a triple), by side.
var pebbles_at: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var stones_at: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]

var w: int = 0
var h: int = 0
var shape: Dictionary = {}
var palette: Dictionary = {}
var styles: Array[Dictionary] = []
## Which of the two styles a side's is, by identity: the pits' is the outlines' own when the shape
## names no `pit_edge` (the tool's `styles[1] is styles[0]`).
var style_of_side := PackedInt32Array([0, 0])
var deeps := PackedInt32Array()
var grounds: Array = []
var land := PackedByteArray()
var land_before := PackedByteArray()
var crack := PackedFloat32Array()
var material := PackedByteArray()
var pit := PackedByteArray()
var pit_side := PackedByteArray()
var solid := PackedByteArray()
var side := PackedByteArray()
var t := PackedFloat32Array()
var floor_image := PackedByteArray()
var under := PackedByteArray()
var glow := PackedByteArray()
var glow_w: int = 0
var glow_h: int = 0
var wall_art := PackedByteArray()
var rims: Array[PackedVector2Array] = []
var rim_sides := PackedInt32Array()
var drips: Array[PackedVector2Array] = []
var drip_colours := PackedStringArray()
var drip_sides := PackedInt32Array()
var band := PackedInt32Array()
var seam := PackedInt32Array()
var _rim_paths: Array[PackedInt32Array] = []
var _rim_every := PackedInt32Array()
var _rim_path_sides := PackedInt32Array()
var _mirror_x: bool = false
var _mirror_y: bool = false


## The ground `spec` describes (`GroundShape.spec`: the shape, where the room's things stand, its
## edge styles, ground materials and palette, and its mirroring; `threads`, read by the native twin
## only, how many threads it draws on, 0 or absent the machine's), as a dictionary of what is drawn:
## `width`, `height`, `solid` (1 where a body stands), `floor` and `under` (RGBA, a pixel each),
## `glow` (RGBA at half size, `glow_width` by `glow_height`), `wall` (RGBA, empty for none), `rims`
## and `drips` (their points), `rim_sides`, `drip_sides` and `drip_colours`; and at 2x (`detail`, its
## `DETAIL`): `fine_floor`, `fine_under` and `fine_wall` (RGBA, `width` * `detail` by `height` * `detail`).
static func draw(spec: Dictionary) -> Dictionary:
	var drawing := new()
	drawing._draw(spec)
	return drawing.result()


func result() -> Dictionary:
	return {
		"width": w, "height": h, "solid": solid, "floor": floor_image, "under": under,
		"glow_width": glow_w, "glow_height": glow_h, "glow": glow, "wall": wall_art,
		"rims": rims, "rim_sides": rim_sides, "drips": drips, "drip_sides": drip_sides, "drip_colours": drip_colours,
		"detail": fine.detail, "fine_floor": fine.floor_image, "fine_under": fine.under, "fine_wall": fine.wall_art,
	}


func _draw(spec: Dictionary) -> void:
	shape = spec["shape"]
	palette = spec["palette"]
	var given: Array = spec["styles"]
	styles = [given[0] as Dictionary, given[1] as Dictionary]
	style_of_side = PackedInt32Array([0, 1 if bool(spec.get("pit_style", false)) else 0])
	for st: Dictionary in styles:
		deeps.append(N.colour(st["deep"], palette))
	grounds = spec["grounds"]
	var geometry := GeometryScript.new(shape, spec.get("placed", PackedFloat64Array()), spec.get("clear", PackedFloat64Array()))
	w = geometry.width
	h = geometry.height
	land = geometry.land
	crack = geometry.crack
	material = geometry.material
	pit = geometry.pit
	pit_side = geometry.pit_side
	land_before = land.duplicate()
	var n: int = w * h
	# Solid: what a body may stand on. Land, and a crack too thin for a whole cell.
	solid.resize(n)
	for p in n:
		if land[p] != 0 or (crack[p] > 0.0 and crack[p] < float(CELL)):
			solid[p] = 1
	_drop_slivers()
	if shape.has("frame"):
		_trim_to_reach()
		_drop_slivers()
	_mirror(bool(spec.get("mirror_x", false)), bool(spec.get("mirror_y", false)))
	side = _sides()
	var fulls := PackedFloat64Array([float(styles[0]["full_width"]), float(styles[1]["full_width"])])
	# t: how much of the whole edge a place has, from the nearest crack's width.
	var near := PackedFloat32Array()
	near.resize(n)
	for p in n:
		var cw: float = crack[p]
		if cw > 0.0:
			var px: int = p % w
			var py: int = p / w
			for dy in range(-4, 5):
				for dx in range(-4 + absi(dy), 5 - absi(dy)):
					var x: int = px + dx
					var y: int = py + dy
					if x >= 0 and x < w and y >= 0 and y < h and near[y * w + x] < cw:
						near[y * w + x] = cw
	t.resize(n)
	t.fill(1.0)
	for p in n:
		if near[p] > 0.0:
			var full: float = fulls[side[p]]
			t[p] = minf(1.0, maxf(0.0, (near[p] - 1.5) / (full - 1.5)))
	floor_image.resize(n * 4)
	under.resize(n * 4)
	band.resize(n)
	band.fill(-1)
	_draw_floor()
	_trace_rims()
	_spread_bands()
	_draw_edges()
	_draw_under()
	_draw_glow()
	_draw_wall_art()
	fine = _fine(DETAIL)


## The same ground drawn again at `d` art pixels a world pixel: this one's outline, each pixel `d` by `d`,
## and on it the floor, the edges, the rock face and the walls' art by the same rules at that detail.
func _fine(d: int) -> GroundDrawing:
	var out: GroundDrawing = GroundDrawing.new()
	out.detail = d
	out.coarse = self
	out.shape = shape
	out.palette = palette
	out.styles = styles
	out.style_of_side = style_of_side
	out.deeps = deeps
	out.grounds = grounds
	out._mirror_x = _mirror_x
	out._mirror_y = _mirror_y
	out.w = w * d
	out.h = h * d
	out.land = _upsampled_bytes(land, d)
	out.pit = _upsampled_bytes(pit, d)
	out.pit_side = _upsampled_bytes(pit_side, d)
	out.material = _upsampled_bytes(material, d)
	out.solid = _upsampled_bytes(solid, d)
	out.side = _upsampled_bytes(side, d)
	out.crack = _upsampled_floats(crack, d)
	out.t = _upsampled_floats(t, d)
	out.band.resize(out.w * out.h)
	for y in out.h:
		for x in out.w:
			out.band[y * out.w + x] = band[(y / d) * w + x / d]
	out.floor_image.resize(out.w * out.h * 4)
	out.under.resize(out.w * out.h * 4)
	out._draw_floor()
	out._draw_edges()
	out._draw_under()
	out._draw_wall_art()
	return out


func _upsampled_bytes(mask: PackedByteArray, d: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * d * h * d)
	var wide: int = w * d
	for y in h * d:
		for x in wide:
			out[y * wide + x] = mask[(y / d) * w + x / d]
	return out


func _upsampled_floats(values: PackedFloat32Array, d: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(w * d * h * d)
	var wide: int = w * d
	for y in h * d:
		for x in wide:
			out[y * wide + x] = values[(y / d) * w + x / d]
	return out


## The shape's outline as placed: every mask mirrored along x and/or y (pixel x to w - 1 - x).
func _mirror(along_x: bool, along_y: bool) -> void:
	_mirror_x = along_x
	_mirror_y = along_y
	if not along_x and not along_y:
		return
	land = _mirrored_bytes(land, along_x, along_y)
	land_before = _mirrored_bytes(land_before, along_x, along_y)
	material = _mirrored_bytes(material, along_x, along_y)
	pit = _mirrored_bytes(pit, along_x, along_y)
	pit_side = _mirrored_bytes(pit_side, along_x, along_y)
	solid = _mirrored_bytes(solid, along_x, along_y)
	var flipped := PackedFloat32Array()
	flipped.resize(w * h)
	for y in h:
		var from_y: int = h - 1 - y if along_y else y
		for x in w:
			flipped[y * w + x] = crack[from_y * w + (w - 1 - x if along_x else x)]
	crack = flipped


func _mirrored_bytes(mask: PackedByteArray, along_x: bool, along_y: bool) -> PackedByteArray:
	var flipped := PackedByteArray()
	flipped.resize(w * h)
	for y in h:
		var from_y: int = h - 1 - y if along_y else y
		for x in w:
			flipped[y * w + x] = mask[from_y * w + (w - 1 - x if along_x else x)]
	return flipped


## Which edge style each pixel's nearest edge is drawn in (`_sides`): open ground is its own side,
## ground takes the side of the nearest open ground, out to SIDE_REACH pixels.
func _sides() -> PackedByteArray:
	var found: PackedByteArray = pit_side.duplicate()
	var any: bool = false
	for p in pit_side.size():
		if pit_side[p] != 0:
			any = true
			break
	if not any:
		return found
	var seen := PackedByteArray()
	seen.resize(w * h)
	var frontier := PackedInt32Array()
	for p in w * h:
		if land_before[p] == 0:
			seen[p] = 1
			frontier.append(p)
	for _step in SIDE_REACH:
		var next := PackedInt32Array()
		for q: int in frontier:
			var x: int = q % w
			var y: int = q / w
			for way in 4:
				var nx: int = x + (1 if way == 0 else (-1 if way == 1 else 0))
				var ny: int = y + (1 if way == 2 else (-1 if way == 3 else 0))
				if nx >= 0 and nx < w and ny >= 0 and ny < h:
					var r: int = ny * w + nx
					if seen[r] == 0:
						seen[r] = 1
						found[r] = found[q]
						next.append(r)
		frontier = next
		if frontier.is_empty():
			break
	return found


## Clear every piece of ground that holds no open cell (`_drop_slivers`).
func _drop_slivers() -> void:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var piece := PackedInt32Array()
	for p0 in w * h:
		if solid[p0] == 0 or seen[p0] != 0:
			continue
		piece.clear()
		piece.append(p0)
		seen[p0] = 1
		var k: int = 0
		var open_cell: bool = false
		while k < piece.size():
			var q: int = piece[k]
			k += 1
			var x: int = q % w
			var y: int = q / w
			if x % CELL == CELL / 2 and y % CELL == CELL / 2:
				open_cell = true
			for way in 4:
				var nx: int = x + (1 if way == 0 else (-1 if way == 1 else 0))
				var ny: int = y + (1 if way == 2 else (-1 if way == 3 else 0))
				if nx >= 0 and nx < w and ny >= 0 and ny < h:
					var r: int = ny * w + nx
					if solid[r] != 0 and seen[r] == 0:
						seen[r] = 1
						piece.append(r)
		if not open_cell:
			for q: int in piece:
				solid[q] = 0
				land[q] = 0


## A hall's floor where no wizard can stand beside it goes (`_trim_to_reach`).
func _trim_to_reach() -> void:
	var cols: int = w / CELL
	var rows: int = h / CELL
	var r2: int = TRIM_ROUND * TRIM_ROUND
	var open := PackedByteArray()
	open.resize(cols * rows)
	var fits := PackedByteArray()
	fits.resize(cols * rows)
	while true:
		for r in rows:
			for c in cols:
				open[r * cols + c] = solid[(r * CELL + CELL / 2) * w + c * CELL + CELL / 2]
		for r in rows:
			for c in cols:
				var all: int = 1
				for dr in range(-1, 2):
					for dc in range(-1, 2):
						var rr: int = r + dr
						var cc: int = c + dc
						if rr < 0 or rr >= rows or cc < 0 or cc >= cols or open[rr * cols + cc] == 0:
							all = 0
				fits[r * cols + c] = all
		var trimmed: int = 0
		for r in rows:
			for c in cols:
				if open[r * cols + c] == 0:
					continue
				var near_fit: bool = false
				for dr in range(-1, 2):
					for dc in range(-1, 2):
						var rr: int = r + dr
						var cc: int = c + dc
						if rr >= 0 and rr < rows and cc >= 0 and cc < cols and fits[rr * cols + cc] != 0:
							near_fit = true
				if near_fit:
					continue
				trimmed += 1
				var mx: int = c * CELL + CELL / 2
				var my: int = r * CELL + CELL / 2
				for y in range(maxi(0, my - TRIM_ROUND), mini(h, my + TRIM_ROUND + 1)):
					for x in range(maxi(0, mx - TRIM_ROUND), mini(w, mx + TRIM_ROUND + 1)):
						if (x - mx) * (x - mx) + (y - my) * (y - my) <= r2:
							var q: int = y * w + x
							solid[q] = 0
							land[q] = 0
		if trimmed == 0:
			return


func _draw_floor() -> void:
	var seed: int = int(shape.get("seed", 0))
	var size := Vector2i(w, h)
	# Each material's middle (its strokes go round it), x then y, as doubles: the room's, then each area's.
	var centres := PackedFloat64Array([float(w) / 2.0, float(h) / 2.0])
	for area: Dictionary in shape.get("areas", []):
		centres.append_array(_area_centre(area["centre"]))
	var mats: Array[GroundMaterial] = []
	var reach: int = 0
	for k in grounds.size():
		var mat: GroundMaterial = MaterialScript.new(grounds[k], k, seed, size, centres[k * 2], centres[k * 2 + 1], palette, detail)
		mats.append(mat)
		if mat.has_edge:
			reach = maxi(reach, int(mat.edge_reach))
	var edge_distance: PackedInt32Array = _edge_distance(reach)
	for p in w * h:
		if solid[p] == 0:
			continue
		if land[p] == 0:
			WallsScript.put(floor_image, p, deeps[side[p]])
			continue
		var ed: float = float(edge_distance[p]) if not edge_distance.is_empty() else 1e9
		WallsScript.put(floor_image, p, mats[material[p]].at(p % w, p / w, ed))


## An area's centre as placed (its strokes go round it), in this drawing's pixels: mirrored with the room.
func _area_centre(centre: Array) -> PackedFloat64Array:
	var x: float = float(centre[0]) * float(detail)
	var y: float = float(centre[1]) * float(detail)
	return PackedFloat64Array([float(w) - x if _mirror_x else x, float(h) - y if _mirror_y else y])


func _edge_distance(reach: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	if reach <= 0:
		return dist
	dist.resize(w * h)
	dist.fill(reach + 1)
	var frontier := PackedInt32Array()
	for p in w * h:
		if _is_edge(p):
			frontier.append(p)
			dist[p] = 0
	for d in range(1, reach + 1):
		var next := PackedInt32Array()
		for q: int in frontier:
			var x: int = q % w
			var y: int = q / w
			for way in 4:
				var nx: int = x + (1 if way == 0 else (-1 if way == 1 else 0))
				var ny: int = y + (1 if way == 2 else (-1 if way == 3 else 0))
				if nx >= 0 and nx < w and ny >= 0 and ny < h:
					var r: int = ny * w + nx
					if land[r] != 0 and dist[r] > d:
						dist[r] = d
						next.append(r)
		frontier = next
	return dist


## Land with a 4-neighbour that is not land (the void, a crack or the room's border).
func _is_edge(p: int) -> bool:
	if land[p] == 0:
		return false
	var x: int = p % w
	var y: int = p / w
	return x + 1 >= w or land[p + 1] == 0 or x == 0 or land[p - 1] == 0 or y + 1 >= h or land[p + w] == 0 or y == 0 or land[p - w] == 0


## The rims: the boundary of each piece of solid ground, traced clockwise on screen (`_trace_rims`).
func _trace_rims() -> void:
	var seen := PackedByteArray()
	seen.resize(w * h)
	for p in w * h:
		if solid[p] == 0 or seen[p] != 0:
			continue
		var x: int = p % w
		var y: int = p / w
		if y > 0 and solid[p - w] != 0:
			continue
		var path: PackedInt32Array = _moore(x, y)
		for q: int in path:
			seen[q] = 1
		if path.size() < 16:
			continue
		var area: int = 0
		for i in path.size():
			var a: int = path[i]
			var b: int = path[(i + 1) % path.size()]
			area += (a % w) * (b / w) - (b % w) * (a / w)
		var at_side: int = side[p - w] if y > 0 else 0
		if not ((area > 0 and at_side == 0) or (area < 0 and at_side == 1)):
			continue
		var style: Dictionary = styles[at_side]
		var every: int = int((style.get("rim", {}) as Dictionary).get("every", 4))
		_rim_paths.append(path)
		_rim_every.append(every)
		_rim_path_sides.append(at_side)
		if style.has("rim"):
			var points := PackedVector2Array()
			for i in range(0, path.size(), every):
				points.append(Vector2(float(path[i] % w) + 0.5, float(path[i] / w) + 0.5))
			rims.append(points)
			rim_sides.append(at_side)


## Moore-neighbour tracing of the solid pixels' boundary from the top-edge pixel (sx, sy).
func _moore(sx: int, sy: int) -> PackedInt32Array:
	var ways_x := PackedInt32Array([1, 1, 0, -1, -1, -1, 0, 1])
	var ways_y := PackedInt32Array([0, 1, 1, 1, 0, -1, -1, -1])
	var start: int = sy * w + sx
	var path := PackedInt32Array([start])
	var x: int = sx
	var y: int = sy
	var back: int = 6
	var first: int = -1
	for _i in w * h * 2:
		var step: int = -1
		for k in 8:
			var d: int = (back + 1 + k) % 8
			var nx: int = x + ways_x[d]
			var ny: int = y + ways_y[d]
			if nx >= 0 and nx < w and ny >= 0 and ny < h and solid[ny * w + nx] != 0:
				step = d
				break
		if step < 0:
			break
		if y * w + x == start and step == first:
			break
		if first < 0:
			first = step
		back = (step + 4) % 8
		x += ways_x[step]
		y += ways_y[step]
		if y * w + x != start:
			path.append(y * w + x)
	return path


## Every pixel within reach of a rim takes the colour band of the nearest stretch of rim.
func _spread_bands() -> void:
	var frontier := PackedInt32Array()
	var reach: int = 0
	for k in _rim_paths.size():
		var path: PackedInt32Array = _rim_paths[k]
		var every: int = _rim_every[k]
		var seam_spec: Dictionary = styles[_rim_path_sides[k]].get("seam", {})
		if seam_spec.is_empty():
			continue
		var length: float = float(seam_spec["band_length"])
		var count: int = (seam_spec["colours"] as Array).size()
		reach = maxi(reach, int(seam_spec.get("reach", 120)))
		var run: float = 0.0
		var has_last: bool = false
		var last_x: float = 0.0
		var last_y: float = 0.0
		var marks := PackedFloat64Array()
		for i in range(0, path.size(), every):
			var q: int = path[i]
			var here_x: float = float(q % w) + 0.5
			var here_y: float = float(q / w) + 0.5
			if has_last:
				run += N.length_of(here_x - last_x, here_y - last_y)
			marks.append(run)
			has_last = true
			last_x = here_x
			last_y = here_y
		for i in path.size():
			var q: int = path[i]
			var b: int = int(marks[mini(i / every, marks.size() - 1)] / length) % count
			if band[q] < 0:
				band[q] = b
				frontier.append(q)
	for _step in reach:
		var next := PackedInt32Array()
		for q: int in frontier:
			var x: int = q % w
			var y: int = q / w
			var b: int = band[q]
			for way in 4:
				var nx: int = x + (1 if way == 0 else (-1 if way == 1 else 0))
				var ny: int = y + (1 if way == 2 else (-1 if way == 3 else 0))
				if nx >= 0 and nx < w and ny >= 0 and ny < h:
					var r: int = ny * w + nx
					if band[r] < 0 and side[r] == side[q]:
						band[r] = b
						next.append(r)
		frontier = next
		if frontier.is_empty():
			break


## The seam's three shades (shadow, base, light) at `p`, empty where it has none.
func _seam_colour(p: int) -> PackedInt32Array:
	var b: int = band[p]
	var seam_spec: Dictionary = styles[side[p]].get("seam", {})
	if b < 0 or seam_spec.is_empty():
		return PackedInt32Array()
	return palette[(seam_spec["colours"] as Array)[b]]


## The seam and the lip inside it, then the lip's pebbles and rubble and a wall's dark foot.
func _draw_edges() -> void:
	var lip_colours: Array[PackedInt32Array] = []
	var lip_widths := PackedInt32Array()
	for st: Dictionary in styles:
		var shades := PackedInt32Array()
		for c: Variant in st["lip"]["shades"]:
			shades.append(N.colour(c, palette))
		lip_colours.append(shades)
		lip_widths.append(int(st["lip"]["width"]))
	var lip_most: int = maxi(lip_widths[0], lip_widths[1])
	var k: int = detail
	var dist := PackedByteArray()
	dist.resize(w * h)
	var frontier := PackedInt32Array()
	for p in w * h:
		if _is_edge(p):
			frontier.append(p)
			dist[p] = 1
	for d in range(2, (lip_most + 1) * k + 1):
		var next := PackedInt32Array()
		for q: int in frontier:
			var x: int = q % w
			var y: int = q / w
			for way in 4:
				var nx: int = x + (1 if way == 0 else (-1 if way == 1 else 0))
				var ny: int = y + (1 if way == 2 else (-1 if way == 3 else 0))
				if nx >= 0 and nx < w and ny >= 0 and ny < h:
					var r: int = ny * w + nx
					if land[r] != 0 and dist[r] == 0:
						dist[r] = d
						next.append(r)
		frontier = next
	var edge_pixels := PackedInt32Array()
	for p in w * h:
		var d: int = dist[p]
		if d == 0:
			continue
		var at_side: int = side[p]
		var tp: float = t[p]
		var roll: float = N.unit3(p % w, p / w, 5051)
		if d == 1:
			edge_pixels.append(p)
		var seamed: bool = styles[at_side].has("seam")
		if d <= k and seamed:
			var ramp: PackedInt32Array = _seam_colour(p)
			if ramp.is_empty():
				continue
			if k > 1:
				# Finer: the seam's inner row toward its light, its outer toward its shadow.
				roll = roll * 0.5 if d > 1 else 0.5 + roll * 0.5
			# Light and base where the edge is whole, base then shadow as a crack narrows.
			var rgb: int
			if roll < tp * 0.5:
				rgb = ramp[2]
			elif roll < 0.25 + tp * 0.75:
				rgb = ramp[1]
			else:
				rgb = ramp[0]
			WallsScript.put(floor_image, p, rgb)
			seam.append(p)
		elif float(d - k) / float(k) <= float(lip_widths[at_side]) * tp + 0.2 and tp > 0.2:
			# Finer: the lip's outer row (under the seam, or the edge's own) in its shadow.
			if k > 1 and d == (k + 1 if seamed else 1):
				WallsScript.put(floor_image, p, lip_colours[at_side][0])
			else:
				WallsScript.put(floor_image, p, lip_colours[at_side][1] if roll < 0.3 else lip_colours[at_side][0])
	# The pebbles and the rubble lie where the 1x drawing put them.
	var placed: GroundDrawing = coarse if coarse != null else self
	for at_side in styles.size():
		var style: Dictionary = styles[at_side]
		var lip: Dictionary = style["lip"]
		if lip.has("pebbles") and not (lip["pebbles"] as Dictionary).is_empty():
			if k == 1:
				var mine := PackedInt32Array()
				for p: int in seam:
					if side[p] == at_side:
						mine.append(p)
				pebbles_at[at_side] = _pebble_places(lip["pebbles"], mine)
			_draw_pebbles(lip["pebbles"], placed.pebbles_at[at_side])
		if lip.has("rubble") and not (lip["rubble"] as Dictionary).is_empty():
			if k == 1:
				var mine := PackedInt32Array()
				for p: int in edge_pixels:
					if side[p] == at_side:
						mine.append(p)
				stones_at[at_side] = _rubble_places(lip["rubble"], mine)
			_draw_rubble(lip["rubble"], placed.stones_at[at_side])
		var face: Dictionary = style.get("face", {})
		if not face.is_empty() and face.has("foot") and at_side == 0:
			_draw_foot(face["foot"])


## The seam pixels a pebble lies above (x, y pairs): one every `every` where the edge is whole.
func _pebble_places(pebbles: Dictionary, along: PackedInt32Array) -> PackedInt32Array:
	var every: int = int(pebbles["every"])
	var found := PackedInt32Array()
	for p: int in along:
		if t[p] < 0.9 or N.hash2(p, 6061) % every != 0:
			continue
		found.append(p % w)
		found.append(p / w)
	return found


## A pebble above each place (world pixels, x, y pairs), 4 by 3 world pixels; finer, rounded.
func _draw_pebbles(pebbles: Dictionary, places: PackedInt32Array) -> void:
	var shades := PackedInt32Array()
	for c: Variant in pebbles["shades"]:
		shades.append(N.colour(c, palette))
	var k: int = detail
	for at in range(0, places.size(), 2):
		var x0: int = places[at]
		var y0: int = places[at + 1]
		for j in 3 * k:
			for i in 4 * k:
				var xx: int = (x0 - 2) * k + i
				var yy: int = (y0 - 6) * k + j
				var q: int = yy * w + xx
				if yy < 0 or yy >= h or xx < 0 or xx >= w or land[q] == 0:
					continue
				var inner: bool = i >= k and i < 3 * k and j >= k and j < 3 * k
				var rgb: int
				if k == 1:
					rgb = shades[2] if (inner and i == 1 and j == 1) else (shades[1] if inner else shades[0])
				elif (i == 0 or i == 4 * k - 1) and (j == 0 or j == 3 * k - 1):
					continue
				elif not inner:
					rgb = shades[0]
				elif i < 2 * k and j < 2 * k and i + j < 3 * k:
					rgb = shades[2]
				elif i == 3 * k - 1 and j == 3 * k - 1:
					rgb = shades[0]
				else:
					rgb = shades[1]
				WallsScript.put(floor_image, q, rgb)


## Where each stone of rubble lies and how big (x, y, size triples, world pixels).
func _rubble_places(rubble: Dictionary, edge: PackedInt32Array) -> PackedInt32Array:
	var sizes: Array = rubble["sizes"]
	var lo: int = int(sizes[0])
	var hi: int = int(sizes[1])
	var every: int = int(rubble["every"])
	var found := PackedInt32Array()
	for p: int in edge:
		if t[p] < 0.6 or N.hash2(p, 7071) % every != 0:
			continue
		var size: int = lo + N.hash2(p, 7072) % (hi - lo + 1)
		var x: int = p % w
		var y: int = p / w
		# Lie inside the edge: step to the land side of the edge pixel.
		var steps_x := PackedInt32Array([x, x + 1, x - 1, x])
		var steps_y := PackedInt32Array([y + 1, y, y, y - 1])
		for k in 4:
			var nx: int = steps_x[k]
			var ny: int = steps_y[k]
			if nx >= 0 and nx < w and ny >= 0 and ny < h and land[ny * w + nx] != 0 and not _is_edge(ny * w + nx):
				x = nx
				y = ny
				break
		found.append(x)
		found.append(y)
		found.append(size)
	return found


## The stones (x, y, size triples, world pixels): each its base colour, a lit top row and a dark row
## under it; finer, its upper corners rounded, its left side lit too, its shadow a step softer.
func _draw_rubble(rubble: Dictionary, stones: PackedInt32Array) -> void:
	var shades: Array = rubble["shades"]
	var dark: int = N.colour(shades[0], palette)
	var base: int = N.colour(shades[1], palette)
	var light: int = N.colour(shades[2], palette)
	var k: int = detail
	for at in range(0, stones.size(), 3):
		var x0: int = stones[at]
		var y0: int = stones[at + 1]
		var size: int = stones[at + 2]
		for dy in (size + 1) * k:
			for dx in (size + 1) * k:
				var xx: int = x0 * k + dx
				var yy: int = y0 * k + dy
				if xx < 0 or xx >= w or yy < 0 or yy >= h or land[yy * w + xx] == 0:
					continue
				if dx / k == size and dy / k < size:
					continue
				var q: int = yy * w + xx
				var rgb: int
				if k == 1:
					rgb = dark if dy == size else (light if dy == 0 and size > 1 else base)
				elif dy >= size * k:
					if dy == size * k:
						rgb = dark
					else:
						rgb = N.mix((floor_image[q * 4] << 16) | (floor_image[q * 4 + 1] << 8) | floor_image[q * 4 + 2], dark, 0.5)
				elif size > 1 and dy == 0 and (dx == 0 or dx == size * k - 1):
					continue
				elif size > 1 and (dy == 0 or dx == 0):
					rgb = light
				else:
					rgb = base
				WallsScript.put(floor_image, q, rgb)


func _draw_foot(foot: Array) -> void:
	var shade: int = N.colour(foot[0], palette)
	var rows: int = int(foot[1]) * detail
	for p in range(w, w * h):
		if land[p] == 0 or land[p - w] != 0 or pit[p - w] != 0 or crack[p - w] > 0.0:
			continue
		for k in rows:
			var q: int = p + k * w
			if q >= w * h or land[q] == 0:
				break
			var old: int = (floor_image[q * 4] << 16) | (floor_image[q * 4 + 1] << 8) | floor_image[q * 4 + 2]
			WallsScript.put(floor_image, q, N.mix(old, shade, float(rows - k) / float(rows + 1)))


## The rock face under every edge that faces down, hanging into the clear pixels below it.
func _draw_under() -> void:
	var rocks: Array[Dictionary] = []
	for st: Dictionary in styles:
		var rock: Dictionary = st.get("rock", {})
		if rock.is_empty():
			rocks.append({})
			continue
		var shades := PackedInt32Array()
		for c: Variant in rock["shades"]:
			shades.append(N.colour(c, palette))
		var depth: Array = rock["depth"]
		rocks.append({"shades": shades, "strata": N.colour(rock["strata"], palette), "roots": N.colour(rock["roots"], palette),
			"lo": float(depth[0]), "hi": float(depth[1])})
	var seed: int = int(shape.get("seed", 0)) + 21
	var fine_k: int = detail
	var bottoms: Dictionary = {}
	var edges: Dictionary = {}
	for x in w:
		for y in h - 1:
			var p: int = y * w + x
			if solid[p] == 0 or solid[p + w] != 0:
				continue
			var below_side: int = side[p + w]
			var rock: Dictionary = rocks[below_side]
			if rock.is_empty():
				continue
			var shades: PackedInt32Array = rock["shades"]
			var strata: int = rock["strata"]
			var lo: float = rock["lo"]
			var hi: float = rock["hi"]
			var deep: int = deeps[below_side]
			var tp: float = t[p]
			var depth: int = int((lo + (hi - lo) * pow(N.noise1(float(x) / (14.0 * float(fine_k)), seed), 1.8)) * tp * float(fine_k))
			var bottom: int = y
			for d in range(1, depth + 1):
				var yy: int = y + d
				if yy >= h:
					break
				var q: int = yy * w + x
				if solid[q] != 0:
					break
				var k: float = N.noise2(float(x), float(yy), 7.0 * float(fine_k), seed + 1)
				var rgb: int = shades[1] if k > 0.55 else shades[0]
				var turn: float = (float(yy) / float(fine_k) + N.noise1(float(x) / (9.0 * float(fine_k)), seed + 2) * 18.0) / 5.0
				var layer: float = sin(turn)
				if layer > 0.85:
					rgb = strata
				elif fine_k > 1 and layer > 0.6 and cos(turn) < 0.0:
					# Finer: the shadow a stratum casts on the rock under it.
					rgb = N.mix(rgb, strata, 0.5)
				elif fine_k > 1 and d == 1:
					# Finer: the face's top row catching the light under the edge.
					rgb = shades[1]
				rgb = N.mix(deep, rgb, tp)
				WallsScript.put(under, q, rgb)
				bottom = yy
			if bottom > y and tp > 0.6:
				var q: int = bottom * w + x
				WallsScript.put(under, q, strata)
				if fine_k == 1:
					bottoms[x * h + bottom] = q
					edges[x * h + bottom] = p
				# A root hangs from a world pixel's edge (finer, from one column of its pixels).
				var xr: int = x / fine_k
				var yr: int = y / fine_k
				if N.hash3(xr, yr, seed) % 7 == 0 and (fine_k == 1 or x % fine_k == N.hash4(xr, yr, seed, 3) % fine_k):
					var length: int = (6 + N.hash4(xr, yr, seed, 2) % 30) * fine_k
					for d in range(1, length):
						var yy: int = bottom + d
						if yy < h and solid[yy * w + x] == 0:
							WallsScript.put(under, yy * w + x, rock["roots"])
	if fine_k > 1:
		return
	# The drips leave from the rock's bottom: runs of neighbouring columns under one band of the
	# seam, each in that band's colour alone; a line runs right to left, so the left of its way
	# (where a line throws its motes) is down.
	var cells: Array = bottoms.keys()
	cells.sort()
	var run_bands := PackedInt32Array()
	var run_sides := PackedInt32Array()
	var runs: Array[PackedVector2Array] = []
	var has_last: bool = false
	var last := PackedInt32Array([0, 0, 0, 0])
	for key: int in cells:
		var x: int = key / h
		var y: int = key % h
		var edge_at: int = edges[key]
		var at_band: int = band[edge_at]
		var at_side: int = side[edge_at + w]
		if has_last and x == last[0] + 1 and absi(y - last[1]) <= 6 and at_band == last[2] and at_side == last[3]:
			runs[runs.size() - 1].append(Vector2(float(x) + 0.5, float(y) + 1.0))
		else:
			runs.append(PackedVector2Array([Vector2(float(x) + 0.5, float(y) + 1.0)]))
			run_bands.append(at_band)
			run_sides.append(at_side)
		has_last = true
		last = PackedInt32Array([x, y, at_band, at_side])
	for i in runs.size():
		var run: PackedVector2Array = runs[i]
		var style: Dictionary = styles[run_sides[i]]
		if run.size() < 12 or run_bands[i] < 0 or not style.has("drip") or not style.has("seam"):
			continue
		var every: int = int((style.get("rim", {}) as Dictionary).get("every", 4))
		var points := PackedVector2Array()
		for k in range(0, run.size(), every):
			points.append(run[k])
		if (run.size() - 1) % every != 0:
			points.append(run[run.size() - 1])
		points.reverse()
		drips.append(points)
		drip_colours.append(String((style["seam"]["colours"] as Array)[run_bands[i]]))
		drip_sides.append(run_sides[i])


## The edges' glow, at half size: every seam pixel adds its band's base colour by its t, blurred
## twice (near and far) and added together.
func _draw_glow() -> void:
	glow_w = w / 2
	glow_h = h / 2
	var size: int = glow_w * glow_h
	var out: Array[PackedFloat32Array] = []
	for c in 3:
		var channel := PackedFloat32Array()
		channel.resize(size)
		out.append(channel)
	for at_side in styles.size():
		var style: Dictionary = styles[at_side]
		var spec: Dictionary = style.get("glow", {})
		if spec.is_empty() or (at_side == 1 and style_of_side[1] == style_of_side[0]):
			continue
		var acc_r := PackedFloat32Array()
		var acc_g := PackedFloat32Array()
		var acc_b := PackedFloat32Array()
		acc_r.resize(size)
		acc_g.resize(size)
		acc_b.resize(size)
		for p: int in seam:
			if style_of_side[side[p]] != style_of_side[at_side]:
				continue
			var ramp: PackedInt32Array = _seam_colour(p)
			if ramp.is_empty():
				continue
			var k: float = pow(t[p], 1.5)
			var q: int = ((p / w) / 2) * glow_w + (p % w) / 2
			var base: int = ramp[1]
			acc_r[q] += float((base >> 16) & 0xFF) * k / 255.0 * 0.25
			acc_g[q] += float((base >> 8) & 0xFF) * k / 255.0 * 0.25
			acc_b[q] += float(base & 0xFF) * k / 255.0 * 0.25
		var acc: Array[PackedFloat32Array] = [acc_r, acc_g, acc_b]
		for blur: Array in spec["blurs"]:
			var radius: int = int(blur[0])
			var strength: float = float(blur[1])
			for c in 3:
				var blurred: PackedFloat32Array = box_blur(box_blur(acc[c], glow_w, glow_h, radius, true), glow_w, glow_h, radius, false)
				var channel: PackedFloat32Array = out[c]
				for q in size:
					channel[q] += blurred[q] * strength
				out[c] = channel
	glow.resize(size * 4)
	for q in size:
		var r: float = out[0][q]
		var g: float = out[1][q]
		var b: float = out[2][q]
		var a: float = minf(1.0, maxf(r, maxf(g, b)))
		if a < 1.0 / 255.0:
			continue
		glow[q * 4] = mini(255, N.round_even(r / a * 255.0))
		glow[q * 4 + 1] = mini(255, N.round_even(g / a * 255.0))
		glow[q * 4 + 2] = mini(255, N.round_even(b / a * 255.0))
		glow[q * 4 + 3] = N.round_even(a * 255.0)


static func box_blur(src: PackedFloat32Array, bw: int, bh: int, radius: int, along_rows: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(bw * bh)
	var span: float = float(2 * radius + 1)
	if along_rows:
		for y in bh:
			var row: int = y * bw
			var total: float = 0.0
			for x in range(-radius, radius + 1):
				if x >= 0 and x < bw:
					total += src[row + x]
			for x in bw:
				out[row + x] = total / span
				if x - radius >= 0:
					total -= src[row + x - radius]
				if x + radius + 1 < bw:
					total += src[row + x + radius + 1]
	else:
		for x in bw:
			var total: float = 0.0
			for y in range(-radius, radius + 1):
				if y >= 0 and y < bh:
					total += src[y * bw + x]
			for y in bh:
				out[y * bw + x] = total / span
				if y - radius >= 0:
					total -= src[(y - radius) * bw + x]
				if y + radius + 1 < bh:
					total += src[(y + radius + 1) * bw + x]
	return out


## The walls' own art where the void is wall and the outlines' style draws a top or a face.
func _draw_wall_art() -> void:
	var style: Dictionary = styles[0]
	if String(shape.get("void", "wall")) == "hole" or not (style.has("top") or style.has("face")):
		return
	var wall := PackedByteArray()
	wall.resize(w * h)
	for p in w * h:
		if solid[p] == 0 and crack[p] == 0.0 and pit[p] == 0:
			wall[p] = 1
	wall_art = WallsScript.draw(w, h, solid, wall, style, palette, int(shape.get("seed", 0)) + 61, detail)
