extends Sprite2D
## A flat cover kind's look in one room (the floor's first slice, docs/milestones/floor.md; its look,
## docs/milestones/floor-look.md): one sprite over the room's cover grid, drawn by
## `cover_flat.gdshader` from a texture of a texel a cell (red: the state the cell shows; green: when
## it began to show it, Feel's clock; blue: the state it showed before, for the mark a state leaves;
## alpha: which of its 8 neighbours are drawn, NEIGHBOURS' bits, so the shader reads one texel a
## pixel but at a shape's inner bends).
## Feel's `cover.gd` makes one for each kind of `CoverKind.Look.FLAT` a room has (`lay`), tells it each
## cell's change (`show_cell`) and hands its picture over once a frame when one changed (`hand`). Its
## states' looks (`CoverState.flat_*`, the palette's shades) are the shader's uniforms, set once.
##
## A puddle grows and shrinks as one shape (the owner, 2026-11-26): a second texture, `depths`, holds
## each growing or shrinking cell's distance from its motion's edge (in cells, at its middle: red) and
## its motion's most (green), worked out here as the motion begins and held until it ends
## (`_work_depths`), and the shader moves the state's front through it.
##
## Its states' glow (`CoverState.flat_glow`) is written as the floor's lights each frame
## (`write_lights`, `cover_lights.gd`), and the shader reads the spell light (`light_views.gdshaderinc`:
## Feel hands its material to the light as a reader, `light_key`), so ice catches it.
##
## Pure view: nothing here is the game's, and nothing here is read by the simulation. Allocates
## nothing a frame once laid.

const SHADER: Shader = preload("res://gameplay/feel/cover_flat.gdshader")
const CoverLightsScript := preload("res://gameplay/feel/cover_lights.gd")
## The most states a flat kind's look holds (the shader's STATES).
const STATES: int = 16
## Art pixels a world pixel of the look (ArtDetail, core/display/art_detail.gd): the shader works its
## shapes out at this detail, 64 px a 32-unit cell (the floor's look, ART0's 2x detail).
const DETAIL: int = ArtDetail.DETAIL
## The chamfer distance's corner step and the start of a drawn cell's distance.
const SQRT2: float = 1.41421356
const FAR: float = 1.0e6
## A neighbour's offset by its bit in a cell's mask (the shader's NB_*): left, right, up, down, then
## up-left, up-right, down-left, down-right.
const NEIGHBOURS: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]

## The kind drawn and its index + 1 in the layout's cells.
var kind: CoverKind = null
var mark: int = 0
var _cells: Image = null
var _upload: TextureUpload = TextureUpload.new()
var _dirty: bool = false
var _columns: int = 0
## Each cell's state shown, the one before and when it began (Feel's clock), as in the picture.
var _state: PackedInt32Array = PackedInt32Array()
var _was: PackedInt32Array = PackedInt32Array()
var _since: PackedFloat32Array = PackedFloat32Array()
## Each cell's drawn neighbours (NEIGHBOURS' bits), and whether each state is drawn.
var _mask: PackedInt32Array = PackedInt32Array()
var _drawn: PackedByteArray = PackedByteArray()
var _rows: int = 0
## The puddles' distances (`depths`), their picture and whether a change of what is drawn wants them
## worked out again at the next `hand`; the work's lists, made once a lay.
var _depths: Image = null
var _depths_upload: TextureUpload = TextureUpload.new()
var _depths_texture: ImageTexture = null
var _shape_dirty: bool = false
var _depth: PackedFloat32Array = PackedFloat32Array()
var _stack: PackedInt32Array = PackedInt32Array()
var _seen: PackedByteArray = PackedByteArray()
## The cells whose state changed since the depths were last worked out, and which states grow or shrink.
var _fresh: PackedByteArray = PackedByteArray()
var _moving: PackedByteArray = PackedByteArray()
## Each state's glow (0: none) and its colour, from its kind's data.
var _glow: PackedFloat32Array = PackedFloat32Array()
var _glow_colour: PackedColorArray = PackedColorArray()
## The cells whose glow is on or easing out (each once: `_glowing_at` its place, -1 none).
var _glowing: PackedInt32Array = PackedInt32Array()
var _glowing_at: PackedInt32Array = PackedInt32Array()
## A frame's patches (`write_lights`): each patch's row being summed (-1 none) and its sums, made once.
var _patch_of: PackedInt32Array = PackedInt32Array()
var _patch_columns: int = 0
var _slot_patch: PackedInt32Array = PackedInt32Array()
var _patch_sum: PackedVector4Array = PackedVector4Array()
var _patch_colour: PackedColorArray = PackedColorArray()


