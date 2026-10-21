extends "res://tests/support/suite.gd"
## The crypt room's torches (content/rooms/crypt/arena_01) move: a looping flame of at least
## three frames and a flickering light, out of step with each other, from one shared set of
## frames each. No script runs them, so they cost the engine's own animation and nothing more.

const RoomData := preload("res://content/rooms/crypt/arena_01.tres")
const RoomScan := preload("res://tests/content/rooms/room_scan.gd")

var room_root: Node
var torches: Array[Node] = []


func before_each() -> void:
	room_root = own((RoomData as RoomBase).scene.instantiate()) as Node
	root.add_child(room_root)
	torches.clear()
	for child in room_root.get_node("Decor").get_children():
		if String(child.name).begins_with("Torch"):
			torches.append(child)


func _flame(torch: Node) -> AnimatedSprite2D:
	return torch.get_node("Flame") as AnimatedSprite2D


func _core(torch: Node) -> AnimatedSprite2D:
	return torch.get_node("Core") as AnimatedSprite2D


func test_the_room_has_torches() -> void:
	check(torches.size() >= 2, "the room has torches")


func test_every_torch_flame_loops_with_three_or_more_frames() -> void:
	for torch in torches:
		var flame: AnimatedSprite2D = _flame(torch)
		check(flame != null, "%s has a Flame" % torch.name)
		if flame == null:
			continue
		check(flame.sprite_frames.get_frame_count(flame.animation) >= 3, "%s's flame has at least 3 frames" % torch.name)
		check(flame.sprite_frames.get_animation_loop(flame.animation), "%s's flame loops" % torch.name)
		check(flame.is_playing(), "%s's flame plays on its own" % torch.name)


func test_every_torch_has_a_flickering_glow() -> void:
	for torch in torches:
		var core: AnimatedSprite2D = _core(torch)
		check(core != null and core.is_playing(), "%s has a playing glow" % torch.name)
		var halo: Sprite2D = torch.get_node("Glow") as Sprite2D
		check(halo != null, "%s has a soft glow" % torch.name)
		if core != null and halo != null:
			var material: CanvasItemMaterial = core.material as CanvasItemMaterial
			check(material != null and material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "%s's light adds to the floor" % torch.name)
			check(core.modulate.a < 0.5 and halo.modulate.a < 0.5, "%s's glow is soft" % torch.name)


func test_the_torches_do_not_flicker_in_step() -> void:
	var seen: Dictionary = {}
	for torch in torches:
		var flame: AnimatedSprite2D = _flame(torch)
		var key: String = "%s/%d" % [str(flame.speed_scale), flame.frame]
		check(not seen.has(key), "%s has the same speed and phase as %s" % [torch.name, str(seen.get(key, ""))])
		seen[key] = torch.name
	var speeds: Dictionary = {}
	for torch in torches:
		speeds[_flame(torch).speed_scale] = true
	check(speeds.size() >= 3, "the flames run at several speeds (%d)" % speeds.size())


func test_the_torches_share_their_frames() -> void:
	var first: AnimatedSprite2D = _flame(torches[0])
	var first_core: AnimatedSprite2D = _core(torches[0])
	for torch in torches:
		check(_flame(torch).sprite_frames == first.sprite_frames, "%s shares the flame frames" % torch.name)
		check(_core(torch).sprite_frames == first_core.sprite_frames, "%s shares the glow frames" % torch.name)


func test_the_flames_move_on_by_themselves() -> void:
	var before: Array[int] = []
	for torch in torches:
		before.append(_flame(torch).frame)
	# The animation advances with the process frames; give it a few of them.
	for _i in 30:
		await process_frame
	var moved: int = 0
	for i in torches.size():
		if _flame(torches[i]).frame != before[i]:
			moved += 1
	check(moved >= torches.size() / 2, "most flames changed frame (%d of %d)" % [moved, torches.size()])


func test_torches_run_no_script() -> void:
	for torch in torches:
		check_equal(RoomScan.scripts_below(torch), 0, "%s runs no script" % torch.name)
