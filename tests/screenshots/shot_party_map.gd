extends "res://tests/support/screenshot.gd"
## Screenshots of the party's map (connected biomes CB9): the split test map (the nave the start room,
## the antechamber west, the ossuary court east; tests/support/biome_maps.gd), played by the keyboard.
##
## Shots: the wizard by the nave's east mouth, the court's kind symbol risen on the bridge beyond it
## (party_map_symbol, with a 4x crop); the wizard in the antechamber holding M (Y on a pad), the map
## open over the view: the nave and the antechamber entered, the bridges from them, the court's
## symbol at the end of its bridge, the wizard's dot (party_map_open).

const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const KEYBOARD: int = -2


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Registry"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry: Node = root.get_node("Registry")
	input.call("join", int(input.get("KEYBOARD")))
	var map: BiomeMap = BiomeMaps.split(registry)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
	if not flow.call("start_biome", 0, map, fights):
		fail("the biome did not start")
		return
	await settle()
	var wizard := flow.call("get_wizard", 0) as Node2D
	var east: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.EAST)
	wizard.global_position = east - Vector2(40.0, 0.0)
	await settle(30)
	var image: Image = await grab()
	save(image, "party_map_symbol")
	save_crop(image, on_screen(east + Vector2(24.0, 0.0)), "party_map_symbol_crop", Vector2i(48, 40))
	var west: Vector2 = BiomeMaps.socket_point(registry, map, 1, RoomSocket.Facing.EAST)
	wizard.global_position = west - Vector2(48.0, 0.0)
	await settle(30)
	var press := InputEventKey.new()
	press.physical_keycode = KEY_M
	press.pressed = true
	input.call("handle_event", press)
	await shot("party_map_open")
