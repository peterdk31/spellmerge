extends RefCounted
## The light grid worked out by a compute shader on the GPU (the owner's decision of 2026-11-22: the
## heaviest per-frame effects on the GPU, the desktop builds only; gameplay/feel/README.md, "The light
## grid on the GPU"). LightGrid's other way to work its cells out: while `LightGrid.use_gpu` holds one
## of these, `add_rows`, `add_beam` and `bake` hand their rows here and the shader
## (`light_grid.glsl`) lights every cell and writes the atlas the readers sample
## (`texture`, a Texture2DRD), so the CPU neither lights a cell nor reads one back. LightGrid's own
## loops (and LightKernel) stay the reference and the fallback (the web, the OpenGL fallback, a GPU
## with no compute: `GpuCompute.available`).
##
## - **What is handed:** each batch of rows as it is (the shots', runes', flashes', cues': the
##   arrays SpellLight hands the grid), into a MultiMesh of this object's own that is never drawn
##   (`RenderingServer.multimesh_set_buffer`, the renderer's own upload of an array of floats, in
##   order with the frame's other calls); the spots' and carried lights' rows copied first, with
##   their flicker's dip worked out (its hash needs doubles); the beams' pieces worked out here (a
##   few a beam). The frame's numbers (the views, the cell, the infusion table, the boxes that block
##   light) in a small buffer. Nothing is made a frame once the buffers have grown.
## - **The render thread:** the dispatch runs there (`GpuCompute.on_render_thread`), after the
##   frame's uploads and before its draw. What it reads of this object's own (the frame's numbers,
##   the segments) is written in one of two sets taken in turn, so the main thread never writes
##   what the render thread may still read (TextureUpload's FRAMES_HELD).
## - **The same light:** the shader is the CPU's `_row`, `_lamp` and `add_beam` in floats where the
##   CPU works in doubles, every lamp added in the CPU's order; a cell differs from the CPU's by at
##   most a byte a channel (tests/gameplay/feel/test_light_grid_gpu.gd, under the Mobile renderer).
##
## View only: nothing here touches the simulation.

const LightBlockersScript := preload("res://gameplay/feel/light_blockers.gd")

## Floats a row holds (LightGrid.STRIDE).
const STRIDE: int = 16
## The kind of a beam's pieces (the shader's ROWS_BEAM; LightGrid's ROWS_* are 0 to 4).
const ROWS_BEAM: int = 5
const ROWS_SPOT: int = 3
## The most views (LightGrid.VIEWS_MOST) and cells a view each way (LightGrid.VIEW_CELLS_MOST): the
## atlas is made at its most once (ATLAS_WIDTH x ATLAS_HEIGHT, 4 MB), so it never grows.
const VIEWS_MOST: int = 4
const ATLAS_WIDTH: int = 2048
const ATLAS_HEIGHT: int = 512
## The most segments (batches of rows) a frame (more are left out, with an error once).
const SEGMENTS_MOST: int = 64
## A MultiMesh a segment, a spots' segment's copy each turn, and the beams' (the last slot).
const SLOTS: int = SEGMENTS_MOST + 1
const BEAM_SLOT: int = SEGMENTS_MOST
## vec4s a lamp holds (the shader's LAMP_VEC4), and the lamps the buffer holds at first.
const LAMP_VEC4: int = 5
const LAMPS_AT_FIRST: int = 4096
## The frame's buffer (the shader's `Frame`): head, 8 view vec4s, 32 tints, the boxes, their columns.
const BLOCKERS_MOST: int = LightBlockersScript.MAX
const FRAME_VEC4: int = 1 + 8 + 32 + 2 * BLOCKERS_MOST
const FRAME_BYTES: int = FRAME_VEC4 * 16
## The push constants (the shader's `Push`: 8 words).
const PUSH_BYTES: int = 32
## The spots' flicker (LightGrid's).
const SPOT_RATE: float = 7.0
## A tile of the cells' step (the shader's TILE), and the threads of a group (its local size).
const TILE: int = 8
const GROUP: int = 64

## The atlas the readers sample (null until made). Read only.
var texture: Texture2DRD = null
## Whether the shader, its pipeline and buffers were made (false: LightGrid lights on the CPU).
var ready: bool = false
## Frames dispatched, and lamps lit the last frame (for tests and benchmarks). Read only.
var dispatched: int = 0
var lamps_last: int = 0
## How many times a slot's MultiMesh was sized anew (for tests: not a frame once the batches settle).
var slots_sized: int = 0

