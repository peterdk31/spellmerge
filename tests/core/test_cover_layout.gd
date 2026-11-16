extends "res://tests/support/suite.gd"
## Where a room's ground cover grows (ground cover GC2, docs/milestones/ground-cover.md, rule 1):
## `CoverLayout.of` works out the same cover every time, from the game's reading and the editor's
## (a layout built as Flow builds it and the scene as saved; the kinds from the registry autoload and from its
## editor scan; the data classes the editor calls are editor scripts); no cover lies under a wall or on a door, a spawn or a placement; the fill keeps its
## gaps; a field overrides the fill and one of no kind clears it; a room with the fill off or with no
## biome has only its fields. The cover kinds are a test grass (tests/core/fixtures/cover_content),
## made to fill the real rooms' biomes, so the rooms are covered whether or not the game has cover yet.
##
## godot --headless --path . --script res://tests/core/test_cover_layout.gd

const RegistryScript := preload("res://core/registry/registry.gd")
const FIXTURE_ROOT: String = "res://tests/core/fixtures/cover_content"
const GRASS: CoverKind = preload("res://tests/core/fixtures/cover_content/cover/test_grass/test_grass.tres")
var KNOWN: Dictionary = {
	&"element": PackedStringArray(["fire", "frost", "lightning", "mend", "storm", "void"]),
	&"status": PackedStringArray(["burn", "chill", "gust", "hex", "static"]),
}

## The hash of the test layout's cells with the test grass at 0.05 (`test_hash4_is_the_engines_hash_of_its_keys`).
const PINNED_CELLS: int = 33864800

var _registry: RegistryScript


func before_each() -> void:
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()


func _rooms() -> Array[RoomBase]:
	var found: Array[RoomBase] = []
	for item: Resource in _registry.get_all(&"rooms"):
		if item is RoomBase:
			found.append(item as RoomBase)
	return found


## The test grass made to fill `biome`, with its numbers.
func _grass(biome: StringName, density: float = 0.08, clump: int = 2, wall_gap: int = 1, keep_gap: int = 1, kind_id: StringName = &"test_grass") -> CoverKind:
	var kind := GRASS.duplicate() as CoverKind
	kind.id = kind_id
	kind.biomes = [biome] as Array[StringName]
	kind.fill_density = density
	kind.clump_size = clump
	kind.wall_gap = wall_gap
	kind.keep_gap = keep_gap
	return kind


## A room of no scene, of `biome`, named `id` (its layout made by the test).
func _room(id: StringName, biome: StringName = &"test_meadow", fill: bool = true) -> RoomBase:
	var room := RoomBase.new()
	room.id = id
	room.biome = biome
	room.cover_fill = fill
	return room


## A layout 640×384 (40×24 cells): walls round the edge a tile thick, one pillar at (320, 160) a tile
## square, a player spawn at (100, 100), a door at (40, 176) and a placement at (500, 250).
func _layout() -> Node2D:
	var layout := own(Node2D.new()) as Node2D
	var walls := StaticBody2D.new()
	walls.collision_layer = RoomBase.WALL_LAYER
	layout.add_child(walls)
	for box: Rect2 in [Rect2(0, 0, 640, 32), Rect2(0, 352, 640, 32), Rect2(0, 0, 32, 384), Rect2(608, 0, 32, 384), Rect2(320, 160, 32, 32)]:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = box.size
		shape.shape = rect
		shape.position = box.get_center()
		walls.add_child(shape)
	for holder: Array in [["PlayerSpawns", Vector2(100, 100)], ["Doors", Vector2(40, 176)]]:
		var node := Node2D.new()
		node.name = holder[0]
		layout.add_child(node)
		var marker := Marker2D.new()
		marker.position = holder[1]
		node.add_child(marker)
	var stand_in := PropStandIn.new()
	stand_in.prop = PropBase.new()
	stand_in.position = Vector2(500, 250)
	layout.add_child(stand_in)
	return layout


## A cover field of `kind_id` at `density` over `rect`, in `layout`.
func _field(layout: Node, rect: Rect2, kind_id: StringName, density: float = 1.0) -> CoverField:
	var field := CoverField.new()
	field.kind = kind_id
	field.density = density
	field.offset_left = rect.position.x
	field.offset_top = rect.position.y
	field.offset_right = rect.end.x
	field.offset_bottom = rect.end.y
	layout.add_child(field)
	return field


