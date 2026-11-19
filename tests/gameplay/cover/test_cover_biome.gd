extends "res://tests/support/suite.gd"
## A cover a room (connected biomes CB3b, docs/milestones/connected-biomes.md), on the real autoloads:
## a biome started by Flow (`start_biome`, the split test map: the nave the start room, the
## antechamber west and the ossuary court east, tests/support/biome_maps.gd) under a stand-in grass
## that fills the crypt (tests/support/stand_in_grass.gd), so every room has cover that burns and
## spreads. Every room's cover plays at its place (a fire lit there burns there, Feel draws it there,
## a body standing in it is burnt); a mirrored room's cover is its template's mirrored, cell by cell
## and pixel by pixel, and its tufts stand in the room; fires in two rooms play the same twice and
## through a snapshot; a sleeping room's fire waits as if no time had passed, against one that never
## slept. What laying a biome's cover costs is printed.
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const CoverScript := preload("res://gameplay/cover/cover.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const CoverViewScript := preload("res://gameplay/feel/cover.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const StandInGrass := preload("res://tests/support/stand_in_grass.gd")
const DT: float = 1.0 / 60.0
const BURNING: int = 1
## The run's seed (a biome's run takes no replay's: the same in every play).
const RUN_SEED: int = 0x0c0f_e3b5
## The ticks the fires play, and the tick the snapshot is taken after.
const TICKS: int = 150
const SNAPSHOT_AT: int = 60

var flow: FlowScript
var events: Node
var tick: TickScript
var input: Node
var frames: Node
var registry: Node
var actors: Node
var cover: CoverScript
var feel: FeelScript
var grass: CoverKind = null
var _statuses: Array = []


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	events = root.get_node("Events")
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	frames = root.get_node("Frames")
	registry = root.get_node("Registry")
	actors = root.get_node("Actors")
	cover = root.get_node("Cover") as CoverScript
	feel = root.get_node("Feel") as FeelScript
	grass = StandInGrass.make([&"crypt"] as Array[StringName], 0.3, 3)
	cover.use_kinds([grass] as Array[CoverKind])
	feel.cover().use_kinds([grass] as Array[CoverKind])
	_statuses.clear()
	events.connect("status_requested", _on_status)
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)


func after_each() -> void:
	events.disconnect("status_requested", _on_status)
	_stop()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	cover.use_kinds(null)
	feel.cover().use_kinds(null)


func _on_status(_caster: int, target: Node, status: StringName, _duration: float, _strength: float) -> void:
	_statuses.append([target, status])


## The split map started with `players` seats standing where they were stood (the nave), its rooms
## mirrored by `mirrors` (the antechamber's, the nave's and the court's), no fights, the run's seed
## fixed.
func _start(players: int, mirrors: Array[int] = [0, 0, 0]) -> BiomeMap:
	var map: BiomeMap = BiomeMaps.split(registry, mirrors)
	for seat in players:
		input.add_virtual_device(seat)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
	check(flow.start_biome(0, map, fights), "the biome starts")
	tick.sim.run_seed = RUN_SEED
	return map


func _stop() -> void:
	flow.stop_run()
	for seat in 4:
		frames.call("set_source", seat, null)
		input.leave(seat)
	tick.begin_run()


func _ticks(count: int) -> void:
	for _i in count:
		tick.run(DT)


## The covered cell of room `room` nearest its grid's middle (in cell order from there).
func _covered(room: int) -> int:
	var laid: CoverLayout = cover.layout_of(room)
	var middle: int = (laid.rows / 2) * laid.columns + laid.columns / 2
	for at in laid.cells.size():
		var cell: int = (middle + at) % laid.cells.size()
		if laid.cells[cell] != 0:
			return cell
	return -1


## A fire touched at the middle of cell `cell` of room `room`, `radius` round it.
func _light(room: int, cell: int, radius: float = 0.0) -> void:
	events.emit_signal("floor_touched", -1, &"fire", cover.layout_of(room).cell_rect(cell).get_center(), radius)


## Room `room`'s cover as its state holds it: each cell's state and seconds, its active cells, its rolls.
func _held(room: int) -> Array:
	var played: CoverRoom = cover.room(room)
	return [played.get(&"_state"), played.get(&"_age"), played.active_cells().duplicate(), played.rolls()]