# The render thread's (made and used there only).
var _rd: RenderingDevice = null
var _shader: RID = RID()
var _pipeline: RID = RID()
var _atlas: RID = RID()
var _frame_buffer: RID = RID()
var _lamp_buffer: RID = RID()
var _lamps_room: int = 0
var _set0: RID = RID()
var _empty_rows: RID = RID()
var _empty_set: RID = RID()
## A segment slot's uniform set and the buffer it was made for (made again when that buffer is).
var _sets: Array[RID] = []
var _set_buffers: Array[RID] = []
var _push: PackedByteArray = PackedByteArray()

# The main thread's: a slot's MultiMesh (its buffer the slot's rows) and its instances.
var _meshes: Array[RID] = []
var _mesh_rows: PackedInt32Array = PackedInt32Array()
## A frame's set (`Staged`), two taken in turn: `_turn` the main thread's this frame, `_render_turn`
## the render thread's next dispatch (one dispatch a bake, in order).
var _staged: Array[Staged] = []
var _turn: int = 0
var _render_turn: int = 0
var _segments: int = 0
var _lamps: int = 0
var _beam_pieces: int = 0
var _too_many_said: bool = false
## The frame each slot was last handed rows in (`begin` counts frames), so a slot is used once a frame.
var _slot_used: PackedInt64Array = PackedInt64Array()
var _frames_begun: int = 0
## The jobs the render thread runs (made once: no Callable a frame).
var _dispatch_job: Callable = Callable()
var _make_job: Callable = Callable()
## The shader (light_grid.glsl), loaded only here, on a renderer with a RenderingDevice: never on the
## web or the OpenGL fallback (the web's exports leave the file out too).
var _shader_file: RDShaderFile = null


## What one frame hands the render thread, written by the main thread only while the render thread
## reads the other set: the frame's numbers (the shader's `Frame`, as bytes), the segments (kind,
## count, first lamp, slot << 1 | blocked; reach, pad), the views' cells (columns, rows a view, then
## the views and the segments), the spots' rows copied a spots' slot and the beams' pieces.
class Staged:
	extends RefCounted
	var frame: PackedByteArray = PackedByteArray()
	var segs: PackedInt32Array = PackedInt32Array()
	var seg_floats: PackedFloat32Array = PackedFloat32Array()
	var views: PackedInt32Array = PackedInt32Array()
	var spots: Array[RowsCopy] = []
	var beams: RowsCopy = RowsCopy.new()

	func _init(frame_bytes: int, segments: int, views_most: int, spot_slots: int) -> void:
		frame.resize(frame_bytes)
		segs.resize(segments * 4)
		seg_floats.resize(segments * 2)
		views.resize(views_most * 2 + 2)
		for i in spot_slots:
			spots.append(RowsCopy.new())

	func put_segment(segment: int, slot: int, kind: int, count: int, first: int, blocked: bool, reach: float, pad: float) -> void:
		segs[segment * 4] = kind
		segs[segment * 4 + 1] = count
		segs[segment * 4 + 2] = first
		segs[segment * 4 + 3] = (slot << 1) | (1 if blocked else 0)
		seg_floats[segment * 2] = reach
		seg_floats[segment * 2 + 1] = pad

	## The frame's head: the cell, the boxes that block light, the lamps.
	func write_head(cell: float, blockers: int, lamps: int) -> void:
		write_vec4(0, Color(cell, float(blockers), float(lamps), 0.0))

	## View `k`'s grid: its first cell's corner, its cells and where they start in the atlas.
	func write_view(k: int, x: float, y: float, columns: int, lines: int, at_x: int, at_y: int) -> void:
		write_vec4(1 + k * 2, Color(x, y, float(columns), float(lines)))
		write_vec4(2 + k * 2, Color(float(at_x), float(at_y), 0.0, 0.0))
		views[k * 2] = columns
		views[k * 2 + 1] = lines

	## The frame's vec4 `index` (four floats).
	func write_vec4(index: int, v: Color) -> void:
		var at: int = index * 16
		frame.encode_float(at, v.r)
		frame.encode_float(at + 4, v.g)
		frame.encode_float(at + 8, v.b)
		frame.encode_float(at + 12, v.a)


