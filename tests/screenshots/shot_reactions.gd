extends "res://tests/support/screenshot.gd"
## Screenshots of element reactions: one reaction (`reaction_one`), four at once, one per player
## (`reaction_four_players`), and all six made by real hits in the combo arena, three at a time:
## `reactions_first_three_1x` and `reactions_last_three_1x` (plain 1x crops, as a player sees
## them), and the same at 4x.

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


func take() -> void:
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await settle()
	if not need(["PlayerInput", "Flow", "Events"]):
		return
	# Feel ages its effects on the real clock, which a slow virtual display stretches past
	# their tenths of a second; on game time each frame is 1/60 s, as in play.
	if root.has_node("Feel"):
		root.get_node("Feel").set("drive_engine", false)
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var events: Node = root.get_node("Events")
	for index in 4:
		input.call("add_virtual_device", index)
	flow.call("start_run", 0)
	await settle()
	var centre: Vector2 = (flow.call("get_wizard", 0) as Node2D).global_position + Vector2(0.0, -60.0)
	# A reaction names its caster by actor id: the actor each wizard opened (actors G3b).
	var casters: Array[int] = []
	for index in 4:
		var wizard: Node = flow.call("get_wizard", index) as Node
		casters.append(int(wizard.get("id")) if wizard != null else -1)
	events.call("emit_signal", "reaction_triggered", casters[0], NAMES[0], centre)
	await _snap(centre, "reaction_one")
	await settle()
	for player in 4:
		var at: Vector2 = centre + Vector2(float(player - 2) * 40.0 + 20.0, float(player % 2) * 14.0)
		events.call("emit_signal", "reaction_triggered", casters[player], NAMES[player], at)
	await _snap(centre, "reaction_four_players")
	await create_timer(1.2).timeout
	await _six(events, root.get_canvas_transform().affine_inverse() * (root.get_visible_rect().size * 0.5), casters[0])


## Make each of the six reactions with two real hits in the combo arena, then show them in the
## live game (as `caster`'s), all in a row, saved at 4x and at 1x.
func _six(events: Node, centre: Vector2, caster: int) -> void:
	var seen: Array[StringName] = []
	for row: Dictionary in SIX:
		var arena: RefCounted = ArenaScript.new(root)
		arena.call("add_imp", Vector2(100.0, 0.0))
		arena.call("install_cards", 0, 0, [row["first"], &"bolt"])
		arena.call("install_cards", 0, 1, [row["second"], &"bolt"])
		arena.call("cast", 0, 0)
		arena.call("run", 0.3)
		arena.call("cast", 0, 1)
		arena.call("run", 0.6)
		var ids: Array = arena.call("reaction_ids")
		arena.call("free_all")
		if not ids.has(row["id"]):
			fail("%s then %s made %s, not %s" % [row["first"], row["second"], ids, row["id"]])
			return
		seen.append(row["id"] as StringName)
	# Feel keeps four reaction flashes live at once, so the six are shown three at a time.
	for group in 2:
		for i in 3:
			var at: Vector2 = centre + Vector2((float(i) - 1.0) * SIX_GAP, 0.0)
			events.call("emit_signal", "reaction_triggered", caster, seen[group * 3 + i], at)
		await _snap(centre, "reactions_%s_4x" % GROUPS[group], 4)
		await _snap(centre, "reactions_%s_1x" % GROUPS[group], 1)
		# Let the names of this group fade (three times a reaction's seconds) before the next.
		if group == 0:
			await create_timer(1.2).timeout


## Let the flashes grow for a few frames, then save a crop around the world point `at`,
## `zoom` times bigger than the game draws it (1 is the real size).
func _snap(at: Vector2, name: String, zoom: int = 8) -> void:
	await settle(5)
	await snap(at, name, Vector2i(96, 64) if zoom == 8 else Vector2i(96, 40), zoom)
