extends "res://tests/support/screenshot.gd"
## Screenshots of ground cover's look (ground cover GC3, docs/milestones/ground-cover.md): every room
## template a run's map can pick (content/rooms, found by folder, as `shot_rooms.gd`), each just after
## its run starts with four wizards in it, covered by a stand-in grass made here that fills every
## template's biome (the game has no cover of its own before GC8; the art is GC8's), still and in the
## wind. A new room shows up here with no edit.
##
## Shots: `cover_<id>`, one a template; `cover_<id>_close`, its first player spawn's corner at 4×.

const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")

## The stand-in grass's colours (docs/STYLE.md's greens: dark, base, light).
const DARK := Color("1e4d2b")
const BASE := Color("3d8a3a")
const LIGHT := Color("8fcf5a")


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
	feel.cover().use_kinds([_grass(biomes)] as Array[CoverKind])
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


## The stand-in grass: the test grass's states (tests/core/fixtures/cover_content), filling `biomes`,
## with a sheet of six frames drawn here (three at rest, two burning, one of ash).
func _grass(biomes: Array[StringName]) -> CoverKind:
	var kind := (load("res://tests/core/fixtures/cover_content/cover/test_grass/test_grass.tres") as CoverKind).duplicate(true) as CoverKind
	kind.id = &"preview_grass"
	kind.biomes = biomes
	kind.fill_density = 0.06
	kind.clump_size = 3
	kind.sway = 1.5
	kind.sheet = _sheet()
	return kind


## Six 16×16 tufts: blades from the foot up, a dark side and a lit tip each.
static func _sheet() -> Texture2D:
	var image := Image.create_empty(96, 16, false, Image.FORMAT_RGBA8)
	var blades: Array[PackedInt32Array] = [
		PackedInt32Array([5, 9, 7, 6, 10, 9]),
		PackedInt32Array([4, 7, 8, 11, 6, 10]),
		PackedInt32Array([6, 10, 8, 7, 9, 8]),
	]
	for frame in 3:
		var shape: PackedInt32Array = blades[frame]
		for blade in 3:
			var x: int = frame * 16 + shape[blade * 2]
			var height: int = shape[blade * 2 + 1]
			for y in range(16 - height, 16):
				image.set_pixel(x, y, DARK if y > 13 else BASE)
			image.set_pixel(x, 16 - height, LIGHT)
	# Burning: shorter blades in flame colours; ash: a low grey stubble.
	for frame in [3, 4]:
		for blade in 3:
			var x: int = frame * 16 + 5 + blade * 3
			for y in range(9 + (blade + frame) % 3, 16):
				image.set_pixel(x, y, Color("f2a93b") if y < 12 else Color("b8442f"))
	for blade in 4:
		image.set_pixel(80 + 5 + blade * 2, 15, Color("5b5966"))
		image.set_pixel(80 + 5 + blade * 2, 14, Color("7a7694"))
	return ImageTexture.create_from_image(image)
