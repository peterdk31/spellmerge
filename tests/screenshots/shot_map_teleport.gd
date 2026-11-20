extends "res://tests/support/screenshot.gd"
## Screenshots of the teleport from the held Y map and of a join held to the run's end (the owner,
## 2026-11-19), on the split test map (the nave the start room, the antechamber west, the ossuary
## court east; tests/support/biome_maps.gd), played by the keyboard.
##
## Shots: P1 in the antechamber holding M (Y on a pad), the map open, the nave picked and outlined in
## its colour (map_teleport_pick); F (A on a pad) pressed: P1 in the nave two frames on, built out of
## light as it materializes (map_teleport_leave, map_teleport_arrive), then standing
## (map_teleport_stood); the column of light a teleport leaves where it stood, staged beside P1 and
## cropped 4x: its first look and two looks on (map_teleport_column_1, map_teleport_column_3); a
## second player joining now that the party has left the start room, its corner panel saying WAIT
## and why (join_held). P2 is a virtual seat (another machine's: the camera holds P1 alone).

const BiomeMaps := preload("res://tests/support/biome_maps.gd")


func _key(input: Node, key: Key, down: bool) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = key
	press.pressed = down
	input.call("handle_event", press)


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Registry", "Hud"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry: Node = root.get_node("Registry")
	input.call("join", int(input.get("KEYBOARD")))
	input.call("add_virtual_device", 1)
	var map: BiomeMap = BiomeMaps.split(registry)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
	if not flow.call("start_biome", 0, map, fights):
		fail("the biome did not start")
		return
	await settle()
	var wizard := flow.call("get_wizard", 0) as Node2D
	var west: Vector2 = BiomeMaps.socket_point(registry, map, 1, RoomSocket.Facing.EAST)
	wizard.global_position = west - Vector2(64.0, 0.0)
	await settle(10)
	(flow.call("get_wizard", 1) as Node2D).global_position = west - Vector2(110.0, 24.0)
	await settle(30)
	_key(input, KEY_M, true)
	await settle(20)
	await shot("map_teleport_pick")
	_key(input, KEY_F, true)
	await settle(2)
	_key(input, KEY_F, false)
	_key(input, KEY_M, false)
	save(await grab(), "map_teleport_leave")
	await settle(8)
	save(await grab(), "map_teleport_arrive")
	await settle(40)
	await shot("map_teleport_stood")
	var beside: Vector2 = wizard.global_position + Vector2(56.0, 0.0)
	root.get_node("Events").wizard_teleported.emit(0, beside, wizard.global_position)
	var image: Image = await grab()
	save_crop(image, on_screen(beside + Vector2(0, -10)), "map_teleport_column_1", Vector2i(32, 24))
	await settle(10)
	image = await grab()
	save_crop(image, on_screen(beside + Vector2(0, -10)), "map_teleport_column_3", Vector2i(32, 24))
	if not (flow.get("biome") as BiomeWorld).room_rect(0).has_point(wizard.global_position):
		fail("the wizard did not teleport to the nave")
		return
	# Another player joins now: the party has left the start room, so it waits.
	input.call("add_virtual_device", 2)
	await settle(20)
	if flow.call("get_wizard", 2) != null:
		fail("the joiner got a wizard")
		return
	await shot("join_held")
