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
## **A biome's layers, one a room** (the performance pass, the owner's decision of 2026-11-20;
## `enter_places`): a biome is laid out over a world far bigger than a room, so each of its places
## (each room and bridge of the grid, `RoomGrid.place_rect`) has a layer of its own, its viewport,
## sprite and batch, the size of its place (at most MAX_SIDE each way, past any room): a view draws
## only the layers of the rooms it shows (a sprite out of the view is culled), and no layer is a
## world wide. A stamp is drawn into every layer its circle reaches, and each layer draws only the
## floor its own place holds (`place_at`, the grid's rule: a bridge's lip over a room's edge is the
## bridge's), masked as the walls are, so a mark across a mouth is one mark, drawn once.
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
## **Off the walls:** the stamp shader is clipped by the walls and the holes (`floor_mask`, one texel a
## wall cell of the projectile manager's grid, `set_walls`, and its holes, hub rework HR-H2: no mark
## over a hole), built once a room.
##
## **Settled motes** (P2b): a mote of a kind that settles (`MoteKind.settles`) is handed over when
## it is thrown, with where and when it comes to rest (`settle`, from `Motes.mote_land`). It waits
## in a wheel of SETTLE_SLOTS time slots, each SETTLE_SLOT long, and is stamped once its slot is
## past (never before it lies still; up to a slot late, under the still mote). At most
## SETTLED_PER_FRAME are stamped a frame and at most SETTLE_SLOT_ROWS wait in a slot; the rest
## just fade with their motes (`settles_faded`). A settle may carry its mote's serial: once the
## motes say that mote is gone (`forget_settles_before`, the ring wrote over it before it rested)
## it fades too, so no mark is left where nothing was seen to land. Their colours, and a surface's (`surface`), are
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
## Settled motes stamped in one frame at most; the rest fade with their motes.
const SETTLED_PER_FRAME: int = 512
## The settle wheel: its slots' length (s), how many (past Motes.LIFE_MAX), the most a slot holds
## and the floats a settled mote takes (where, its kind, its source, its core colour).
const SETTLE_SLOT: float = 1.0 / 30.0
const SETTLE_SLOTS: int = 128
const SETTLE_SLOT_ROWS: int = 256
const SETTLE_STRIDE: int = 8
## The longest side of a layer, in texels: a bigger room's layer covers its first MAX_SIDE pixels
## across and down (rooms are at most 1,344 px across today; a biome has a layer a room).
const MAX_SIDE: int = 4096
## How far past a stamp's radius it may draw (px): what a layer near it takes it for.
const STAMP_PAD: float = 4.0

## Renders of the viewport asked for (a frame with stamps, or a clear; for tests).
var renders: int = 0
## Stamps left out because PENDING_MAX were waiting (for tests and the benchmarks).
var left_out: int = 0
## Settled motes that faded with no stamp (past SETTLED_PER_FRAME, or a full slot; for tests).
var settles_faded: int = 0

var _kinds: Array[MarkKind] = []
var _layer_kinds: Array[PackedInt32Array] = []
## The kinds that name each card by id (`MarkKind.cards`; spell-spectacle-2.md, S2).
var _card_kinds: Dictionary[StringName, PackedInt32Array] = {}
## The layers: one over the room's bounds (`enter`), or one a place of a biome (`enter_places`).
var _pieces: Array[Piece] = []
## The first layer's (`viewport()` and the others, for tests and the single room).
var _viewport: SubViewport = null
var _sprite: Sprite2D = null
var _batch: MultiMeshInstance2D = null
## The stamps' material: the first layer's, and the one every other layer's copies its numbers from.
var _material: ShaderMaterial = null
## The rows drawn this frame (each layer's own: a `Piece`'s `rows`).
var _rows: PackedFloat32Array = PackedFloat32Array()
## The waiting stamps: a ring of PENDING_MAX rows, its oldest and how many.
var _pending: PackedFloat32Array = PackedFloat32Array()
var _pending_head: int = 0
var _pending_count: int = 0
## The corner the waiting stamps are kept from (the bounds'), and the first layer's size in texels.
var _origin: Vector2 = Vector2.ZERO
var _size: Vector2i = Vector2i.ZERO
var _z: int = 0
## The settle wheel: per slot its motes and how many; the last slot stamped (a slot number since
## the clock's start), and whether the clock is known yet (the first `step` with one).
var _settle: PackedFloat32Array = PackedFloat32Array()
var _settle_count: PackedInt32Array = PackedInt32Array()
var _settle_serial: PackedInt64Array = PackedInt64Array()
var _settle_done: int = -1
var _settle_started: bool = false
## Settles whose serial is below this are gone (`forget_settles_before`).
var _settle_forget: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## One layer: its viewport, sprite, batch and material, its corner in the world and size in texels,
## the rows it draws this frame, and whether a render was asked (a clear) or is due.
class Piece:
	extends RefCounted
	var viewport: SubViewport = null
	var sprite: Sprite2D = null
	var batch: MultiMeshInstance2D = null
	var material: ShaderMaterial = null
	var origin: Vector2 = Vector2.ZERO
	var size: Vector2i = Vector2i.ZERO
	var rows: PackedFloat32Array = PackedFloat32Array()
	var count: int = 0
	var asked: bool = false
	var live: bool = false

	## Its rect in the world.
	func rect() -> Rect2:
		return Rect2(origin, Vector2(size))


## A layer of the kinds `kinds` (at most MAX_KINDS; a kind with problems is left out), shown at
## `z`. It has no viewport until `enter` gives it a room.
func _init(z: int, kinds: Array[MarkKind]) -> void:
	top_level = true
	_z = z
	_rng.seed = 11
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_pending.resize(PENDING_MAX * DRAW_STRIDE)
	_settle.resize(SETTLE_SLOTS * SETTLE_SLOT_ROWS * SETTLE_STRIDE)
	_settle_count.resize(SETTLE_SLOTS)
	_settle_serial.resize(SETTLE_SLOTS * SETTLE_SLOT_ROWS)
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


## The kinds that name the card `card` by id (`MarkKind.cards`); empty for none. Kept: read it,
## never change it.
func kinds_of_card(card: StringName) -> PackedInt32Array:
	var found: Variant = _card_kinds.get(card)
	return found if found != null else PackedInt32Array()


## Whether any kind names a card by id.
func has_card_kinds() -> bool:
	return not _card_kinds.is_empty()


## The kinds that name look layer `layer` (1 to LOOK_LAYERS). Kept: read it, never change it.
func kinds_named_by_layer(layer: int) -> PackedInt32Array:
	return _layer_kinds[layer] if layer >= 0 and layer < _layer_kinds.size() else PackedInt32Array()


## Make the layer cover `bounds` (the room's, in world pixels; at most MAX_SIDE across and down)
## with the walls of `walls` (one pixel a `cell`-pixel square from the corner of `bounds`, white
## for a wall; null for none), and wipe it. The viewport is made again only when its size changes.
func enter(bounds: Rect2, walls: Image, cell: float) -> void:
	_origin = bounds.position.floor()
	var size := Vector2i(clampi(ceili(bounds.size.x), 1, MAX_SIDE), clampi(ceili(bounds.size.y), 1, MAX_SIDE))
	_fit_pieces(1)
	var piece: Piece = _pieces[0]
	if piece.viewport == null or size != piece.size:
		_make_layer(piece, size)
	piece.size = size
	piece.origin = _origin
	piece.sprite.position = _origin
	_mask(piece, walls, cell, walls != null and not walls.is_empty())
	_first_is(piece)
	clear()


## A biome (`enter_places`): a layer a place of `grid` (its rect, at most MAX_SIDE each way, its
## corner on the `cell` squares of `walls` from the corner of `bounds`), each masked by the walls and
## by the floor its place does not hold (`grid.place_at` of each square's middle), and wipe them all.
## With no place it is `enter`. Layers of the sizes wanted are kept from the last biome.
func enter_places(bounds: Rect2, walls: Image, cell: float, grid: RoomGrid) -> void:
	if grid == null or grid.places() == 0:
		enter(bounds, walls, cell)
		return
	_origin = bounds.position.floor()
	var count: int = grid.places()
	_fit_pieces(count)
	var step: float = maxf(cell, 1.0)
	for place in count:
		var rect: Rect2 = grid.place_rect(place)
		# On the walls' squares from the bounds' corner, so a layer's mask texel is a wall cell.
		var low := Vector2(floorf((rect.position.x - _origin.x) / step), floorf((rect.position.y - _origin.y) / step))
		var high := Vector2(ceilf((rect.end.x - _origin.x) / step), ceilf((rect.end.y - _origin.y) / step))
		var corner: Vector2 = _origin + low * step
		var size := Vector2i(clampi(ceili((high.x - low.x) * step), 1, MAX_SIDE), clampi(ceili((high.y - low.y) * step), 1, MAX_SIDE))
		var piece: Piece = _pieces[place]
		if piece.viewport == null or size != piece.size:
			_make_layer(piece, size)
		piece.size = size
		piece.origin = corner
		piece.sprite.position = corner
		_mask(piece, _place_mask(walls, Vector2i(low), size, step, grid, place, corner), step, true)
	_first_is(_pieces[0])
	clear()