func _cells_in(cover: CoverLayout, rect: Rect2) -> PackedInt32Array:
	var found := PackedInt32Array()
	for cell in cover.cells.size():
		if rect.has_point(cover.cell_rect(cell).get_center()):
			found.append(cell)
	return found


func test_the_test_grass_is_sound_and_a_broken_kind_is_named() -> void:
	check_equal(GRASS.problems(KNOWN), PackedStringArray(), "the test grass has no problems")
	check_equal(GRASS.state_at(&"burning"), 1, "its states by name")
	check_equal(GRASS.states[0].on_element(&"fire"), &"burning", "fire lights it at rest")
	check_equal(GRASS.states[1].on_element(&"frost"), &"rest", "frost puts it out")
	check(GRASS.states[0].listens_to_elements() and not CoverState.make(&"bare").listens_to_elements(), "which states hear elements")
	var broken := CoverKind.new()
	broken.states = [CoverState.make(&"rest", [CoverTrigger.make(CoverTrigger.When.ELEMENT, &"nowhere", &"fire"), CoverTrigger.make(CoverTrigger.When.AFTER, &"rest")] as Array[CoverTrigger]), CoverState.make(&"rest")] as Array[CoverState]
	broken.states[0].status = &"soggy"
	broken.states[0].spreads = &"fire"
	var problems: String = "\n".join(broken.problems(KNOWN))
	for line: String in ["no id", "two states are named 'rest'", "'nowhere'", "after waits 0", "'soggy'", "with no chance"]:
		check(problems.contains(line), "a broken kind's problems name %s:\n%s" % [line, problems])
	var sheeted := GRASS.duplicate(true) as CoverKind
	sheeted.sheet = ImageTexture.create_from_image(Image.create_empty(96, 16, false, Image.FORMAT_RGBA8))
	sheeted.states[0].trampled_frames = PackedInt32Array([5, 6])
	check("\n".join(sheeted.problems(KNOWN)).contains("draws frame 6 trampled"), "a trampled frame its sheet lacks is named")


## The editor finds the kinds without the autoload (`scan_folder`), as the autoload does.
func test_the_editor_scan_finds_the_kinds_the_registry_does() -> void:
	var scanned: Array[Resource] = RegistryScript.scan_folder(&"cover", FIXTURE_ROOT)
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan(FIXTURE_ROOT)
	check_equal(scanned.size(), 1, "the editor's scan finds the test grass")
	check_equal(scanned, registry.get_all(&"cover"), "the same kinds, in the same order, as the registry")
	check(scanned.size() == 1 and (scanned[0] as CoverKind).id == &"test_grass", "by its id")
	check(RegistryScript.scan_folder(&"nothing_here", FIXTURE_ROOT).is_empty(), "a folder there is not: nothing")
	# The game's own cover folder reads the same both ways too.
	check_equal(RegistryScript.scan_folder(&"cover"), _registry.get_all(&"cover"), "the game's cover kinds, both ways")


## Every room's cover, worked out again and again, from a fresh build each time and with the kinds in
## any order: the same cells. The game's reading (a layout built with the run's chance, as Flow builds
## it) and the saved scene's (as the editor holds it) agree.
func test_the_same_layout_every_time_by_the_games_and_the_saved_scenes_reading() -> void:
	check(_rooms().size() >= 3, "the rooms are found")
	var sim := Sim.new()
	# The game's own kinds too, which the rooms' fields name (GC8).
	var own_kinds: Array[CoverKind] = []
	for item: Resource in _registry.get_all(&"cover"):
		if item is CoverKind:
			own_kinds.append(item as CoverKind)
	for room in _rooms():
		var kinds: Array[CoverKind] = [_grass(room.biome if room.biome != &"" else &"none", 0.1), _grass(room.biome if room.biome != &"" else &"none", 0.05, 3, 0, 0, &"test_moss")]
		kinds.append_array(own_kinds)
		var backwards: Array[CoverKind] = kinds.duplicate()
		backwards.reverse()
		var game_layout: Node = own(room.build(sim))
		var editor_layout: Node = own(room.scene.instantiate())
		var game: CoverLayout = CoverLayout.of(game_layout, room, kinds)
		var editor: CoverLayout = CoverLayout.of(editor_layout, room, backwards)
		var again: CoverLayout = CoverLayout.of(game_layout, room, kinds)
		check_equal(game.cells, editor.cells, "%s: the game's and the saved scene's cover agree" % room.id)
		check_equal(game.cells, again.cells, "%s: the same cover read twice" % room.id)
		check_equal([game.columns, game.rows], [ceili(room.places().size.x / 16.0), ceili(room.places().size.y / 16.0)], "%s: a cell each 16 px of the room" % room.id)
		check_equal(game.problems(), PackedStringArray(), "%s: its cover has no problems" % room.id)
		if room.biome != &"" and room.cover_fill:
			check(game.count() > 0, "%s: its biome's kinds fill it" % room.id)
		else:
			check_equal(game.count(), 0, "%s: a room of no biome has no fill" % room.id)