## Lays kind `kind_index` of `laid` at rest, its cells shown since `now`.
func lay(laid: CoverLayout, kind_index: int, now: float) -> void:
	kind = laid.kinds[kind_index]
	mark = kind_index + 1
	centered = false
	position = laid.origin
	scale = Vector2(CoverLayout.CELL, CoverLayout.CELL)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_columns = maxi(laid.columns, 1)
	var rows: int = maxi(laid.rows, 1)
	_rows = rows
	_cells = Image.create_empty(_columns, rows, false, Image.FORMAT_RGBAF)
	_cells.fill(Color(0.0, now, 0.0, 0.0))
	texture = _upload.hand(_cells)
	_dirty = false
	var cells: int = _columns * rows
	_state.resize(cells)
	_state.fill(0)
	_was.resize(cells)
	_was.fill(0)
	_since.resize(cells)
	_since.fill(now)
	_mask.resize(cells)
	_mask.fill(0)
	_depth.resize(cells)
	_stack.resize(cells)
	_seen.resize(cells)
	_fresh.resize(cells)
	_fresh.fill(0)
	_depths = Image.create_empty(_columns, rows, false, Image.FORMAT_RGF)
	_glowing.resize(0)
	_glowing_at.resize(cells)
	_glowing_at.fill(-1)
	_patch_columns = (_columns + CoverLightsScript.PATCH - 1) / CoverLightsScript.PATCH
	var patches: int = _patch_columns * ((rows + CoverLightsScript.PATCH - 1) / CoverLightsScript.PATCH)
	_patch_of.resize(patches)
	_patch_of.fill(-1)
	_slot_patch.resize(CoverLightsScript.MOST)
	_patch_sum.resize(CoverLightsScript.MOST)
	_patch_colour.resize(CoverLightsScript.MOST)
	var made := ShaderMaterial.new()
	made.shader = SHADER
	_set_looks(made)
	if _glow_of(0) > 0.0:
		# A kind whose rest glows: every cell lights from the start.
		for cell in cells:
			_glowing_at[cell] = _glowing.size()
			_glowing.append(cell)
	if _is_drawn(0):
		# Every cell at rest is drawn: each one's neighbours inside the grid are.
		for cell in cells:
			_mask[cell] = _mask_of(cell)
			_write(cell)
	made.set_shader_parameter(&"cells", texture)
	_work_depths()
	_shape_dirty = false
	_depths_texture = _depths_upload.hand(_depths)
	made.set_shader_parameter(&"depths", _depths_texture)
	made.set_shader_parameter(&"art_detail", DETAIL)
	made.set_shader_parameter(&"room_origin", laid.origin)
	material = made


## The uniforms of the kind's states' looks (the shader's arrays, STATES long), and their glow.
func _set_looks(made: ShaderMaterial) -> void:
	var fills := PackedColorArray()
	var edges := PackedColorArray()
	var glints := PackedColorArray()
	var unders := PackedColorArray()
	var under_edges := PackedColorArray()
	var under_lights := PackedColorArray()
	var sparks := PackedColorArray()
	var motions := PackedColorArray()
	var surfaces := PackedColorArray()
	var traces := PackedColorArray()
	for list: PackedColorArray in [fills, edges, glints, unders, under_edges, under_lights, sparks, motions, surfaces, traces]:
		list.resize(STATES)
		list.fill(Color(0.0, 0.0, 0.0, 0.0))
	_glow.resize(STATES)
	_glow.fill(0.0)
	_glow_colour.resize(STATES)
	_glow_colour.fill(Color.BLACK)
	_drawn.resize(STATES)
	_drawn.fill(0)
	_moving.resize(STATES)
	_moving.fill(0)
	for at in mini(kind.states.size(), STATES):
		var state: CoverState = kind.states[at]
		if state == null:
			continue
		if state.flat_trace != &"" and Palette.has(state.flat_trace):
			traces[at] = Palette.shades_of(state.flat_trace)[0]
		surfaces[at] = Color(float(state.flat_surface), state.flat_trace_seconds, 0.0, 0.0)
		if state.flat_glow != &"" and Palette.has(state.flat_glow) and state.flat_glow_strength > 0.0:
			_glow[at] = state.flat_glow_strength
			_glow_colour[at] = Palette.shades_of(state.flat_glow)[2]
		if state.flat_material == &"" or not Palette.has(state.flat_material):
			continue
		var shades: PackedColorArray = Palette.shades_of(state.flat_material)
		_drawn[at] = 1
		if state.flat_motion == CoverState.FlatMotion.GROW or state.flat_motion == CoverState.FlatMotion.SHRINK or state.flat_motion == CoverState.FlatMotion.GROW_IN:
			_moving[at] = 1
		edges[at] = shades[0]
		fills[at] = shades[1]
		glints[at] = shades[2]
		if state.flat_under != &"" and Palette.has(state.flat_under):
			var under: PackedColorArray = Palette.shades_of(state.flat_under)
			under_edges[at] = under[0]
			unders[at] = under[1]
			under_lights[at] = under[2]
		if state.flat_spark != &"" and Palette.has(state.flat_spark):
			sparks[at] = Palette.shades_of(state.flat_spark)[2]
		motions[at] = Color(float(state.flat_motion), float(state.animation_frames), float(state.animation_fps), 1.0 if state.animation_loops else 0.0)
	made.set_shader_parameter(&"fills", fills)
	made.set_shader_parameter(&"edges", edges)
	made.set_shader_parameter(&"glints", glints)
	made.set_shader_parameter(&"unders", unders)
	made.set_shader_parameter(&"under_edges", under_edges)
	made.set_shader_parameter(&"under_lights", under_lights)
	made.set_shader_parameter(&"sparks", sparks)
	made.set_shader_parameter(&"motions", motions)
	made.set_shader_parameter(&"surfaces", surfaces)
	made.set_shader_parameter(&"traces", traces)


## The animated detail (ripples, twinkles, wisps) played (on) or held still (the effects' Low row).
func set_shimmer(on: bool) -> void:
	if material != null:
		(material as ShaderMaterial).set_shader_parameter(&"shimmer", on)


## Cell `cell` (of `columns` a row) shows `state` from `now` on.
func show_cell(cell: int, columns: int, state: int, now: float) -> void:
	if _cells == null or columns <= 0 or cell < 0 or cell >= _state.size():
		return
	var was: int = _state[cell]
	if was == state:
		# The same look renewed (water on a wet cell): it keeps playing as it was.
		return
	_was[cell] = was
	_state[cell] = state
	_since[cell] = now
	_write(cell)
	_fresh[cell] = 1
	if _is_moving(state):
		_shape_dirty = true
	if _is_drawn(state) != _is_drawn(was):
		# Its neighbours' masks change with it.
		var x: int = cell % _columns
		var y: int = cell / _columns
		for bit in NEIGHBOURS.size():
			var nx: int = x + NEIGHBOURS[bit].x
			var ny: int = y + NEIGHBOURS[bit].y
			if nx >= 0 and ny >= 0 and nx < _columns and ny < _rows:
				var other: int = ny * _columns + nx
				_mask[other] = _mask_of(other)
				_write(other)
	_dirty = true
	if _glowing_at[cell] < 0 and (_glow_of(state) > 0.0 or _glow_of(was) > 0.0):
		_glowing_at[cell] = _glowing.size()
		_glowing.append(cell)


## The state cell `cell` shows (0 at rest).
func shown_cell(cell: int, columns: int) -> int:
	if _cells == null or columns <= 0 or cell < 0 or cell >= _state.size():
		return 0
	return _state[cell]


## The state cell `cell` showed before its last change (0 at rest).
func shown_before(cell: int) -> int:
	return _was[cell] if cell >= 0 and cell < _was.size() else 0


## How many cells glow or ease out now (for tests).
func glowing_count() -> int:
	return _glowing.size()


func _is_moving(state: int) -> bool:
	return state >= 0 and state < _moving.size() and _moving[state] != 0


func _is_drawn(state: int) -> bool:
	return state >= 0 and state < _drawn.size() and _drawn[state] != 0


## Which of cell `cell`'s neighbours are drawn (NEIGHBOURS' bits).
func _mask_of(cell: int) -> int:
	var x: int = cell % _columns
	var y: int = cell / _columns
	var mask: int = 0
	for bit in NEIGHBOURS.size():
		var nx: int = x + NEIGHBOURS[bit].x
		var ny: int = y + NEIGHBOURS[bit].y
		if nx >= 0 and ny >= 0 and nx < _columns and ny < _rows and _is_drawn(_state[ny * _columns + nx]):
			mask |= 1 << bit
	return mask


## Each cell that began a growing or shrinking state this frame: its distance from its motion's edge
## (cells, at its middle) and its motion's most, into `depths`. A motion is the cells joined by a side
## that began the same state at the same moment (the same Feel clock: one touch, or a lake that dries
## at once), so new water at a puddle's edge, a patch of steam in a lake or a ring that dries first is
## each its own shape. The distance is a two-pass chamfer (1 a side, SQRT2 a corner) to the nearest cell
## not of its motion (the grid's outside too), less half a cell; each motion flooded for its most, then
## again to write it. A cell's values are written once, as its motion begins, and held until it ends,
## so a change nearby never moves a front already playing. Runs only on a frame when a motion began;
## allocates nothing (its lists are made at `lay`).
func _work_depths() -> void:
	var cells: int = _state.size()
	for cell in cells:
		_depth[cell] = FAR if _is_moving(_state[cell]) else 0.0
	for y in _rows:
		for x in _columns:
			var at: int = y * _columns + x
			if _depth[at] > 0.0:
				var d: float = _depth[at]
				d = minf(d, _chamfer(at, x - 1, y, 1.0))
				d = minf(d, _chamfer(at, x, y - 1, 1.0))
				d = minf(d, _chamfer(at, x - 1, y - 1, SQRT2))
				d = minf(d, _chamfer(at, x + 1, y - 1, SQRT2))
				_depth[at] = d
	for y in range(_rows - 1, -1, -1):
		for x in range(_columns - 1, -1, -1):
			var at: int = y * _columns + x
			if _depth[at] > 0.0:
				var d: float = _depth[at]
				d = minf(d, _chamfer(at, x + 1, y, 1.0))
				d = minf(d, _chamfer(at, x, y + 1, 1.0))
				d = minf(d, _chamfer(at, x + 1, y + 1, SQRT2))
				d = minf(d, _chamfer(at, x - 1, y + 1, SQRT2))
				_depth[at] = d
	_seen.fill(0)
	for start in cells:
		if _fresh[start] == 0 or _seen[start] != 0 or _depth[start] <= 0.0:
			continue
		var most: float = _flood(start, 1, 0.0)
		_flood(start, 2, most)
	_fresh.fill(0)


## Floods the motion of cell `start` (cells joined by a side, of its state and start), marking each
## `mark` in `_seen`: mark 1 returns its most distance; mark 2 writes each cell's distance and `most`
## into `depths`.
func _flood(start: int, mark: int, most: float) -> float:
	var top: int = 1
	_stack[0] = start
	_seen[start] = mark
	var found: float = 0.0
	while top > 0:
		top -= 1
		var at: int = _stack[top]
		if mark == 1:
			found = maxf(found, _depth[at] - 0.5)
		else:
			_depths.set_pixel(at % _columns, at / _columns, Color(_depth[at] - 0.5, most, 0.0, 1.0))
		var x: int = at % _columns
		var y: int = at / _columns
		for k in 4:
			var nx: int = x + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny: int = y + (1 if k == 2 else (-1 if k == 3 else 0))
			if nx < 0 or ny < 0 or nx >= _columns or ny >= _rows:
				continue
			var next: int = ny * _columns + nx
			if _seen[next] < mark and _same_motion(at, next):
				_seen[next] = mark
				_stack[top] = next
				top += 1
	return found


## Whether cells `a` and `b` play one motion: the same growing or shrinking state, begun at the same moment.
func _same_motion(a: int, b: int) -> bool:
	return _state[a] == _state[b] and _since[a] == _since[b] and _is_moving(_state[a])


## The chamfer's distance for cell `at` through cell (`x`, `y`) at `step` more: a cell not of its
## motion, or the grid's outside, is its edge (0).
func _chamfer(at: int, x: int, y: int, step: float) -> float:
	if x < 0 or y < 0 or x >= _columns or y >= _rows:
		return step
	var other: int = y * _columns + x
	return _depth[other] + step if _same_motion(at, other) else step


