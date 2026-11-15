extends Node2D
## Ground cover's look (ground cover GC3, docs/milestones/ground-cover.md, rule 6): the tufts of the
## room's cover, swaying in a slow wind. Feel's own script (`Feel.cover()`), never more of feel.gd.
##
## **The layout** is heard, never asked: each `room_built` (Flow, whenever it lays a room out: a run's
## start, each room entered, a restore into another room) works out the room's cover
## (`CoverLayout.of`, from the layout, its `RoomBase` and the registry's cover kinds) and lays its
## tufts; the layout's node is not kept. A restore into the room shown sends nothing and needs
## nothing: the tufts are still the room's.
##
## **One batch a kind** (made by `Batches.multimesh()`, so never culled), its rows the tufts of every
## cell of that kind, scattered by `CoverTufts` (the editor's preview draws the same ones), drawn by
## `cover.gdshader` with the kind's sheet. The node is at the floor marks' z (`RoomBase.FLOOR_Z + 1`)
## and before the marks' layer in Feel's tree, so the marks lie over the cover and every body (z 0)
## over both.
##
## **A cell's state picks its tufts' frames** through each row's custom data (`show_state`; the
## cover area's changes, GC5): a state that draws no frame folds its tufts away. The rows are kept
## here and a changed kind's are handed to its batch once, at the frame's `step`, however many of its
## cells changed. Nothing is allocated once a room is laid: a frame sets the wind's time and hands
## over the changed rows (`step`).
##
## Pure view: no state of the game is here, and nothing here is read by the simulation.

const SHADER: Shader = preload("res://gameplay/feel/cover.gdshader")
const BatchesScript := preload("res://core/projectiles/batches.gd")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const ROOM_FOLDER: StringName = &"rooms"
const COVER_FOLDER: StringName = &"cover"
## Floats in a row: the transform (8), the colour (4) and the custom data (4).
const STRIDE: int = 16
## The most a tuft sways at its tip, in pixels (the shader's SWAY_CODE).
const SWAY_CODE: float = 8.0

## The bus and the registry (Feel's; null in a test that lays a layout itself).
var events: EventsScript = null
var registry: RegistryScript = null

## The cover laid (null before the first room). Read only.
var layout: CoverLayout = null
## Each laid kind's batch, in the layout's kinds' order (a kind with no sheet has none: null).
var _batches: Array[MultiMeshInstance2D] = []
## Each laid kind's rows (STRIDE floats a tuft), the copy every change is written to, and whether
## they changed since they were last handed to their batch (`step` hands them over).
var _rows: Array[PackedFloat32Array] = []
var _dirty: PackedByteArray = PackedByteArray()
## Batches made for an earlier room and not used by this one, kept to be used again.
var _spare: Array[MultiMeshInstance2D] = []
## Each cell's first row in its kind's batch (-1 for none), and the state it shows.
var _first_row: PackedInt32Array = PackedInt32Array()
var _shown: PackedInt32Array = PackedInt32Array()
## The kinds a test or a screenshot gave (`use_kinds`); the registry's while null.
var _given: Array[CoverKind] = []
var _use_given: bool = false


## Cover drawn at `z` (Feel's MARK_Z).
func _init(z: int) -> void:
	top_level = true
	z_index = z


func _ready() -> void:
	ShaderWarmupScript.want(SHADER, ShaderWarmupScript.BATCH)
	if events != null and not events.room_built.is_connected(_on_room_built):
		events.room_built.connect(_on_room_built)


## Lay the cover with `kinds` instead of the registry's from the next room on (tests and
## screenshots, before the game has cover of its own); null: the registry's again.
func use_kinds(kinds: Variant) -> void:
	_use_given = kinds != null
	_given = [] as Array[CoverKind]
	if kinds != null:
		for kind: CoverKind in kinds as Array:
			_given.append(kind)


## The cover kinds a room's cover is worked out with.
func kinds() -> Array[CoverKind]:
	if _use_given:
		return _given
	var found: Array[CoverKind] = []
	if registry != null:
		for item: Resource in registry.get_all(COVER_FOLDER):
			if item is CoverKind:
				found.append(item as CoverKind)
	return found


## A room was laid out (`room_built`): its cover, from its layout as built.
func _on_room_built(room_id: StringName, layout_root: Node) -> void:
	var room: RoomBase = registry.get_resource(ROOM_FOLDER, room_id) as RoomBase if registry != null else null
	lay(CoverLayout.of(layout_root, room, kinds()))


## Show `laid`, a room's cover, every cell in its kind's first state (at rest).
func lay(laid: CoverLayout) -> void:
	layout = laid
	for batch in _batches:
		if batch != null:
			batch.multimesh.instance_count = 0
			batch.visible = false
			_spare.append(batch)
	_batches.clear()
	_rows.clear()
	_first_row.resize(laid.cells.size())
	_first_row.fill(-1)
	_shown.resize(laid.cells.size())
	_shown.fill(0)
	_dirty.resize(laid.kinds.size())
	_dirty.fill(0)
	for index in laid.kinds.size():
		_rows.append(PackedFloat32Array())
		_batches.append(_lay_kind(index))


## The batch of the kind `kind_id` in the room laid (null for none, or a kind with no sheet).
func batch_of(kind_id: StringName) -> MultiMeshInstance2D:
	if layout == null:
		return null
	for index in layout.kinds.size():
		if layout.kinds[index].id == kind_id:
			return _batches[index]
	return null


## The rows of the kind `kind_id` in the room laid, as its batch draws them after the next `step`
## (STRIDE floats a tuft: its transform, colour and custom data; empty for none). Read only.
func rows_of(kind_id: StringName) -> PackedFloat32Array:
	if layout == null:
		return PackedFloat32Array()
	for index in layout.kinds.size():
		if layout.kinds[index].id == kind_id:
			return _rows[index]
	return PackedFloat32Array()


## Every batch of the room laid, in its kinds' order (null for a kind with no sheet).
func batches() -> Array[MultiMeshInstance2D]:
	return _batches


## The state cell `cell` shows (its index in its kind's states; 0 at rest).
func shown_state(cell: int) -> int:
	return _shown[cell] if cell >= 0 and cell < _shown.size() else 0


## Once a frame, at Feel's clock `now`: the wind's time, and the rows of each kind changed since the
## last frame handed to its batch.
func step(now: float) -> void:
	for index in _batches.size():
		var batch: MultiMeshInstance2D = _batches[index]
		if batch == null:
			continue
		(batch.material as ShaderMaterial).set_shader_parameter(&"view_time", now)
		if _dirty[index] != 0:
			_dirty[index] = 0
			batch.multimesh.buffer = _rows[index]


## Show cell `cell` in state `state` of its kind (its index in `CoverKind.states`): its tufts draw
## that state's frames with its sway and bend, or fold away when it draws none.
func show_state(cell: int, state: int) -> void:
	if layout == null or cell < 0 or cell >= _first_row.size() or _first_row[cell] < 0:
		return
	var index: int = layout.cells[cell] - 1
	var kind: CoverKind = layout.kinds[index]
	if state < 0 or state >= kind.states.size() or kind.states[state] == null:
		return
	_shown[cell] = state
	# Taken out while it is written, so the write is in place (a copy-on-write array held twice
	# would be copied).
	var rows: PackedFloat32Array = _rows[index]
	_rows[index] = PackedFloat32Array()
	var kind_key: int = CoverLayout.name_hash(kind.id)
	for tuft in kind.tufts_per_cell:
		var rolled: int = CoverTufts.roll(layout, kind_key, cell, tuft)
		_write_look(rows, (_first_row[cell] + tuft) * STRIDE, kind, kind.states[state], rolled)
	_rows[index] = rows
	_dirty[index] = 1


## The batch of the layout's kind `index`, its rows the tufts of its cells at rest; null for a kind
## with no sheet or no state.
func _lay_kind(index: int) -> MultiMeshInstance2D:
	var kind: CoverKind = layout.kinds[index]
	if kind.sheet == null or kind.states.is_empty() or kind.states[0] == null:
		return null
	var cells: int = 0
	for cell in layout.cells.size():
		if layout.cells[cell] == index + 1:
			cells += 1
	var per_cell: int = kind.tufts_per_cell
	var rows := PackedFloat32Array()
	rows.resize(cells * per_cell * STRIDE)
	var kind_key: int = CoverLayout.name_hash(kind.id)
	var rest: CoverState = kind.states[0]
	var row: int = 0
	for cell in layout.cells.size():
		if layout.cells[cell] != index + 1:
			continue
		_first_row[cell] = row
		for tuft in per_cell:
			var rolled: int = CoverTufts.roll(layout, kind_key, cell, tuft)
			var foot: Vector2 = CoverTufts.foot(layout, cell, tuft, per_cell, rolled)
			var at: int = row * STRIDE
			rows[at] = -1.0 if CoverTufts.mirrored(rolled) else 1.0
			rows[at + 1] = 0.0
			rows[at + 2] = 0.0
			rows[at + 3] = foot.x
			rows[at + 4] = 0.0
			rows[at + 5] = 1.0
			rows[at + 6] = 0.0
			rows[at + 7] = foot.y
			_write_look(rows, at, kind, rest, rolled)
			row += 1
	var batch: MultiMeshInstance2D = _batch()
	batch.name = "Cover_%s" % kind.id
	batch.texture = kind.sheet
	var material := batch.material as ShaderMaterial
	material.set_shader_parameter(&"frame_count", float(maxi(kind.frame_count(), 1)))
	material.set_shader_parameter(&"frame_size", Vector2(kind.frame_size))
	batch.multimesh.instance_count = row
	if row > 0:
		batch.multimesh.buffer = rows
	batch.visible = true
	_rows[index] = rows
	return batch


## A batch to lay a kind in: a spare one, or a new one.
func _batch() -> MultiMeshInstance2D:
	if not _spare.is_empty():
		return _spare.pop_back()
	var multimesh: MultiMesh = BatchesScript.multimesh()
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _quad()
	var batch := MultiMeshInstance2D.new()
	batch.multimesh = multimesh
	batch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = SHADER
	batch.material = material
	add_child(batch)
	return batch


## Write a tuft's look in `state` of `kind` into the row at `at` of `rows`: its colour (shown, or not
## drawn, alpha 0, when the state draws no frame) and its custom data (its frame, its sway, its bend,
## where its sway starts).
static func _write_look(rows: PackedFloat32Array, at: int, kind: CoverKind, state: CoverState, rolled: int) -> void:
	var frame: int = CoverTufts.frame(rolled, state.frames)
	rows[at + 8] = 1.0
	rows[at + 9] = 1.0
	rows[at + 10] = 1.0
	rows[at + 11] = 1.0 if frame >= 0 else 0.0
	rows[at + 12] = float(maxi(frame, 0)) / 255.0
	rows[at + 13] = clampf(kind.sway * state.sway / SWAY_CODE, 0.0, 1.0)
	rows[at + 14] = clampf(state.bend, 0.0, 1.0)
	rows[at + 15] = CoverTufts.phase(rolled)


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
