extends "res://tests/support/screenshot.gd"
## Screenshots of every room template a run's map can pick (content/rooms: a room that hosts a kind,
## found by folder), each as the game plays it: four wizards at its player spawns and the enemies the
## run fills it with, so a new room shows up here with no edit.
##
## Shots: `room_<id>`, one a template, just after its run starts; `room_<id>_fight` a few seconds into
## its fight, the four wizards casting up into it, with spell light on, and `room_<id>_fight_plain`
## half a second on (each shot settles first) with spell light off (crypt rework, docs/milestones/crypt-rework.md, rule 6: shots,
## enemies and wizards read first, the dark stays out of the fight).

## How long the wizards cast before the fight's shots, in frames.
const FIGHT_FRAMES: int = 150

const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const RegistryScript := preload("res://core/registry/registry.gd")


func take() -> void:
	if not need(["PlayerInput", "Flow", "Registry"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry := root.get_node("Registry") as RegistryScript
	for index in 4:
		input.call("add_virtual_device", index)
	var templates: Array[RoomBase] = RoomScan.templates(registry)
	if templates.is_empty():
		fail("no room template was found")
		return
	for room: RoomBase in templates:
		flow.set("run_id_to_play", PinnedRun.pin(registry, room))
		if not flow.call("start_run", 0):
			fail("the run of %s did not start" % room.id)
			return
		await shot("room_%s" % room.id)
		await _fight(input, room)


## The wizards cast up into the room's fight, the two shots taken, and their hands let go.
func _fight(input: Node, room: RoomBase) -> void:
	var feel: Node = root.get_node_or_null("Feel")
	for index in 4:
		input.call("send_virtual_aim", index, Vector2.UP)
		input.call("send_virtual", index, &"staff_1", 1.0)
	await settle(FIGHT_FRAMES)
	var was_on: bool = feel != null and feel.call("light") != null
	if feel != null:
		feel.call("set_spell_light", true)
	await shot("room_%s_fight" % room.id)
	if feel != null:
		feel.call("set_spell_light", false)
		await shot("room_%s_fight_plain" % room.id)
		feel.call("set_spell_light", was_on)
	for index in 4:
		input.call("send_virtual", index, &"staff_1", 0.0)
