extends "res://tests/support/screenshot.gd"
## Screenshots of the "Effects" setting's rows (core/settings/effects_setting.gd; gameplay/feel/
## effects_quality.gd; the owner's choice of 2026-11-21): the crypt's mist room in a fight (four
## wizards casting up into it: the shots' light, the torches', the room's dark, its mist and its air)
## drawn at each row, Low, Medium and High, one after the other (Feel's `set_effects_mode`).
##
## Shots: `effects_low`, `effects_medium`, `effects_high`, and `effects_rows` (the three side by side,
## left to right). The HUD is hidden. The fight moves on between them, so the shots are a few frames
## apart.

const RegistryScript := preload("res://core/registry/registry.gd")
const EffectsQualityScript := preload("res://gameplay/feel/effects_quality.gd")

const ROOM: StringName = &"arena_04"
const FIGHT_FRAMES: int = 120
## The rows, left to right, and the setting's mode for each.
const MODES: Array[int] = [EffectsSetting.LOW, EffectsSetting.MEDIUM, EffectsSetting.HIGH]


func take() -> void:
	if not need(["PlayerInput", "Flow", "Registry", "Feel"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var feel: Node = root.get_node("Feel")
	var registry := root.get_node("Registry") as RegistryScript
	for index in 4:
		input.call("add_virtual_device", index)
	var room := registry.get_resource(&"rooms", ROOM) as RoomBase
	if room == null:
		fail("no room %s" % ROOM)
		return
	flow.set("run_id_to_play", PinnedRun.pin(registry, room))
	if not flow.call("start_run", 0):
		fail("the run of %s did not start" % ROOM)
		return
	var hud := root.get_node_or_null("Hud") as CanvasLayer
	if hud != null:
		hud.visible = false
	feel.call("set_spell_light", true)
	feel.call("set_fog", true)
	for index in 4:
		input.call("send_virtual_aim", index, Vector2.UP)
		input.call("send_virtual", index, &"staff_1", 1.0)
	await settle(FIGHT_FRAMES)
	var shots: Array[Image] = []
	for mode: int in MODES:
		feel.call("set_effects_mode", mode)
		await settle(4)
		var drawn: int = int(((feel.call("spectacle") as Object).get("quality") as Object).get("level"))
		if drawn != int(EffectsQualityScript.of_setting(mode)):
			fail("%s asked, row %d drawn" % [EffectsSetting.word_of(mode), drawn])
			return
		var image: Image = await grab()
		if not save(image, "effects_" + EffectsSetting.word_of(mode).to_lower()):
			return
		shots.append(image)
	var width: int = shots[0].get_width()
	var height: int = shots[0].get_height()
	var rows := Image.create(width * shots.size() + 4 * (shots.size() - 1), height, false, shots[0].get_format())
	rows.fill(Color.BLACK)
	for at in shots.size():
		rows.blit_rect(shots[at], Rect2i(0, 0, width, height), Vector2i(at * (width + 4), 0))
	save(rows, "effects_rows")
	for index in 4:
		input.call("send_virtual", index, &"staff_1", 0.0)
