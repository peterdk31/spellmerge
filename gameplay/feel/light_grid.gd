extends RefCounted
## Grid lighting (the owner's decision of 2026-11-21, docs/milestones/connected-biomes.md, "Grid
## lighting"): the spell light worked out on a coarse grid of world cells, CELL px each way, in
## place of a light buffer drawn by the GPU. The spell light's (`spell_light.gd`): it hands over the
## rows it is handed (the shots', runes', flashes', cues', spots' and carried lights', each in the
## row format the GPU's light read before, light.gdshader's: ROWS_*), the live beams' paths and the boxes that block light;
## this works the light out at each cell's middle with the shader's falloff and blocking, and writes
## one small texture (`texture`) that every reader of the light samples by its world place
## (`light_grid.gdshaderinc`): whole cells (hard steps, never blurred), then cut into the light's
## bands as before.
##
## - **The views:** a grid a view (`fit`: up to VIEWS_MOST world boxes), its first cell's corner on a
##   multiple of the cell (the world's grid: the light does not swim as the camera moves), laid side by
##   side in one picture (the atlas): view k's cells from `view_at[k]`, `view_size[k]` of them. The
##   atlas's room only grows (`texture` made again then), so a frame makes nothing.
## - **A frame:** `clear`, then `add_rows` for each batch of rows and `add_beam` for each beam, then
##   `bake` writes the bytes and hands them to the texture. Each light adds its colour times
##   (1 - its distance from its middle as a share of its reach)² at every cell whose middle it reaches
##   (its reach at least a cell each way, so no light falls between the cells' middles)
##   (the GPU light's falloff, its ellipse along its way), blocked as the shader blocks it
##   (`LightBlockers.shade_between`, the boxes near it only); the cells add up and are cut at 1.
## - **Native:** while the module is loaded, `add_rows`, `add_beam` and `bake` run in `MoteKernel`
##   (`light_grid_rows`, `light_grid_beam`, `light_grid_bake`), on this object's arrays in place, to
##   the bit as here (tests/gameplay/feel/test_light_grid.gd compares them byte for byte). Here is the
##   reference and the fallback.
## - **The colours** are the shader's: a shot's, rune's, flash's or cue's glow from its row's colour
##   and core (`glow_of`: `shot_look.gdshaderinc`'s `look_from_color(...).glow`, its palette's
##   infusions read from the infusion table, `use_tints`), a spot's its own colour.
## - **Quality** (for a later setting): the cell (`cell`, from CELL; a coarser grid is fewer cells) and
##   how many lights of each kind (`most_rows`) are this object's numbers, set by the light.
##
## View only: nothing here touches the simulation.

const LightBlockersScript := preload("res://gameplay/feel/light_blockers.gd")
const NativeScript := preload("res://core/native/native.gd")

