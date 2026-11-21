extends "res://tests/support/screenshot.gd"
## Before and after of the performance pass of 2026-11-21, round two (docs/LOG.md, "Baked floors"),
## each pair in one held frame: a room's floor baked into one texture (`floor_bake.gd`), its
## enemies' bodies and faces on one page a kind (`TexturePage`, `CreatureLook`) and its candles on
## one page (`decal_pages.gd`), then the same frame with all three put back as they were (the floor's
## layers shown again, every region swapped for the texture it was copied from). The game is held
## (paused, its time stopped) while the pair is taken, so the two differ only by what was changed.
##
## Shots: `baked_<id>_after`, `baked_<id>_before` (rooms with shades, cobwebs and candles), and
## `baked_<id>_crop_after`, `_crop_before` round a wall's shade over its ground cover, 4 times big.

const ROOMS: Array[StringName] = [&"arena_02", &"arena_03", &"arena_04", &"arena_11"]
## Where each room's crop is (world px): a wall's shade over a cobweb.
const CROPS: Dictionary = {&"arena_02": Vector2(390, 196), &"arena_04": Vector2(320, 224)}

const RegistryScript := preload("res://core/registry/registry.gd")
const FloorBakeScript := preload("res://gameplay/feel/ground/floor_bake.gd")
const DecalPagesScript := preload("res://gameplay/feel/decal_pages.gd")


func take() -> void:
	if not need(["PlayerInput", "Flow", "Registry", "Feel"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry := root.get_node("Registry") as RegistryScript
	var ground: Node = root.get_node("Feel").get_node("Ground")
	ground.get("bake").set("keep_layers", true)
	for index in 4:
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
		var bakes: Array[Node] = root.find_children(String(FloorBakeScript.BAKE), "", true, false)
		if bakes.is_empty() or not FloorBakeScript.is_baked(bakes[0].get_parent()):
			fail("the floor of %s was not baked" % id)
			return
		root.get_tree().paused = true
		Engine.time_scale = 0.0
		await settle(10)
		var after: Image = await grab()
		save(after, "baked_%s_after" % id)
		for bake: Node in bakes:
			FloorBakeScript.unshow(bake.get_parent())
		_unpage(root)
		await settle(2)
		var before: Image = await grab()
		save(before, "baked_%s_before" % id)
		if CROPS.has(id):
			save_crop(after, on_screen(CROPS[id]), "baked_%s_crop_after" % id)
			save_crop(before, on_screen(CROPS[id]), "baked_%s_crop_before" % id)
		root.get_tree().paused = false
		Engine.time_scale = 1.0


## Every region under `node` swapped back for the texture it was copied from (bodies, faces,
## decals' sprites and frames).
func _unpage(node: Node) -> void:
	for item: Node in node.find_children("*", "", true, false):
		if item is Sprite2D:
			var sprite := item as Sprite2D
			sprite.texture = TexturePage.source_of(sprite.texture)
		elif item is AnimatedSprite2D:
			var flame := item as AnimatedSprite2D
			var own: SpriteFrames = DecalPagesScript.own_frames_of(flame.sprite_frames)
			if own != flame.sprite_frames:
				var at: int = flame.frame
				var progress: float = flame.frame_progress
				flame.sprite_frames = own
				flame.set_frame_and_progress(at, progress)
