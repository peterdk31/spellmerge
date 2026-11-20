extends "res://tests/support/screenshot.gd"
## Screenshots of the crypt's low floor mist (docs/milestones/atmosphere.md, F: `RoomBase.mist`,
## gameplay/feel/mist.gd): thin over a fight's middle, thicker toward the slab's edge and the pits,
## lit by the spell light, parted by bodies and pushed by shots and blasts.
##
## Shots: `mist_fight`, a crypt fight (four wizards casting up into it) with its mist and spell
## light on; `mist_fight_off` the same moment with the mist taken away (what it adds, side by side);
## `mist_fight_plain` with spell light off (no mist is drawn); `mist_walk`, a filmstrip of FRAMES
## frames GAP apart at ZOOM of a wizard walking through the mist pooled by the room's pit (it parts round its
## feet and closes behind it); `mist_blast`, a blast in the mist (pushed out as its wave passes and
## drifting back); `mist_shots`, shots through it (dragged along their way); `mist_pit`, the crossing's
## pit with the mist pooled over it; `mist_boss`, the broom's hall; and `mist_walled_<room>`, rooms
## whose slab's dark is drawn as walls out to their edge (WALLED_ROOMS), thin over their middle and
## round their pillars and tombs (playtest, 2026-11-20: their mist lay thick over the whole room). The
## HUD is hidden.

const RegistryScript := preload("res://core/registry/registry.gd")

const ROOM: StringName = &"arena_02"
const PIT_ROOM: StringName = &"arena_04"
const BOSS_ROOM: StringName = &"boss_broom"
const WALLED_ROOMS: Array[StringName] = [&"arena_07", &"arena_11"]
const FIGHT_FRAMES: int = 150
const FRAMES: int = 6
const GAP: int = 7
const ZOOM: int = 4
## Where the walk's crop is from the pit's middle.
const WALK_FROM_PIT: Vector2 = Vector2(24.0, -34.0)
## Where the blast is from the pit's middle (the shots cross the pit itself).
const BLAST_FROM_PIT: Vector2 = Vector2(36.0, -6.0)
const WALK_CROP: Vector2i = Vector2i(56, 30)
const BLAST_CROP: Vector2i = Vector2i(56, 34)
const BLAST_RADIUS: float = 16.0


