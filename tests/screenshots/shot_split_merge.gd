extends "res://tests/support/screenshot.gd"
## A strip of the Dynamic split merging as two players walk back together (the owner's report of
## 2026-11-21: "the voronoi line split does not disappear for some time"; gameplay/feel/
## split_camera.gd, MERGE_TIME). On the split test map (tests/support/biome_maps.gd), two players on
## this machine (virtual devices) parted into the antechamber west and the ossuary court east; then the east one
## walks back to the other at a wizard's pace (90 px/s). `split_merge_walk_back`: every 6th frame
## (a tenth of a second) from the frame the screen stops wanting the split, 12 of them, left to
## right and top to bottom, half size: the divider shrinks out and the one picture is left while
## the walker is still on the way (it used to stay until the walker stopped, and seconds after).

const BiomeMaps := preload("res://tests/support/biome_maps.gd")

## A wizard's pace a frame (90 px/s at 60 fps).
const STEP: float = 1.5
## Frames between the strip's pictures, and how many.
const EVERY: int = 6
const COUNT: int = 12


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Registry"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry: Node = root.get_node("Registry")
	var feel: Node = root.get_node("Feel")
	feel.call("set_split_mode", SplitScreenSetting.DYNAMIC)
	var map: BiomeMap = BiomeMaps.split(registry)
	var east: Vector2 = BiomeMaps.socket_point(registry, map, 2, RoomSocket.Facing.WEST)
	var west: Vector2 = BiomeMaps.socket_point(registry, map, 1, RoomSocket.Facing.EAST)
	input.call("add_virtual_device", 0)
	input.call("add_virtual_device", 1)
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.new(), RoomFight.new()]
	if not flow.call("start_biome", 0, map, fights):
		fail("the biome did not start")
		return
	await settle(30)
	var a := flow.call("get_wizard", 0) as Node2D
	var b := flow.call("get_wizard", 1) as Node2D
	if a == null or b == null:
		fail("no wizards")
		return
	a.global_position = west - Vector2(120.0, 0.0)
	b.global_position = east + Vector2(120.0, 0.0)
	await settle(150)
	var camera: Object = (feel.get("split_screen") as Object).get("camera")
	if not bool(camera.get("split")):
		fail("parted: not split")
		return
	# From here Feel steps on the frame's delta (a sixtieth of a second with --fixed-fps 60), not the
	# real clock, which a slow software render stretches: the strip's frames are the game's at 60 fps.
	feel.set("drive_engine", false)
	var frames: Array[Image] = []
	var frame: int = 0
	var started: int = -1
	while frames.size() < COUNT and frame < 3000:
		frame += 1
		var to: Vector2 = a.global_position + Vector2(48.0, 0.0) - b.global_position
		b.global_position += to.limit_length(STEP)
		if started < 0 and not bool(camera.get("split")):
			started = frame
		if started >= 0 and (frame - started) % EVERY == 0:
			var image: Image = await grab()
			image.resize(image.get_width() >> 1, image.get_height() >> 1, Image.INTERPOLATE_NEAREST)
			frames.append(image)
			var views: int = int(camera.get("views").get("count"))
			print("SPLIT MERGE: %.2f s after the split's end: %d views, the walker %.0f px from the other" % [float(frame - started) / 60.0, views, a.global_position.distance_to(b.global_position)])
		else:
			await process_frame
	if frames.size() < COUNT:
		fail("the split never ended")
		return
	var strip := Image.create(frames[0].get_width() * 4, frames[0].get_height() * 3, false, frames[0].get_format())
	for i in frames.size():
		strip.blit_rect(frames[i], Rect2i(Vector2i.ZERO, frames[i].get_size()), Vector2i(frames[0].get_width() * (i % 4), frames[0].get_height() * (i >> 2)))
	save(strip, "split_merge_walk_back")