func test_every_rooms_cover_plays_at_its_place() -> void:
	_start(1)
	_ticks(1)
	check_equal(cover.rooms(), flow.biome.places(), "a cover for every piece, the bridges too")
	for room in 3:
		var laid: CoverLayout = cover.layout_of(room)
		check(laid != null and laid.count() > 0, "room %d has cover" % room)
		check_equal(laid.origin, flow.biome.room_rect(room).position, "room %d's at its place" % room)
		check_equal(cover.cell_count(room), laid.cells.size(), "room %d's state sized to it" % room)
		var view: CoverViewScript = feel.cover_rooms().view_of(room)
		check(view != null and view.layout != null and view.layout.origin == laid.origin and view.layout.cells == laid.cells, "Feel lays room %d's the same, at its place" % room)
	var lit: Array[int] = []
	for room in 3:
		lit.append(_covered(room))
		_light(room, lit[room])
	_ticks(1)
	for room in 3:
		check_equal(cover.state_at(lit[room], room), BURNING, "fire lights room %d's cover, where it lies in the world" % room)
		check_equal(feel.cover_rooms().view_of(room).shown_state(lit[room]), BURNING, "and Feel draws it there")
	# A body standing in the court's burning grass is burnt.
	var wizard := flow.get_wizard(0) as Actor
	wizard.global_position = cover.layout_of(2).cell_rect(lit[2]).get_center()
	_statuses.clear()
	_ticks(1)
	var burnt: bool = false
	for asked: Array in _statuses:
		burnt = burnt or asked[0] == wizard
	check(burnt, "a wizard standing in the court's fire is asked its status")


func test_a_mirrored_rooms_cover_is_its_templates_mirrored() -> void:
	# The end rooms have a socket on one side only, so only the nave mirrors left for right.
	var mirrors: Array[int] = [PieceShape.MIRROR_Y, PieceShape.MIRROR_X | PieceShape.MIRROR_Y, PieceShape.MIRROR_Y]
	var map: BiomeMap = _start(1, mirrors)
	# The split map's rooms: the nave (0, unmirrored), the antechamber (1) and the court (2).
	var by_room: Array[int] = [mirrors[1], mirrors[0], mirrors[2]]
	for room in 3:
		var template: RoomBase = registry.call(&"get_resource", &"rooms", map.room_templates[room]) as RoomBase
		var built: Node = template.build()
		var plain: CoverLayout = CoverLayout.of(built, template, cover.kinds())
		built.free()
		var laid: CoverLayout = cover.layout_of(room)
		var place: Vector2 = map.room_places[room]
		var flip_x: bool = (by_room[room] & PieceShape.MIRROR_X) != 0
		var flip_y: bool = (by_room[room] & PieceShape.MIRROR_Y) != 0
		var same: bool = laid.columns == plain.columns and laid.rows == plain.rows
		var placed: bool = same
		for y in plain.rows:
			for x in plain.columns:
				if not same:
					break
				var from: int = y * plain.columns + x
				var to: int = (plain.rows - 1 - y if flip_y else y) * plain.columns + (plain.columns - 1 - x if flip_x else x)
				same = same and laid.cells[to] == plain.cells[from]
				# The cell's pixels are its template cell's, mirrored within the room and moved to its place.
				var own: Rect2 = plain.cell_rect(from)
				var mirrored := Rect2(Vector2(plain.size.x - own.end.x if flip_x else own.position.x, plain.size.y - own.end.y if flip_y else own.position.y) + place, own.size)
				placed = placed and laid.cell_rect(to) == mirrored
		check(same, "room %d's cells are its template's, mirrored (%d)" % [room, by_room[room]])
		check(placed, "each at its template cell's pixels, mirrored and moved to its place")
		if by_room[room] != 0:
			check(laid.cells != plain.cells, "room %d's grass lies otherwise than its template's" % room)
		# Its tufts are drawn again on the mirrored cells: every foot in its room.
		var view: CoverViewScript = feel.cover_rooms().view_of(room)
		var rows: PackedFloat32Array = view.rows_of(grass.id)
		var inside: bool = rows.size() > 0
		var rect: Rect2 = flow.biome.room_rect(room).grow(1.0)
		for at in range(0, rows.size(), CoverViewScript.STRIDE):
			inside = inside and rect.has_point(Vector2(rows[at + 3], rows[at + 7]))
		check(inside, "room %d's tufts all stand in it" % room)
		check_equal(view.layout.cells, laid.cells, "Feel draws room %d's as the area plays it" % room)


## Fires in the antechamber and the court, a wizard in each keeping it awake: `TICKS` ticks, each
## tick's hashes in `into`, the snapshot taken after tick `snapshot_at` (null when none).
func _two_fires(snapshot_at: int, into: Desync) -> Snapshot:
	_stop()
	_start(2)
	_stand_in_both()
	_ticks(2)
	_light(1, _covered(1), 20.0)
	_light(2, _covered(2), 20.0)
	var snapshot: Snapshot = null
	for i in TICKS:
		tick.run(DT)
		into.capture(tick.state_areas())
		if i == snapshot_at:
			snapshot = Snapshot.take(tick.state_areas(), root)
	return snapshot


func _stand_in_both() -> void:
	(flow.get_wizard(0) as Actor).global_position = flow.biome.room_rect(1).get_center()
	(flow.get_wizard(1) as Actor).global_position = flow.biome.room_rect(2).get_center()


