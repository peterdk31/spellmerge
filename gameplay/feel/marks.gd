extends Node2D
## Floor marks (docs/milestones/spell-spectacle.md, P2): the room's mark layer, a texture over the
## floor and under every body that cues stamp scorches, cracks and frost into and that is never
## cleared until the room ends. A stamp is drawn once, the frame it lands, and then costs
## nothing: a frame with no new stamps renders nothing.
##
## **The layer** is a `SubViewport` the size of the room's bounds (the projectile manager's
## `bounds()`) at one texel a world pixel, with `CLEAR_MODE_NEVER` and `UPDATE_DISABLED`; a frame
## with stamps sets `UPDATE_ONCE`, so the viewport renders that frame alone. Its texture is shown
## by one `Sprite2D` at the layer's corner, at `z` (Feel's MARK_Z: over the room's floor, which
## is at `RoomBase.FLOOR_Z`, and under the bodies at 0). Nothing is allocated while playing: the
## viewport, the sprite and the batch are made once a room (`enter`; again only when its size
## changes).
##
## **Stamps** go into a queue (`stamp`); `step`, once a frame, writes up to STAMPS_PER_FRAME of
## them into the one batch inside the viewport (made by `Batches.multimesh()`), drawn by
## `gameplay/feel/mark.gdshader`, and the rest wait for the next frame (a flood is spread over
## frames, never dropped, up to PENDING_MAX waiting; past that a stamp is left out and counted).
## The batch shows only the rows of its frame (`visible_instance_count`), so a later render
## (another frame's stamps, a clear) never draws them twice.
##
## **Kinds are data** (`MarkKind`, content/marks): their forms and numbers go to the shader as
## `kind_form` and `kind_colour`, so a new mark is a new file. **Colours are never here:** the
## floor's are the room's own art (`set_floor_colors`, from `RoomBase.floor_colors`), a spell's the
## shot's own ramp, picked in the shader as the motes pick theirs (`Motes.spell_source`).
##
## **Off the walls:** the stamp shader is clipped by the walls (`floor_mask`, one texel a wall
## cell of the projectile manager's grid, `set_walls`), built once a room.
##
## **Settled motes** (P2b): a mote of a kind that settles (`MoteKind.settles`) is handed over when
## it is thrown, with where and when it comes to rest (`settle`, from `Motes.mote_land`). It waits
## in a wheel of SETTLE_SLOTS time slots, each SETTLE_SLOT long, and is stamped once its slot is
## past (never before it lies still; up to a slot late, under the still mote). At most
## SETTLED_PER_FRAME are stamped a frame and at most SETTLE_SLOT_ROWS wait in a slot; the rest
## just fade with their motes (`settles_faded`). Their colours, and a surface's (`surface`), are
## the ramp table's that the motes use (`set_ramp_table`).

const SHADER: Shader = preload("res://gameplay/feel/mark.gdshader")
const BatchesScript := preload("res://core/projectiles/batches.gd")

## Floats in a row: the transform (8), the colour (4) and the custom data (4).
const DRAW_STRIDE: int = 16
## The most stamps drawn in one frame (the batch's rows); more wait for the next.
const STAMPS_PER_FRAME: int = 512
## The most stamps waiting at once; past that a new one is left out (`left_out`).
const PENDING_MAX: int = STAMPS_PER_FRAME * 8
## The most kinds the shader holds (its `kind_form` and `kind_colour` arrays).
const MAX_KINDS: int = 16
## What a row's colour channels are divided by (the shader's KIND_CODE and SOURCE_CODE).
const KIND_CODE: float = 16.0
const SOURCE_CODE: float = 128.0
## The biggest radius a stamp has (px); a bigger one is drawn this big.
const MAX_RADIUS: float = 160.0
## Settled motes stamped in one frame at most; the rest fade with their motes.
const SETTLED_PER_FRAME: int = 512
## The settle wheel: its slots' length (s), how many (past Motes.LIFE_MAX), the most a slot holds
## and the floats a settled mote takes (where, its kind, its source, its core colour).
const SETTLE_SLOT: float = 1.0 / 30.0
const SETTLE_SLOTS: int = 128
const SETTLE_SLOT_ROWS: int = 256
const SETTLE_STRIDE: int = 8
## The longest side of the layer, in texels: a bigger room's layer covers its first MAX_SIDE
## pixels across and down (rooms are at most 1,344 px across today; a tiled layer would be next).
const MAX_SIDE: int = 4096

## Renders of the viewport asked for (a frame with stamps, or a clear; for tests).
var renders: int = 0
## Stamps left out because PENDING_MAX were waiting (for tests and the benchmarks).
var left_out: int = 0
## Settled motes that faded with no stamp (past SETTLED_PER_FRAME, or a full slot; for tests).
var settles_faded: int = 0

