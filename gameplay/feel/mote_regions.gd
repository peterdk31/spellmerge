extends RefCounted
## The motes drawn by the room they fly in (the performance pass, the owner's decision of
## 2026-11-20, after #890; docs/milestones/connected-biomes.md, "Motes by room"). The motes' pool's
## (`mote.gd`), drawing only: nothing of the motes' flights or the simulation reads it.
##
## The pool's ring is written in time order, so each of its chunks holds every fight's motes, and a
## batch is never culled by where its motes are (core/README.md, "Batches are never culled"): every
## view drew every mote of the biome. While the room grid has places (a biome's rooms and bridges)
## the ring's chunks draw nothing, and each row written is copied, at the pool's next step, into a
## **chunk of its room's**: a `MultiMeshInstance2D` of ROWS rows drawn with the pool's material, whose
## box is its room's place grown by REACH (`Batches.box_of`: never stale, its motes are only ever
## drawn inside it), so a view culls the rooms it does not show and no mote is worked out for them.
##
## **A mote's region** (`region_of`, the rule the native kernel follows to the bit): the place whose
## PLACE_CELL square its ground point at birth lies wholly in (the grid's `whole_places`), when the
## box of everywhere its flight can be drawn (`reach_of`: along the floor its speed times the most
## its drag lets it glide in its life, its sway twice, PAD for its shape, glow and the stirs; up its
## height's highest) lies inside the place grown by REACH; else region 0, the **crossers**, whose box
## is the world (a mote at a mouth, over a bridge's lip, in the void, or one flung far). So a mote
## that drifts across a room's edge is still drawn, by its room's chunk or by the crossers'.
##
## **The chunks** are a pool shared by the regions, made as needed (at most `most_chunks`) and kept:
## each region writes into its open chunk until it is full, then takes a free one. A chunk is free
## again once every mote in it is gone (by its own life, `until`, or overwritten in the ring: the ring
## overwrites its oldest row, and that row's copy is folded away as the new one is handed out, so no
## more motes are drawn than the ring holds). With every chunk in use, the one whose motes end
## soonest is taken (`stolen`). Only the chunks written or folded in a step are uploaded, and only
## their filled rows are drawn (`visible_instance_count`).
##
## The hand-out runs in the native kernel when there is one (`MoteKernel.region_rows`), to the bit as
## here (`tests/gameplay/feel/test_mote_regions.gd`). The ring itself, its rows and what writes them
## are as they were: `tests/gameplay/feel/test_native_motes.gd` holds them.

const BatchesScript := preload("res://core/projectiles/batches.gd")

## Drawing only: none of it is the simulation's state (core/sim/README.md).
const VIEW_ONLY: bool = true

## Rows in a region's chunk: one batch, uploaded whole when any of its rows is written or folded.
const ROWS: int = 512
## Floats in a row and where a row's numbers are (the pool's DRAW_STRIDE and ROW_*; the native kernel
## checks them against the pool's, `MoteKernel.check_regions`).
const DRAW_STRIDE: int = 16
const ROW_VX: int = 0
const ROW_BORN: int = 1
const ROW_X: int = 3
const ROW_VY: int = 4
const ROW_VZ: int = 5
const ROW_Y: int = 7
const ROW_KIND: int = 9
const ROW_LIFE: int = 10
const ROW_HEIGHT: int = 11
## The pool's codes (`Motes.KIND_CODE`, `LIFE_MAX`, `HEIGHT_MAX`, `MAX_KINDS`).
const KIND_CODE: float = 255.0
const LIFE_MAX: float = MoteKind.LIFE_MAX
const HEIGHT_MAX: float = 63.75
const MAX_KINDS: int = 256
## The most places drawn by region (the shots' `DrawRegions.MOST`); the motes of a place past them
## are crossers.
const MOST: int = 64
## How far past its place a mote of the place's region may be drawn (px).
const REACH: float = 96.0
## What a mote draws past its pixel at the most, px: its shape turned (3), its glow (2) and the
## world's stirs (`mote.gdshader`'s STIR_SHOT_PIXELS and STIR_BLAST_PIXELS, 13), with room to spare.
const PAD: float = 24.0
## The grid's place squares (RoomGrid.PLACE_CELL) and its code for one `place_at` must be asked.
const PLACE_CELL: float = RoomGrid.PLACE_CELL
const PLACE_ASK: int = RoomGrid.WHOLE_ASK

