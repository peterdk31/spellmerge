extends SceneTree
## Screenshots of element reactions, for people and for Claude to look at: one reaction
## (`reaction_one`), four at once, one per player (`reaction_four_players`), and all six made
## by real hits in the combo arena, three at a time: `reactions_first_three_1x` and
## `reactions_last_three_1x` (plain 1x crops, as a player sees them), and the same at 4x.
## Needs a display, so it runs only through `ci/build/build.sh --quick --screenshots`; each
## shot is saved as user://screenshots/<name>.png and copied to build/screenshots/.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 20
const NAMES: Array[StringName] = [&"shatter", &"thaw", &"flare", &"rift"]
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
## The six reactions, each made by two real bolts on one imp: the first bolt's element puts a
## status on, the second one reacts with it.
const SIX: Array[Dictionary] = [
	{"id": &"shatter", "first": &"frost", "second": &"storm"},
	{"id": &"thaw", "first": &"fire", "second": &"frost"},
	{"id": &"flare", "first": &"fire", "second": &"storm"},
	{"id": &"kindle", "first": &"fire", "second": &"void"},
	{"id": &"stillness", "first": &"frost", "second": &"void"},
	{"id": &"rift", "first": &"storm", "second": &"void"},
]
## The names of the two groups of three in the shot files.
const GROUPS: Array[String] = ["first_three", "last_three"]
## Pixels between neighbours in the row of six; wide enough for the names not to touch.
const SIX_GAP: float = 52.0


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await _settle()
	var input: Node = root.get_node_or_null("PlayerInput")
	var flow: Node = root.get_node_or_null("Flow")
	var events: Node = root.get_node_or_null("Events")
	if input == null or flow == null or events == null:
		printerr("SHOT FAILED: the PlayerInput, Flow and Events autoloads must exist")
		quit(1)
		return
	for index in 4:
		input.call("add_virtual_device", index)
	flow.call("start_run", 0)
	await _settle()
	var centre: Vector2 = (flow.call("get_wizard", 0) as Node2D).global_position + Vector2(0.0, -60.0)
	events.call("emit_signal", "reaction_triggered", 0, NAMES[0], centre)
	await _snap(centre, "reaction_one")
	await _settle()
	for player in 4:
		var at: Vector2 = centre + Vector2(float(player - 2) * 40.0 + 20.0, float(player % 2) * 14.0)
		events.call("emit_signal", "reaction_triggered", player, NAMES[player], at)
	await _snap(centre, "reaction_four_players")
	await create_timer(1.2).timeout
	await _six(events, root.get_canvas_transform().affine_inverse() * (root.get_visible_rect().size * 0.5))
	quit(0)


## Make each of the six reactions with two real hits in the combo arena, then show them in the
## live game, all in a row, saved at 4x and at 1x.
func _six(events: Node, centre: Vector2) -> void:
	var seen: Array[StringName] = []
	for row: Dictionary in SIX:
		var arena: RefCounted = ArenaScript.new(root)
		arena.call("add_imp", Vector2(100.0, 0.0))
		arena.call("install", 0, 0, {"form": &"bolt", "element": row["first"]})
		arena.call("install", 0, 1, {"form": &"bolt", "element": row["second"]})
		arena.call("cast", 0, 0)
		arena.call("run", 0.3)
		arena.call("cast", 0, 1)
		arena.call("run", 0.6)
		var ids: Array = arena.call("reaction_ids")
		arena.call("free_all")
		if not ids.has(row["id"]):
			printerr("SHOT FAILED: %s then %s made %s, not %s" % [row["first"], row["second"], ids, row["id"]])
			quit(1)
			return
		seen.append(row["id"] as StringName)
	# Feel keeps four reaction flashes live at once, so the six are shown three at a time.
	for group in 2:
		for i in 3:
			var at: Vector2 = centre + Vector2((float(i) - 1.0) * SIX_GAP, 0.0)
			events.call("emit_signal", "reaction_triggered", 0, seen[group * 3 + i], at)
		await _snap(centre, "reactions_%s_4x" % GROUPS[group], 4)
		await _snap(centre, "reactions_%s_1x" % GROUPS[group], 1)
		# Let the names of this group fade (three times a reaction's seconds) before the next.
		await create_timer(1.2).timeout


## Let the flashes grow for a few frames, then save a crop around the world point `at`,
## `zoom` times bigger than the game draws it (1 is the real size).
func _snap(at: Vector2, name: String, zoom: int = 8) -> void:
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var scale_to_image: Vector2 = Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
	var centre: Vector2i = Vector2i((root.get_canvas_transform() * at) * scale_to_image)
	var half: Vector2i = Vector2i(96, 64) if zoom == 8 else Vector2i(96, 40)
	var corner: Vector2i = (centre - half).clamp(Vector2i.ZERO, image.get_size() - half * 2)
	var crop: Image = image.get_region(Rect2i(corner, half * 2))
	if zoom != 1:
		crop.resize(crop.get_width() * zoom, crop.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [SHOTS_DIR, name])
	print("SHOT: %s" % name)


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame
