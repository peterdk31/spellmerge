extends "res://tests/support/suite.gd"
## The game's ground cover in its rooms (ground cover GC8, docs/milestones/ground-cover.md): the hub
## is grassy (its biome `hub`, its grass's fill and a meadow) with its ways kept clear, the stone,
## the altar, the lectern and the paths from the spawns to them; every crypt room holds moss and a
## few cobwebs, few enough not to crowd its fights; every room with cover holds a `CoverPreview`, so
## the editor shows it; and every kind's fill reaches a room. Rooms and kinds are found by folder.
const RegistryScript := preload("res://core/registry/registry.gd")

## The most of a crypt room's open floor its cobwebs may hold (GC7: the AI walks round them).
const MOST_COBWEBS: float = 0.06
## The art of the hub's stone and altar: each 96 px a side round where it stands.
const HUB_PROP_ART: Vector2 = Vector2(96.0, 96.0)

var _registry: RegistryScript


func before_each() -> void:
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()


func _kinds() -> Array[CoverKind]:
	var kinds: Array[CoverKind] = []
	for item: Resource in _registry.get_all(&"cover"):
		if item is CoverKind:
			kinds.append(item as CoverKind)
	return kinds


func _rooms() -> Array[RoomBase]:
	var rooms: Array[RoomBase] = []
	for item: Resource in _registry.get_all(&"rooms"):
		if item is RoomBase:
			rooms.append(item as RoomBase)
	return rooms


func _cover_of(room: RoomBase) -> CoverLayout:
	return CoverLayout.of(own(room.build()), room, _kinds())


## The covered cells whose middles lie in `box`, by their kind's id.
func _covered_in(layout: CoverLayout, box: Rect2) -> PackedStringArray:
	var found := PackedStringArray()
	for cell in layout.cells.size():
		if layout.cells[cell] != 0 and box.has_point(layout.cell_rect(cell).get_center()):
			found.append("%s at %s" % [layout.kind_at(cell).id, layout.cell_rect(cell).position])
	return found


## The covered cells a body walking straight from `from` to `to` crosses (its middle within a cell
## of the line).
func _covered_along(layout: CoverLayout, from: Vector2, to: Vector2) -> PackedStringArray:
	var found := PackedStringArray()
	for cell in layout.cells.size():
		if layout.cells[cell] == 0:
			continue
		var middle: Vector2 = layout.cell_rect(cell).get_center()
		if Geometry2D.get_closest_point_to_segment(middle, from, to).distance_to(middle) < float(CoverLayout.CELL):
			found.append("%s at %s" % [layout.kind_at(cell).id, layout.cell_rect(cell).position])
	return found


func test_every_room_with_cover_shows_it_in_the_editor() -> void:
	var covered: int = 0
	for room in _rooms():
		if _cover_of(room).count() == 0:
			continue
		covered += 1
		var scene: Node = own(room.scene.instantiate())
		check_equal(scene.find_children("*", "CoverPreview", true, false).size(), 1, "%s has cover and one CoverPreview" % room.id)
	check(covered >= 6, "the hub, the four arenas and the boss's arena have cover (%d rooms)" % covered)