## Rows of this object's own, written in place (a member written by its own methods is never copied).
class RowsCopy:
	extends RefCounted
	var data: PackedFloat32Array = PackedFloat32Array()

	## The first `count` rows of `rows` with each one's flicker's dip at +12 (LightGrid._row's, in
	## doubles: its hash cannot be worked out in floats), in place of how deep it dips.
	func flickered(rows: PackedFloat32Array, count: int, now: float, rate: float, stride: int) -> void:
		if data.size() != rows.size():
			data.resize(rows.size())
		for i in count:
			var at: int = i * stride
			var step_of: float = floorf(now * rate + rows[at + 13] * 13.0)
			var wave: float = sin(step_of * 12.9898 + rows[at + 13] * 78.233) * 43758.5453
			for f in stride:
				data[at + f] = rows[at + f]
			data[at + 12] = rows[at + 12] * (wave - floorf(wave))

	## Room for `rows` rows of `stride` (it only grows).
	func room(rows: int, stride: int) -> void:
		if data.size() < rows * stride:
			data.resize(maxi(rows * stride, data.size() * 2))

	## A beam's piece at row `row`: its start, way, length, reach, ends (1 first, 2 last), colour and box.
	func piece(row: int, stride: int, ax: float, ay: float, wx: float, wy: float, length: float, reach: float, ends: float, colour: Color, box: Vector4) -> void:
		var at: int = row * stride
		data[at] = ax
		data[at + 1] = ay
		data[at + 2] = wx
		data[at + 3] = wy
		data[at + 4] = length
		data[at + 5] = reach
		data[at + 6] = ends
		data[at + 7] = 0.0
		data[at + 8] = colour.r
		data[at + 9] = colour.g
		data[at + 10] = colour.b
		data[at + 11] = 0.0
		data[at + 12] = box.x
		data[at + 13] = box.y
		data[at + 14] = box.z
		data[at + 15] = box.w


## Made on the render thread at once (the frame waits for it, once): `ready` says whether it can run.
func _init() -> void:
	for turn in 2:
		_staged.append(Staged.new(FRAME_BYTES, SEGMENTS_MOST, VIEWS_MOST, SEGMENTS_MOST))
	_push.resize(PUSH_BYTES)
	_mesh_rows.resize(SLOTS)
	_mesh_rows.fill(-1)
	_slot_used.resize(SLOTS)
	_slot_used.fill(-1)
	for slot in SLOTS:
		_meshes.append(RID())
		_sets.append(RID())
		_set_buffers.append(RID())
	_dispatch_job = _dispatch
	_make_job = _make
	if not GpuCompute.available():
		return
	_shader_file = load("res://gameplay/feel/light_grid.glsl") as RDShaderFile
	GpuCompute.on_render_thread(_make_job)
	# The atlas's RID is the render thread's: wait for it once, here, before the readers bind it.
	RenderingServer.force_sync()
	if not ready:
		return
	texture = Texture2DRD.new()
	texture.texture_rd_rid = _atlas


## Let go of everything made on the GPU (the light switched off or the grid freed).
func release() -> void:
	var was_ready: bool = ready
	# A dispatch still queued sees `ready` false and does nothing; force_sync waits for any that runs
	# now, so nothing it reads is freed under it (and this object outlives it).
	ready = false
	if was_ready:
		RenderingServer.force_sync()
	for slot in _meshes.size():
		if _meshes[slot].is_valid():
			RenderingServer.free_rid(_meshes[slot])
			_meshes[slot] = RID()
	if texture != null:
		texture.texture_rd_rid = RID()
		texture = null
	if was_ready:
		# Freed by the render thread after every dispatch queued before (not through this object,
		# which may be gone by then). The uniform sets go with the buffers they were made over.
		GpuCompute.free_later([_empty_set, _set0, _lamp_buffer, _frame_buffer, _empty_rows, _atlas, _pipeline, _shader])


## The frame begins: no rows, no beams yet.
func begin() -> void:
	_frames_begun += 1
	_segments = 0
	_lamps = 0
	_beam_pieces = 0


## The first `count` rows of `rows`, read as `kind` (LightGrid.ROWS_*) with a flash's `reach` and
## `pad`, the spots' flicker by `now`, and whether the boxes stop them (`blocked`).
func add_rows(rows: PackedFloat32Array, count: int, kind: int, reach: float, pad: float, now: float, blocked: bool) -> void:
	if count <= 0 or not ready:
		return
	if _segments >= SEGMENTS_MOST:
		if not _too_many_said:
			_too_many_said = true
			push_error("LightGridGpu: more than %d batches of lights in a frame; the rest are left out" % SEGMENTS_MOST)
		return
	var instances: int = rows.size() / STRIDE
	var slot: int = _slot_for(instances)
	var staged: Staged = _staged[_turn]
	var handed: PackedFloat32Array = rows
	if kind == ROWS_SPOT:
		staged.spots[slot].flickered(rows, count, now, SPOT_RATE, STRIDE)
		handed = staged.spots[slot].data
	if not _hand(slot, handed):
		return
	staged.put_segment(_segments, slot, kind, count, _lamps, blocked, reach, pad)
	_slot_used[slot] = _frames_begun
	_lamps += count
	_segments += 1


## A live beam's pieces along the first `points` points of `path`, `beam_reach` px each side (at least
## `cell`), in `colour` (LightGrid.add_beam's numbers, worked out here a piece at a time).
func add_beam(path: PackedVector3Array, points: int, beam_reach: float, colour: Color, cell: float) -> void:
	if not ready or points < 2 or beam_reach <= 0.0:
		return
	beam_reach = maxf(beam_reach, cell)
	if colour.r * colour.r + colour.g * colour.g + colour.b * colour.b <= 0.0:
		return
	var beams: RowsCopy = _staged[_turn].beams
	beams.room(_beam_pieces + points - 1, STRIDE)
	for k in points - 1:
		var ax: float = path[k].x
		var ay: float = path[k].y
		var dx: float = path[k + 1].x - ax
		var dy: float = path[k + 1].y - ay
		var length: float = sqrt(dx * dx + dy * dy)
		var ends: float = (1.0 if k == 0 else 0.0) + (2.0 if k == points - 2 else 0.0)
		var box := Vector4(minf(ax, ax + dx) - beam_reach, minf(ay, ay + dy) - beam_reach, maxf(ax, ax + dx) + beam_reach, maxf(ay, ay + dy) + beam_reach)
		beams.piece(_beam_pieces, STRIDE, ax, ay, dx / length if length > 0.0 else 1.0, dy / length if length > 0.0 else 0.0, length, beam_reach, ends, colour, box)
		_beam_pieces += 1


## The frame's light into the atlas: the beams handed as one segment more, the frame's numbers
## (LightGrid's: the cell, its views, the infusion table, the boxes that block light) written, and
## the dispatch queued.
func bake(cell: float, views: int, origin: PackedFloat64Array, size: PackedInt32Array, placed: PackedInt32Array, tints: PackedColorArray, boxes: PackedVector4Array, bodies: PackedVector4Array, blockers: int) -> void:
	if not ready:
		return
	var staged: Staged = _staged[_turn]
	if _beam_pieces > 0 and _segments < SEGMENTS_MOST and _hand(BEAM_SLOT, staged.beams.data):
		staged.put_segment(_segments, BEAM_SLOT, ROWS_BEAM, _beam_pieces, _lamps, false, 0.0, 0.0)
		_lamps += _beam_pieces
		_segments += 1
	_write_frame(staged, cell, views, origin, size, placed, tints, boxes, bodies, mini(blockers, BLOCKERS_MOST))
	lamps_last = _lamps
	dispatched += 1
	_turn = 1 - _turn
	GpuCompute.on_render_thread(_dispatch_job)


## The atlas's bytes as the GPU last wrote them, `width` x `height` cells (r, g, b, a a cell; for
## tests: a read back, never in a frame).
func read_back(width: int, height: int) -> PackedByteArray:
	if not ready:
		return PackedByteArray()
	RenderingServer.force_sync()
	var image: Image = RenderingServer.texture_2d_get(texture.get_rid())
	if image == null:
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(width * height * 4)
	for y in height:
		for x in width:
			var c: Color = image.get_pixel(x, y)
			var at: int = (y * width + x) * 4
			out[at] = c.r8
			out[at + 1] = c.g8
			out[at + 2] = c.b8
			out[at + 3] = c.a8
	return out


