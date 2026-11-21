extends "res://tests/support/suite.gd"
## What stands where nobody has seen yet is hidden one by one (the owner, 2026-11-21, on #899: no
## cover over an unvisited room, no layer of void motes over it), on the real autoloads and the split
## test map (the nave the start room, the antechamber west, the ossuary court east;
## tests/support/biome_maps.gd), Feel's parts stepped by hand: nothing in an unvisited room is drawn
## (its bodies, what lies on its floor, its mist, its light spots), only the bridges' ends reaching
## into it lie under the void's black, and all of it is drawn again from its reveal's first stage; a
## secret room's hidden way stays hidden until found.
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const UnseenDarkScript := preload("res://gameplay/feel/unseen_dark.gd")
const UnseenMaskScript := preload("res://gameplay/feel/unseen_mask.gd")
const UnseenStandingScript := preload("res://gameplay/feel/unseen_standing.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const MistScript := preload("res://gameplay/feel/mist.gd")
const DT: float = 1.0 / 60.0
const IMP: StringName = &"ember_imp"
const START: int = 0
const WEST: int = 1
const EAST: int = 2

var flow: FlowScript
var events: Node
var tick: TickScript
var input: Node
var registry: Node
var projectiles: Node
var feel: Node


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	events = root.get_node("Events")
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	registry = root.get_node("Registry")
	projectiles = root.get_node("Projectiles")
	feel = root.get_node("Feel")
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)


func after_each() -> void:
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	for seat in 4:
		input.leave(seat)
	tick.begin_run()


func _start(map: BiomeMap) -> void:
	input.add_virtual_device(0)
	var fights: Array[RoomFight] = []
	for room in map.rooms():
		fights.append(RoomFight.new())
	check(flow.start_biome(0, map, fights), "the biome starts")
	tick.run(DT)


func _grid() -> RoomGrid:
	return projectiles.call(&"grid") as RoomGrid


func _dark() -> UnseenDarkScript:
	return feel.call(&"unseen_dark") as UnseenDarkScript


## An imp standing in place `place`'s middle (the run's world; asleep there until a wizard comes).
func _imp_in(place: int) -> Actor:
	var data: EnemyBase = registry.call("get_resource", &"enemies", IMP) as EnemyBase
	var imp := data.scene.instantiate() as Actor
	imp.data = data
	imp.position = _grid().nearest_ground(_grid().place_rect(place).get_center(), 10.0)
	(flow.get("world") as Node2D).add_child(imp)
	return imp


func _step() -> void:
	feel.call(&"_step_rooms", 0.0, 1)


func test_an_unvisited_rooms_bodies_and_what_lies_there_are_hidden_until_its_reveal() -> void:
	var map: BiomeMap = BiomeMaps.split(registry)
	_start(map)
	var in_start: Actor = _imp_in(START)
	var in_west: Actor = _imp_in(WEST)
	var in_east: Actor = _imp_in(EAST)
	tick.run(DT)
	_step()
	var dark: UnseenDarkScript = _dark()
	var mask: UnseenMaskScript = dark.mask
	var standing: UnseenStandingScript = feel.call(&"unseen_standing") as UnseenStandingScript
	check(mask.hides(_grid().place_rect(WEST).get_center()) and mask.hides(_grid().place_rect(EAST).get_center()), "the unvisited rooms are hidden")
	check(not mask.hides(_grid().place_rect(START).get_center()), "the start room is not")
	check(in_start.visible, "a foe in the start room is drawn")
	check(not in_west.visible and not in_east.visible, "the foes in the unvisited rooms are not")
	check(standing.hides_body(in_west.id) and not standing.hides_body(in_start.id), "hidden by what stands unseen")
	# Every look that draws what lies on a floor leaves out what lies there.
	var looks: Array[CanvasItem] = feel.get(&"_masked_looks")
	check(looks.size() >= 8, "the looks of what lies on a floor (%d)" % looks.size())
	for look in looks:
		check(look.get(&"unseen") == mask, "%s is told the dark's mask" % look.name)
	# Nothing over the rooms but the bridges' ends reaching into them, under everything else.
	var bridge: int = map.rooms()
	var landings: Array[Rect2] = dark.landing_rects()
	for landing in landings:
		check(_grid().place_rect(WEST).encloses(landing) or _grid().place_rect(EAST).encloses(landing), "a landing lies in an unvisited room: %s" % landing)
		check(landing.get_area() < _grid().place_rect(WEST).get_area() / 4.0, "only a bridge's end, never the room: %s" % landing)
	var west_end: Rect2 = _grid().place_rect(WEST).intersection(_grid().place_rect(bridge))
	var east_end: Rect2 = _grid().place_rect(EAST).intersection(_grid().place_rect(bridge + 1))
	check(landings.has(west_end) and landings.has(east_end), "each bridge's end in an unvisited room is under the void's black")
	check(UnseenDarkScript.LANDING_Z < 1 and UnseenDarkScript.LANDING_Z > RoomBase.FLOOR_Z, "over the floors, under the bodies and every look")
	# The antechamber entered: from its reveal's first stage all of it is drawn again; the court not.
	var wizard := flow.get_wizard(0) as Actor
	wizard.global_position = _grid().nearest_ground(_grid().place_rect(WEST).get_center() + Vector2(24.0, 0.0), 10.0)
	tick.run(DT)
	dark.step(0.0, _grid())
	dark.advance()
	check(dark.stage_of(WEST) > 0 and not dark.covers_whole(WEST), "a stage into its reveal")
	_step()
	check(not mask.hides(_grid().place_rect(WEST).get_center()), "the antechamber is no longer hidden")
	check(in_west.visible, "its foe is drawn again, under the opening blocks")
	check(not in_east.visible, "the court's still is not")
	check(not dark.landing_rects().has(west_end), "its bridge's end is no longer under black")
	check(dark.landing_rects().has(east_end), "the court's still is")


