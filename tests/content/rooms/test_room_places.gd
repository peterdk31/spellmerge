extends "res://tests/support/suite.gd"
## Every room's places (props W8a, docs/milestones/props.md, "W8a: a room is its scene"): found by
## folder, so a new room is checked too. Every stand-in and zone has its data (`RoomPlaces.problems`),
## and the editor never lies: a prop's stand-in draws its first picture where, and at the depth,
## the game draws it (`PropLayer.drawn_at`, `z_index`), and a dummy's draws its enemy's `Sprite`
## where its scene does. Flow's room shows none of them (`RoomPlaces.strip`).
##
## godot --headless --path . --script res://tests/content/rooms/test_room_places.gd

const RegistryScript := preload("res://core/registry/registry.gd")

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


func _children(layout: Node, holder: StringName) -> Array[Node]:
	var node: Node = layout.get_node_or_null(NodePath(String(holder)))
	return node.get_children() if node != null else [] as Array[Node]


func test_every_stand_in_and_zone_has_its_data() -> void:
	check(_rooms().size() >= 3, "the rooms are found")
	for room in _rooms():
		check_equal(room.places().problems(), PackedStringArray(), "%s: its places are sound" % room.id)


func test_a_props_stand_in_shows_what_the_game_draws() -> void:
	for room in _rooms():
		var layout: Node = own(room.scene.instantiate())
		for node in _children(layout, RoomPlaces.PROPS):
			var sprite := node as Sprite2D
			var data := (node.get_meta(RoomPlaces.PROP_META) if node.has_meta(RoomPlaces.PROP_META) else null) as PropBase
			if sprite == null or data == null or data.states == null or data.states.list.is_empty():
				check(false, "%s: %s is a Sprite2D stand-in with a prop that has states" % [room.id, node.name])
				continue
			var look: PropStateLook = data.look_of(data.states.list[0].state_id)
			var layer: PropLayer = look.layers[0] if look != null and not look.layers.is_empty() else null
			if layer == null:
				check(false, "%s: %s's prop has a first picture" % [room.id, data.id])
				continue
			var where: String = "%s: %s's stand-in" % [room.id, data.id]
			check_equal(sprite.texture, layer.texture, "%s shows its first picture" % where)
			check(sprite.centered, "%s is centred, as the game's" % where)
			check_equal(sprite.offset, layer.drawn_at(), "%s draws it where the game does" % where)
			check_equal(sprite.z_index, layer.z_index(), "%s at the game's depth" % where)


func test_a_dummys_stand_in_shows_its_enemy() -> void:
	for room in _rooms():
		var layout: Node = own(room.scene.instantiate())
		for node in _children(layout, RoomPlaces.DUMMIES):
			var sprite := node as Sprite2D
			var data := (node.get_meta(RoomPlaces.ENEMY_META) if node.has_meta(RoomPlaces.ENEMY_META) else null) as EnemyBase
			if sprite == null or data == null or data.scene == null:
				check(false, "%s: %s is a Sprite2D stand-in with an enemy that has a scene" % [room.id, node.name])
				continue
			var body: Node = own(data.scene.instantiate())
			var drawn := body.get_node_or_null("Sprite") as Sprite2D
			if drawn == null:
				check(false, "%s: %s's scene has a Sprite" % [room.id, data.id])
				continue
			var where: String = "%s: %s's stand-in" % [room.id, data.id]
			check_equal(sprite.texture, drawn.texture, "%s shows its picture" % where)
			check_equal(sprite.offset, drawn.position + drawn.offset, "%s draws it where its scene does" % where)


func test_the_room_flow_shows_has_no_stand_ins() -> void:
	for room in _rooms():
		var layout: Node = own(room.scene.instantiate())
		RoomPlaces.strip(layout)
		for holder: StringName in RoomPlaces.EDITOR_ONLY:
			check(layout.get_node_or_null(NodePath(String(holder))) == null, "%s: %s taken out" % [room.id, holder])
