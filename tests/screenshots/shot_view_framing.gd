extends "res://tests/support/screenshot.gd"
## Screenshots of the view changes of 2026-11-19 (gameplay/feel/README.md): on the split test map
## (tests/support/biome_maps.gd), the camera framing the foes of a sealed fight besides the wizard
## (`framing_sealed_fight`, zoomed out for the imps, no further than 0.5), the black void with its
## motes and the big lit doorway signs (`framing_void_signs`), a sign rising in by rows as the
## wizard comes near (`framing_sign_rises`, a strip), and an unentered room's black opening
## by shrinking blocks as the wizard steps in (`framing_dark_opens`: a strip of its stages).

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
	var map: BiomeMap = BiomeMaps.split(registry, [0, 0, 0] as Array[int], [&"arena_04", BiomeMaps.MIDDLE, BiomeMaps.LAST] as Array[StringName])
	var imps: Array[StringName] = [&"ember_imp", &"ember_imp", &"ember_imp"]
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.of(imps), RoomFight.new()]
	if not flow.call("start_biome", 0, map, fights):
		fail("the biome did not start")
		return
	await settle()
	var wizard := flow.call("get_wizard", 0) as Node2D
	# The void and the signs: on the nave's east bridge, the court beyond still black.
	var east: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.EAST)
	# A sign rising as the wizard comes near (a row a frame at 12 fps, lit as it rises).
	wizard.global_position = east - Vector2(400.0, 0.0)
	await settle(60)
	wizard.global_position = east - Vector2(24.0, 0.0)
	await settle(2)
	var rising: Array[Image] = []
	for stage in 8:
		rising.append(crop_round(await grab(), on_screen(east + Vector2(72.0, 0.0)), Vector2i(48, 32)))
		await settle(5)
	var rise_strip := Image.create(rising[0].get_width() * rising.size(), rising[0].get_height(), false, rising[0].get_format())
	for i in rising.size():
		rise_strip.blit_rect(rising[i], Rect2i(Vector2i.ZERO, rising[i].get_size()), Vector2i(rising[0].get_width() * i, 0))
	rise_strip.resize(rise_strip.get_width() * 2, rise_strip.get_height() * 2, Image.INTERPOLATE_NEAREST)
	save(rise_strip, "framing_sign_rises")
	wizard.global_position = east - Vector2(24.0, 0.0)
	await settle(60)
	await shot("framing_void_signs")
	# The antechamber's sealed fight: the camera frames the imps too.
	var west_room: Vector2 = BiomeMaps.socket_point(registry, map, 1, RoomSocket.Facing.EAST)
	wizard.global_position = west_room - Vector2(40.0, 0.0)
	await settle(120)
	var grid: RoomGrid = root.get_node("Projectiles").call("grid") as RoomGrid
	if not grid.is_sealed(1):
		fail("the antechamber did not seal in framing_sealed_fight")
		return
	# The wizard in one corner of the room, an imp in the far one: the camera eases out to hold both.
	var table: Node = root.get_node("Actors")
	var ids := PackedInt32Array()
	var room: Rect2 = grid.place_rect(1)
	for i in int(table.call("open_ids", ids)):
		if int(table.call("team_of", ids[i])) == 1:
			var imp := table.call("node_of", ids[i]) as Node2D
			if imp != null:
				imp.global_position = room.position + Vector2(56.0, 56.0)
				break
	wizard.global_position = room.end - Vector2(56.0, 56.0)
	await settle(90)
	var foes: Object = feel.get("close_foes")
	if foes == null or int(foes.get("count")) == 0:
		fail("no close foe was found in framing_sealed_fight")
		return
	var camera: Object = feel.get("party_camera")
	print("FRAMING: %d close foes, zoom %.2f, room %s" % [int(foes.get("count")), float(camera.get("target_zoom")), room])
	await shot("framing_sealed_fight")
	# The court entered: its black opens by shrinking blocks, a stage a frame at 12 fps.
	var court: Vector2 = BiomeMaps.socket_point(registry, map, 2, RoomSocket.Facing.WEST)
	wizard.global_position = court - Vector2(40.0, 0.0)
	await settle(60)
	wizard.global_position = court + Vector2(24.0, 0.0)
	var frames: Array[Image] = []
	for stage in 6:
		frames.append(crop_round(await grab(), on_screen(court + Vector2(150.0, 110.0)), Vector2i(80, 60)))
		await settle(5)
	var strip := Image.create(frames[0].get_width() * frames.size(), frames[0].get_height(), false, frames[0].get_format())
	for i in frames.size():
		strip.blit_rect(frames[i], Rect2i(Vector2i.ZERO, frames[i].get_size()), Vector2i(frames[0].get_width() * i, 0))
	save(strip, "framing_dark_opens")