func test_items_coins_and_light_spots_in_an_unvisited_room_are_left_out() -> void:
	var map: BiomeMap = BiomeMaps.split(registry)
	_start(map)
	_step()
	var mask: UnseenMaskScript = _dark().mask
	var west: Vector2 = _grid().nearest_ground(_grid().place_rect(WEST).get_center(), 6.0)
	var home: Vector2 = _grid().nearest_ground(_grid().place_rect(START).get_center(), 6.0)
	check(mask.hides(west) and not mask.hides(home), "the antechamber hidden, the start room not")
	# A light spot there gives no light (no glow over the void).
	var spectacle: Node = feel.call(&"spectacle")
	var was_lit: bool = spectacle.get(&"light") != null
	if not was_lit:
		events.emit_signal(&"spell_light_changed", true)
	var light: SpellLightScript = spectacle.get(&"light") as SpellLightScript
	check(light != null, "the spell light is on")
	if light == null:
		return
	var spot := Marker2D.new()
	spot.position = west
	spot.add_to_group(LightSpot.GROUP)
	root.add_child(own(spot))
	light.hide_unseen(null)
	light.draw_spots()
	var all: int = light.spots.multimesh.instance_count
	var hidden: int = 0
	for node: Node in root.get_tree().get_nodes_in_group(LightSpot.GROUP):
		if node is Node2D and node.is_inside_tree() and mask.hides((node as Node2D).global_position):
			hidden += 1
	check(hidden >= 1, "a spot in the antechamber")
	light.hide_unseen(mask)
	light.draw_spots()
	check_equal(light.spots.multimesh.instance_count, all - hidden, "the spots in the unvisited rooms give no light")
	_step()
	check(light.unseen == mask, "Feel hands the light the mask each frame")
	if not was_lit:
		events.emit_signal(&"spell_light_changed", false)


func test_an_unvisited_rooms_mist_is_hidden_until_its_reveal() -> void:
	var standing := UnseenStandingScript.new()
	var mask := UnseenMaskScript.new()
	var room := Rect2(Vector2(640.0, 0.0), Vector2(320.0, 256.0))
	var mist := MistScript.new(RoomBase.FLOOR_Z + 1)
	add_child_of_root(mist)
	var data := RoomMist.new()
	# Laid wider than its room (a room laid before its size is known): judged by its room's corner.
	var o: Vector2 = room.position
	var sea: Array[Rect2] = [Rect2(o, Vector2(640.0, 32.0)), Rect2(o + Vector2(0.0, 328.0), Vector2(640.0, 32.0)), Rect2(o, Vector2(32.0, 360.0)), Rect2(o + Vector2(608.0, 0.0), Vector2(32.0, 360.0))]
	mist.lay(Vector2(640.0, 360.0), [] as Array[Rect2], sea, o)
	mist.use(data)
	check(mist.visible, "a room's mist is drawn")
	var covers: Array[Rect2] = [room]
	mask.lay(covers)
	standing.step(mask, null, null, [mist] as Array[MistScript])
	check(not mist.visible, "not while its room is unseen")
	covers[0] = Rect2()
	mask.lay(covers)
	standing.step(mask, null, null, [mist] as Array[MistScript])
	check(mist.visible, "drawn again from its reveal")


func add_child_of_root(node: Node) -> void:
	root.add_child(own(node))


## The owner's secret ways (2026-11-20): a wall-to-wall secret room's seam is hidden (its rectangle in
## the mask, under the void's black over its floor, what stands on it not drawn) until found.
func test_a_secret_rooms_hidden_way_stays_hidden() -> void:
	var map: BiomeMap = BiomeMaps.wall_secret(registry)
	_start(map)
	_step()
	var dark: UnseenDarkScript = _dark()
	var seam: int = map.rooms()
	check_equal(dark.build_of(seam), UnseenDarkScript.HIDDEN, "the seam is hidden")
	var cover: Rect2 = dark.covered_of(seam)
	check(cover.has_area(), "what it hides")
	check(dark.mask.rects.has(cover), "in the mask: nothing on it is drawn")
	check(dark.landing_rects().has(cover), "its floor under the void's black")
	check(dark.mask.hides(_grid().place_rect(1).get_center()), "the secret room hidden")
	check(not dark.mask.hides(_grid().place_rect(0).get_center()), "the nave not")
	var imp: Actor = _imp_in(1)
	tick.run(DT)
	_step()
	check(not imp.visible, "a body in the secret room is not drawn")


## The mask: a point in a hidden rectangle; written in place, empty ones left out.
func test_the_mask_hides_points_in_its_rectangles() -> void:
	var mask := UnseenMaskScript.new()
	check(mask.is_empty() and not mask.hides(Vector2.ZERO), "nothing hidden at first")
	var covers: Array[Rect2] = [Rect2(), Rect2(Vector2(10.0, 10.0), Vector2(20.0, 20.0)), Rect2()]
	mask.lay(covers)
	check_equal(mask.rects.size(), 1, "the empty ones left out")
	check(mask.hides(Vector2(15.0, 15.0)) and not mask.hides(Vector2(5.0, 5.0)), "a point inside is hidden, one outside not")
	var changes: int = mask.changes
	covers[1] = Rect2()
	mask.lay(covers)
	check(mask.is_empty() and mask.changes == changes + 1, "laid again: none hidden, counted")