## The places drawn by region (0: none, the ring's chunks draw). Read only.
var places: int = 0
## How many times the places were read (`fit` finding them changed): each region's z is the pool's
## again then. Read only.
var fits: int = 0
## Chunks taken from another region while every chunk was in use (for tests and the benchmarks).
var stolen: int = 0
## The place squares (a copy of the grid's `whole_places`), how many across and down, their corner;
## each place's rect grown by REACH (x0, y0, x1, y1).
var _whole: PackedByteArray = PackedByteArray()
var _columns: int = 0
var _lines: int = 0
var _origin: Vector2 = Vector2.ZERO
var _rects: Array[Rect2] = []
var _bounds: PackedFloat64Array = PackedFloat64Array()
## By ring row: the slot its copy is in (chunk * ROWS + row in it; -1 none). By slot: the ring row
## copied there (good only below its chunk's fill).
var _slot_of: PackedInt32Array = PackedInt32Array()
var _row_of_slot: PackedInt32Array = PackedInt32Array()
## By chunk: its batch, its rows, how many are filled, how many of them still hold a mote not
## overwritten, the clock time its last mote is gone by, whether it changed since its upload, its
## region (-1: free) and the region its box was set for.
var _nodes: Array[MultiMeshInstance2D] = []
var _buffers: Array[PackedFloat32Array] = []
var _fill: PackedInt32Array = PackedInt32Array()
var _live: PackedInt32Array = PackedInt32Array()
var _until: PackedFloat64Array = PackedFloat64Array()
var _dirty: PackedByteArray = PackedByteArray()
var _region: PackedInt32Array = PackedInt32Array()
var _boxed: PackedInt32Array = PackedInt32Array()
## By region (0 the crossers): the chunk it writes into (-1: none yet).
var _open: PackedInt32Array = PackedInt32Array()
## The free chunks, the first `_free_count` of `_free`.
var _free: PackedInt32Array = PackedInt32Array()
var _free_count: int = 0
## The most chunks made (`most_chunks`), where they are drawn, with what, and at what z.
var _most: int = 0
var _parent: Node = null
var _material: Material = null
var _mesh: Mesh = null
var _z: int = 0
## The ring's rows a chunk (the pool's CHUNK).
var _ring_rows: int = 1
## By region: 1 while its chunks are not drawn (`set_region_shown`: a room nobody has entered, under
## the void's dark, unseen_rooms.gd); their rows are still copied, so they show as they stand again.
var _region_hidden: PackedByteArray = PackedByteArray()


## The regions of a ring of `cap` rows in chunks of `ring_rows`, their chunks under `parent`, drawn
## with `material` and `mesh` at `z`.
func _init(cap: int, ring_rows: int, parent: Node, material: Material, mesh: Mesh, z: int) -> void:
	_ring_rows = maxi(ring_rows, 1)
	_slot_of.resize(maxi(cap, 1))
	_slot_of.fill(-1)
	_most = most_chunks(cap, MOST)
	_free.resize(_most)
	_parent = parent
	_material = material
	_mesh = mesh
	_z = z


## The most chunks a ring of `cap` rows over `regions` regions (and the crossers') has: twice the
## ring's rows (a chunk is free only once all of its motes are gone), and two a region (a region's
## rows among the ring's last `cap` may begin in one chunk and end in another).
static func most_chunks(cap: int, regions: int) -> int:
	return 2 * ceili(float(maxi(cap, 1)) / ROWS) + 2 * (regions + 1)


## Read the places of `grid` (null: none) when they changed. True when they did: every region is
## emptied and the ring must be handed out again (`hand_out` of every row).
func fit(grid: RoomGrid) -> bool:
	var count: int = mini(grid.places(), MOST) if grid != null else 0
	if count == places:
		if count == 0:
			return false
		var same: bool = grid.place_origin() == _origin and grid.place_columns() == _columns and grid.place_rows() == _lines
		for place in count:
			if not same:
				break
			same = grid.place_rect(place) == _rects[place]
		if same:
			return false
	_take(grid, count)
	return true


## Whether the motes are drawn by region now.
func is_on() -> bool:
	return places > 0


