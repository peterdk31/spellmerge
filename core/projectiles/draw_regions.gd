extends RefCounted
## The shots drawn by the room they are in (the performance pass, the owner's decision of
## 2026-11-20; CB1's fallback 2, docs/milestones/connected-biomes.md). The projectile manager's,
## drawing only: nothing in the simulation reads it.
##
## In a biome every view draws the world again, and a batch is never culled by where its shots are
## (core/README.md, "Batches are never culled"), so each view drew every shot of every fight. While
## the room grid has places (a biome's rooms and bridges), each draw batch's rows are handed out by
## the place their square lies wholly in (the grid's `whole_places`, as `shot_places` reads it): a
## **region** a place, a `MultiMeshInstance2D` of its own under the batch's node (its material the
## batch's, `use_parent_material`, so a batch's shader settings reach every region), whose box is
## its place's rect grown by REACH (`Batches.box_of`: never stale, the shots in it are only ever
## drawn there), so a view culls the rooms it does not show. **Crossers** (a shot in a square two
## places share, at a mouth, over a bridge's lip, outside every place, or a row reaching past
## SPAN_MOST: a long wall, a stretched bolt) go to region 0, whose box is the world. The batch's own
## node then draws nothing itself (its rows still go to the light's mirror and the still shots'
## views whole, as before). Order: a batch's regions draw just after it, crossers first, so the
## batches keep their order; within a batch, two shots of different rooms rarely meet.
##
## Every region's node, buffer and room is made the first time a shot is in it and kept; its room
## grows by powers of two (as `_fit_batch`) and shrinks when a quarter is used. The hand-out runs in
## the native kernel when there is one (`ShotKernel.region_counts`, `region_rows`), to the bit as
## here (`tests/core/test_draw_regions.gd`).

const BatchesScript := preload("res://core/projectiles/batches.gd")

## Floats in a row (the manager's DRAW_STRIDE), and the floats of its transform's origin.
const DRAW_STRIDE: int = 16
const ROW_X: int = 3
const ROW_Y: int = 7
## The most places drawn by region; the shots of a place past them are crossers.
const MOST: int = 64
## How far past its place a shot of the place's region may be drawn (px): the largest head with its
## light quad and its streak, a rune's quad, under SPAN_MOST each way.
const REACH: float = 320.0
## A row whose transform has a part past this (px: a quad's length or width) is drawn as a crosser.
const SPAN_MOST: float = 128.0
## The smallest room a region's batch has (rows).
const MIN_ROOM: int = 16
## The grid's place squares (RoomGrid.PLACE_CELL) and its code for one `place_at` must be asked.
const PLACE_CELL: float = RoomGrid.PLACE_CELL
const PLACE_ASK: int = RoomGrid.WHOLE_ASK

## The places drawn by region (0: none, every shot is drawn by its batch). Read only.
var places: int = 0
## The rows handed to each region by the last `draw` (region 0 the crossers). Read only.
var counts: PackedInt32Array = PackedInt32Array()
## The place squares (a copy of the grid's `whole_places`), how many across and down, their corner.
var _whole: PackedByteArray = PackedByteArray()
var _columns: int = 0
var _lines: int = 0
var _origin: Vector2 = Vector2.ZERO
var _rects: Array[Rect2] = []
## By batch, by region: its node (null until a shot is in it), its buffer and its room.
var _nodes: Array[Array] = []
var _buffers: Array[Array] = []
var _rooms: Array[PackedInt32Array] = []
## The batch `draw` writes now (`region_rows` reads its buffers here), and each region's next row.
var _current: Array = []
var _fill: PackedInt32Array = PackedInt32Array()


## Read the places of `grid` (null: none) when they changed. True while shots are drawn by region.
func fit(grid: RoomGrid) -> bool:
	var count: int = mini(grid.places(), MOST) if grid != null else 0
	if count == 0:
		if places != 0:
			_take(grid, 0)
		return false
	var same: bool = count == places and grid.place_origin() == _origin and grid.place_columns() == _columns and grid.place_rows() == _lines
	for place in count:
		if not same:
			break
		same = grid.place_rect(place) == _rects[place]
	if not same:
		_take(grid, count)
	return true


## Hand batch `batch`'s first `count` rows of `rows` out to its regions under `node` (the batch's
## own node, which draws nothing itself while there are places), upload each region's and hide the
## empty ones; in `kernel` (null: here, in GDScript).
func draw(batch: int, node: MultiMeshInstance2D, rows: PackedFloat32Array, count: int, kernel: Object) -> void:
	_fit_batch(batch)
	var regions: int = places + 1
	counts.fill(0)
	if count > 0:
		if kernel != null:
			kernel.call(&"region_counts", self, rows, count)
		else:
			_count(rows, count)
	var room: PackedInt32Array = _rooms[batch]
	for region in regions:
		var used: int = counts[region]
		if used == 0:
			continue
		if _nodes[batch][region] == null:
			_nodes[batch][region] = _make(node, region)
		var wanted: int = _room_for(room[region], used)
		if wanted != room[region]:
			room[region] = wanted
			(_nodes[batch][region] as MultiMeshInstance2D).multimesh.instance_count = wanted
			# Through a typed variable: the Array's own buffer is resized (a cast would resize a copy).
			var buffer: PackedFloat32Array = _buffers[batch][region]
			buffer.resize(wanted * DRAW_STRIDE)
	_current = _buffers[batch]
	if count > 0:
		_fill.fill(0)
		if kernel != null:
			kernel.call(&"region_rows", self, rows, count)
		else:
			_write(rows, count)
	for region in regions:
		var shown := _nodes[batch][region] as MultiMeshInstance2D
		if shown == null:
			continue
		var used: int = counts[region]
		if used > 0:
			shown.multimesh.buffer = _buffers[batch][region]
			if shown.texture != node.texture:
				shown.texture = node.texture
		if shown.multimesh.visible_instance_count != used:
			shown.multimesh.visible_instance_count = used
	_current = []