## Cell `cell`'s distance from its motion's edge (cells, at its middle) and its motion's most, as the
## shader reads them (held from when its motion began; for tests).
func depth_of(cell: int) -> Vector2:
	if _depths == null or cell < 0 or cell >= _state.size():
		return Vector2(-0.5, 0.0)
	var texel: Color = _depths.get_pixel(cell % _columns, cell / _columns)
	return Vector2(texel.r, texel.g)


## Cell `cell`'s texel from its arrays.
func _write(cell: int) -> void:
	_cells.set_pixel(cell % _columns, cell / _columns, Color(float(_state[cell]), _since[cell], float(_was[cell]), float(_mask[cell])))


## Cell `cell`'s drawn neighbours (NEIGHBOURS' bits; for tests).
func neighbours_drawn(cell: int) -> int:
	return _mask[cell] if cell >= 0 and cell < _mask.size() else 0


func _glow_of(state: int) -> float:
	return _glow[state] if state >= 0 and state < _glow.size() else 0.0


## This frame's floor lights into `lights` at Feel's clock `now`: the glowing cells, a patch of
## CoverLights.PATCH cells a row, at the middle of its glowing cells, its glow its cells' over its
## share of the patch. A cell whose glow has eased out leaves the list.
func write_lights(lights: CoverLightsScript, now: float) -> void:
	var at: int = 0
	var patch_cells: float = float(CoverLightsScript.PATCH * CoverLightsScript.PATCH)
	var used: int = 0
	while at < _glowing.size():
		var cell: int = _glowing[at]
		var age: float = now - _since[cell]
		var glows: float = _glow_of(_state[cell])
		var glowed: float = _glow_of(_was[cell])
		if glows <= 0.0 and age >= CoverLightsScript.EASE_SECONDS:
			_drop_glowing(at)
			continue
		at += 1
		var share: float = CoverLightsScript.share_of(age, glows, glowed)
		if share <= 0.0:
			continue
		var column: int = cell % _columns
		var row: int = cell / _columns
		var patch: int = (row / CoverLightsScript.PATCH) * _patch_columns + column / CoverLightsScript.PATCH
		var slot: int = _patch_of[patch]
		if slot < 0:
			if used >= CoverLightsScript.MOST:
				continue
			slot = used
			used += 1
			_patch_of[patch] = slot
			_slot_patch[slot] = patch
			_patch_sum[slot] = Vector4.ZERO
			_patch_colour[slot] = Color.BLACK
		var sum: Vector4 = _patch_sum[slot]
		var middle: Vector2 = position + (Vector2(column, row) + Vector2(0.5, 0.5)) * float(CoverLayout.CELL)
		if sum.z <= 0.0 or share > sum.w / sum.z:
			_patch_colour[slot] = _glow_colour[_state[cell]] if glows > 0.0 else _glow_colour[_was[cell]]
		_patch_sum[slot] = Vector4(sum.x + middle.x, sum.y + middle.y, sum.z + 1.0, sum.w + share)
	for slot in used:
		var sum: Vector4 = _patch_sum[slot]
		# Its cells' mean glow, and half of it for a lone cell (a patch of PATCH x PATCH lit at two).
		var strength: float = sum.w / sum.z * minf(1.0, sum.z * 2.0 / patch_cells)
		if lights.has_room():
			lights.add(Vector2(sum.x, sum.y) / sum.z, strength, _patch_colour[slot])
		_patch_of[_slot_patch[slot]] = -1


func _drop_glowing(at: int) -> void:
	var cell: int = _glowing[at]
	var last: int = _glowing[_glowing.size() - 1]
	_glowing[at] = last
	_glowing_at[last] = at
	_glowing.resize(_glowing.size() - 1)
	_glowing_at[cell] = -1


## The frame's picture: the clock set, the grid handed over when a cell changed.
func hand(now: float) -> void:
	(material as ShaderMaterial).set_shader_parameter(&"view_time", now)
	if _shape_dirty:
		_shape_dirty = false
		_work_depths()
		var shaped: ImageTexture = _depths_upload.hand(_depths)
		if shaped != _depths_texture:
			_depths_texture = shaped
			(material as ShaderMaterial).set_shader_parameter(&"depths", shaped)
	if _dirty:
		_dirty = false
		var handed: ImageTexture = _upload.hand(_cells)
		if handed != texture:
			texture = handed
			(material as ShaderMaterial).set_shader_parameter(&"cells", handed)