## How many layers there are (1 for a room, one a place for a biome; 0 before a room).
func layer_count() -> int:
	return _pieces.size() if _viewport != null else 0


## Layer `k`'s viewport and sprite (null for none; for tests).
func layer_viewport(k: int) -> SubViewport:
	return _pieces[k].viewport if k >= 0 and k < _pieces.size() else null


func layer_sprite(k: int) -> Sprite2D:
	return _pieces[k].sprite if k >= 0 and k < _pieces.size() else null


## Layer `k`'s rect in the world (empty for none; for tests).
func layer_rect(k: int) -> Rect2:
	return _pieces[k].rect() if k >= 0 and k < _pieces.size() else Rect2()


## Rows layer `k` draws at its next render (for tests).
func layer_drawn(k: int) -> int:
	return _pieces[k].batch.multimesh.visible_instance_count if k >= 0 and k < _pieces.size() and _pieces[k].batch != null else 0


## Layer `k`'s stamps' material (null for none; for tests).
func layer_material(k: int) -> ShaderMaterial:
	return _pieces[k].material if k >= 0 and k < _pieces.size() else null


## Exactly `count` layers: more made empty (their viewports at `_make_layer`), the rest freed.
func _fit_pieces(count: int) -> void:
	while _pieces.size() > count:
		var gone: Piece = _pieces.pop_back()
		if gone.viewport != null:
			gone.viewport.queue_free()
			gone.sprite.queue_free()
	while _pieces.size() < count:
		var piece := Piece.new()
		# The first layer draws with the material the kinds and colours are set on; the others with
		# copies of it, which every later setting reaches too (`_set_all`).
		piece.material = _material if _pieces.is_empty() else _material.duplicate() as ShaderMaterial
		piece.rows.resize(STAMPS_PER_FRAME * DRAW_STRIDE)
		_pieces.append(piece)


## The first layer is `piece` (the single room's, and what the tests read).
func _first_is(piece: Piece) -> void:
	_viewport = piece.viewport
	_sprite = piece.sprite
	_batch = piece.batch
	_size = piece.size
	_rows = piece.rows


## `piece`'s mask `mask` (a texel a `cell` square from its corner, white where no mark is drawn; null
## or empty: none, when `known` is false).
func _mask(piece: Piece, mask: Image, cell: float, known: bool) -> void:
	var shown: Image = mask
	if shown == null or shown.is_empty():
		shown = Image.create_empty(1, 1, false, Image.FORMAT_L8)
		known = false
	piece.material.set_shader_parameter(&"floor_mask", ImageTexture.create_from_image(shown))
	piece.material.set_shader_parameter(&"mask_size", Vector2(shown.get_width(), shown.get_height()) if known else Vector2(1.0e6, 1.0e6))
	piece.material.set_shader_parameter(&"mask_cell", cell)