## Every region of every batch hidden (no places any more, or nothing drawn).
func hide_all() -> void:
	for batch in _nodes.size():
		for region in _nodes[batch].size():
			var shown := _nodes[batch][region] as MultiMeshInstance2D
			if shown != null:
				shown.multimesh.visible_instance_count = 0


## The region the row at `i` of `rows` is drawn by: its place plus one, or 0 (a crosser). The rule
## `ShotKernel.region_counts` and `region_rows` follow to the bit.
func region_of(rows: PackedFloat32Array, i: int) -> int:
	if absf(rows[i]) > SPAN_MOST or absf(rows[i + 1]) > SPAN_MOST or absf(rows[i + 4]) > SPAN_MOST or absf(rows[i + 5]) > SPAN_MOST:
		return 0
	var x: int = floori((float(rows[i + ROW_X]) - _origin.x) / PLACE_CELL)
	var y: int = floori((float(rows[i + ROW_Y]) - _origin.y) / PLACE_CELL)
	if x < 0 or x >= _columns or y < 0 or y >= _lines:
		return 0
	var code: int = _whole[y * _columns + x]
	if code == 0 or code == PLACE_ASK or code > places:
		return 0
	return code


## Batch `batch`'s node for region `region` (null before a shot was in it; for tests).
func node_of(batch: int, region: int) -> MultiMeshInstance2D:
	if batch < 0 or batch >= _nodes.size() or region < 0 or region >= _nodes[batch].size():
		return null
	return _nodes[batch][region]


## Batch `batch`'s buffer for region `region` (for tests and the kernel's check).
func buffer_of(batch: int, region: int) -> PackedFloat32Array:
	if batch < 0 or batch >= _buffers.size() or region < 0 or region >= _buffers[batch].size():
		return PackedFloat32Array()
	return _buffers[batch][region]


## The places of `grid` read (the first `count`): every region's box set again, each hidden.
func _take(grid: RoomGrid, count: int) -> void:
	places = count
	_rects.clear()
	if count > 0:
		_whole = grid.whole_places().duplicate()
		_columns = grid.place_columns()
		_lines = grid.place_rows()
		_origin = grid.place_origin()
		for place in count:
			_rects.append(grid.place_rect(place))
	else:
		_whole = PackedByteArray()
		_columns = 0
		_lines = 0
		_origin = Vector2.ZERO
	counts.resize(count + 1)
	_fill.resize(count + 1)
	for batch in _nodes.size():
		_fit_batch(batch)
		for region in _nodes[batch].size():
			var shown := _nodes[batch][region] as MultiMeshInstance2D
			if shown != null:
				shown.multimesh.visible_instance_count = 0
				shown.multimesh.custom_aabb = _box(region)


## The batch's regions sized for the places now.
func _fit_batch(batch: int) -> void:
	while _nodes.size() <= batch:
		_nodes.append([])
		_buffers.append([])
		_rooms.append(PackedInt32Array())
	var regions: int = places + 1
	if _nodes[batch].size() < regions:
		var from: int = _nodes[batch].size()
		_nodes[batch].resize(regions)
		_buffers[batch].resize(regions)
		_rooms[batch].resize(regions)
		for region in range(from, regions):
			_buffers[batch][region] = PackedFloat32Array()
			_rooms[batch][region] = 0


## The box of region `region`: the world for the crossers, else its place's rect grown by REACH.
func _box(region: int) -> AABB:
	if region == 0 or region > _rects.size():
		return BatchesScript.WORLD
	return BatchesScript.box_of(_rects[region - 1], REACH)


## A region's node under `node`: its batch's material and look, drawn just after it.
func _make(node: MultiMeshInstance2D, region: int) -> MultiMeshInstance2D:
	var multimesh: MultiMesh = BatchesScript.multimesh()
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = node.multimesh.mesh
	multimesh.instance_count = 0
	multimesh.custom_aabb = _box(region)
	var shown := MultiMeshInstance2D.new()
	shown.name = "Region%d" % region
	shown.multimesh = multimesh
	shown.use_parent_material = true
	shown.texture = node.texture
	node.add_child(shown)
	# In order of region under the batch: the crossers first.
	var at: int = 0
	for child in node.get_children():
		if child == shown:
			break
		if child.name.begins_with("Region") and int(String(child.name).trim_prefix("Region")) < region:
			at = child.get_index() + 1
	node.move_child(shown, at)
	return shown


## The room a region of `room` rows wants for `used`: kept while it holds them and more than a
## quarter is used, else `used` up to a power of two (at least MIN_ROOM).
static func _room_for(room: int, used: int) -> int:
	if used <= room and used * 4 > room:
		return room
	var wanted: int = MIN_ROOM
	while wanted < used:
		wanted *= 2
	return wanted


## `counts`: the rows of `rows` each region draws (the first `count`).
func _count(rows: PackedFloat32Array, count: int) -> void:
	for row in count:
		counts[region_of(rows, row * DRAW_STRIDE)] += 1


## Each of the first `count` rows of `rows` into its region's buffer of `_current`, in order.
func _write(rows: PackedFloat32Array, count: int) -> void:
	for row in count:
		var from: int = row * DRAW_STRIDE
		var region: int = region_of(rows, from)
		var buffer: PackedFloat32Array = _current[region]
		var to: int = _fill[region] * DRAW_STRIDE
		_fill[region] += 1
		for f in DRAW_STRIDE:
			buffer[to + f] = rows[from + f]