# --- The main thread's ---------------------------------------------------------------------------

## A slot for a batch of `instances` rows this frame: one not used yet this frame whose MultiMesh
## already holds that many, so a batch that moves in the frame's order (another batch came or went)
## does not make the slot's buffer anew; else the first slot free this frame. A slot is a MultiMesh
## and a spots' copy a turn; the beams have the last one.
func _slot_for(instances: int) -> int:
	var free: int = -1
	for slot in SEGMENTS_MOST:
		if _slot_used[slot] == _frames_begun:
			continue
		if _mesh_rows[slot] == instances:
			return slot
		if free < 0:
			free = slot
	return free


## Hand `rows` to slot `slot`'s MultiMesh (its instance count follows the array's size). False when it
## cannot be (no whole rows).
func _hand(slot: int, rows: PackedFloat32Array) -> bool:
	var instances: int = rows.size() / STRIDE
	if instances <= 0 or rows.size() != instances * STRIDE:
		return false
	if not _meshes[slot].is_valid():
		_meshes[slot] = RenderingServer.multimesh_create()
	if _mesh_rows[slot] != instances:
		_mesh_rows[slot] = instances
		slots_sized += 1
		RenderingServer.multimesh_allocate_data(_meshes[slot], instances, RenderingServer.MULTIMESH_TRANSFORM_2D, true, true)
	RenderingServer.multimesh_set_buffer(_meshes[slot], rows)
	return true


## The frame's numbers into `staged`: the head, the views, the infusion table, the boxes; the views'
## cells and how many segments.
func _write_frame(staged: Staged, cell: float, views: int, origin: PackedFloat64Array, size: PackedInt32Array, placed: PackedInt32Array, tints: PackedColorArray, boxes: PackedVector4Array, bodies: PackedVector4Array, blockers: int) -> void:
	staged.write_head(cell, blockers, _lamps)
	for k in VIEWS_MOST:
		var shown: bool = k < views
		staged.write_view(k, float(origin[k * 2]) if shown else 0.0, float(origin[k * 2 + 1]) if shown else 0.0,
			size[k * 2] if shown else 0, size[k * 2 + 1] if shown else 0, placed[k * 2] if shown else 0, placed[k * 2 + 1] if shown else 0)
	for layer in 32:
		staged.write_vec4(1 + 8 + layer, tints[layer] if layer < tints.size() else Color(0, 0, 0, 0))
	for k in BLOCKERS_MOST:
		var box: Vector4 = boxes[k] if k < blockers else Vector4.ZERO
		var body: Vector4 = bodies[k] if k < blockers else Vector4.ZERO
		staged.write_vec4(1 + 8 + 32 + k, Color(box.x, box.y, box.z, box.w))
		staged.write_vec4(1 + 8 + 32 + BLOCKERS_MOST + k, Color(body.x, body.y, body.z, body.w))
	staged.views[VIEWS_MOST * 2] = views
	staged.views[VIEWS_MOST * 2 + 1] = _segments


# --- The render thread's -------------------------------------------------------------------------

func _make() -> void:
	_rd = GpuCompute.device()
	if _rd == null:
		return
	_shader = GpuCompute.compile(_rd, _shader_file, "light_grid.glsl")
	if not _shader.is_valid():
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	var format := RDTextureFormat.new()
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.width = ATLAS_WIDTH
	format.height = ATLAS_HEIGHT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	_atlas = _rd.texture_create(format, RDTextureView.new())
	_rd.texture_clear(_atlas, Color(0, 0, 0, 1), 0, 1, 0, 1)
	_frame_buffer = _rd.storage_buffer_create(FRAME_BYTES)
	var empty := PackedByteArray()
	empty.resize(STRIDE * 4)
	_empty_rows = _rd.storage_buffer_create(empty.size(), empty)
	_empty_set = _rows_set(_empty_rows)
	_grow_lamps(LAMPS_AT_FIRST)
	ready = _pipeline.is_valid() and _atlas.is_valid() and _set0.is_valid() and _empty_set.is_valid()


