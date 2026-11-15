extends "res://tests/support/screenshot.gd"
## Screenshots of every room template a run's map can pick (content/rooms: a room that hosts a kind,
## found by folder), each as the game plays it: four wizards at its player spawns and the enemies the
## run fills it with, so a new room shows up here with no edit.
##
## Shots: `room_<id>`, one a template, just after its run starts.

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