## Fill as thick as can be and a field over the whole room: still nothing under a wall, on a door, a
## spawn or a placement, in every room.
func test_no_cover_on_a_wall_a_door_a_spawn_or_a_placement() -> void:
	for room in _rooms():
		var layout: Node = own(room.build())
		var places: RoomPlaces = RoomPlaces.read(layout)
		var biome: StringName = room.biome if room.biome != &"" else &"none"
		for crowded in [false, true]:
			if crowded:
				_field(layout, Rect2(Vector2(-64, -64), places.size + Vector2(128, 128)), &"test_grass")
			var cover: CoverLayout = CoverLayout.of(layout, room, [_grass(biome, 1.0, 4, 0, 0)] as Array[CoverKind])
			var where: String = "%s%s" % [room.id, ", under a field" if crowded else ""]
			for wall: Rect2 in RoomPlaces.wall_rects(layout):
				var inside: Rect2 = wall.intersection(Rect2(Vector2.ZERO, places.size))
				if inside.size.x <= 0.0 or inside.size.y <= 0.0:
					continue
				for cell in cover.cells.size():
					if cover.cells[cell] != 0 and cover.cell_rect(cell).intersects(inside):
						check(false, "%s: cell %d is covered under the wall %s" % [where, cell, wall])
						break
			for list: PackedVector2Array in [places.player_spawns, places.enemy_spawns, places.doors, places.joiner_spawns, places.placed_at]:
				for at in list:
					check(cover.kind_at(cover.cell_of(at)) == null, "%s: nothing covers the spawn, door or placement at %s" % [where, at])
			if room.biome != &"":
				check(cover.count() > 0, "%s: something is covered" % where)


func test_the_fill_keeps_its_gaps_from_walls_and_places() -> void:
	var layout: Node2D = _layout()
	var cover: CoverLayout = CoverLayout.of(layout, _room(&"gaps"), [_grass(&"test_meadow", 1.0, 4, 2, 3)] as Array[CoverKind])
	check(cover.count() > 0, "a full fill covers the open floor")
	for cell in cover.cells.size():
		if cover.cells[cell] == 0:
			continue
		var x: int = cell % cover.columns
		var y: int = cell / cover.columns
		# The edge walls are 2 cells thick, the pillar's cells (20, 10) to (21, 11).
		check(x >= 4 and y >= 4 and x <= cover.columns - 5 and y <= cover.rows - 5, "cell (%d, %d) keeps 2 cells from the edge walls" % [x, y])
		check(not (x >= 18 and x <= 23 and y >= 8 and y <= 13), "cell (%d, %d) keeps 2 cells from the pillar" % [x, y])
		for at: Vector2 in [Vector2(100, 100), Vector2(40, 176), Vector2(500, 250)]:
			var px: int = int(at.x) / CoverLayout.CELL
			var py: int = int(at.y) / CoverLayout.CELL
			check(maxi(absi(x - px), absi(y - py)) > 3, "cell (%d, %d) keeps 3 cells from the place at %s" % [x, y, at])
	var close: CoverLayout = CoverLayout.of(layout, _room(&"gaps"), [_grass(&"test_meadow", 1.0, 4, 0, 0)] as Array[CoverKind])
	check(close.count() > cover.count(), "no gaps: it grows up to the walls and places")
	check(close.kind_at(close.cell_of(Vector2(40, 40))) != null, "right beside the corner wall")


