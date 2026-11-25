extends "res://tests/support/screenshot.gd"
## Screenshots of the view changes of 2026-11-19 and 2026-11-23 (gameplay/feel/README.md): on the
## split test map (tests/support/biome_maps.gd), a sealed fight at the default zoom (1 since 2026-11-25; 0.8 before), the camera
## on the wizard alone and a marker at the picture's edge for an imp out of it
## (`framing_sealed_fight`, and the marker four times bigger, `framing_foe_marker`; split in two
## views, the marker in its seat's own cell, `framing_split_marker`; the owner,
## 2026-11-23: the camera no longer frames close foes), the black void with its
## motes and the big lit doorway signs (`framing_void_signs`), a sign rising in by rows as the
## wizard comes near (`framing_sign_rises`, a strip), and an unentered room's black opening
## by shrinking blocks as the wizard steps in (`framing_dark_opens`: a strip of its stages).

const BiomeMaps := preload("res://tests/support/biome_maps.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Registry", "Projectiles"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry: Node = root.get_node("Registry")
	var feel: Node = root.get_node("Feel")
	# The keyboard's seat: one played on this machine (a virtual device's is another machine's, and
	# only this machine's seats get foe markers).
	input.call("join_as", InputManagerScript.KEYBOARD, 0)
	# A second seat played here (a gamepad's), kept beside the first until the split shot.
	input.call("join_as", 0, 1)
	var map: BiomeMap = BiomeMaps.split(registry, [0, 0, 0] as Array[int], [&"arena_04", BiomeMaps.MIDDLE, BiomeMaps.LAST] as Array[StringName])
	var imps: Array[StringName] = [&"ember_imp", &"ember_imp", &"ember_imp"]
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.of(imps), RoomFight.new()]
	if not flow.call("start_biome", 0, map, fights):
		fail("the biome did not start")
		return
	await settle()
	var wizard := flow.call("get_wizard", 0) as Node2D
	var second := flow.call("get_wizard", 1) as Node2D
	if wizard == null or second == null:
		fail("the two wizards were not made")
		return
	# The void and the signs: on the nave's east bridge, the court beyond still black.
	var east: Vector2 = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.EAST)
	# A sign rising as the wizard comes near (a row a frame at 12 fps, lit as it rises).
	wizard.global_position = east - Vector2(400.0, 0.0)
	second.global_position = wizard.global_position + Vector2(12.0, 0.0)
	await settle(60)
	wizard.global_position = east - Vector2(24.0, 0.0)
	second.global_position = wizard.global_position + Vector2(12.0, 0.0)
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
	second.global_position = wizard.global_position + Vector2(12.0, 0.0)
	await settle(60)
	await shot("framing_void_signs")
	# The antechamber's sealed fight: the camera stays on the wizard, a marker points at an imp out of view.
	var west_room: Vector2 = BiomeMaps.socket_point(registry, map, 1, RoomSocket.Facing.EAST)
	wizard.global_position = west_room - Vector2(40.0, 0.0)
	second.global_position = wizard.global_position + Vector2(12.0, 0.0)
	await settle(120)
	var grid: RoomGrid = root.get_node("Projectiles").call("grid") as RoomGrid
	if not grid.is_sealed(1):
		fail("the antechamber did not seal in framing_sealed_fight")
		return
	# The wizard in one corner of the room, an imp in the far one, out of the picture.
	var table: Node = root.get_node("Actors")
	var ids := PackedInt32Array()
	var room: Rect2 = grid.place_rect(1)
	# One imp in the far corner, the others beside the wizard (in the picture: no marker for them).
	var far_imp: Node2D = null
	for i in int(table.call("open_ids", ids)):
		if int(table.call("team_of", ids[i])) == 1:
			var imp := table.call("node_of", ids[i]) as Node2D
			if imp == null:
				continue
			if far_imp == null:
				far_imp = imp
				imp.global_position = room.position + Vector2(56.0, 56.0)
			else:
				imp.global_position = room.end - Vector2(150.0, 150.0)
	wizard.global_position = room.end - Vector2(56.0, 56.0)
	second.global_position = wizard.global_position + Vector2(12.0, 0.0)
	await settle(90)
	var markers: Object = feel.call("foe_markers") as Object
	if markers == null or int(markers.get("count")) == 0:
		fail("no foe marker in framing_sealed_fight: the imp in the far corner is in the picture (room %s)" % room)
		return
	var camera: Object = feel.get("party_camera")
	print("FRAMING: %d foe markers, zoom %.2f, room %s" % [int(markers.get("count")), float(camera.get("target_zoom")), room])
	await settle()
	var fight: Image = await grab()
	save(fight, "framing_sealed_fight")
	save_crop(fight, markers.call("position_of", 0) as Vector2, "framing_foe_marker", Vector2i(24, 24))
	# The court entered: its black opens by shrinking blocks, a stage a frame at 12 fps.
	var court: Vector2 = BiomeMaps.socket_point(registry, map, 2, RoomSocket.Facing.WEST)
	wizard.global_position = court - Vector2(40.0, 0.0)
	second.global_position = wizard.global_position + Vector2(12.0, 0.0)
	await settle(60)
	wizard.global_position = court + Vector2(24.0, 0.0)
	second.global_position = wizard.global_position + Vector2(12.0, 0.0)
	var frames: Array[Image] = []
	for stage in 6:
		frames.append(crop_round(await grab(), on_screen(court + Vector2(150.0, 110.0)), Vector2i(80, 60)))
		await settle(5)
	var strip := Image.create(frames[0].get_width() * frames.size(), frames[0].get_height(), false, frames[0].get_format())
	for i in frames.size():
		strip.blit_rect(frames[i], Rect2i(Vector2i.ZERO, frames[i].get_size()), Vector2i(frames[0].get_width() * i, 0))
	save(strip, "framing_dark_opens")
	# Split: the second seat stays in the court, the first goes back to its fight; the far imp's
	# marker sits in the first seat's own cell.
	second.global_position = court + Vector2(300.0, 0.0)
	wizard.global_position = room.end - Vector2(56.0, 56.0)
	await settle(240)
	var split: Object = feel.get("split_screen")
	if not bool(split.call("is_drawing")) or int(markers.get("count")) == 0:
		fail("framing_split_marker: split %s, %d foe markers" % [split.call("is_drawing"), int(markers.get("count"))])
		return
	print("FRAMING: split, %d foe markers, the first at %s" % [int(markers.get("count")), markers.call("position_of", 0)])
	await shot("framing_split_marker")