## The lamps' buffer made room for `lamps` (and set 0 made again for it).
func _grow_lamps(lamps: int) -> void:
	if _lamp_buffer.is_valid():
		_rd.free_rid(_lamp_buffer)
	_lamps_room = lamps
	_lamp_buffer = _rd.storage_buffer_create(lamps * LAMP_VEC4 * 16)
	var frame_uniform := RDUniform.new()
	frame_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	frame_uniform.binding = 0
	frame_uniform.add_id(_frame_buffer)
	var lamp_uniform := RDUniform.new()
	lamp_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	lamp_uniform.binding = 1
	lamp_uniform.add_id(_lamp_buffer)
	var atlas_uniform := RDUniform.new()
	atlas_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	atlas_uniform.binding = 2
	atlas_uniform.add_id(_atlas)
	_set0 = _rd.uniform_set_create([frame_uniform, lamp_uniform, atlas_uniform], _shader, 0)


func _rows_set(buffer: RID) -> RID:
	var rows_uniform := RDUniform.new()
	rows_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	rows_uniform.binding = 0
	rows_uniform.add_id(buffer)
	return _rd.uniform_set_create([rows_uniform], _shader, 1)


## Slot `slot`'s uniform set over its MultiMesh's buffer as it is now (made again when the renderer
## made the buffer anew: the MultiMesh grew).
func _slot_set(slot: int) -> RID:
	var buffer: RID = RenderingServer.multimesh_get_buffer_rd_rid(_meshes[slot])
	if not buffer.is_valid():
		return RID()
	if buffer != _set_buffers[slot] or not _rd.uniform_set_is_valid(_sets[slot]):
		_set_buffers[slot] = buffer
		_sets[slot] = _rows_set(buffer)
	return _sets[slot]


func _dispatch() -> void:
	if _rd == null or not ready:
		return
	# The set of the bake that queued this (one dispatch a bake, in order).
	var staged: Staged = _staged[_render_turn]
	_render_turn = 1 - _render_turn
	var segs: PackedInt32Array = staged.segs
	var floats: PackedFloat32Array = staged.seg_floats
	var views: PackedInt32Array = staged.views
	var segments: int = views[VIEWS_MOST * 2 + 1]
	var lamps: int = 0
	for s in segments:
		lamps = maxi(lamps, segs[s * 4 + 2] + segs[s * 4 + 1])
	if lamps > _lamps_room:
		_grow_lamps(maxi(lamps, _lamps_room * 2))
	_rd.buffer_update(_frame_buffer, 0, FRAME_BYTES, staged.frame)
	var list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, _set0, 0)
	for s in segments:
		var count: int = segs[s * 4 + 1]
		var rows_set: RID = _slot_set(segs[s * 4 + 3] >> 1)
		if count <= 0 or not rows_set.is_valid():
			continue
		_rd.compute_list_bind_uniform_set(list, rows_set, 1)
		_push_words(0, count, segs[s * 4 + 2], segs[s * 4], floats[s * 2], floats[s * 2 + 1], segs[s * 4 + 3] & 1, 0)
		_rd.compute_list_set_push_constant(list, _push, PUSH_BYTES)
		_rd.compute_list_dispatch(list, (count + GROUP - 1) / GROUP, 1, 1)
	_rd.compute_list_add_barrier(list)
	_rd.compute_list_bind_uniform_set(list, _empty_set, 1)
	for k in views[VIEWS_MOST * 2]:
		var columns: int = views[k * 2]
		var lines: int = views[k * 2 + 1]
		if columns <= 0 or lines <= 0:
			continue
		var across: int = (columns + TILE - 1) / TILE
		var down: int = (lines + TILE - 1) / TILE
		_push_words(1, 0, 0, k, 0.0, 0.0, 0, across)
		_rd.compute_list_set_push_constant(list, _push, PUSH_BYTES)
		_rd.compute_list_dispatch(list, across * down, 1, 1)
	_rd.compute_list_end()


func _push_words(mode: int, count: int, first: int, kind: int, reach: float, pad: float, blocked: int, tiles_across: int) -> void:
	_push.encode_s32(0, mode)
	_push.encode_s32(4, count)
	_push.encode_s32(8, first)
	_push.encode_s32(12, kind)
	_push.encode_float(16, reach)
	_push.encode_float(20, pad)
	_push.encode_s32(24, blocked)
	_push.encode_s32(28, tiles_across)