## A field over the fill decides its cells: its kind (at its density), or none for a field of no kind;
## the fill outside it stays as it was.
func test_a_field_overrides_the_fill_and_one_of_no_kind_clears_it() -> void:
	var kinds: Array[CoverKind] = [_grass(&"test_meadow", 1.0, 4, 0, 0), _grass(&"", 0.0, 0, 0, 0, &"test_moss")]
	var bare: CoverLayout = CoverLayout.of(_layout(), _room(&"fields"), kinds)
	var layout: Node2D = _layout()
	var moss_rect := Rect2(64, 64, 128, 64)
	var clear_rect := Rect2(400, 64, 96, 96)
	_field(layout, moss_rect, &"test_moss")
	_field(layout, clear_rect, &"")
	var cover: CoverLayout = CoverLayout.of(layout, _room(&"fields"), kinds)
	check_equal(cover.problems(), PackedStringArray(), "no problems")
	for cell in _cells_in(cover, moss_rect):
		if cover.blocked[cell] == 0:
			check(cover.kind_at(cell) != null and cover.kind_at(cell).id == &"test_moss", "cell %d: the moss field's" % cell)
	check(cover.kind_at(cover.cell_of(Vector2(100, 100))) == null, "the spawn in the field is still bare")
	for cell in _cells_in(cover, clear_rect):
		check(cover.kind_at(cell) == null, "cell %d: cleared" % cell)
	var outside: int = cover.cell_of(Vector2(300, 260))
	check(bare.kind_at(outside) != null and cover.kind_at(outside) == bare.kind_at(outside), "outside the fields, the fill as it was")
	# A later field over an earlier one: the later decides.
	_field(layout, Rect2(64, 64, 64, 64), &"")
	var later: CoverLayout = CoverLayout.of(layout, _room(&"fields"), kinds)
	check(later.kind_at(later.cell_of(Vector2(72, 72))) == null and later.kind_at(later.cell_of(Vector2(150, 72))).id == &"test_moss", "fields in the tree's order, the later over the earlier")


func test_a_fields_density_and_an_unknown_kind() -> void:
	var layout: Node2D = _layout()
	var rect := Rect2(400, 192, 192, 112)
	_field(layout, rect, &"test_grass", 0.5)
	_field(layout, Rect2(64, 200, 64, 64), &"no_such_cover")
	var cover: CoverLayout = CoverLayout.of(layout, _room(&"dense", &"test_meadow", false), [_grass(&"other")] as Array[CoverKind])
	var cells: PackedInt32Array = _cells_in(cover, rect)
	var covered: int = 0
	for cell in cells:
		if cover.kind_at(cell) != null:
			covered += 1
	check(covered > cells.size() / 4 and covered < cells.size() * 3 / 4, "about half of a half-dense field is covered (%d of %d)" % [covered, cells.size()])
	check_equal(cover.problems().size(), 1, "a field of a kind there is none of is named")
	check(cover.problems().size() == 1 and cover.problems()[0].contains("no_such_cover"), "by its kind")
	check(_cells_in(cover, Rect2(64, 200, 64, 64)).size() > 0 and cover.kind_at(cover.cell_of(Vector2(80, 220))) == null, "and puts nothing")


func test_a_room_with_the_fill_off_has_only_its_fields() -> void:
	var kinds: Array[CoverKind] = [_grass(&"test_meadow", 1.0, 4, 0, 0)]
	var layout: Node2D = _layout()
	var rect := Rect2(64, 192, 128, 96)
	_field(layout, rect, &"test_grass")
	var off: CoverLayout = CoverLayout.of(layout, _room(&"off", &"test_meadow", false), kinds)
	var fields: int = 0
	for cell in _cells_in(off, rect):
		if off.blocked[cell] == 0:
			fields += 1
	check(fields > 0 and off.count() == fields, "the fill off: only the field is covered (%d of %d)" % [off.count(), fields])
	var none: CoverLayout = CoverLayout.of(layout, _room(&"elsewhere", &"another_biome"), kinds)
	check_equal(none.count(), fields, "a kind of another biome fills nothing")
	var no_biome: CoverLayout = CoverLayout.of(layout, _room(&"nowhere", &""), kinds)
	check_equal(no_biome.count(), fields, "a room of no biome is filled by nobody")


