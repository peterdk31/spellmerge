extends "res://tests/support/screenshot.gd"
## Screenshots of ground cover's look (ground cover GC3, docs/milestones/ground-cover.md): every room
## template a run's map can pick (content/rooms, found by folder, as `shot_rooms.gd`), each just after
## its run starts with four wizards in it, covered by a stand-in grass (tests/support/stand_in_grass.gd) that fills every
## template's biome (the game has no cover of its own before GC8; the art is GC8's), a moment of its
## wind. A new room shows up here with no edit.
##
## Shots: `cover_<id>`, one a template; `cover_<id>_close`, its first player spawn's corner at 4×.

const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const StandInGrass := preload("res://tests/support/stand_in_grass.gd")


func take() -> void:
	if not need(["PlayerInput", "Flow", "Registry", "Feel"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry := root.get_node("Registry") as RegistryScript
	var feel := root.get_node("Feel") as FeelScript
	for index in 4:
		input.call("add_virtual_device", index)
	var templates: Array[RoomBase] = RoomScan.templates(registry)
	if templates.is_empty():
		fail("no room template was found")
		return
	var biomes: Array[StringName] = []
	for room in templates:
		if room.biome != &"" and not biomes.has(room.biome):
			biomes.append(room.biome)
	feel.cover().use_kinds([StandInGrass.make(biomes)] as Array[CoverKind])
	for room: RoomBase in templates:
		flow.set("run_id_to_play", PinnedRun.pin(registry, room))
		if not flow.call("start_run", 0):
			fail("the run of %s did not start" % room.id)
			return
		if feel.cover().layout == null or feel.cover().layout.count() == 0:
			fail("%s was given no cover" % room.id)
			return
		await shot("cover_%s" % room.id)
		var spawns: PackedVector2Array = room.places().player_spawns
		if not spawns.is_empty():
			await snap(spawns[0], "cover_%s_close" % room.id, Vector2i(64, 40))
	feel.cover().use_kinds(null)