## Hand the `count` rows of `pool`'s ring from row `from` (round the ring) out to their regions at
## the clock time `now`: each one's earlier copy folded away, a mote still alive copied into its
## region's chunk; in `kernel` (null: here, in GDScript).
func hand_out(pool: Object, from: int, count: int, now: float, kernel: Object) -> void:
	var done: int = 0
	var cap: int = _slot_of.size()
	count = mini(count, cap)
	while done < count:
		var at: int = (from + done) % cap
		var handed: int
		if kernel != null:
			handed = kernel.call(&"region_rows", self, pool, at, count - done, now)
			# Nothing handed with a chunk free: the kernel refused the call (it says why); here.
			if handed == 0 and _free_count > 0:
				handed = _hand(pool, at, count - done, now)
		else:
			handed = _hand(pool, at, count - done, now)
		done += handed
		if done < count:
			# A region needs a chunk and none is free: make one, or take the one ending soonest.
			_one_more()


## Once a frame, at the clock time `now`, after `hand_out`: upload the chunks that changed, each
## drawing its filled rows in its region's box; hide and free those with nothing alive.
func step(now: float) -> void:
	for c in _nodes.size():
		var region: int = _region[c]
		if region < 0:
			continue
		var node: MultiMeshInstance2D = _nodes[c]
		if _live[c] <= 0 or now >= _until[c]:
			_release(c)
			continue
		if _dirty[c] == 1:
			_dirty[c] = 0
			if _boxed[c] != region:
				_boxed[c] = region
				node.multimesh.custom_aabb = _box(region)
			node.multimesh.buffer = _buffers[c]
			if node.multimesh.visible_instance_count != _fill[c]:
				node.multimesh.visible_instance_count = _fill[c]
			node.visible = _region_hidden[region] == 0


## Region `region`'s chunks drawn (`shown`) or not from now on (its chunks now at once; one taken
## later at its next upload). Its rows are copied either way, so shown again it draws as it stands.
func set_region_shown(region: int, shown: bool) -> void:
	if region < 0 or region >= _region_hidden.size() or (_region_hidden[region] == 0) == shown:
		return
	_region_hidden[region] = 0 if shown else 1
	for c in _nodes.size():
		if _region[c] == region:
			_nodes[c].visible = shown and _fill[c] > 0


## Whether region `region`'s chunks are drawn (`set_region_shown`; true for none).
func region_shown(region: int) -> bool:
	return region < 0 or region >= _region_hidden.size() or _region_hidden[region] == 0


## Every chunk hidden and free, no row copied (the places gone, or changed).
func clear() -> void:
	for c in _nodes.size():
		if _region[c] >= 0:
			_release(c)
	_slot_of.fill(-1)
	_open.fill(-1)


## The region of the row at `i` of `buffer` at the clock time `now`, the pool's kinds' numbers in
## `gravity`, `drag`, `bounce` and `wobble`: its place plus one, 0 (a crosser), or -1 for a row with
## no mote alive. The rule `MoteKernel.region_rows` follows to the bit.
func region_of(buffer: PackedFloat32Array, i: int, now: float, gravity: PackedFloat64Array, drag: PackedFloat64Array, bounce: PackedFloat64Array, wobble: PackedFloat64Array) -> int:
	var life: float = float(buffer[i + ROW_LIFE]) * LIFE_MAX
	var born: float = buffer[i + ROW_BORN]
	if life <= 0.0 or born + life <= now:
		return -1
	var x: float = buffer[i + ROW_X]
	var y: float = buffer[i + ROW_Y]
	var cx: int = floori((x - _origin.x) / PLACE_CELL)
	var cy: int = floori((y - _origin.y) / PLACE_CELL)
	if cx < 0 or cx >= _columns or cy < 0 or cy >= _lines:
		return 0
	var code: int = _whole[cy * _columns + cx]
	if code == 0 or code == PLACE_ASK or code > places:
		return 0
	var k: int = clampi(roundi(float(buffer[i + ROW_KIND]) * KIND_CODE), 0, MAX_KINDS - 1)
	if k >= gravity.size():
		return 0
	var reach: Vector2 = reach_of(buffer, i, life, gravity[k], drag[k], bounce[k], wobble[k])
	var at: int = (code - 1) * 4
	if x - reach.x < _bounds[at] or x + reach.x > _bounds[at + 2] or y - reach.x - reach.y < _bounds[at + 1] or y + reach.x > _bounds[at + 3]:
		return 0
	return code


