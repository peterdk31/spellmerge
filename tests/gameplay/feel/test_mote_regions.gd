extends "res://tests/support/suite.gd"
## The motes drawn by the room they fly in (`MoteRegions`, gameplay/feel/mote_regions.gd; the
## performance pass's follow-up, the owner's decision of 2026-11-20): while the room grid has places
## the ring's chunks draw nothing and each row written is copied into a chunk of its room's, boxed to
## the room grown by REACH; every flight of a room's mote stays inside that box, so a mote that
## drifts across the room's edge is still drawn; a mote at a mouth, in the void or flung far is a
## crosser (the world's box); a row the ring overwrites is folded away, so no more motes are drawn
## than the ring holds; a chunk is free once its motes are gone and is used again; with no places the
## ring draws as before; and the native hand-out (`MoteKernel.region_rows`) is the GDScript's byte
## for byte. Drawing only: the ring's rows are as they were (`test_native_motes.gd`).
const MotesScript := preload("res://gameplay/feel/mote.gd")
const MoteRegionsScript := preload("res://gameplay/feel/mote_regions.gd")
const NativeScript := preload("res://core/native/native.gd")
const BatchesScript := preload("res://core/projectiles/batches.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const BOUNDS: Rect2 = Rect2(-200.0, -200.0, 3000.0, 2000.0)
const ROOM_A: Rect2 = Rect2(0.0, 0.0, 640.0, 384.0)
const ROOM_B: Rect2 = Rect2(704.0, 0.0, 512.0, 352.0)
## A walkway over both rooms' lips (an `over` place: its squares are asked, so its motes cross).
const WALK: Rect2 = Rect2(600.0, 150.0, 140.0, 64.0)
const ROOM_C: Rect2 = Rect2(96.0, 640.0, 704.0, 448.0)
## The members of the regions compared, native against GDScript.
const ARRAYS: Array[StringName] = [&"_slot_of", &"_row_of_slot", &"_fill", &"_live", &"_until", &"_dirty", &"_region", &"_open", &"_free"]
const SCALARS: Array[StringName] = [&"_free_count", &"stolen", &"places"]


func _grid() -> RoomGrid:
	var grid := RoomGrid.new()
	grid.size_to(BOUNDS)
	grid.add_place(ROOM_A)
	grid.add_place(ROOM_B)
	grid.add_place(WALK, true)
	grid.add_place(ROOM_C)
	return grid


func _kind(id: StringName, gravity: float, speed: Vector2, drag: float) -> MoteKind:
	var kind := MoteKind.new()
	kind.id = id
	kind.gravity = gravity
	kind.bounce = 0.35
	kind.drag = drag
	kind.look_layers = PackedInt32Array([0])
	kind.speed = speed
	kind.up = Vector2(15.0, 70.0)
	kind.life = Vector2(0.6, 2.2)
	kind.spread = 360.0
	kind.height = 5.0
	return kind


func _kinds() -> Array[MoteKind]:
	var spark := _kind(&"spark", 300.0, Vector2(30.0, 110.0), 2.0)
	var ember := _kind(&"ember", -14.0, Vector2(5.0, 20.0), 1.0)
	ember.wobble = 3.0
	ember.wobble_rate = 6.0
	# Flung far with no drag: from near a wall it reaches past its room's REACH (a crosser).
	var shard := _kind(&"shard", 200.0, Vector2(150.0, 220.0), 0.0)
	return [spark, ember, shard]


func _pool(cap: int, native: bool = false, kinds: Array[MoteKind] = []) -> MotesScript:
	var motes: MotesScript = own(MotesScript.new(cap, 0, kinds if not kinds.is_empty() else _kinds())) as MotesScript
	motes.native = native
	root.add_child(motes)
	return motes


## A burst of `count` motes of kind `k` at `at` (all round, the kind's own numbers).
func _burst(motes: MotesScript, k: int, at: Vector2, count: int) -> void:
	var kind: MoteKind = motes.kinds()[k]
	motes.burst(k, at, Vector2.ZERO, count, kind.speed, 360.0, kind.up, kind.life, 0, Color.WHITE, kind.height)


## The ring's rows written last step (`count` of them, ending at the next row).
func _rows_back(motes: MotesScript, count: int) -> PackedInt32Array:
	var rows := PackedInt32Array()
	for n in count:
		rows.append(posmod(motes.next_row() - count + n, motes.cap()))
	return rows


func _ring_nodes_shown(motes: MotesScript) -> int:
	var shown: int = 0
	for child in motes.get_children():
		if child is MultiMeshInstance2D and not String(child.name).begins_with("RegionChunk") and (child as CanvasItem).visible:
			shown += 1
	return shown


func test_each_rooms_motes_are_drawn_by_a_chunk_boxed_to_its_room() -> void:
	var motes: MotesScript = _pool(4096)
	motes.use_places(_grid())
	check(motes.regions.is_on(), "a biome's motes are drawn by room")
	motes.step(0.0)
	_burst(motes, 0, ROOM_A.get_center(), 40)
	var in_a: PackedInt32Array = _rows_back(motes, 40)
	_burst(motes, 0, ROOM_B.get_center(), 30)
	var in_b: PackedInt32Array = _rows_back(motes, 30)
	_burst(motes, 1, Vector2(1800.0, 1500.0), 20)
	var in_void: PackedInt32Array = _rows_back(motes, 20)
	_burst(motes, 0, WALK.get_center(), 10)
	var on_walk: PackedInt32Array = _rows_back(motes, 10)
	motes.step(0.05)
	var regions: MoteRegionsScript = motes.regions
	for pair: Array in [[in_a, 1, "room A"], [in_b, 2, "room B"], [in_void, 0, "the void"], [on_walk, 0, "the walkway over two rooms' lips"]]:
		var rows: PackedInt32Array = pair[0]
		var wrong: int = 0
		for row in rows:
			var c: int = regions.chunk_of_row(row)
			if c < 0 or regions.region_of_chunk(c) != int(pair[1]):
				wrong += 1
				continue
			# Its copy is its row, byte for byte.
			var copy: PackedFloat32Array = regions.buffer_of(c)
			var at: int = (regions.get(&"_slot_of") as PackedInt32Array)[row] % MoteRegionsScript.ROWS * MoteRegionsScript.DRAW_STRIDE
			if copy.slice(at, at + MoteRegionsScript.DRAW_STRIDE) != motes.row_data(row):
				wrong += 1
		check_equal(wrong, 0, "every mote of %s is copied whole into a chunk of its region" % pair[2])
	var c_a: int = regions.chunk_of_row(in_a[0])
	var node: MultiMeshInstance2D = regions.node_of(c_a)
	check(node.visible and node.material == motes.draw_material(), "a room's chunk is drawn, with the motes' material")
	check_equal(node.multimesh.custom_aabb, BatchesScript.box_of(ROOM_A, MoteRegionsScript.REACH), "boxed to its room grown by REACH")
	check_equal(node.multimesh.visible_instance_count, 40, "drawing only its filled rows")
	check_equal(regions.node_of(regions.chunk_of_row(in_void[0])).multimesh.custom_aabb, BatchesScript.WORLD, "the crossers are boxed to the world")
	check_equal(_ring_nodes_shown(motes), 0, "the ring's chunks draw nothing")
	check_equal(motes.chunks_shown(), 3, "one chunk a region that has motes")


func test_every_flight_of_a_rooms_mote_stays_in_its_rooms_box() -> void:
	var registry: RegistryScript = own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var kinds: Array[MoteKind] = []
	for found: Resource in registry.get_all(&"motes"):
		if found is MoteKind and (found as MoteKind).problems().is_empty():
			kinds.append(found)
	check(kinds.size() > 10, "the game's mote kinds")
	var motes: MotesScript = _pool(32768, false, kinds)
	motes.frame_rows = 4096
	var grid: RoomGrid = _grid()
	motes.use_places(grid)
	motes.step(0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	# Bursts all over the rooms, near their walls most of all, of every kind.
	for n in 1500:
		var k: int = n % motes.kinds().size()
		var room: Rect2 = [ROOM_A, ROOM_B, ROOM_C][n % 3]
		var at := Vector2(rng.randf_range(room.position.x, room.end.x), rng.randf_range(room.position.y, room.end.y))
		if n % 2 == 0:
			at.x = room.position.x + rng.randf_range(0.0, 40.0) if rng.randf() < 0.5 else room.end.x - rng.randf_range(0.0, 40.0)
		var kind: MoteKind = motes.kinds()[k]
		motes.burst(k, at, Vector2.from_angle(rng.randf() * TAU), 2, kind.speed, kind.spread, kind.up, kind.life, 0, Color.WHITE, kind.height)
	var written: int = motes.next_row()
	motes.step(0.01)
	var regions: MoteRegionsScript = motes.regions
	var by_room: int = 0
	var crossers: int = 0
	var outside: int = 0
	for row in written:
		var c: int = regions.chunk_of_row(row)
		check(c >= 0, "row %d is drawn" % row)
		if c < 0:
			continue
		var region: int = regions.region_of_chunk(c)
		if region == 0:
			crossers += 1
			continue
		by_room += 1
		var box_3d: AABB = regions.box_of(region)
		var box := Rect2(box_3d.position.x, box_3d.position.y, box_3d.size.x, box_3d.size.y)
		var data: PackedFloat32Array = motes.row_data(row)
		var born: float = data[MotesScript.ROW_BORN]
		var life: float = data[MotesScript.ROW_LIFE] * MotesScript.LIFE_MAX
		for step in 25:
			var at: Vector3 = motes.mote_at(row, born + life * float(step) / 24.0)
			# Its pixels, its glow and the stirs reach this far round where it is drawn.
			var seen := Rect2(at.x, at.y - at.z, 0.0, 0.0).grow(18.0)
			if not box.encloses(seen):
				outside += 1
	check(by_room > 2000, "most motes are drawn by their room (%d)" % by_room)
	check(crossers > 0, "a mote flung far from near a wall crosses (%d)" % crossers)
	check_equal(outside, 0, "no room's mote is ever drawn outside its room's box")


func test_a_row_overwritten_in_the_ring_is_folded_away() -> void:
	var motes: MotesScript = _pool(2048)
	motes.use_places(_grid())
	var now: float = 0.0
	motes.step(now)
	# Long-lived motes, more than the ring holds, in two rooms.
	for frame in 16:
		_burst(motes, 1, ROOM_A.get_center() if frame % 2 == 0 else ROOM_C.get_center(), 200)
		now += 0.01
		motes.step(now)
	check_equal(motes.written, 3200, "more motes than the ring holds")
	var regions: MoteRegionsScript = motes.regions
	var drawn: int = 0
	var made: int = regions.chunks_made()
	for c in made:
		if regions.region_of_chunk(c) < 0:
			continue
		var buffer: PackedFloat32Array = regions.buffer_of(c)
		for r in regions.node_of(c).multimesh.visible_instance_count:
			if buffer[r * MoteRegionsScript.DRAW_STRIDE + MoteRegionsScript.ROW_LIFE] > 0.0:
				drawn += 1
	check_equal(drawn, motes.cap(), "no more motes drawn than the ring holds")
	var copied: int = 0
	for row in motes.cap():
		if regions.chunk_of_row(row) >= 0:
			copied += 1
	check_equal(copied, motes.cap(), "each row of the ring has one copy")


func test_a_chunk_is_free_once_its_motes_are_gone_and_used_again() -> void:
	var motes: MotesScript = _pool(4096)
	motes.use_places(_grid())
	motes.step(0.0)
	_burst(motes, 0, ROOM_A.get_center(), 60)
	motes.step(0.05)
	check_equal(motes.chunks_shown(), 1, "a chunk drawn while its motes live")
	check_equal([motes.regions.rows_drawn(), motes.regions.rows_alive(motes.clock())], [60, 60], "its rows drawn, each mote alive")
	check_equal([motes.regions.rows_drawn(), motes.regions.rows_alive(motes.clock() + MotesScript.LIFE_MAX)], [60, 0], "the rows are drawn until the chunk is free, though their motes are gone by then")
	motes.step(0.05 + MotesScript.LIFE_MAX)
	check_equal(motes.chunks_shown(), 0, "hidden once they are gone")
	var made: int = motes.regions.chunks_made()
	_burst(motes, 0, ROOM_B.get_center(), 60)
	motes.step(0.1 + MotesScript.LIFE_MAX)
	check_equal(motes.chunks_shown(), 1, "a new room's motes drawn")
	check_equal(motes.regions.chunks_made(), made, "by the chunk freed, not a new one")


func test_with_no_places_the_ring_draws_as_before() -> void:
	var motes: MotesScript = _pool(4096)
	motes.use_places(null)
	motes.step(0.0)
	_burst(motes, 0, ROOM_A.get_center(), 50)
	var rows: PackedInt32Array = _rows_back(motes, 50)
	motes.step(0.05)
	check(not motes.regions.is_on(), "no places: not by room")
	check_equal(_ring_nodes_shown(motes), 1, "the ring's chunk draws its motes")
	check_equal(motes.regions.chunks_made(), 0, "and no room's chunk is made")
	# The places come: the motes alive are handed to their rooms at the next step.
	motes.use_places(_grid())
	motes.step(0.1)
	check_equal(_ring_nodes_shown(motes), 0, "a biome: the ring draws nothing")
	check(motes.regions.chunk_of_row(rows[0]) >= 0 and motes.regions.chunk_of_row(rows[49]) >= 0, "the motes alive are drawn by their room")
	# And gone again: the ring draws them.
	motes.use_places(null)
	motes.step(0.15)
	check_equal(motes.regions.chunks_shown(), 0, "the rooms' chunks hidden")
	check_equal(_ring_nodes_shown(motes), 1, "the ring draws again")


func test_the_native_hand_out_is_the_gdscripts_byte_for_byte() -> void:
	if not NativeScript.loaded():
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
		return
	var a: MotesScript = _pool(3072, true)
	var b: MotesScript = _pool(3072, false)
	check(a.get(&"_kernel") != null and b.get(&"_kernel") == null, "one side native, one GDScript")
	# Few chunks, so a region takes one in use (`stolen`).
	for side: MotesScript in [a, b]:
		side.regions.set(&"_most", 7)
		side.use_places(_grid())
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var now: float = 0.0
	for frame in 60:
		var at: Array[Vector2] = []
		for n in 6:
			at.append(Vector2(rng.randf_range(BOUNDS.position.x, BOUNDS.end.x * 0.4), rng.randf_range(BOUNDS.position.y, BOUNDS.end.y * 0.6)))
		for side: MotesScript in [a, b]:
			for n in 6:
				_burst(side, n % 3, at[n], 40)
		if frame == 30:
			# The places change (another biome): the whole ring is handed out again.
			var other := RoomGrid.new()
			other.size_to(BOUNDS)
			other.add_place(Rect2(0.0, 0.0, 900.0, 900.0))
			for side: MotesScript in [a, b]:
				side.use_places(other)
		now += 0.05
		for side: MotesScript in [a, b]:
			side.step(now)
		if not _same(a.regions, b.regions, "frame %d" % frame):
			return
	check(a.regions.stolen > 0, "a chunk was taken while every one was in use (%d)" % a.regions.stolen)


func _same(a: MoteRegionsScript, b: MoteRegionsScript, when: String) -> bool:
	for name in ARRAYS:
		if a.get(name) != b.get(name):
			check(false, "%s: %s differs" % [when, name])
			return false
	for name in SCALARS:
		if a.get(name) != b.get(name):
			check(false, "%s: %s native %s, GDScript %s" % [when, name, a.get(name), b.get(name)])
			return false
	if a.chunks_made() != b.chunks_made():
		check(false, "%s: chunks made %d, %d" % [when, a.chunks_made(), b.chunks_made()])
		return false
	for c in a.chunks_made():
		if a.buffer_of(c) != b.buffer_of(c):
			check(false, "%s: chunk %d's rows differ" % [when, c])
			return false
	return true
