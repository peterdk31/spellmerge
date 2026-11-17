extends "res://tests/support/suite.gd"
## Every room template's torches and candles (content/rooms: every room a run's map can pick, found
## by folder; `content/rooms/crypt/decals/`, crypt rework CR3) move: a looping flame of at least three
## frames and a flickering light, out of step with the others in its room, every one of a kind from
## one shared set of frames. No script runs them, so they cost the engine's own animation and nothing
## more. Here "torch" is either: a room lit by candles alone (a floating crypt room, whose torches
## had no wall to hang on) is lit all the same.

const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## Every template's torches, room by room (its id: its torches), and all of them in one list.
var by_room: Dictionary[StringName, Array] = {}
var torches: Array[Node] = []
## Each torch's room id, by the torch, so a failure names the room (every room has a Torch1).
var room_of: Dictionary[Node, StringName] = {}


func before_each() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	by_room.clear()
	torches.clear()
	room_of.clear()
	for room in RoomScan.templates(registry):
		var layout: Node = own(room.scene.instantiate()) as Node
		root.add_child(layout)
		var found: Array[Node] = []
		for child in layout.get_node("Decor").get_children():
			if String(child.name).begins_with("Torch") or String(child.name).begins_with("Candles"):
				found.append(child)
		by_room[room.id] = found
		for torch in found:
			room_of[torch] = room.id
		torches.append_array(found)


## "<room>/<torch>", for messages.
func _named(torch: Node) -> String:
	return "%s/%s" % [room_of.get(torch, &"?"), torch.name]


func _flame(torch: Node) -> AnimatedSprite2D:
	return torch.get_node("Flame") as AnimatedSprite2D


func _core(torch: Node) -> AnimatedSprite2D:
	return torch.get_node("Core") as AnimatedSprite2D


func test_every_room_has_torches() -> void:
	check(not by_room.is_empty(), "the templates are found")
	for id: StringName in by_room:
		check(by_room[id].size() >= 2, "%s has torches" % id)


func test_every_torch_flame_loops_with_three_or_more_frames() -> void:
	for torch in torches:
		var flame: AnimatedSprite2D = _flame(torch)
		check(flame != null, "%s has a Flame" % _named(torch))
		if flame == null:
			continue
		check(flame.sprite_frames.get_frame_count(flame.animation) >= 3, "%s's flame has at least 3 frames" % _named(torch))
		check(flame.sprite_frames.get_animation_loop(flame.animation), "%s's flame loops" % _named(torch))
		check(flame.is_playing(), "%s's flame plays on its own" % _named(torch))


func test_every_torch_has_a_flickering_glow() -> void:
	for torch in torches:
		var core: AnimatedSprite2D = _core(torch)
		check(core != null and core.is_playing(), "%s has a playing glow" % _named(torch))
		var halo: Sprite2D = torch.get_node("Glow") as Sprite2D
		check(halo != null, "%s has a soft glow" % _named(torch))
		if core != null and halo != null:
			var material: CanvasItemMaterial = core.material as CanvasItemMaterial
			check(material != null and material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "%s's light adds to the floor" % _named(torch))
			check(core.modulate.a < 0.5 and halo.modulate.a < 0.5, "%s's glow is soft" % _named(torch))


func test_the_torches_do_not_flicker_in_step() -> void:
	for id: StringName in by_room:
		var seen: Dictionary = {}
		var speeds: Dictionary = {}
		for torch: Node in by_room[id]:
			var flame: AnimatedSprite2D = _flame(torch)
			var key: String = "%s/%d" % [str(flame.speed_scale), flame.frame]
			check(not seen.has(key), "%s: %s has the same speed and phase as %s" % [id, torch.name, str(seen.get(key, ""))])
			seen[key] = torch.name
			speeds[flame.speed_scale] = true
		check(speeds.size() >= 3, "%s: the flames run at several speeds (%d)" % [id, speeds.size()])


## Every torch of a kind (an instance of one decal scene) draws from that kind's one set of frames.
func test_the_torches_share_their_frames() -> void:
	var first_of: Dictionary[String, Node] = {}
	for torch in torches:
		check(torch.scene_file_path != "", "%s is an instance of a decal" % _named(torch))
		if not first_of.has(torch.scene_file_path):
			first_of[torch.scene_file_path] = torch
		var first: Node = first_of[torch.scene_file_path]
		check(_flame(torch).sprite_frames == _flame(first).sprite_frames, "%s shares the flame frames" % _named(torch))
		check(_core(torch).sprite_frames == _core(first).sprite_frames, "%s shares the glow frames" % _named(torch))


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
		check_equal(RoomScan.scripts_below(torch), 0, "%s runs no script" % _named(torch))
