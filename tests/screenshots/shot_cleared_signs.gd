extends "res://tests/support/screenshot.gd"
## Screenshots of a cleared room's doorway signs and map symbol, and of an unvisited room's dark
## opening (the owner, 2026-11-20, #883), on the split test map (the nave the start room, the
## antechamber west, the ossuary court east; tests/support/biome_maps.gd), played by the keyboard.
##
## Shots: the wizard on the nave's west bridge, the antechamber dark, frozen mid-way through its
## reveal (stage 2 of the blocks; reveal_midway, with a 4x crop); the antechamber's sign there before
## it is cleared (sign_uncleared_crop) and after (sign_cleared_crop, its fight cleared as it was
## entered: the test map's fights are empty), the court's sign beside the nave's east mouth still
## uncleared for comparison (sign_court_uncleared_crop); the map held open with the antechamber
## cleared and the court not (map_cleared).

const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const UnseenDarkScript := preload("res://gameplay/feel/unseen_dark.gd")
const MouthSymbolsScript := preload("res://gameplay/feel/mouth_symbols.gd")
const MouthLooksScript := preload("res://gameplay/feel/mouth_looks.gd")
const KindSymbolLook := preload("res://gameplay/feel/kind_symbol.gd")
const WEST: int = 1


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Registry", "Projectiles"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var feel: Node = root.get_node("Feel")
	var registry: Node = root.get_node("Registry")
	input.call("join", int(input.get("KEYBOARD")))
	var map: BiomeMap = BiomeMaps.split(registry)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
	if not flow.call("start_biome", 0, map, fights):
		fail("the biome did not start")
		return
	await settle()
	var wizard := flow.call("get_wizard", 0) as Node2D
	var grid := root.get_node("Projectiles").call("grid") as RoomGrid
	# On the nave's west bridge, by the antechamber's mouth: its sign risen, the room dark.
	var west_mouth: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.WEST)
	wizard.global_position = west_mouth + Vector2(-40.0, 0.0)
	await settle(40)
	var symbols := feel.call(&"mouth_symbols") as MouthSymbolsScript
	var mouths := feel.call(&"mouth_looks") as MouthLooksScript
	var into_west: int = -1
	for mouth in mouths.mouths():
		if mouths.room_of(mouth) == WEST:
			into_west = mouth
	if into_west < 0:
		fail("no mouth into the antechamber")
		return
	var sign_at: Vector2 = symbols.corner_of(into_west) + Vector2.ONE * (RoomKind.SYMBOL_SIDE * MouthSymbolsScript.SCALE * 0.5)
	var image: Image = await grab()
	save_crop(image, on_screen(sign_at), "sign_uncleared_crop", Vector2i(24, 24))
	# Into the antechamber with Feel held, its dark stepped by hand to the reveal's middle stage.
	var dark := feel.call(&"unseen_dark") as UnseenDarkScript
	feel.process_mode = Node.PROCESS_MODE_DISABLED
	var inside: Vector2 = BiomeMaps.socket_point(registry, map, WEST, RoomSocket.Facing.EAST) + Vector2(-24.0, 0.0)
	wizard.global_position = inside
	await settle(4)
	wizard.global_position = west_mouth + Vector2(-40.0, 0.0)
	dark.step(0.0, grid)
	dark.advance()
	dark.advance()
	if dark.stage_of(WEST) != 2:
		fail("the antechamber's dark is at stage %d, not mid-way" % dark.stage_of(WEST))
		return
	await settle(2)
	image = await grab()
	save(image, "reveal_midway")
	save_crop(image, on_screen(west_mouth + Vector2(24.0, 0.0)), "reveal_midway_crop", Vector2i(64, 40))
	feel.process_mode = Node.PROCESS_MODE_INHERIT
	await settle(40)
	if symbols.cleared_of(into_west) != KindSymbolLook.CLEARED_STAGES:
		fail("the antechamber's sign is not cleared (%d)" % symbols.cleared_of(into_west))
		return
	image = await grab()
	save_crop(image, on_screen(sign_at), "sign_cleared_crop", Vector2i(24, 24))
	# The court's sign by the nave's east mouth, not cleared.
	var east_mouth: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.EAST)
	wizard.global_position = east_mouth - Vector2(40.0, 0.0)
	await settle(40)
	var into_east: int = -1
	for mouth in mouths.mouths():
		if mouths.room_of(mouth) == 2:
			into_east = mouth
	image = await grab()
	save_crop(image, on_screen(symbols.corner_of(into_east) + Vector2.ONE * (RoomKind.SYMBOL_SIDE * MouthSymbolsScript.SCALE * 0.5)), "sign_court_uncleared_crop", Vector2i(24, 24))
	var press := InputEventKey.new()
	press.physical_keycode = KEY_M
	press.pressed = true
	input.call("handle_event", press)
	await shot("map_cleared")