func take() -> void:
	if not need(["PlayerInput", "Flow", "Registry", "Feel", "Events", "Projectiles"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var feel: Node = root.get_node("Feel")
	var registry := root.get_node("Registry") as RegistryScript
	for index in 4:
		input.call("add_virtual_device", index)
	if not _start(flow, registry, ROOM):
		return
	feel.call("set_spell_light", true)
	# Before the fight: the walk, the blast and the shots, while nobody is down.
	await _walk(input, flow, feel)
	await _blast(flow, feel)
	await _shots(flow, feel)
	if not _start(flow, registry, ROOM):
		return
	for index in 4:
		input.call("send_virtual_aim", index, Vector2.UP)
		input.call("send_virtual", index, &"staff_1", 1.0)
	await settle(FIGHT_FRAMES)
	paused = true
	await settle(2)
	await shot("mist_fight")
	var spectacle: Node = feel.call("spectacle")
	var mist: Node = spectacle.get("mist")
	if mist == null:
		fail("no mist with spell light on")
		return
	var room := registry.get_resource(&"rooms", ROOM) as RoomBase
	mist.call("use", null)
	await settle(2)
	await shot("mist_fight_off")
	mist.call("use", room.mist)
	feel.call("set_spell_light", false)
	await settle(2)
	await shot("mist_fight_plain")
	feel.call("set_spell_light", true)
	paused = false
	for index in 4:
		input.call("send_virtual", index, &"staff_1", 0.0)
	if not _start(flow, registry, PIT_ROOM):
		return
	await settle(90)
	var pit: Vector2 = _pit_middle(feel)
	if pit.is_finite():
		save_crop(await grab(), on_screen(pit), "mist_pit", Vector2i(80, 56), 3)
	if not _start(flow, registry, BOSS_ROOM):
		return
	await settle(150)
	await shot("mist_boss")
	for id in WALLED_ROOMS:
		if not _start(flow, registry, id):
			return
		await settle(150)
		await shot("mist_walled_%s" % id)


func _start(flow: Node, registry: RegistryScript, id: StringName) -> bool:
	var room := registry.get_resource(&"rooms", id) as RoomBase
	if room == null or room.mist == null:
		fail("%s has no mist to show" % id)
		return false
	flow.set("run_id_to_play", PinnedRun.pin(registry, room))
	if not flow.call("start_run", 0):
		fail("the run of %s did not start" % id)
		return false
	var hud := root.get_node_or_null("Hud") as CanvasLayer
	if hud != null:
		hud.visible = false
	return true


## A wizard walking right through the mist by the slab's edge, the crop held still.
func _walk(input: Node, flow: Node, feel: Node) -> void:
	var wizard := flow.call("get_wizard", 0) as Node2D
	# Just above the room's pit, where the mist pools thickest.
	var at: Vector2 = _pit_middle(feel) + WALK_FROM_PIT
	if wizard == null or not at.is_finite():
		fail("no wizard or no pit")
		return
	for index in [1, 2, 3]:
		var other := flow.call("get_wizard", index) as Node2D
		if other != null:
			other.global_position = at + Vector2(-60.0 + 40.0 * index, -170.0)
	wizard.global_position = at + Vector2(-44.0, 0.0)
	await settle(40)
	input.call("send_virtual", 0, &"move_right", 1.0)
	var frames: Array[Image] = []
	for frame in FRAMES:
		frames.append(crop_round(await grab(), on_screen(at), WALK_CROP))
		await settle(GAP - 1)
	input.call("send_virtual", 0, &"move_right", 0.0)
	_save_strip(frames, "mist_walk")


## A blast in the mist by the slab's edge, the wizards away.
func _blast(flow: Node, feel: Node) -> void:
	var wizard := flow.call("get_wizard", 0) as Node2D
	var at: Vector2 = _pit_middle(feel) + BLAST_FROM_PIT
	if not at.is_finite():
		return
	wizard.global_position = at + Vector2(90.0, -80.0)
	await settle(40)
	root.get_node("Events").emit_signal(&"cue_shown", 0, &"blast", at, Vector2.ZERO, BLAST_RADIUS, Color.WHITE, 0)
	var frames: Array[Image] = []
	for frame in FRAMES:
		frames.append(crop_round(await grab(), on_screen(at), BLAST_CROP))
		await settle(GAP - 1)
	_save_strip(frames, "mist_blast")


## Shots through the mist by the slab's edge.
func _shots(flow: Node, feel: Node) -> void:
	var wizard := flow.call("get_wizard", 0) as Node2D
	var at: Vector2 = _pit_middle(feel)
	if not at.is_finite():
		return
	wizard.global_position = at + Vector2(110.0, -90.0)
	await settle(60)
	var shots: Node = root.get_node("Projectiles")
	for k in 4:
		shots.call("spawn", int(wizard.get("id")), at + Vector2(-60.0 - 14.0 * float(k), float(k % 2) * 8.0 - 4.0), Vector2.RIGHT * 220.0, 3.0, 4.0, 0)
	await settle(8)
	var frames: Array[Image] = []
	for frame in FRAMES:
		frames.append(crop_round(await grab(), on_screen(at), BLAST_CROP))
		await settle(GAP - 1)
	_save_strip(frames, "mist_shots")


## The middle of the room's holes (INF: none).
func _pit_middle(feel: Node) -> Vector2:
	var holes: Array[Rect2] = feel.call("spectacle").get("_room_holes")
	if holes.is_empty():
		return Vector2.INF
	var box: Rect2 = holes[0]
	for hole in holes:
		box = box.merge(hole)
	return box.get_center()


## The frames side by side, a pixel of black between, at ZOOM.
func _save_strip(frames: Array[Image], shot_name: String) -> void:
	if frames.is_empty():
		return
	var w: int = frames[0].get_width()
	var h: int = frames[0].get_height()
	var strip := Image.create_empty((w + 1) * frames.size() - 1, h, false, frames[0].get_format())
	strip.fill(Color.BLACK)
	for k in frames.size():
		strip.blit_rect(frames[k], Rect2i(Vector2i.ZERO, Vector2i(w, h)), Vector2i(k * (w + 1), 0))
	strip.resize(strip.get_width() * ZOOM, strip.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	save(strip, shot_name)
