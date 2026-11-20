extends "res://tests/support/screenshot.gd"
## Screenshots of a wide biome's floor marks (the performance pass, 2026-11-20: a mark layer a room,
## gameplay/feel/marks.gd `enter_places`): the twelve-room test biome (tests/support/biome_maps.gd,
## a row of crypt rooms far wider than the old 4,096 px layer), one wizard in its last room, past
## 4,096 px, where blasts are played through Feel; once their flashes and motes are gone,
## `wide_marks_far_room` shows the marks there (before, past the layer's cap, none were drawn), and
## `wide_marks_mouth` a scorch on a mouth between two rooms, drawn whole across both rooms' layers.

const BiomeMaps := preload("res://tests/support/biome_maps.gd")


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Registry"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry: Node = root.get_node("Registry")
	var feel: Node = root.get_node("Feel")
	var map: BiomeMap = BiomeMaps.twelve_rooms(registry)
	input.call("add_virtual_device", 0)
	var fights: Array[RoomFight] = []
	for room in map.rooms():
		fights.append(RoomFight.new())
	if not flow.call("start_biome", 0, map, fights):
		fail("the twelve-room biome did not start")
		return
	await settle(30)
	var wizard := flow.call("get_wizard", 0) as Node2D
	if wizard == null:
		fail("no wizard")
		return
	var last: int = map.rooms() - 1
	var west: Vector2 = BiomeMaps.socket_point(registry, map, last, RoomSocket.Facing.WEST)
	var middle: Vector2 = west + Vector2(260.0, 0.0)
	if middle.x <= 4096.0:
		fail("the last room is not past 4,096 px (%s)" % middle)
		return
	wizard.global_position = middle + Vector2(0.0, 60.0)
	await settle(90)
	var marks: Object = feel.call("marks")
	if marks == null:
		fail("Feel has no mark layer (the Floor marks setting is off?)")
		return
	print("WIDE MARKS: %d layers, the last room at %s" % [int(marks.call("layer_count")), middle])
	var spots: Array[Vector2] = [middle + Vector2(-90.0, -20.0), middle + Vector2(0.0, -40.0), middle + Vector2(90.0, -20.0)]
	var tints: Array[Color] = [Color.WHITE, Color("e0592f"), Color("4fd6dc")]
	var looks: Array[int] = [0, 1 << 0, 1 << 1]
	for i in spots.size():
		feel.call("play_cue", &"blast", 0, spots[i], Vector2.RIGHT, 34.0, tints[i], looks[i])
		await settle(1)
	await settle(300)
	await shot("wide_marks_far_room")
	# A scorch on the mouth between the last two rooms: across both rooms' layers, one mark.
	var mouth: Vector2 = west + Vector2(-8.0, 0.0)
	wizard.global_position = mouth + Vector2(40.0, 70.0)
	await settle(60)
	feel.call("play_cue", &"blast", 0, mouth, Vector2.RIGHT, 40.0, Color("e0592f"), 1 << 0)
	await settle(300)
	await shot("wide_marks_mouth")