var _kinds: Array[MarkKind] = []
var _layer_kinds: Array[PackedInt32Array] = []
var _viewport: SubViewport = null
var _sprite: Sprite2D = null
var _batch: MultiMeshInstance2D = null
var _material: ShaderMaterial = null
## The rows drawn this frame, uploaded whole when there are any.
var _rows: PackedFloat32Array = PackedFloat32Array()
## The waiting stamps: a ring of PENDING_MAX rows, its oldest and how many.
var _pending: PackedFloat32Array = PackedFloat32Array()
var _pending_head: int = 0
var _pending_count: int = 0
## The layer's corner in the world, and its size in texels.
var _origin: Vector2 = Vector2.ZERO
var _size: Vector2i = Vector2i.ZERO
var _z: int = 0
## A render was asked since the last step (a clear), and one is due at the end of this frame.
var _asked: bool = false
var _live: bool = false
## The settle wheel: per slot its motes and how many; the last slot stamped (a slot number since
## the clock's start), and whether the clock is known yet (the first `step` with one).
var _settle: PackedFloat32Array = PackedFloat32Array()
var _settle_count: PackedInt32Array = PackedInt32Array()
var _settle_done: int = -1
var _settle_started: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## A layer of the kinds `kinds` (at most MAX_KINDS; a kind with problems is left out), shown at
## `z`. It has no viewport until `enter` gives it a room.
func _init(z: int, kinds: Array[MarkKind]) -> void:
	top_level = true
	_z = z
	_rng.seed = 11
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rows.resize(STAMPS_PER_FRAME * DRAW_STRIDE)
	_pending.resize(PENDING_MAX * DRAW_STRIDE)
	_settle.resize(SETTLE_SLOTS * SETTLE_SLOT_ROWS * SETTLE_STRIDE)
	_settle_count.resize(SETTLE_SLOTS)
	_take_kinds(kinds)


## The kinds, in the order the rows name them.
func kinds() -> Array[MarkKind]:
	return _kinds


## The index of the kind `id`, or -1.
func kind_index(id: StringName) -> int:
	for i in _kinds.size():
		if _kinds[i].id == id:
			return i
	return -1


## The kinds of the cards of the look `look` (LOOK_* bits, layer n is bit n - 1): every kind
## that names one of its layers; empty when none does.
func kinds_of_look(look: int) -> PackedInt32Array:
	var found := PackedInt32Array()
	for layer in range(1, _layer_kinds.size()):
		if (look >> (layer - 1)) & 1 == 1:
			for k in _layer_kinds[layer]:
				if not found.has(k):
					found.append(k)
	return found


## Make the layer cover `bounds` (the room's, in world pixels; at most MAX_SIDE across and down)
## with the walls of `walls` (one pixel a `cell`-pixel square from the corner of `bounds`, white
## for a wall; null for none), and wipe it. The viewport is made again only when its size changes.
func enter(bounds: Rect2, walls: Image, cell: float) -> void:
	_origin = bounds.position.floor()
	var size := Vector2i(clampi(ceili(bounds.size.x), 1, MAX_SIDE), clampi(ceili(bounds.size.y), 1, MAX_SIDE))
	if _viewport == null or size != _size:
		_make_layer(size)
	_size = size
	_sprite.position = _origin
	var mask: Image = walls
	if mask == null or mask.is_empty():
		mask = Image.create_empty(1, 1, false, Image.FORMAT_L8)
	_material.set_shader_parameter(&"floor_mask", ImageTexture.create_from_image(mask))
	_material.set_shader_parameter(&"mask_size", Vector2(mask.get_width(), mask.get_height()) if walls != null and not walls.is_empty() else Vector2(1.0e6, 1.0e6))
	_material.set_shader_parameter(&"mask_cell", cell)
	clear()


## The floor's colours (light, base, shadow; `RoomBase.floor_colors`); empty for unknown, and then
## no part coloured from the floor is drawn.
func set_floor_colors(colours: PackedColorArray) -> void:
	var ramp := PackedVector3Array()
	ramp.resize(3)
	for i in 3:
		var c: Color = colours[mini(i, colours.size() - 1)] if not colours.is_empty() else Color.BLACK
		ramp[i] = Vector3(c.r, c.g, c.b)
	_material.set_shader_parameter(&"floor_ramp", ramp)
	_material.set_shader_parameter(&"floor_known", 0.0 if colours.is_empty() else 1.0)


## The ramp table's texture (`ramp_table.gd`, the one the motes use) that `surface` colours, and
## a settled mote's own, are read from; null for none, and then such a part is not drawn.
func set_ramp_table(texture: Texture2D) -> void:
	_material.set_shader_parameter(&"ramp_table", texture)
	_material.set_shader_parameter(&"table_rows", float(texture.get_height()) if texture != null else 0.0)


