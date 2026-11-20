extends "res://tests/support/suite.gd"
## The shots drawn by the room they are in (`DrawRegions`, core/projectiles/draw_regions.gd; the
## performance pass, 2026-11-20): every row goes to exactly one region, a room's region only when its
## square lies wholly in that room and its quad is small, so its box (the room grown by REACH) holds
## it; the native hand-out (`ShotKernel.region_counts`, `region_rows`) is the GDScript's byte for
## byte; and the projectile manager in a biome draws its shots by room (its own batch none), and as
## before with no places.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const NativeScript := preload("res://core/native/native.gd")
const DrawRegionsScript := preload("res://core/projectiles/draw_regions.gd")
const BatchesScript := preload("res://core/projectiles/batches.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const BOUNDS: Rect2 = Rect2(-40.0, -20.0, 3000.0, 2000.0)
const STRIDE: int = DrawRegionsScript.DRAW_STRIDE


func _grid() -> RoomGrid:
	var grid := RoomGrid.new()
	grid.size_to(BOUNDS)
	grid.add_place(Rect2(0.0, 0.0, 640.0, 384.0))
	grid.add_place(Rect2(704.0, 0.0, 512.0, 352.0))
	grid.add_place(Rect2(600.0, 150.0, 140.0, 64.0), true)
	grid.add_place(Rect2(100.3, 500.7, 700.0, 500.0))
	return grid


## `count` rows at seeded points over the bounds and past them, some with long quads.
func _rows(count: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	rows.resize(count * STRIDE)
	for n in count:
		var i: int = n * STRIDE
		for f in STRIDE:
			rows[i + f] = rng.randf_range(-1.0, 1.0)
		rows[i + 3] = rng.randf_range(BOUNDS.position.x - 80.0, BOUNDS.end.x + 80.0)
		rows[i + 7] = rng.randf_range(BOUNDS.position.y - 80.0, BOUNDS.end.y + 80.0)
		if n % 11 == 0:
			rows[i] = 300.0
		if n % 13 == 0:
			rows[i + 5] = -200.0
	return rows


func _batch_node() -> MultiMeshInstance2D:
	var node := own(MultiMeshInstance2D.new()) as MultiMeshInstance2D
	var multimesh: MultiMesh = BatchesScript.multimesh()
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = QuadMesh.new()
	node.multimesh = multimesh
	root.add_child(node)
	return node


func test_every_row_goes_to_one_region_whose_box_holds_it() -> void:
	var grid: RoomGrid = _grid()
	var regions := DrawRegionsScript.new()
	check(regions.fit(grid), "a grid with places draws by region")
	check_equal(regions.places, 4, "a region a place")
	var rng := RandomNumberGenerator.new()
	rng.seed = 885
	var rows: PackedFloat32Array = _rows(4000, rng)
	var node: MultiMeshInstance2D = _batch_node()
	regions.draw(0, node, rows, 4000, null)
	var total: int = 0
	for region in regions.places + 1:
		total += regions.counts[region]
	check_equal(total, 4000, "every row in one region")
	var wrong: int = 0
	for n in 4000:
		var i: int = n * STRIDE
		var region: int = regions.region_of(rows, i)
		var at := Vector2(rows[i + 3], rows[i + 7])
		if region == 0:
			continue
		var place: int = region - 1
		if grid.place_at(at) != place or absf(rows[i]) > DrawRegionsScript.SPAN_MOST or absf(rows[i + 5]) > DrawRegionsScript.SPAN_MOST:
			wrong += 1
	check_equal(wrong, 0, "a room's region holds only its own small shots")
	for region in range(1, regions.places + 1):
		var shown: MultiMeshInstance2D = regions.node_of(0, region)
		if shown == null:
			continue
		var box: AABB = shown.multimesh.custom_aabb
		var rect: Rect2 = grid.place_rect(region - 1).grow(DrawRegionsScript.REACH)
		check(box.position.is_equal_approx(Vector3(rect.position.x, rect.position.y, -1.0)) and box.size.is_equal_approx(Vector3(rect.size.x, rect.size.y, 2.0)), "region %d's box is its room's, grown by REACH" % region)
		check(shown.use_parent_material and shown.get_parent() == node, "it draws with its batch's material, under it")
		check_equal(shown.multimesh.visible_instance_count, regions.counts[region], "region %d draws its rows" % region)
	var crossers: MultiMeshInstance2D = regions.node_of(0, 0)
	check(crossers != null and crossers.multimesh.custom_aabb == BatchesScript.WORLD, "the crossers' box is the world")
	check(crossers != null and crossers.get_index() == 0, "the crossers draw first")
	# Hidden again when nothing is drawn.
	regions.draw(0, node, rows, 0, null)
	for region in regions.places + 1:
		var shown: MultiMeshInstance2D = regions.node_of(0, region)
		check(shown == null or shown.multimesh.visible_instance_count == 0, "an empty frame hides region %d" % region)


func test_the_native_hand_out_is_the_gdscripts() -> void:
	var kernel: Object = NativeScript.shot_kernel()
	if kernel == null:
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded (ci/build/native.sh)")
		return
	var grid: RoomGrid = _grid()
	for seed: int in [1, 2, 3]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var count: int = 500 * seed
		var rows: PackedFloat32Array = _rows(count, rng)
		var by_script := DrawRegionsScript.new()
		var by_kernel := DrawRegionsScript.new()
		by_script.fit(grid)
		by_kernel.fit(grid)
		by_script.draw(0, _batch_node(), rows, count, null)
		by_kernel.draw(0, _batch_node(), rows, count, kernel)
		check_equal(by_kernel.counts, by_script.counts, "seed %d: the same counts" % seed)
		for region in by_script.places + 1:
			var used: int = by_script.counts[region] * STRIDE
			check_equal(by_kernel.buffer_of(0, region).slice(0, used), by_script.buffer_of(0, region).slice(0, used), "seed %d: region %d's rows, byte for byte" % [seed, region])


func test_a_biome_draws_its_shots_by_room() -> void:
	for native: bool in [false, true]:
		if native and not NativeScript.loaded():
			continue
		var mgr: ManagerScript = own(ManagerScript.new()) as ManagerScript
		mgr.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
		mgr.events = own(EventsScript.new()) as EventsScript
		mgr.native = native
		root.add_child(mgr)
		mgr.set_cap(256)
		mgr.set_bounds(BOUNDS)
		var spots: PackedVector2Array = [Vector2(100.0, 100.0), Vector2(120.0, 90.0), Vector2(900.0, 100.0), Vector2(400.0, 700.0)]
		for at in spots:
			mgr.spawn(1, at, Vector2(1.0, 0.0), 4.0)
		mgr.update_draw(1.0)
		check_equal(mgr.drawn, 4, "the four shots are drawn")
		check_equal(_drawn_by_batches(mgr), 4, "no places: the batches draw their shots themselves")
		var grid: RoomGrid = mgr.grid()
		grid.add_place(Rect2(0.0, 0.0, 640.0, 384.0))
		grid.add_place(Rect2(704.0, 0.0, 512.0, 352.0))
		grid.add_place(Rect2(100.0, 500.0, 700.0, 500.0))
		mgr.update_draw(1.0)
		check_equal(_drawn_by_batches(mgr), 0, "a biome: the batches draw none themselves")
		check_equal(mgr.drawn, 4, "every shot is still drawn")
		var regions: DrawRegionsScript = mgr.get(&"_draw_regions")
		check_equal([_drawn_in(mgr, regions, 0), _drawn_in(mgr, regions, 1), _drawn_in(mgr, regions, 2), _drawn_in(mgr, regions, 3)], [0, 2, 1, 1], "two in the first room's batch, one in each other's")
		for batch in mgr.batch_count():
			var mirror: MultiMesh = mgr.batch_mirror(batch)
			check(mirror == null or mirror.visible_instance_count == (mgr.get(&"_draw_out") as PackedInt32Array)[ManagerScript.DRAW_OUT_FIRST + batch], "a mirror still takes them all")
		grid.clear_places()
		mgr.update_draw(1.0)
		check_equal(_drawn_by_batches(mgr), 4, "places gone: the batches draw them themselves again")
		check_equal(_drawn_in(mgr, regions, 1) + _drawn_in(mgr, regions, 2) + _drawn_in(mgr, regions, 3), 0, "and the rooms' batches none")


## Rows the batches' own nodes draw.
func _drawn_by_batches(mgr: ManagerScript) -> int:
	var sum: int = 0
	for node: MultiMeshInstance2D in mgr.get(&"_nodes"):
		sum += node.multimesh.visible_instance_count
	return sum


## Rows region `region` of every batch draws.
func _drawn_in(mgr: ManagerScript, regions: DrawRegionsScript, region: int) -> int:
	var sum: int = 0
	for batch in mgr.batch_count():
		var shown: MultiMeshInstance2D = regions.node_of(batch, region)
		if shown != null:
			sum += shown.multimesh.visible_instance_count
	return sum
