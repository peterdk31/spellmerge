extends "res://tests/support/screenshot.gd"
## Screenshots of the light in a bigger picture (the owner's decisions of 2026-11-21 and 2026-11-22,
## docs/milestones/connected-biomes.md, "The light at a fixed resolution" and "One pass"):
## the crypt's mist room in a fight (four wizards casting up into it: the shots' light, the torches',
## the room's dark and its mist) and the broom's hall, with spell light on.
##
## Shots, at the picture's size: `light_res_<w>x<h>_fight` and `light_res_<w>x<h>_hall`. The picture is
## the project's (640 x 360), or the size `--picture=WxH` asks for (the root's `content_scale_size`: the
## cameras draw the same world finer, the light a world pixel at a time); run it at both, on two checkouts,
## to compare them pixel by pixel. The HUD is hidden.

const RegistryScript := preload("res://core/registry/registry.gd")
const BiomeFramesScript := preload("res://bench/biome_frames_runner.gd")

const ROOM: StringName = &"arena_02"
const HALL: StringName = &"boss_broom"
const FIGHT_FRAMES: int = 150


func take() -> void:
	if not need(["PlayerInput", "Flow", "Registry", "Feel"]):
		return
	settle_frames = 30
	var picture: Vector2i = BiomeFramesScript.picture_asked(OS.get_cmdline_user_args())
	if picture != Vector2i.ZERO:
		root.content_scale_size = picture
	var size: Vector2i = Vector2i(root.get_visible_rect().size)
	var named: String = "light_res_%dx%d" % [size.x, size.y]
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var feel: Node = root.get_node("Feel")
	var registry := root.get_node("Registry") as RegistryScript
	for index in 4:
		input.call("add_virtual_device", index)
	if not _start(flow, registry, ROOM):
		return
	feel.call("set_spell_light", true)
	for index in 4:
		input.call("send_virtual_aim", index, Vector2.UP)
		input.call("send_virtual", index, &"staff_1", 1.0)
	await settle(FIGHT_FRAMES)
	paused = true
	await settle(2)
	await shot("%s_fight" % named)
	paused = false
	for index in 4:
		input.call("send_virtual", index, &"staff_1", 0.0)
	if not _start(flow, registry, HALL):
		return
	await settle(150)
	await shot("%s_hall" % named)


func _start(flow: Node, registry: RegistryScript, id: StringName) -> bool:
	var room := registry.get_resource(&"rooms", id) as RoomBase
	if room == null:
		fail("no room %s" % id)
		return false
	flow.set("run_id_to_play", PinnedRun.pin(registry, room))
	if not flow.call("start_run", 0):
		fail("the run of %s did not start" % id)
		return false
	var hud := root.get_node_or_null("Hud") as CanvasLayer
	if hud != null:
		hud.visible = false
	return true