## The cell's size (world px each way) by default.
const CELL: float = 8.0
## The cell sizes a quality setting may pick from (no finer than 4).
const CELLS: PackedFloat32Array = [8.0, 12.0, 16.0]
## The most views a grid each (ScreenViews.VIEWS_MOST).
const VIEWS_MOST: int = 4
## The most cells a view's grid may have each way (a view zoomed out past this is cut at its right and
## bottom).
const VIEW_CELLS_MOST: int = 512
## Floats a light row holds (SpellLight.STRIDE: a 2D transform, a colour, custom data).
const STRIDE: int = 16
## How the rows of `add_rows` read (SpellLight.ROWS_*; the GPU light's once).
const ROWS_SHOT: int = 0
const ROWS_RUNE: int = 1
const ROWS_FLASH: int = 2
const ROWS_SPOT: int = 3
const ROWS_CUE: int = 4
## The GPU light's numbers (light.gdshader's, before grid lighting).
const SHOT_STRENGTH: float = 0.9
const RUNE_STRENGTH: float = 0.55
const SHOT_REACH: float = 26.0
const SHOT_REACH_ZOOM: float = 6.0
const SPECK_REACH: float = 14.0
const RUNE_REACH: float = 1.5
const FLASH_FROM: float = 0.02
const FLASH_SPAN: float = 0.42
const SPOT_RATE: float = 7.0
const HF_LIVE: float = 1.0
## shot_palette.gdshaderinc's: the players' ramps (light, base) and the enemies' (the fifth), the
## palette materials' shades (shadow, base, light), and the look bits.
const P_BASE: PackedFloat64Array = [0.231, 0.451, 0.788, 0.851, 0.278, 0.478, 0.247, 0.561, 0.310, 0.541, 0.310, 0.769, 0.651, 0.541, 0.165]
const P_LIGHT: PackedFloat64Array = [0.498, 0.753, 0.941, 0.961, 0.604, 0.722, 0.561, 0.831, 0.416, 0.788, 0.604, 0.941, 0.890, 0.812, 0.420]
const MATERIALS: int = 7
const SHADES: PackedFloat64Array = [
	0.561, 0.176, 0.165, 0.878, 0.349, 0.184, 1.0, 0.635, 0.235,
	0.722, 0.502, 0.122, 0.949, 0.761, 0.188, 1.0, 0.953, 0.651,
	0.122, 0.439, 0.502, 0.310, 0.839, 0.863, 0.769, 0.965, 0.949,
	0.290, 0.078, 0.314, 0.627, 0.188, 0.604, 0.878, 0.541, 0.847,
	0.247, 0.420, 0.063, 0.706, 0.910, 0.165, 0.933, 1.0, 0.651,
	0.639, 0.624, 0.722, 0.831, 0.816, 0.878, 0.957, 0.945, 0.918,
	0.059, 0.290, 0.267, 0.118, 0.612, 0.549, 0.435, 0.863, 0.753,
]
const ENEMY_PLAYER: int = 4
const KIND_COUNT: int = 22
const ENEMY_RAMP: int = 23
const EXACT: int = 24
const PALETTE_MOST: int = 4
## The most boxes that block light (LightBlockers.MAX; the kernel's checked against it).
const BLOCKERS_MOST: int = LightBlockersScript.MAX
## The infusion table's mark (InfusionTable.MARK): a tint whose alpha is near it is an infusion's.
const INFUSION_MARK: float = 128.0 / 255.0

## The cell (world px each way). Read only (`set_cell`).
var cell: float = CELL
## How many views have a grid, each one's first cell's corner (world px: x, y), its cells (columns,
## rows) and where they start in the atlas (x, y). Read only.
var view_count: int = 0
var view_origin: PackedFloat64Array = PackedFloat64Array()
var view_size: PackedInt32Array = PackedInt32Array()
var view_at: PackedInt32Array = PackedInt32Array()
## The atlas's room (cells each way; it only grows). Read only.
var atlas_width: int = 1
var atlas_height: int = 1
## The light at every cell of the atlas this frame (r, g, b), and the bytes handed to the texture
## (r, g, b, 255 a cell; two buffers written in turn, `bytes` this frame's, so the one the texture's
## picture still holds is never written: no copy a frame). Read only.
var rgb: PackedFloat32Array = PackedFloat32Array()
var bytes: PackedByteArray = PackedByteArray()
var _bytes_other: PackedByteArray = PackedByteArray()
## The boxes that block light (`set_blockers`, LightBlockers' lists) and how many. Read only.
var blocker_boxes: PackedVector4Array = PackedVector4Array()
var blocker_bodies: PackedVector4Array = PackedVector4Array()
var blocker_count: int = 0
## The infusion table (InfusionTable's, `use_tints`; every layer none until handed). Read only.
var tints: PackedColorArray = PackedColorArray()
## The atlas as a texture (made again only when the atlas grows). Read only.
var texture: ImageTexture = null
## The kernel these calls run in (null: here). Read only.
var kernel: Object = null
var _image: Image = null


func _init() -> void:
	view_origin.resize(VIEWS_MOST * 2)
	view_size.resize(VIEWS_MOST * 2)
	view_at.resize(VIEWS_MOST * 2)
	tints.resize(32)
	_grow(1, 1)


## `add_rows`, `add_beam` and `bake` run in the native module from now on while `on` and it is loaded
## (its numbers and this object's members checked first: a mismatch is an error and the GDScript
## runs), else here. Returns whether they run natively.
func use_native(on: bool) -> bool:
	kernel = NativeScript.mote_kernel() if on else null
	if kernel != null:
		var wrong: PackedStringArray = kernel.call(&"check_light_grid", self)
		if not wrong.is_empty():
			push_error("LightGrid: the native kernel does not match: %s" % ", ".join(wrong))
			kernel = null
	return kernel != null


## The cell (world px each way; at least 4).
func set_cell(size: float) -> void:
	cell = maxf(size, 4.0)


## The infusion table (InfusionTable.of_registry or `published`: a tint a look layer, alpha above 0
## for one) the colours' palettes read, as the shaders read it: each tint a byte a channel with alpha
## INFUSION_MARK (InfusionTable.texture), every other layer none.
func use_tints(table: PackedColorArray) -> void:
	for layer in tints.size():
		var tint: Color = table[layer] if layer < table.size() else Color(0, 0, 0, 0)
		if tint.a > 0.0:
			tints[layer] = Color(roundf(tint.r * 255.0) / 255.0, roundf(tint.g * 255.0) / 255.0, roundf(tint.b * 255.0) / 255.0, INFUSION_MARK)
		else:
			tints[layer] = Color(0, 0, 0, 0)


## The boxes that block light (LightBlockers' `boxes` and `bodies`, `count` of them).
func set_blockers(boxes: PackedVector4Array, bodies: PackedVector4Array, count: int) -> void:
	blocker_boxes = boxes
	blocker_bodies = bodies
	blocker_count = clampi(count, 0, mini(BLOCKERS_MOST, mini(boxes.size(), bodies.size())))


## A grid for each of the first `count` world boxes of `boxes` (x0, y0, x1, y1; the views' parts of the
## world): its cells cover the box, its first cell's corner on the world's grid of `cell`.
func fit(boxes: PackedVector4Array, count: int) -> void:
	view_count = clampi(count, 0, mini(VIEWS_MOST, boxes.size()))
	var across: int = 0
	var down: int = 1
	for k in view_count:
		var box: Vector4 = boxes[k]
		var x0: float = floorf(box.x / cell) * cell
		var y0: float = floorf(box.y / cell) * cell
		var columns: int = clampi(ceili((box.z - x0) / cell), 1, VIEW_CELLS_MOST)
		var lines: int = clampi(ceili((box.w - y0) / cell), 1, VIEW_CELLS_MOST)
		view_origin[k * 2] = x0
		view_origin[k * 2 + 1] = y0
		view_size[k * 2] = columns
		view_size[k * 2 + 1] = lines
		view_at[k * 2] = across
		view_at[k * 2 + 1] = 0
		across += columns
		down = maxi(down, lines)
	if across > atlas_width or down > atlas_height:
		_grow(maxi(across, atlas_width), maxi(down, atlas_height))


## Every cell dark again (the frame's start).
func clear() -> void:
	rgb.fill(0.0)


## The light of the first `count` rows of `rows` (STRIDE floats each), read as `kind` says (ROWS_*):
## `reach` and `pad` a flash's (the GPU light's `flash_reach`, `flash_pad`), `now` the clock a spot's
## flicker steps by, and `blocked` whether the boxes stop it (SpellLight.SHOTS_BLOCKED for shots and
## runes).
func add_rows(rows: PackedFloat32Array, count: int, kind: int, reach: float, pad: float, now: float, blocked: bool) -> void:
	count = mini(count, rows.size() / STRIDE)
	if count <= 0 or view_count == 0:
		return
	if kernel != null:
		kernel.call(&"light_grid_rows", self, rows, count, kind, reach, pad, now, blocked)
		return
	for i in count:
		var at: int = i * STRIDE
		_row(rows, at, kind, reach, pad, now, blocked)


## A live beam's light along the first `points` points of `path` (world x, y; z unused), `beam_reach`
## px each side, in `colour` (its glow times its strength and fade: SpellLight works it out).
func add_beam(path: PackedVector3Array, points: int, beam_reach: float, colour: Color) -> void:
	points = mini(points, path.size())
	if points < 2 or view_count == 0 or beam_reach <= 0.0:
		return
	# At least a cell each side, as every light (`_lamp`).
	beam_reach = maxf(beam_reach, cell)
	if kernel != null:
		kernel.call(&"light_grid_beam", self, path, points, beam_reach, colour)
		return
	var r: float = colour.r
	var g: float = colour.g
	var b: float = colour.b
	if r * r + g * g + b * b <= 0.0:
		return
	for k in points - 1:
		var ax: float = path[k].x
		var ay: float = path[k].y
		var dx: float = path[k + 1].x - ax
		var dy: float = path[k + 1].y - ay
		var length: float = sqrt(dx * dx + dy * dy)
		var wx: float = dx / length if length > 0.0 else 1.0
		var wy: float = dy / length if length > 0.0 else 0.0
		var first: bool = k == 0
		var last: bool = k == points - 2
		var from_x: float = -beam_reach if first else 0.0
		var to_x: float = length + beam_reach if last else length
		# The piece's box in the world: its two ends grown by the reach.
		var low_x: float = minf(ax, ax + dx) - beam_reach
		var low_y: float = minf(ay, ay + dy) - beam_reach
		var high_x: float = maxf(ax, ax + dx) + beam_reach
		var high_y: float = maxf(ay, ay + dy) + beam_reach
		for view in view_count:
			var c0: int = 0
			var c1: int = 0
			var l0: int = 0
			var l1: int = 0
			var ox: float = view_origin[view * 2]
			var oy: float = view_origin[view * 2 + 1]
			c0 = maxi(floori((low_x - ox) / cell), 0)
			l0 = maxi(floori((low_y - oy) / cell), 0)
			c1 = mini(floori((high_x - ox) / cell), view_size[view * 2] - 1)
			l1 = mini(floori((high_y - oy) / cell), view_size[view * 2 + 1] - 1)
			for line in range(l0, l1 + 1):
				var py: float = oy + (float(line) + 0.5) * cell
				for column in range(c0, c1 + 1):
					var px: float = ox + (float(column) + 0.5) * cell
					var qx: float = px - ax
					var qy: float = py - ay
					var x: float = qx * wx + qy * wy
					var y: float = (-qx * wy + qy * wx) / beam_reach
					if x < from_x or x > to_x or y < -1.0 or y > 1.0:
						continue
					var past: float = 0.0
					if x < 0.0 and first:
						past = -x / beam_reach
					elif x > length and last:
						past = (x - length) / beam_reach
					var f: float = clampf(1.0 - sqrt(past * past + y * y), 0.0, 1.0)
					if f <= 0.0:
						continue
					var cell_at: int = ((view_at[view * 2 + 1] + line) * atlas_width + view_at[view * 2] + column) * 3
					var lit: float = f * f
					rgb[cell_at] += r * lit
					rgb[cell_at + 1] += g * lit
					rgb[cell_at + 2] += b * lit


## The frame's light into the texture: each cell's colour cut at 1, a byte a channel.
func bake() -> void:
	if kernel != null:
		kernel.call(&"light_grid_bake", self)
	else:
		var cells: int = atlas_width * atlas_height
		for c in cells:
			bytes[c * 4] = int(minf(rgb[c * 3], 1.0) * 255.0 + 0.5)
			bytes[c * 4 + 1] = int(minf(rgb[c * 3 + 1], 1.0) * 255.0 + 0.5)
			bytes[c * 4 + 2] = int(minf(rgb[c * 3 + 2], 1.0) * 255.0 + 0.5)
	_image.set_data(atlas_width, atlas_height, false, Image.FORMAT_RGBA8, bytes)
	texture.update(_image)
	# The picture holds this frame's bytes now (and lets go of last frame's): the next frame writes
	# the other buffer.
	var held: PackedByteArray = bytes
	bytes = _bytes_other
	_bytes_other = held


## The bytes the last `bake` wrote and handed to the texture (for tests).
func baked() -> PackedByteArray:
	return _bytes_other


## The light at world point `at` in view `view` this frame (r, g, b; for tests).
func light_at(view: int, at: Vector2) -> Color:
	if view < 0 or view >= view_count:
		return Color.BLACK
	var column: int = floori((at.x - view_origin[view * 2]) / cell)
	var line: int = floori((at.y - view_origin[view * 2 + 1]) / cell)
	if column < 0 or line < 0 or column >= view_size[view * 2] or line >= view_size[view * 2 + 1]:
		return Color.BLACK
	var c: int = ((view_at[view * 2 + 1] + line) * atlas_width + view_at[view * 2] + column) * 3
	return Color(rgb[c], rgb[c + 1], rgb[c + 2])


## The atlas's room made `width` by `height` cells (cleared), and its texture made again.
func _grow(width: int, height: int) -> void:
	atlas_width = width
	atlas_height = height
	rgb.resize(width * height * 3)
	rgb.fill(0.0)
	bytes = PackedByteArray()
	bytes.resize(width * height * 4)
	bytes.fill(255)
	for c in width * height:
		bytes[c * 4] = 0
		bytes[c * 4 + 1] = 0
		bytes[c * 4 + 2] = 0
	_bytes_other = bytes.duplicate()
	_image = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, _bytes_other)
	texture = ImageTexture.create_from_image(_image)


# --- One row (the GPU light's vertex stage, then its fragment stage at each cell) ------------------

func _row(rows: PackedFloat32Array, at: int, kind: int, reach: float, pad: float, now: float, blocked: bool) -> void:
	var cx: float = rows[at + 3]
	var cy: float = rows[at + 7]
	var hx: float = 0.0
	var hy: float = 0.0
	var wx: float = 1.0
	var wy: float = 0.0
	var r: float = 0.0
	var g: float = 0.0
	var b: float = 0.0
	var gx: float = 0.0
	var gy: float = 0.0
	if kind == ROWS_RUNE:
		var half: float = sqrt(rows[at] * rows[at] + rows[at + 4] * rows[at + 4]) * 0.5 * RUNE_REACH * rows[at + 2]
		hx = half
		hy = half
		var glow: Vector3 = glow_of(rows, at, false)
		var k: float = RUNE_STRENGTH * rows[at + 6]
		r = glow.x * k
		g = glow.y * k
		b = glow.z * k
	elif kind == ROWS_FLASH:
		var through: float = clampf((_coded_code(rows[at + 15]) - FLASH_FROM) / FLASH_SPAN, 0.0, 1.0)
		var strength: float = rows[at + 6] * (1.0 - through)
		if strength > 0.0:
			var ax: float = rows[at]
			var ay: float = rows[at + 4]
			var along: float = sqrt(ax * ax + ay * ay)
			if along > 0.0:
				wx = ax / along
				wy = ay / along
			hx = along * 0.5 * reach + pad
			hy = sqrt(rows[at + 1] * rows[at + 1] + rows[at + 5] * rows[at + 5]) * 0.5 * reach + pad
			var glow: Vector3 = glow_of(rows, at, false)
			r = glow.x * strength
			g = glow.y * strength
			b = glow.z * strength
	elif kind == ROWS_CUE:
		var half: float = sqrt(rows[at] * rows[at] + rows[at + 4] * rows[at + 4])
		hx = half
		hy = half
		var glow: Vector3 = glow_of(rows, at, false)
		var bright: float = rows[at + 15]
		r = glow.x * bright
		g = glow.y * bright
		b = glow.z * bright
	elif kind == ROWS_SPOT:
		var half: float = sqrt(rows[at] * rows[at] + rows[at + 4] * rows[at + 4])
		var step_of: float = floorf(now * SPOT_RATE + rows[at + 13] * 13.0)
		var wave: float = sin(step_of * 12.9898 + rows[at + 13] * 78.233) * 43758.5453
		var dip: float = rows[at + 12] * (wave - floorf(wave))
		hx = half
		hy = half
		var k: float = rows[at + 11] * (1.0 - dip)
		r = rows[at + 8] * k
		g = rows[at + 9] * k
		b = rows[at + 10] * k
		gx = rows[at + 14]
		gy = rows[at + 15]
	else:
		if _flag_set(rows[at + 5], HF_LIVE):
			var red: float = floorf(rows[at + 8] * 255.0 + 0.5)
			var shot_reach: float = SPECK_REACH if red < 4.0 else SHOT_REACH + SHOT_REACH_ZOOM * maxf(floorf(red / 4.0), 1.0)
			hx = shot_reach * rows[at + 2]
			hy = hx
			var glow: Vector3 = glow_of(rows, at, false)
			var k: float = SHOT_STRENGTH * rows[at + 6]
			r = glow.x * k
			g = glow.y * k
			b = glow.z * k
	if hx <= 0.0 or r * r + g * g + b * b <= 0.0:
		return
	_lamp(cx, cy, hx, hy, wx, wy, r, g, b, gx, gy, kind == ROWS_SPOT, blocked)


## One light: its middle (cx, cy), half sizes along its way and across, its way, its colour, where a
## spot stands from its middle (gx, gy) and whether the boxes stop it.
func _lamp(cx: float, cy: float, hx: float, hy: float, wx: float, wy: float, r: float, g: float, b: float, gx: float, gy: float, spot: bool, blocked: bool) -> void:
	# Every light reaches at least a cell each way (the owner, 2026-11-21): one smaller than that could
	# fall between the cells' middles and blink as it moves.
	hx = maxf(hx, cell)
	hy = maxf(hy, cell)
	var near: int = 0
	var lx: float = cx
	var ly: float = cy
	if blocked and blocker_count > 0:
		if spot:
			lx = cx + gx
			ly = cy + gy
		else:
			var lit: Vector2 = LightBlockersScript.lit_as(Vector2(cx, cy), blocker_boxes, blocker_bodies, blocker_count)
			lx = lit.x
			ly = lit.y
		var half: float = sqrt(hx * hx + hy * hy)
		var lit_x0: float = minf(cx - half, lx)
		var lit_y0: float = minf(cy - half, ly)
		var lit_x1: float = maxf(cx + half, lx)
		var lit_y1: float = maxf(cy + half, ly)
		for k in blocker_count:
			var box: Vector4 = blocker_boxes[k]
			var body: Vector4 = blocker_bodies[k]
			if body.w > 0.0 and minf(box.x, body.x) <= lit_x1 and maxf(box.z, body.z) >= lit_x0 and minf(box.y, body.y) <= lit_y1 and box.w >= lit_y0:
				near |= 1 << k
	var big: float = maxf(hx, hy)
	for view in view_count:
		var ox: float = view_origin[view * 2]
		var oy: float = view_origin[view * 2 + 1]
		var c0: int = maxi(floori((cx - big - ox) / cell), 0)
		var l0: int = maxi(floori((cy - big - oy) / cell), 0)
		var c1: int = mini(floori((cx + big - ox) / cell), view_size[view * 2] - 1)
		var l1: int = mini(floori((cy + big - oy) / cell), view_size[view * 2 + 1] - 1)
		for line in range(l0, l1 + 1):
			var py: float = oy + (float(line) + 0.5) * cell
			var dy: float = py - cy
			for column in range(c0, c1 + 1):
				var px: float = ox + (float(column) + 0.5) * cell
				var dx: float = px - cx
				var sx: float = (dx * wx + dy * wy) / hx
				var sy: float = (-dx * wy + dy * wx) / hy
				var f: float = 1.0 - sqrt(sx * sx + sy * sy)
				if f <= 0.0:
					continue
				var open: float = 1.0
				if near != 0:
					open = 1.0 - LightBlockersScript.shade_between(Vector2(px, py), Vector2(lx, ly), blocker_boxes, blocker_bodies, blocker_count, false, near)
				var lit: float = f * f * open
				var c: int = ((view_at[view * 2 + 1] + line) * atlas_width + view_at[view * 2] + column) * 3
				rgb[c] += r * lit
				rgb[c + 1] += g * lit
				rgb[c + 2] += b * lit


# --- The colours (shot_look.gdshaderinc's look_from_color(...).glow) ------------------------------

## The glow of the row at `at` of `rows` (its colour at +8, its core at +12): `look_from_color`'s
## glow; with `own_infusions` the first material's alone (a beam's, LOOK_OWN_INFUSIONS).
func glow_of(rows: PackedFloat32Array, at: int, own_infusions: bool) -> Vector3:
	var red: float = floorf(rows[at + 8] * 255.0 + 0.5)
	var who: int = int(fmod(red, 4.0))
	var b0: int = int(floorf(rows[at + 9] * 255.0 + 0.5))
	var b1: int = int(floorf(rows[at + 10] * 255.0 + 0.5))
	var b2: int = int(floorf(rows[at + 11] * 255.0 + 0.5))
	return look_glow(rows[at + 12], rows[at + 13], rows[at + 14], who, b0, b1, b2, own_infusions)