## The mask of place `place`'s layer: `size` texels at `corner` (the `walls` square `from`, each
## `step` px), white for a wall (and a hole) of `walls` and for each square whose middle `grid` says
## is not in `place`.
static func _place_mask(walls: Image, from: Vector2i, size: Vector2i, step: float, grid: RoomGrid, place: int, corner: Vector2) -> Image:
	var columns: int = maxi(ceili(float(size.x) / step), 1)
	var lines: int = maxi(ceili(float(size.y) / step), 1)
	var bytes := PackedByteArray()
	bytes.resize(columns * lines)
	var has_walls: bool = walls != null and not walls.is_empty() and walls.get_format() == Image.FORMAT_L8
	var wall_bytes: PackedByteArray = walls.get_data() if has_walls else PackedByteArray()
	var wall_w: int = walls.get_width() if has_walls else 0
	var wall_h: int = walls.get_height() if has_walls else 0
	# The grid's squares answer most points at once (`whole_places`); `place_at` only the rest.
	var whole: PackedByteArray = grid.whole_places()
	var origin: Vector2 = grid.place_origin()
	var square_columns: int = grid.place_columns()
	var square_rows: int = grid.place_rows()
	for y in lines:
		for x in columns:
			var wall: bool = false
			if has_walls:
				var wx: int = from.x + x
				var wy: int = from.y + y
				wall = wx < 0 or wy < 0 or wx >= wall_w or wy >= wall_h or wall_bytes[wy * wall_w + wx] > 127
			if not wall:
				var middle: Vector2 = corner + (Vector2(x, y) + Vector2(0.5, 0.5)) * step
				var sx: int = floori((middle.x - origin.x) / RoomGrid.PLACE_CELL)
				var sy: int = floori((middle.y - origin.y) / RoomGrid.PLACE_CELL)
				var code: int = whole[sy * square_columns + sx] if sx >= 0 and sy >= 0 and sx < square_columns and sy < square_rows else RoomGrid.WHOLE_ASK
				var held: int = grid.place_at(middle) if code == RoomGrid.WHOLE_ASK else code - 1
				wall = held != place
			bytes[y * columns + x] = 255 if wall else 0
	return Image.create_from_data(columns, lines, false, Image.FORMAT_L8, bytes)


## `value` for the stamps' shader parameter `name` on every layer's material.
func _set_all(name: StringName, value: Variant) -> void:
	_material.set_shader_parameter(name, value)
	for piece in _pieces:
		if piece.material != _material:
			piece.material.set_shader_parameter(name, value)


## The floor's colours (light, base, shadow; `RoomBase.floor_colors`); empty for unknown, and then
## no part coloured from the floor is drawn.
func set_floor_colors(colours: PackedColorArray) -> void:
	var ramp := PackedVector3Array()
	ramp.resize(3)
	for i in 3:
		var c: Color = colours[mini(i, colours.size() - 1)] if not colours.is_empty() else Color.BLACK
		ramp[i] = Vector3(c.r, c.g, c.b)
	_set_all(&"floor_ramp", ramp)
	_set_all(&"floor_known", 0.0 if colours.is_empty() else 1.0)


## The ramp table's texture (`ramp_table.gd`, the one the motes use) that `surface` colours, and
## a settled mote's own, are read from; null for none, and then such a part is not drawn.
func set_ramp_table(texture: Texture2D) -> void:
	_set_all(&"ramp_table", texture)
	_set_all(&"table_rows", float(texture.get_height()) if texture != null else 0.0)


## Wipe every mark: the layer renders once more, cleared, with nothing drawn; the waiting stamps
## and settled motes go.
func clear() -> void:
	_pending_head = 0
	_pending_count = 0
	_settle_count.fill(0)
	for piece in _pieces:
		if piece.viewport == null:
			continue
		piece.batch.multimesh.visible_instance_count = 0
		piece.viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
		piece.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		piece.asked = true
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
	# As big as it is asked to be (the owner, 2026-11-09: no cue is capped in size).
	_pending[i] = roundf(radius)
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
## stamped once the clock is past `when`'s slot (`step`). `serial` names the mote (its row's
## serial, `forget_settles_before`; -1 for one never forgotten). Nothing before the first `step`
## with a clock, or with no room.
func settle(k: int, at: Vector2, when: float, source: int, core: Color, serial: int = -1) -> void:
	if not _settle_started or _viewport == null or k < 0 or k >= _kinds.size() or not at.is_finite() or not is_finite(when):
		return
	var slot: int = clampi(floori(when / SETTLE_SLOT), _settle_done + 1, _settle_done + SETTLE_SLOTS)
	var ring: int = slot % SETTLE_SLOTS
	var n: int = _settle_count[ring]
	if n >= SETTLE_SLOT_ROWS:
		settles_faded += 1
		return
	_settle_count[ring] = n + 1
	_settle_serial[ring * SETTLE_SLOT_ROWS + n] = serial
	var i: int = (ring * SETTLE_SLOT_ROWS + n) * SETTLE_STRIDE
	_settle[i] = at.x
	_settle[i + 1] = at.y
	_settle[i + 2] = float(k)
	_settle[i + 3] = float(source)
	_settle[i + 4] = core.r
	_settle[i + 5] = core.g
	_settle[i + 6] = core.b