## The clumps are the room's and the kind's: another room or another kind, other clumps; a kind never
## covers the cell of another that filled it first (kinds in id order).
func test_the_clumps_are_keyed_by_room_and_kind() -> void:
	var one: CoverLayout = CoverLayout.of(_layout(), _room(&"room_one"), [_grass(&"test_meadow", 0.05)] as Array[CoverKind])
	var two: CoverLayout = CoverLayout.of(_layout(), _room(&"room_two"), [_grass(&"test_meadow", 0.05)] as Array[CoverKind])
	var other: CoverLayout = CoverLayout.of(_layout(), _room(&"room_one"), [_grass(&"test_meadow", 0.05, 2, 1, 1, &"test_other")] as Array[CoverKind])
	check(one.count() > 0 and one.cells != two.cells, "another room, other clumps")
	check(one.cells != other.cells, "another kind, other clumps")
	var both: CoverLayout = CoverLayout.of(_layout(), _room(&"room_one"), [_grass(&"test_meadow", 0.05, 2, 1, 1, &"b_second"), _grass(&"test_meadow", 0.05, 2, 1, 1, &"a_first")] as Array[CoverKind])
	check_equal(both.kinds[0].id, &"a_first", "the kinds in id order")
	var first_alone: CoverLayout = CoverLayout.of(_layout(), _room(&"room_one"), [_grass(&"test_meadow", 0.05, 2, 1, 1, &"a_first")] as Array[CoverKind])
	var kept: bool = true
	for cell in both.cells.size():
		if first_alone.cells[cell] != 0 and both.kind_at(cell).id != &"a_first":
			kept = false
	check(first_alone.count() > 0 and kept, "every cell the first kind fills alone it keeps beside the second")
	check(both.count() > first_alone.count(), "the second fills more of what is left")


func test_hash4_is_the_engines_hash_of_its_keys() -> void:
	# Pinned: an engine that hashes otherwise would lay every room's cover out anew (and the cover
	# area's cells, GC5), so a change of engine must show here.
	check_equal(CoverLayout.hash4(1, 2, 3, 4), 3206438488, "the engine's hash of a Vector4i, pinned")
	check_equal(CoverLayout.name_hash(&"grass"), 260508453, "a name's hash, pinned")
	var pinned: CoverLayout = CoverLayout.of(_layout(), _room(&"pinned"), [_grass(&"test_meadow", 0.05)] as Array[CoverKind])
	check_equal(hash(pinned.cells), PINNED_CELLS, "a fixed room's cover, pinned")
	var keys: Array[int] = [CoverLayout.hash4(1, 2, 3, 4), CoverLayout.hash4(9, 2, 3, 4), CoverLayout.hash4(1, 9, 3, 4), CoverLayout.hash4(1, 2, 9, 4), CoverLayout.hash4(1, 2, 3, 9)]
	for i in keys.size():
		check(keys.find(keys[i]) == i, "each key changes it (%d)" % i)
	check_equal(CoverLayout.name_hash(&"grass"), "grass".hash(), "a name enters as its string's hash")
	check(CoverLayout.rolls(1.0, 1, 2, 3, 4) and not CoverLayout.rolls(0.0, 1, 2, 3, 4), "a sure roll and an impossible one")


func test_cells_and_places() -> void:
	var cover: CoverLayout = CoverLayout.of(_layout(), _room(&"cells", &""), [] as Array[CoverKind])
	check_equal([cover.columns, cover.rows], [40, 24], "640×384: 40×24 cells")
	check_equal(cover.cell_of(Vector2(17, 33)), 2 * 40 + 1, "a pixel's cell")
	check_equal(cover.cell_of(Vector2(-1, 5)), -1, "outside: none")
	check_equal(cover.cell_rect(2 * 40 + 1), Rect2(16, 32, 16, 16), "a cell's rectangle")
	check_equal(cover.blocked[cover.cell_of(Vector2(330, 170))], CoverLayout.BLOCKED_WALL, "the pillar's cell is a wall's")
	check_equal(cover.blocked[cover.cell_of(Vector2(100, 100))], CoverLayout.BLOCKED_POINT, "the spawn's cell is a place's")
	check_equal(cover.blocked[cover.cell_of(Vector2(200, 100))], 0, "open floor")


## The data classes the editor calls (its cover preview, GC3) are editor scripts: a resource whose
## script is not one loads in the editor as a placeholder, whose methods cannot be called.
func test_the_cover_data_is_editor_scripts() -> void:
	for path: String in ["res://core/base/cover_kind.gd", "res://core/base/cover_state.gd", "res://core/base/cover_trigger.gd", "res://core/base/cover_patch.gd", "res://core/base/cover_field.gd", "res://core/base/room_zone.gd"]:
		check((load(path) as Script).is_tool(), "%s is an editor script (@tool)" % path)


