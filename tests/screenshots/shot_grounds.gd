extends "res://tests/support/screenshot.gd"
## The grounds as they are played (ART3 part 3: the floors, edges, pits, bridges, rock faces and the
## hub's island drawn at 2x detail, gameplay/feel/ground/): each room started as a run, its floor
## baked as the game shows it, the game held while the shot is taken; and two crops of each, 4 times
## big, round the first wizard and round a point of the room's ground (an edge, a pit).
##
## Shots: `ground_<id>`, `ground_<id>_crop_wizard`, `ground_<id>_crop_ground` a room, then
## `ground_hub`, `ground_hub_crop_wizard`, `ground_hub_crop_ground`.

const ROOMS: Array[StringName] = [&"arena_02", &"arena_04", &"crypt_fountain", &"arena_05"]
## A point of each room's ground to crop round (world px from the wizard): its edge or a pit.
const GROUND_AT: Dictionary = {
	&"arena_02": Vector2(-120, 60), &"arena_04": Vector2(0, -70), &"crypt_fountain": Vector2(90, 40),
	&"arena_05": Vector2(60, -40), &"hub": Vector2(-150, -40),
}
## How much of the picture a crop holds, in layout px each way from its middle.
const CROP_HALF := Vector2i(64, 40)

const RegistryScript := preload("res://core/registry/registry.gd")


func take() -> void:
	if not need(["PlayerInput", "Flow", "Registry", "Feel", "Events"]):
		return
	settle_frames = 40
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry := root.get_node("Registry") as RegistryScript
	for index in 2:
		input.call("add_virtual_device", index)
	for id: StringName in ROOMS:
		var room := registry.get_resource(&"rooms", id) as RoomBase
		if room == null:
			fail("no room %s" % id)
			return
		flow.set("run_id_to_play", PinnedRun.pin(registry, room))
		if not flow.call("start_run", 0):
			fail("the run of %s did not start" % id)
			return
		await settle()
		await _take(String(id), flow)
	# The hub starts only once no run is going (Flow's `_on_hub_requested`).
	flow.call("stop_run")
	await settle(5)
	root.get_node("Events").emit_signal("hub_requested", 0)
	if not await wait_for(func() -> bool: return flow.get("mode") == &"hub" and flow.call("get_wizard", 0) != null, 600):
		fail("the hub did not start")
		return
	await settle()
	await _take("hub", flow)


func _take(id: String, flow: Node) -> void:
	root.get_tree().paused = true
	Engine.time_scale = 0.0
	await settle(10)
	var image: Image = await grab()
	save(image, "ground_%s" % id)
	var wizard := flow.call("get_wizard", 0) as Node2D
	if wizard != null:
		save_crop(image, on_screen(wizard.global_position), "ground_%s_crop_wizard" % id, CROP_HALF, 4)
		save_crop(image, on_screen(wizard.global_position + (GROUND_AT.get(StringName(id), Vector2.ZERO) as Vector2)), "ground_%s_crop_ground" % id, CROP_HALF, 4)
	root.get_tree().paused = false
	Engine.time_scale = 1.0