## How far from its ground point at birth the mote of the row at `i` of `buffer`, living `life`
## seconds, of a kind of the numbers `gravity`, `drag`, `bounce` and `wobble`, may be drawn: along
## the floor each way (x; its speed times the most its drag lets it glide, its sway twice, PAD) and
## up past that (y; its height's highest: its start and its rise, or its bounce's, never above the
## rise for a bounce of 1 or less; or a gravity that lifts it). `mote.gdshader`'s `mote_flight` never
## draws it past these (a test holds every kind's flights to them).
static func reach_of(buffer: PackedFloat32Array, i: int, life: float, gravity: float, drag: float, bounce: float, wobble: float) -> Vector2:
	var vx: float = buffer[i + ROW_VX]
	var vy: float = buffer[i + ROW_VY]
	var vz: float = buffer[i + ROW_VZ]
	var h0: float = maxf(float(buffer[i + ROW_HEIGHT]) * HEIGHT_MAX, 0.0)
	var along: float = (1.0 - exp(-drag * life)) / drag if drag > 0.0 else life
	var spread: float = sqrt(vx * vx + vy * vy) * along + 2.0 * absf(wobble) + PAD
	var rise: float
	if gravity > 0.0:
		rise = (h0 + vz * vz / (2.0 * gravity)) * maxf(bounce * bounce, 1.0)
	else:
		rise = h0 + maxf(vz, 0.0) * life - 0.5 * gravity * life * life
	return Vector2(spread, rise)


## The chunk ring row `row`'s copy is in (-1 for none; for tests), and the region of chunk `c`
## (-1: free), its node and its buffer.
func chunk_of_row(row: int) -> int:
	var slot: int = _slot_of[row] if row >= 0 and row < _slot_of.size() else -1
	if slot < 0 or slot % ROWS >= _fill[slot / ROWS] or _row_of_slot[slot] != row:
		return -1
	return slot / ROWS


func region_of_chunk(c: int) -> int:
	return _region[c] if c >= 0 and c < _region.size() else -1


func node_of(c: int) -> MultiMeshInstance2D:
	return _nodes[c] if c >= 0 and c < _nodes.size() else null


func buffer_of(c: int) -> PackedFloat32Array:
	return _buffers[c] if c >= 0 and c < _buffers.size() else PackedFloat32Array()


## Chunks made, and those drawn now (for tests and the benchmarks).
func chunks_made() -> int:
	return _nodes.size()


func chunks_shown() -> int:
	var shown: int = 0
	for node in _nodes:
		if node.visible:
			shown += 1
	return shown


## The box region `region` draws in: the world for the crossers, else its place grown by REACH.
func box_of(region: int) -> AABB:
	return _box(region)


## The places of `grid` read (the first `count`): every region emptied.
func _take(grid: RoomGrid, count: int) -> void:
	clear()
	places = count
	_rects.clear()
	_bounds.resize(count * 4)
	if count > 0:
		_whole = grid.whole_places().duplicate()
		_columns = grid.place_columns()
		_lines = grid.place_rows()
		_origin = grid.place_origin()
		for place in count:
			var rect: Rect2 = grid.place_rect(place)
			_rects.append(rect)
			var grown: Rect2 = rect.grow(REACH)
			_bounds[place * 4] = grown.position.x
			_bounds[place * 4 + 1] = grown.position.y
			_bounds[place * 4 + 2] = grown.end.x
			_bounds[place * 4 + 3] = grown.end.y
	else:
		_whole = PackedByteArray()
		_columns = 0
		_lines = 0
		_origin = Vector2.ZERO
	_open.resize(count + 1)
	_open.fill(-1)
	_region_hidden.resize(count + 1)
	_region_hidden.fill(0)
	fits += 1
	# A chunk's box is set again when next written (its region's number may name another place).
	_boxed.fill(-1)


## The box of region `region`.
func _box(region: int) -> AABB:
	if region <= 0 or region > _rects.size():
		return BatchesScript.WORLD
	return BatchesScript.box_of(_rects[region - 1], REACH)


## One more free chunk: a new one while fewer than `_most` are made, else the one in use whose motes
## end soonest (its motes folded away: they are drawn no more).
func _one_more() -> void:
	if _nodes.size() < _most:
		_free[_free_count] = _make()
		_free_count += 1
		return
	var soonest: int = -1
	for c in _nodes.size():
		if _region[c] >= 0 and (soonest < 0 or _until[c] < _until[soonest]):
			soonest = c
	if soonest >= 0:
		stolen += 1
		_release(soonest)