## Wipe every mark: the layer renders once more, cleared, with nothing drawn; the waiting stamps
## and settled motes go.
func clear() -> void:
	_pending_head = 0
	_pending_count = 0
	_settle_count.fill(0)
	if _viewport == null:
		return
	_batch.multimesh.visible_instance_count = 0
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_asked = true
	renders += 1


## Stamp a mark of kind `k` at `at` (world pixels), `radius` pixels round, turned by `turn`
## radians, in the colours of `source` (`Motes.spell_source`, or a ramp table row) with the core
## colour `core` for the parts coloured from the spell, and of `surface` (a ramp table row; -1 for
## none) for those coloured from the surface. It is drawn at the next `step`.
func stamp(k: int, at: Vector2, radius: float, turn: float, source: int, core: Color, surface: int = -1) -> void:
	if k < 0 or k >= _kinds.size() or not at.is_finite() or radius <= 0.0 or _viewport == null:
		return
	if _pending_count >= PENDING_MAX:
		left_out += 1
		return
	var i: int = ((_pending_head + _pending_count) % PENDING_MAX) * DRAW_STRIDE
	_pending_count += 1
	var middle: Vector2 = (at - _origin).round()
	_pending[i] = minf(roundf(radius), MAX_RADIUS)
	_pending[i + 1] = _rng.randf()
	_pending[i + 3] = middle.x
	_pending[i + 4] = turn
	_pending[i + 7] = middle.y
	_pending[i + 8] = float(k) / KIND_CODE
	_pending[i + 9] = float(maxi(source, 0)) / SOURCE_CODE
	_pending[i + 10] = float(maxi(surface, 0)) / SOURCE_CODE
	_pending[i + 11] = 1.0
	_pending[i + 12] = core.r
	_pending[i + 13] = core.g
	_pending[i + 14] = core.b


## A mote that comes to rest at `at` at the clock time `when` leaves the mark of kind `k` there,
## in its own colours (`source`, a spell's or a ramp table row, with the core colour `core`),
## stamped once the clock is past `when`'s slot (`step`). Nothing before the first `step` with a
## clock, or with no room.
func settle(k: int, at: Vector2, when: float, source: int, core: Color) -> void:
	if not _settle_started or _viewport == null or k < 0 or k >= _kinds.size() or not at.is_finite() or not is_finite(when):
		return
	var slot: int = clampi(floori(when / SETTLE_SLOT), _settle_done + 1, _settle_done + SETTLE_SLOTS)
	var ring: int = slot % SETTLE_SLOTS
	var n: int = _settle_count[ring]
	if n >= SETTLE_SLOT_ROWS:
		settles_faded += 1
		return
	_settle_count[ring] = n + 1
	var i: int = (ring * SETTLE_SLOT_ROWS + n) * SETTLE_STRIDE
	_settle[i] = at.x
	_settle[i + 1] = at.y
	_settle[i + 2] = float(k)
	_settle[i + 3] = float(source)
	_settle[i + 4] = core.r
	_settle[i + 5] = core.g
	_settle[i + 6] = core.b


## Settled motes waiting for their slot (for tests).
func settling() -> int:
	var n: int = 0
	for count in _settle_count:
		n += count
	return n


## A turn picked at random for a stamp (its shape is its own either way).
func random_turn() -> float:
	return _rng.randf() * TAU


## Once a frame, at the clock time `now` (below 0 for none): stamp the settled motes whose slot
## is past, then draw up to STAMPS_PER_FRAME waiting stamps into the layer (one upload, one
## render); a frame with none renders nothing, and the viewport reads UPDATE_DISABLED again once
## the render asked for the frame before is done.
func step(now: float = -1.0) -> void:
	# The clock is learnt even with no room yet, so a room's first frame can settle motes.
	if now >= 0.0:
		settle_due(now)
	if _viewport == null:
		return
	var want: bool = _asked or _pending_count > 0
	if _live and not want:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_live = want
	_asked = false
	if _pending_count == 0:
		return
	var n: int = mini(_pending_count, STAMPS_PER_FRAME)
	for s in n:
		var from: int = ((_pending_head + s) % PENDING_MAX) * DRAW_STRIDE
		var to: int = s * DRAW_STRIDE
		for f in DRAW_STRIDE:
			_rows[to + f] = _pending[from + f]
	_pending_head = (_pending_head + n) % PENDING_MAX
	_pending_count -= n
	_batch.multimesh.buffer = _rows
	_batch.multimesh.visible_instance_count = n
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	renders += 1