func test_fires_in_two_rooms_play_the_same_twice_and_through_a_snapshot() -> void:
	var first := Desync.new()
	var snapshot: Snapshot = _two_fires(SNAPSHOT_AT, first)
	check(snapshot != null and snapshot.problems.is_empty(), "the snapshot was taken without problems")
	check(cover.room(1).rolls() > 0 and cover.room(2).rolls() > 0, "both rooms' fires rolled to spread")
	check(not cover.active_cells(1).is_empty() or not cover.active_cells(2).is_empty(), "and burn on")
	var second := Desync.new()
	_two_fires(-1, second)
	var parted: int = Desync.first_parting(first, second)
	check_equal(parted, -1, "played twice, the same%s" % ("" if parted < 0 else ": " + Desync.compare(first, second)))
	if snapshot == null:
		return
	# A joining machine: the same biome started, the snapshot restored, played on.
	_stop()
	_start(2)
	check(cover.active_cells(1).is_empty() and cover.active_cells(2).is_empty(), "the joining game's cover at rest")
	check_equal(snapshot.restore(tick.state_areas(), root), PackedStringArray(), "restored without problems")
	for room in [1, 2]:
		var shown: bool = true
		for cell in cover.active_cells(room):
			shown = shown and feel.cover_rooms().view_of(room).shown_state(cell) == cover.state_at(cell, room)
		check(shown and not cover.active_cells(room).is_empty(), "room %d's fire restored, and Feel draws it" % room)
	var resumed := Desync.new()
	for _i in range(SNAPSHOT_AT + 1, TICKS):
		tick.run(DT)
		resumed.capture(tick.state_areas())
	var after := Desync.new()
	after.hashes = first.hashes.slice(SNAPSHOT_AT + 1)
	parted = Desync.first_parting(after, resumed)
	check_equal(parted, -1, "restored, it plays on as it did%s" % ("" if parted < 0 else ": " + Desync.compare(after, resumed)))


func test_a_sleeping_rooms_fire_waits_as_if_no_time_had_passed() -> void:
	# Slept: the court's grass lit while nobody is there, 60 ticks asleep, then a wizard in it.
	_start(1)
	_ticks(2)
	check(not flow.life.is_awake(2), "the court sleeps")
	var cell: int = _covered(2)
	_light(2, cell, 20.0)
	_ticks(1)
	check_equal(cover.state_at(cell, 2), BURNING, "a touch lights it all the same")
	var lit: Array = _held(2)
	_ticks(60)
	check_equal(_held(2), lit, "asleep, its fire waits: no second counted, no roll made")
	(flow.get_wizard(0) as Actor).global_position = flow.biome.room_rect(2).get_center()
	# The tick it is woken on (Flow wakes it after the cover stepped).
	_ticks(1)
	_ticks(45)
	var slept: Array = _held(2)
	_stop()
	# Never slept: a wizard in the court from the start, the same fire, the same ticks awake.
	_start(1)
	(flow.get_wizard(0) as Actor).global_position = flow.biome.room_rect(2).get_center()
	_ticks(2)
	check(flow.life.is_awake(2), "the court awake")
	# The touch's tick steps it too, so as many steps awake as the slept room took after waking.
	_light(2, cell, 20.0)
	_ticks(45)
	check_equal(_held(2), slept, "the room that slept burns on as the one that never did")
	check(int(slept[3]) > 0, "and its fire rolled while awake")


func test_what_laying_a_biomes_cover_costs() -> void:
	# The twelve-room biome (every other nave mirrored), its cover worked out and drawn as it is laid.
	var map: BiomeMap = BiomeMaps.twelve_rooms(registry)
	input.add_virtual_device(0)
	var started: int = Time.get_ticks_usec()
	check(flow.start_biome(0, map, [] as Array[RoomFight]), "the biome starts")
	var whole_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	var sim_us: int = 0
	var view_us: int = 0
	var cells: int = 0
	for room in map.rooms():
		var template: RoomBase = registry.call(&"get_resource", &"rooms", map.room_templates[room]) as RoomBase
		var built := template.build() as Node2D
		built.position = map.room_places[room]
		built.set_meta(PieceShape.GROUND_MIRROR_META, Vector2i(map.room_mirrors[room] & 1, (map.room_mirrors[room] >> 1) & 1))
		var at: int = Time.get_ticks_usec()
		var laid: CoverLayout = CoverLayout.of_piece(built, template, cover.kinds())
		sim_us += Time.get_ticks_usec() - at
		cells += laid.count()
		at = Time.get_ticks_usec()
		feel.cover_rooms().view_of(room).lay(laid)
		view_us += Time.get_ticks_usec() - at
		built.free()
	check_equal(cover.rooms(), map.rooms() + map.bridges(), "every piece's cover laid")
	print("CB3b cover of a 12-room biome (%d covered cells): the biome laid in %.1f ms in all; the cover worked out in %.1f ms, drawn (tufts laid) in %.1f ms" % [cells, whole_ms, float(sim_us) / 1000.0, float(view_us) / 1000.0])