## A look's glow: core colour (cr, cg, cb), player ramp `who` (0-3), look bits in three bytes.
func look_glow(cr: float, cg: float, cb: float, who: int, b0: int, b1: int, b2: int, own_infusions: bool) -> Vector3:
	var player: int = ENEMY_PLAYER if _bit_set(b0, b1, b2, ENEMY_RAMP) else who
	var mid := Vector3.ZERO
	var hi := Vector3.ZERO
	var first: int = -1
	var plain: bool = cr > 0.99 and cg > 0.99 and cb > 0.99
	if _bit_set(b0, b1, b2, EXACT):
		mid = Vector3(cr, cg, cb)
		hi = Vector3(cr + (1.0 - cr) * 0.35, cg + (1.0 - cg) * 0.35, cb + (1.0 - cb) * 0.35)
	elif plain:
		hi = Vector3(P_LIGHT[player * 3], P_LIGHT[player * 3 + 1], P_LIGHT[player * 3 + 2])
		mid = Vector3(P_BASE[player * 3], P_BASE[player * 3 + 1], P_BASE[player * 3 + 2])
	else:
		first = material_of(cr, cg, cb)
		mid = _shade(first, 1)
		hi = _shade(first, 2)
	var glow: Vector3 = _mix(mid, hi, 0.35)
	if first >= 0 and not own_infusions:
		# The palette's materials (shot_look's `palette_of`), the first the core's: four locals, no array.
		var m1: int = -1
		var m2: int = -1
		var count: int = 1
		for layer in range(1, KIND_COUNT + 1):
			if count < PALETTE_MOST and _bit_set(b0, b1, b2, layer):
				var t: Color = tints[layer] if layer < tints.size() else Color(0, 0, 0, 0)
				var m: int = first
				if absf(t.a - INFUSION_MARK) < 0.1:
					m = material_of(t.r, t.g, t.b)
				if m != first and m != m1 and m != m2:
					if count == 1:
						m1 = m
					elif count == 2:
						m2 = m
					count += 1
		if count > 1:
			var glows: int = m2 if count > 2 else m1
			glow = _mix(_shade(glows, 1), _shade(glows, 2), 0.35)
	return glow


## The palette material nearest `c` (shot_look.gdshaderinc's `material_of`: the first of the nearest).
static func material_of(r: float, g: float, b: float) -> int:
	var best: int = 0
	var nearest: float = 9.0
	for i in MATERIALS * 3:
		var dr: float = r - SHADES[i * 3]
		var dg: float = g - SHADES[i * 3 + 1]
		var db: float = b - SHADES[i * 3 + 2]
		var d: float = sqrt(dr * dr + dg * dg + db * db)
		if d < nearest:
			nearest = d
			best = i / 3
	return best


static func _shade(m: int, shade: int) -> Vector3:
	var i: int = (m * 3 + shade) * 3
	return Vector3(SHADES[i], SHADES[i + 1], SHADES[i + 2])


## `a` toward `b` by `t` (GLSL's mix), a channel at a time in doubles, kept as a Vector3.
static func _mix(a: Vector3, b: Vector3, t: float) -> Vector3:
	return Vector3(float(a.x) + (float(b.x) - float(a.x)) * t, float(a.y) + (float(b.y) - float(a.y)) * t, float(a.z) + (float(b.z) - float(a.z)) * t)


## Whether look bit `look` (1 to 24) is set in the three bytes.
static func _bit_set(b0: int, b1: int, b2: int, look: int) -> bool:
	var bit: int = look - 1
	var byte: int = b0 if bit < 8 else (b1 if bit < 16 else b2)
	return (byte >> (bit % 8)) & 1 == 1


static func _flag_set(flags: float, f: float) -> bool:
	return fmod(floorf(flags / f + 0.001), 2.0) > 0.5


static func _coded_code(custom_a: float) -> float:
	var coded: float = (1.0 - custom_a) * 16.0
	return coded - floorf(coded + 0.5)