## Queue the stamps of the settled motes whose slot is past at the clock time `now` and not
## stamped yet (SETTLED_PER_FRAME at most; the rest fade); `step` draws them. The first call only
## learns the clock.
func settle_due(now: float) -> void:
	var due: int = floori(now / SETTLE_SLOT) - 1
	if not _settle_started:
		_settle_started = true
		_settle_done = due
		return
	if due <= _settle_done:
		return
	var budget: int = SETTLED_PER_FRAME
	for slot in range(maxi(_settle_done + 1, due - SETTLE_SLOTS + 1), due + 1):
		var ring: int = slot % SETTLE_SLOTS
		var n: int = _settle_count[ring]
		_settle_count[ring] = 0
		var drawn_here: int = mini(n, budget)
		settles_faded += n - drawn_here
		budget -= drawn_here
		for m in drawn_here:
			var i: int = (ring * SETTLE_SLOT_ROWS + m) * SETTLE_STRIDE
			var source: int = int(_settle[i + 3])
			stamp(int(_settle[i + 2]), Vector2(_settle[i], _settle[i + 1]), 1.0, 0.0, source, Color(_settle[i + 4], _settle[i + 5], _settle[i + 6]), source)
	_settle_done = due


## Stamps waiting for a frame (for tests).
func pending() -> int:
	return _pending_count


## Waiting stamp `n` (0 the oldest) as the shader reads its row (a copy, for tests).
func pending_row(n: int) -> PackedFloat32Array:
	var i: int = ((_pending_head + n) % PENDING_MAX) * DRAW_STRIDE
	return _pending.slice(i, i + DRAW_STRIDE)


## Rows of the batch drawn by the next render (for tests).
func drawn() -> int:
	return _batch.multimesh.visible_instance_count if _batch != null else 0


## The layer's viewport, its sprite and its batch (null before `enter`; for tests).
func viewport() -> SubViewport:
	return _viewport


func sprite() -> Sprite2D:
	return _sprite


func batch() -> MultiMeshInstance2D:
	return _batch


## The layer's corner in the world, and its size in texels (for tests).
func origin() -> Vector2:
	return _origin


func layer_size() -> Vector2i:
	return _size


## The texture's bytes (RGBA8), for the measurements.
func texture_bytes() -> int:
	return _size.x * _size.y * 4


## A shader parameter of the stamps' material (for tests).
func shader_parameter(name: StringName) -> Variant:
	return _material.get_shader_parameter(name)


## Keep the kinds with no problems (MAX_KINDS at most), index them by look layer and hand their
## numbers to the shader.
func _take_kinds(kinds: Array[MarkKind]) -> void:
	_layer_kinds.resize(22)
	for layer in _layer_kinds.size():
		_layer_kinds[layer] = PackedInt32Array()
	var forms := PackedVector4Array()
	var colours := PackedVector4Array()
	forms.resize(MAX_KINDS)
	colours.resize(MAX_KINDS)
	for kind in kinds:
		if kind == null or not kind.problems().is_empty():
			continue
		if _kinds.size() >= MAX_KINDS:
			push_warning("Marks: more than %d mark kinds; '%s' is left out" % [MAX_KINDS, kind.id])
			continue
		var k: int = _kinds.size()
		_kinds.append(kind)
		forms[k] = Vector4(float(MarkKind.FORMS.find(kind.form)), kind.rough, kind.fill, float(kind.lines))
		colours[k] = Vector4(float(MarkKind.SOURCES.find(kind.body_from)), float(MarkKind.SHADES.find(kind.body_shade)), float(MarkKind.SOURCES.find(kind.edge_from)), float(MarkKind.SHADES.find(kind.edge_shade)))
		for layer in kind.look_layers:
			_layer_kinds[layer].append(k)
	_material.set_shader_parameter(&"kind_form", forms)
	_material.set_shader_parameter(&"kind_colour", colours)
	set_floor_colors(PackedColorArray())


## The viewport `size` texels big that holds the marks, the batch drawing into it and the sprite
## showing it (the old ones freed).
func _make_layer(size: Vector2i) -> void:
	if _viewport != null:
		_viewport.queue_free()
		_sprite.queue_free()
	_viewport = SubViewport.new()
	_viewport.name = "Layer"
	_viewport.size = size
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var multimesh: MultiMesh = BatchesScript.multimesh()
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _quad()
	multimesh.instance_count = STAMPS_PER_FRAME
	multimesh.visible_instance_count = 0
	_batch = MultiMeshInstance2D.new()
	_batch.name = "Stamps"
	_batch.multimesh = multimesh
	_batch.material = _material
	_viewport.add_child(_batch)
	add_child(_viewport)
	_sprite = Sprite2D.new()
	_sprite.name = "Marks"
	_sprite.texture = _viewport.get_texture()
	_sprite.centered = false
	_sprite.top_level = true
	_sprite.z_index = _z
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


## One quad: the shader places its corners (a vertex's UV is its corner).
static func _quad() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
