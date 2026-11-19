extends "res://tests/support/screenshot.gd"
## Screenshots of a biome's look (connected biomes CB12): the split test map (the nave the start
## room, the antechamber west with an imp's fight, the ossuary court east; tests/support/biome_maps.gd).
##
## Shots: the wizard by the nave's east mouth, the bridge's causeway, its mouths shimmering and the
## court beyond still dark (biome_mouths, with a 4x crop of the mouth); the wizard in the
## antechamber's sealed fight, its mouth's bars down and its rune lit (biome_seal, with a crop); the
## court as the wizard steps in, lit again (biome_lit).

const BiomeMaps := preload("res://tests/support/biome_maps.gd")


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Registry", "Projectiles"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry: Node = root.get_node("Registry")
	var feel: Node = root.get_node("Feel")
	input.call("add_virtual_device", 0)
	var map: BiomeMap = BiomeMaps.split(registry)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.of([&"ember_imp"] as Array[StringName]), RoomFight.new()]
	if not flow.call("start_biome", 0, map, fights):
		fail("the biome did not start")
		return
	await settle()
	var wizard := flow.call("get_wizard", 0) as Node2D
	var east: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.EAST)
	wizard.global_position = east - Vector2(56.0, 0.0)
	await settle(60)
	var mouths: Node = feel.call("mouth_looks")
	if int(mouths.call("mouths")) != 4:
		fail("the four mouths are not found in biome_mouths")
		return
	var image: Image = await grab()
	save(image, "biome_mouths")
	save_crop(image, on_screen(east + Vector2(8.0, 0.0)), "biome_mouths_crop", Vector2i(48, 40))
	# Into the antechamber's fight: it seals.
	var west_room: Vector2 = BiomeMaps.socket_point(registry, map, 1, RoomSocket.Facing.EAST)
	wizard.global_position = west_room - Vector2(40.0, 0.0)
	await settle(60)
	var grid: RoomGrid = root.get_node("Projectiles").call("grid") as RoomGrid
	if not grid.is_sealed(1):
		fail("the antechamber did not seal in biome_seal")
		return
	image = await grab()
	save(image, "biome_seal")
	save_crop(image, on_screen(west_room + Vector2(8.0, 0.0)), "biome_seal_crop", Vector2i(48, 40))
	# The court, entered, lit again.
	var court: Vector2 = BiomeMaps.socket_point(registry, map, 2, RoomSocket.Facing.WEST)
	wizard.global_position = court + Vector2(64.0, 0.0)
	await shot("biome_lit")
