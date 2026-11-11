extends "res://tests/support/suite.gd"
## Every room's places (props W8a/W8b/W8c, docs/milestones/props.md): found by folder, so a new room
## is checked too. Its places are sound (`RoomPlaces.problems`: every placement has its data, every
## zone its name, places are whole translations); a prop's stand-in (`PropStandIn`, the editor's)
## draws its look as the game's body does (`PropLook`), state by state, so the editor never lies;
## and the room the game shows has no placement or zone left (`RoomPlaces.strip`).
##
## godot --headless --path . --script res://tests/content/rooms/test_room_places.gd

const RegistryScript := preload("res://core/registry/registry.gd")
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")

var _registry: RegistryScript
var _world: Fixture


func before_each() -> void:
	_registry = own(RegistryScript.new()) as RegistryScript
	_registry.scan()
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


func _rooms() -> Array[RoomBase]:
	var found: Array[RoomBase] = []
	for item: Resource in _registry.get_all(&"rooms"):
		if item is RoomBase:
			found.append(item as RoomBase)
	return found


func test_every_rooms_places_are_sound() -> void:
	check(_rooms().size() >= 3, "the rooms are found")
	for room in _rooms():
		check_equal(room.places().problems(), PackedStringArray(), "%s: its places are sound" % room.id)


## What the editor draws for a prop (its stand-in's sprites) is what the game draws (its body's
## look's sprites), in every state: picture, frames, place, depth, shown.
func test_a_props_stand_in_draws_what_the_game_draws() -> void:
	var props: Array[PropBase] = []
	for room in _rooms():
		for data: PropBase in room.places().placed_of(PropBase):
			if not props.has(data):
				props.append(data)
	props.append(preload("res://tests/gameplay/actor/fixtures/exploding_barrel.tres"))
	for data in props:
		for state in data.states.list:
			var stand_in := own(PropStandIn.new()) as PropStandIn
			stand_in.prop = data
			stand_in.state = state.state_id
			stand_in.show_look()
			var body: Actor = _world.add(PropBody.make(data), Vector2(100, 100))
			if state != data.states.list[0]:
				body.state_triggers.enter(state.state_id)
			var drawn: Array[Sprite2D] = []
			for child in [body.get_node("Sprite")] + body.get_node("PropLook").get_children():
				if child is Sprite2D and not child.is_queued_for_deletion():
					drawn.append(child as Sprite2D)
			var shown: Array[Sprite2D] = stand_in.look_sprites()
			var where: String = "%s, %s" % [data.id, state.state_id]
			check_equal(shown.size(), drawn.size(), "%s: as many pictures" % where)
			for i in mini(shown.size(), drawn.size()):
				check_equal(shown[i].texture, drawn[i].texture, "%s, layer %d: the picture" % [where, i])
				check_equal(shown[i].hframes, drawn[i].hframes, "%s, layer %d: its frames" % [where, i])
				check_equal(shown[i].position + shown[i].offset, drawn[i].position + drawn[i].offset, "%s, layer %d: where" % [where, i])
				check_equal(shown[i].z_index, drawn[i].z_index, "%s, layer %d: its depth" % [where, i])
				check_equal(shown[i].visible, drawn[i].visible, "%s, layer %d: shown" % [where, i])


func test_the_room_the_game_shows_has_no_placements_or_zones() -> void:
	for room in _rooms():
		var layout: Node = own(room.build())
		RoomPlaces.strip(layout)
		check(layout.find_children("*", "RoomPlacement", true, false).is_empty(), "%s: no placement left" % room.id)
		check(layout.find_children("*", "RoomZone", true, false).is_empty(), "%s: no zone left" % room.id)
