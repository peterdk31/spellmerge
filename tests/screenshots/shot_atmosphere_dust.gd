extends "res://tests/support/screenshot.gd"
## Screenshots of the crypt's lit dust in the air (docs/milestones/atmosphere.md, B: `RoomBase.air`,
## the lit-only `air_dust` kind): a crypt room in a fight, four wizards casting up into it, the dust
## drifting over the whole room but seen only where light falls (the candles' pools, the wizards'
## carried lights, the shots going past).
##
## Shots: `dust_fight` with spell light on; `dust_fight_bare` the same fight a few seconds after
## its air is taken away (the dust gone: what it adds, side by side); `dust_fight_plain` with spell
## light off (no dust is drawn); `dust_candle`, a close crop round the candle nearest the middle of
## the view, and `dust_wizard` round a wizard, each with spell light on; then `dust_hub` and
## `dust_hub_wizard`, the hub's glimmers in its wizards' lights.

const RegistryScript := preload("res://core/registry/registry.gd")

## The crypt room shown, how long the wizards cast before the shots and how long the dust takes to
## clear once the air is gone (its longest life), in frames.
const ROOM: StringName = &"arena_02"
const FIGHT_FRAMES: int = 150
const CLEAR_FRAMES: int = 260


func take() -> void:
	if not need(["PlayerInput", "Flow", "Registry", "Feel", "Events"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var feel: Node = root.get_node("Feel")
	var registry := root.get_node("Registry") as RegistryScript
	var room := registry.get_resource(&"rooms", ROOM) as RoomBase
	if room == null or room.air == null:
		fail("%s has no air to show" % ROOM)
		return
	for index in 4:
		input.call("add_virtual_device", index)
	flow.set("run_id_to_play", PinnedRun.pin(registry, room))
	if not flow.call("start_run", 0):
		fail("the run of %s did not start" % ROOM)
		return
	feel.call("set_spell_light", true)
	for index in 4:
		input.call("send_virtual_aim", index, Vector2.UP)
		input.call("send_virtual", index, &"staff_1", 1.0)
	await settle(FIGHT_FRAMES)
	var image: Image = await grab()
	save(image, "dust_fight")
	var candle: Node2D = _candle_nearest(root.get_canvas_transform().affine_inverse() * (root.get_visible_rect().size * 0.5))
	if candle != null:
		save_crop(image, on_screen(candle.global_position), "dust_candle", Vector2i(56, 40), 4)
	var wizard: Node2D = get_first_node_in_group(&"wizards") as Node2D
	if wizard != null:
		save_crop(image, on_screen(wizard.global_position), "dust_wizard", Vector2i(56, 40), 4)
	feel.call("set_spell_light", false)
	await shot("dust_fight_plain")
	feel.call("set_spell_light", true)
	var spectacle: Node = feel.call("spectacle")
	spectacle.get("air").call("use", null)
	await settle(CLEAR_FRAMES)
	await shot("dust_fight_bare")
	for index in 4:
		input.call("send_virtual", index, &"staff_1", 0.0)
	await _hub(flow)


## The hub's glimmers (its air, `air_glimmer`), seen only round the wizards' lights: `dust_hub` and
## `dust_hub_wizard`, a close crop round a wizard there.
func _hub(flow: Node) -> void:
	flow.call("stop_run")
	root.get_node("Events").emit_signal("hub_requested", 0)
	if not await wait_for(func() -> bool: return flow.get("mode") == &"hub" and flow.call("get_wizard", 0) != null, 600):
		fail("the hub did not start")
		return
	await settle(FIGHT_FRAMES)
	var image: Image = await grab()
	save(image, "dust_hub")
	var wizard := flow.call("get_wizard", 0) as Node2D
	if wizard != null:
		save_crop(image, on_screen(wizard.global_position), "dust_hub_wizard", Vector2i(56, 40), 4)


## The room's light spot (a candle's flame) nearest `to`, or null.
func _candle_nearest(to: Vector2) -> Node2D:
	var best: Node2D = null
	for node: Node in get_nodes_in_group(LightSpot.GROUP):
		var spot := node as Node2D
		if spot != null and (best == null or spot.global_position.distance_to(to) < best.global_position.distance_to(to)):
			best = spot
	return best