## The motes of serials below `serial` are gone (overwritten in their ring): their settles fade.
func forget_settles_before(serial: int) -> void:
	_settle_forget = serial


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
	for piece in _pieces:
		piece.count = 0
	var n: int = mini(_pending_count, STAMPS_PER_FRAME)
	for s in n:
		_draw_stamp(((_pending_head + s) % PENDING_MAX) * DRAW_STRIDE)
	_pending_head = (_pending_head + n) % PENDING_MAX
	_pending_count -= n
	for piece in _pieces:
		var want: bool = piece.asked or piece.count > 0
		if piece.live and not want:
			piece.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		piece.live = want
		piece.asked = false
		if piece.count == 0:
			continue
		piece.batch.multimesh.buffer = piece.rows
		piece.batch.multimesh.visible_instance_count = piece.count
		piece.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		renders += 1


## The waiting stamp at `from` (its row's first float in `_pending`) written into the rows of every
## layer its circle reaches, its middle from that layer's corner (one layer: the room's).
func _draw_stamp(from: int) -> void:
	var middle := Vector2(_pending[from + 3], _pending[from + 7])
	var reach: float = _pending[from] + STAMP_PAD
	for piece in _pieces:
		if piece.count >= STAMPS_PER_FRAME:
			continue
		var shift: Vector2 = _origin - piece.origin
		var at: Vector2 = middle + shift
		if _pieces.size() > 1 and (at.x + reach < 0.0 or at.y + reach < 0.0 or at.x - reach > float(piece.size.x) or at.y - reach > float(piece.size.y)):
			continue
		var to: int = piece.count * DRAW_STRIDE
		for f in DRAW_STRIDE:
			piece.rows[to + f] = _pending[from + f]
		piece.rows[to + 3] = at.x
		piece.rows[to + 7] = at.y
		piece.count += 1


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
			var serial: int = _settle_serial[ring * SETTLE_SLOT_ROWS + m]
			if serial >= 0 and serial < _settle_forget:
				settles_faded += 1
				continue
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


## Rows of the first layer's batch drawn by the next render (for tests).
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


## The textures' bytes (RGBA8; every layer's), for the measurements.
func texture_bytes() -> int:
	var bytes: int = 0
	for piece in _pieces:
		if piece.viewport != null:
			bytes += piece.size.x * piece.size.y * 4
	return bytes


## A shader parameter of the stamps' material (for tests).
func shader_parameter(name: StringName) -> Variant:
	return _material.get_shader_parameter(name)


## Keep the kinds with no problems (MAX_KINDS at most), index them by look layer and hand their
## numbers to the shader.
func _take_kinds(kinds: Array[MarkKind]) -> void:
	_layer_kinds.resize(MoteKind.LOOK_LAYERS + 1)
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
		for card in kind.cards:
			if not _card_kinds.has(card):
				_card_kinds[card] = PackedInt32Array()
			_card_kinds[card].append(k)
	_set_all(&"kind_form", forms)
	_set_all(&"kind_colour", colours)
	set_floor_colors(PackedColorArray())


## `piece`'s viewport `size` texels big that holds its marks, the batch drawing into it and the
## sprite showing it (the old ones freed).
func _make_layer(piece: Piece, size: Vector2i) -> void:
	if piece.viewport != null:
		piece.viewport.queue_free()
		piece.sprite.queue_free()
	var named: String = "" if _pieces.find(piece) <= 0 else str(_pieces.find(piece))
	var viewport := SubViewport.new()
	viewport.name = "Layer" + named
	viewport.size = size
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var multimesh: MultiMesh = BatchesScript.multimesh()
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _quad()
	multimesh.instance_count = STAMPS_PER_FRAME
	multimesh.visible_instance_count = 0
	var batch := MultiMeshInstance2D.new()
	batch.name = "Stamps"
	batch.multimesh = multimesh
	batch.material = piece.material
	viewport.add_child(batch)
	add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.name = "Marks" + named
	sprite.texture = viewport.get_texture()
	sprite.centered = false
	sprite.top_level = true
	sprite.z_index = _z
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	piece.viewport = viewport
	piece.sprite = sprite
	piece.batch = batch
	piece.live = false
	piece.asked = false


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
