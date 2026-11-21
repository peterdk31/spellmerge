extends "res://tests/support/screenshot.gd"
## Screenshots of an unvisited room as the void (the owner, 2026-11-21: an unseen room is not black,
## it looks like the background round it, its motes drifting about, until revealed), on the split
## test map (the nave the start room, the antechamber west, the ossuary court east;
## tests/support/biome_maps.gd), played by the keyboard.
##
## Shots: the wizard on the nave's west bridge with the antechamber unvisited, one with the void
## round it, the void's motes drifting over it (unseen_void, with a 4x crop over the room's edge,
## unseen_void_crop); frozen mid-way through its reveal, the blocks opening from the void into the
## room (unseen_reveal_midway, its crop); and the room revealed (unseen_revealed, its crop).

const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const UnseenDarkScript := preload("res://gameplay/feel/unseen_dark.gd")
const AirMotesScript := preload("res://gameplay/feel/air_motes.gd")
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
	var west_mouth: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.WEST)
	var edge: Vector2 = BiomeMaps.socket_point(registry, map, WEST, RoomSocket.Facing.EAST)
	# On the nave's west bridge, by the antechamber's mouth, long enough for the void's motes to fill
	# the view (their life is 3 to 4 s).
	wizard.global_position = west_mouth + Vector2(-40.0, 0.0)
	await settle(300)
	var dark := feel.call(&"unseen_dark") as UnseenDarkScript
	if not dark.void_covers().has(grid.place_rect(WEST)):
		fail("the antechamber is not the void")
		return
	var air := feel.call(&"spectacle").get(&"void_air") as AirMotesScript
	if air.given <= 0:
		fail("no void motes were given off")
		return
	var image: Image = await grab()
	save(image, "unseen_void")
	save_crop(image, on_screen(edge + Vector2(-40.0, 0.0)), "unseen_void_crop", Vector2i(80, 45))
	# Into the antechamber with Feel held, its dark stepped by hand to the reveal's middle stage.
	feel.process_mode = Node.PROCESS_MODE_DISABLED
	wizard.global_position = edge + Vector2(-24.0, 0.0)
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
	save(image, "unseen_reveal_midway")
	save_crop(image, on_screen(edge + Vector2(-40.0, 0.0)), "unseen_reveal_midway_crop", Vector2i(80, 45))
	feel.process_mode = Node.PROCESS_MODE_INHERIT
	await settle(60)
	if dark.stage_of(WEST) != 0:
		fail("the antechamber is not revealed (%d)" % dark.stage_of(WEST))
		return
	image = await grab()
	save(image, "unseen_revealed")
	save_crop(image, on_screen(edge + Vector2(-40.0, 0.0)), "unseen_revealed_crop", Vector2i(80, 45))