## Chunk `c` hidden and free: its region writes into another from now on.
func _release(c: int) -> void:
	var region: int = _region[c]
	if region >= 0 and region < _open.size() and _open[region] == c:
		_open[region] = -1
	_region[c] = -1
	_fill[c] = 0
	_live[c] = 0
	_until[c] = 0.0
	_dirty[c] = 0
	_nodes[c].visible = false
	_free[_free_count] = c
	_free_count += 1


## A new chunk (free, hidden), its rows with no life: folded away.
func _make() -> int:
	var c: int = _nodes.size()
	var multimesh: MultiMesh = BatchesScript.multimesh()
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _mesh
	multimesh.instance_count = ROWS
	multimesh.visible_instance_count = 0
	var buffer := PackedFloat32Array()
	buffer.resize(ROWS * DRAW_STRIDE)
	var node := MultiMeshInstance2D.new()
	node.name = "RegionChunk%d" % c
	node.multimesh = multimesh
	# Its material before it is in the tree, so the light finds it a reader (`ViewReaders.take`).
	node.material = _material
	node.top_level = true
	node.z_index = _z
	node.visible = false
	_nodes.append(node)
	_buffers.append(buffer)
	_fill.append(0)
	_live.append(0)
	_until.append(0.0)
	_dirty.append(0)
	_region.append(-1)
	_boxed.append(-1)
	var slots: int = _row_of_slot.size()
	_row_of_slot.resize(slots + ROWS)
	for s in ROWS:
		_row_of_slot[slots + s] = -1
	_parent.add_child(node)
	return c


## `hand_out`'s rows here: from ring row `from`, up to `count` of them; stops at a row whose region
## needs a chunk while none is free. Returns how many rows were handed out.
func _hand(pool: Object, from: int, count: int, now: float) -> int:
	var ring: Array[PackedFloat32Array] = pool.get(&"_buffers")
	var ring_rows: int = _ring_rows
	var gravity: PackedFloat64Array = pool.get(&"_k_gravity")
	var drag: PackedFloat64Array = pool.get(&"_k_drag")
	var bounce: PackedFloat64Array = pool.get(&"_k_bounce")
	var wobble: PackedFloat64Array = pool.get(&"_k_wobble")
	var cap: int = _slot_of.size()
	for n in count:
		var row: int = (from + n) % cap
		# Its earlier copy folded away (a row overwritten in the ring is drawn no more).
		var old: int = _slot_of[row]
		if old >= 0:
			var oc: int = old / ROWS
			var oi: int = old % ROWS
			if oi < _fill[oc] and _row_of_slot[old] == row:
				var folded: PackedFloat32Array = _buffers[oc]
				var o: int = oi * DRAW_STRIDE
				# A copy whose mote is gone already is drawn as nothing: no upload for it.
				if float(folded[o + ROW_BORN]) + float(folded[o + ROW_LIFE]) * LIFE_MAX > now:
					folded[o + ROW_LIFE] = 0.0
					_dirty[oc] = 1
				_live[oc] -= 1
				_row_of_slot[old] = -1
			_slot_of[row] = -1
		var source: PackedFloat32Array = ring[row / ring_rows]
		var i: int = (row % ring_rows) * DRAW_STRIDE
		# A chunk of the ring never written (the whole ring handed out as the places come).
		if i + DRAW_STRIDE > source.size():
			continue
		var region: int = region_of(source, i, now, gravity, drag, bounce, wobble)
		if region < 0:
			continue
		var c: int = _open[region]
		if c < 0 or _fill[c] >= ROWS:
			if _free_count == 0:
				return n
			_free_count -= 1
			c = _free[_free_count]
			_open[region] = c
			_region[c] = region
			_fill[c] = 0
			_live[c] = 0
			_until[c] = 0.0
		var at: int = _fill[c]
		_fill[c] = at + 1
		var into: PackedFloat32Array = _buffers[c]
		var to: int = at * DRAW_STRIDE
		for f in DRAW_STRIDE:
			into[to + f] = source[i + f]
		var slot: int = c * ROWS + at
		_slot_of[row] = slot
		_row_of_slot[slot] = row
		_live[c] += 1
		_until[c] = maxf(_until[c], float(source[i + ROW_BORN]) + float(source[i + ROW_LIFE]) * LIFE_MAX)
		_dirty[c] = 1
	return count