## One clump alone in an open room: a disc of cells, dx² + dy² ≤ r² + r round its middle, of a reach
## between half the kind's clump size (rounded up) and all of it.
func test_a_clump_is_a_disc_of_its_reach() -> void:
	var layout := own(Node2D.new()) as Node2D
	for size: int in [1, 2, 3, 4]:
		var seen: int = 0
		for attempt in 40:
			var room: RoomBase = _room(StringName("disc_%d_%d" % [size, attempt]))
			var cover: CoverLayout = CoverLayout.of(layout, room, [_grass(&"test_meadow", 0.002, size, 0, 0)] as Array[CoverKind])
			var centres: Array[int] = []
			var key: int = CoverLayout.name_hash(room.id)
			for cell in cover.cells.size():
				if CoverLayout.rolls(0.002, key, CoverLayout.name_hash(&"test_grass"), cell, CoverLayout.ROLL_CLUMP):
					centres.append(cell)
			if centres.size() != 1:
				continue
			var centre: int = centres[0]
			var cx: int = centre % cover.columns
			var cy: int = centre / cover.columns
			if cx < 6 or cy < 6 or cx >= cover.columns - 6 or cy >= cover.rows - 6:
				continue
			seen += 1
			var reach: int = -1
			for r in range(0, size + 1):
				var disc: int = 0
				var matches: bool = true
				for cell in cover.cells.size():
					var dx: int = cell % cover.columns - cx
					var dy: int = cell / cover.columns - cy
					var inside: bool = dx * dx + dy * dy <= r * r + r
					if inside != (cover.cells[cell] != 0):
						matches = false
				if matches:
					reach = r
			check(reach >= (size + 1) / 2 and reach <= size, "clump size %d: a disc of reach %d" % [size, reach])
		check(seen > 0, "clump size %d: a lone clump was found" % size)


## A wall that covers part of a cell blocks it; a room's edge with no wall is still kept from; a room
## not a whole number of cells has a last, part cell.
func test_walls_and_edges_block_whole_cells() -> void:
	var layout := own(Node2D.new()) as Node2D
	var walls := StaticBody2D.new()
	walls.collision_layer = RoomBase.WALL_LAYER
	walls.position = Vector2(24, 100)
	layout.add_child(walls)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	shape.position = Vector2(8, 8)
	walls.add_child(shape)
	var cover: CoverLayout = CoverLayout.of(layout, _room(&"edges"), [_grass(&"test_meadow", 1.0, 2, 1, 0)] as Array[CoverKind])
	check_equal([cover.columns, cover.rows], [40, 23], "640×360: the last row a part cell")
	for at: Vector2 in [Vector2(20, 105), Vector2(36, 105), Vector2(20, 120), Vector2(36, 120)]:
		check_equal(cover.blocked[cover.cell_of(at)], CoverLayout.BLOCKED_WALL, "a wall over part of the cell at %s blocks it" % at)
	check_equal(cover.blocked[cover.cell_of(Vector2(50, 105))], 0, "the cell beside it is open")
	check(cover.kind_at(cover.cell_of(Vector2(4, 300))) == null and cover.kind_at(cover.cell_of(Vector2(20, 300))) != null, "the room's edge is kept from as a wall (wall_gap 1)")


## Hub rework HR-H2: a hole blocks the cover as a wall does, so no cover grows over one and a kind
## keeps its `wall_gap` from a crack's lip.
func test_no_cover_grows_over_a_hole() -> void:
	var layout := own(Node2D.new()) as Node2D
	var holes := StaticBody2D.new()
	holes.collision_layer = RoomBase.HOLE_LAYER
	layout.add_child(holes)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(32, 360)
	shape.shape = rect
	shape.position = Vector2(316, 180)
	holes.add_child(shape)
	var cover: CoverLayout = CoverLayout.of(layout, _room(&"holes"), [_grass(&"test_meadow", 1.0, 2, 1, 0)] as Array[CoverKind])
	for cell in cover.cells.size():
		if cover.cell_rect(cell).intersects(Rect2(300, 0, 32, 360)):
			check_equal(cover.blocked[cell], CoverLayout.BLOCKED_WALL, "a cell over the hole is blocked: %d" % cell)
			check(cover.kind_at(cell) == null, "and uncovered: %d" % cell)
	check(cover.kind_at(cover.cell_of(Vector2(280, 100))) == null, "a cell from its lip is kept clear (wall_gap 1)")
	check(cover.kind_at(cover.cell_of(Vector2(200, 100))) != null, "farther off, grass")