func test_the_hub_is_grassy_and_its_ways_are_clear() -> void:
	var hub := _registry.get_resource(&"rooms", &"hub") as RoomBase
	check_equal(hub.biome, &"hub", "the hub's biome, for its grass's fill")
	check(hub.kinds.is_empty(), "and no room kind, so no run is offered it")
	var layout: CoverLayout = _cover_of(hub)
	check(layout.count(&"hub_grass") > 400, "grassy (%d cells)" % layout.count(&"hub_grass"))
	check_equal(layout.count(), layout.count(&"hub_grass"), "the hub's grass alone")
	var places: RoomPlaces = hub.places()
	var stone: Vector2 = Vector2.INF
	for i in places.placed.size():
		var prop := places.placed[i] as PropBase
		if prop == null or (prop.role != &"run_start" and prop.role != &"party_altar"):
			continue
		if prop.role == &"run_start":
			stone = places.placed_at[i]
		check_equal(_covered_in(layout, Rect2(places.placed_at[i] - HUB_PROP_ART * 0.5, HUB_PROP_ART)), PackedStringArray(), "nothing grows on the %s" % prop.id)
	check(stone.is_finite(), "the stone stands in the hub")
	check_equal(_covered_in(layout, places.zone(&"start_lectern").grow(8.0)), PackedStringArray(), "nor round the lectern")
	for spawn in places.player_spawns:
		check_equal(_covered_along(layout, spawn, stone), PackedStringArray(), "the way from %s to the stone is clear" % spawn)
	for spawn in places.joiner_spawns:
		check_equal(_covered_along(layout, spawn, stone), PackedStringArray(), "the way from %s by the altar to the stone is clear" % spawn)


func test_every_crypt_room_holds_moss_and_a_few_cobwebs() -> void:
	var rooms: int = 0
	for room in _rooms():
		if room.biome != &"crypt" or room.kinds.is_empty():
			continue
		rooms += 1
		var layout: CoverLayout = _cover_of(room)
		var open: int = 0
		for cell in layout.blocked.size():
			if layout.blocked[cell] == 0:
				open += 1
		check(layout.count(&"crypt_moss") > 0, "%s has moss" % room.id)
		check(layout.count(&"cobweb") > 0, "%s has cobwebs" % room.id)
		var share: float = float(layout.count(&"cobweb")) / float(maxi(open, 1))
		check(share <= MOST_COBWEBS, "%s: its cobwebs hold %.1f%% of its floor, at most %.0f%%" % [room.id, share * 100.0, MOST_COBWEBS * 100.0])
	check(rooms >= 5, "the four arenas and the boss's arena (%d)" % rooms)


## No cover that harms at rest (cobwebs) on a spawn's or a door's cell or the eight round it, hand-placed fields
## too (the fill keeps its own `keep_gap`; a field keeps only the spawn's own cell bare): nobody
## starts in a web, nor walks through one coming in.
func test_no_harmful_cover_beside_a_spawn_or_a_door() -> void:
	for room in _rooms():
		var layout: CoverLayout = _cover_of(room)
		var places: RoomPlaces = room.places()
		var points := PackedVector2Array()
		points.append_array(places.player_spawns)
		points.append_array(places.enemy_spawns)
		points.append_array(places.doors)
		points.append_array(places.joiner_spawns)
		for point in points:
			var own: int = layout.cell_of(point)
			var reach := layout.cell_rect(own).grow(float(CoverLayout.CELL)) if own >= 0 else Rect2(point, Vector2.ZERO)
			var near := PackedStringArray()
			for cell in layout.cells.size():
				var kind: CoverKind = layout.kind_at(cell)
				if kind != null and kind.states[0].status != &"" and reach.has_point(layout.cell_rect(cell).get_center()):
					near.append(String(kind.id))
			check_equal(near, PackedStringArray(), "%s: nothing harmful on or beside the cell of %s" % [room.id, point])


## Every mote a cover state gives off is a mote kind there is (content/motes).
func test_every_cover_states_motes_are_mote_kinds() -> void:
	for kind in _kinds():
		for state in kind.states:
			for look: MoteSource in state.motes:
				check(_registry.get_resource(&"motes", look.kind) != null, "%s: %s gives off '%s', a mote kind" % [kind.id, state.state_id, look.kind])


func test_every_kinds_fill_reaches_a_room() -> void:
	var biomes: Array[StringName] = []
	for room in _rooms():
		if room.biome != &"" and not biomes.has(room.biome):
			biomes.append(room.biome)
	for kind in _kinds():
		check(not kind.biomes.is_empty(), "%s fills a biome by itself" % kind.id)
		for biome in kind.biomes:
			check(biomes.has(biome), "%s fills %s, a biome of some room" % [kind.id, biome])
