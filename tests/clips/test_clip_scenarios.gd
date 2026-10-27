extends "res://tests/support/suite.gd"
## The clip scenarios (#245, tests/clips/scenarios.gd) are read from the content: a combo row, a
## component or a reaction is a clip with no code change, every clip id is one the pipeline
## accepts, and a stage played twice gives the same simulation. The pixels of the recorder
## need a display, so they are not checked here (docs/DECISIONS.md, 2026-10-25).
##
## godot --headless --path . --script res://tests/clips/test_clip_scenarios.gd

const ScenariosScript := preload("res://tests/clips/scenarios.gd")
const StageScript := preload("res://tests/clips/stage.gd")
const RecordScript := preload("res://tests/clips/record.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")

var _registry: Node
## A Spells node that knows the registry, for component names and kinds.
var _namer: Node
var _table: ReactionTable
var _combos: Array = []


func before_each() -> void:
	_registry = root.get_node("Registry")
	_namer = own(SpellsScript.new()) as Node
	_namer.set("registry", _registry)
	_table = load(ScenariosScript.REACTIONS) as ReactionTable
	_combos = ScenariosScript.read_combos()


func _all() -> Array[Dictionary]:
	return ScenariosScript.build(_registry, _namer, _combos, _table)


func _find(scenarios: Array[Dictionary], id: String) -> Dictionary:
	for scenario in scenarios:
		if scenario["id"] == id:
			return scenario
	return {}


func test_every_combo_row_is_a_clip() -> void:
	check(_combos.size() > 0, "the catalogue has combos")
	var scenarios: Array[Dictionary] = _all()
	for combo: Dictionary in _combos:
		var scenario: Dictionary = _find(scenarios, "combo_" + str(combo["id"]))
		check(not scenario.is_empty(), "%s is a clip" % combo["id"])
		if not scenario.is_empty():
			check_equal(scenario["kind"], "combo", "%s is a combo clip" % combo["id"])
			check_equal((scenario["casts"] as Array).size(), (combo["casts"] as Array).size(), "%s keeps its casts" % combo["id"])
			check_equal((scenario["imps"] as Array).size(), (combo["imps"] as Array).size(), "%s keeps its imps" % combo["id"])


func test_a_new_combo_row_is_a_clip_with_no_code_change() -> void:
	var row: Dictionary = {
		"id": "fake_row", "name": "Fake row", "does": "Test only.", "seconds": 1.5,
		"casts": [{"staff": 0, "cards": ["fire", "bolt"]}, {"staff": 1, "cards": ["nova"], "at": 0.5, "player": 1}],
		"imps": [[80, 10]], "checks": [{"kind": "damaged", "imps": [0]}],
	}
	var more: Array = _combos.duplicate()
	more.append(row)
	var scenario: Dictionary = _find(ScenariosScript.build(_registry, _namer, more, _table), "combo_fake_row")
	check(not scenario.is_empty(), "the new row is a clip")
	check_equal(scenario["title"], "Fake row", "with the row's name as its title")
	check_equal(scenario["seconds"], 1.5, "and its length")
	check_equal((scenario["casts"] as Array)[1]["player"], 1, "and its second player")
	check_equal((scenario["imps"] as Array)[0], Vector2(80.0, 10.0), "and its imp")


func test_every_component_is_a_clip_of_its_kind_that_builds() -> void:
	var scenarios: Array[Dictionary] = _all()
	var arena := ArenaScript.new(root)
	var count: int = 0
	for id: StringName in _registry.call("get_ids", &"spells"):
		count += 1
		var kind: StringName = arena.spells.component_kind(id)
		var scenario: Dictionary = _find(scenarios, "%s_%s" % [kind, id])
		check(not scenario.is_empty(), "%s has a clip" % id)
		if scenario.is_empty():
			continue
		check_equal(scenario["kind"], str(kind), "%s is a %s clip" % [id, kind])
		check_equal(scenario["title"], arena.spells.component_name(id), "%s is titled by its name" % id)
		for entry: Dictionary in scenario["casts"]:
			var ids: Array[StringName] = []
			for card: Variant in entry["cards"]:
				ids.append(StringName(str(card)))
			var built: CompiledStaff = arena.spells.compile_staff(ids, ArenaScript.plain_staff(ids.size()))
			check(not built.is_empty() and not built.wasted.has(0), "%s on a bolt casts and does something: %s" % [id, built.wasted])
	check(count >= 18, "the shipped components were found (%d)" % count)
	arena.free_all()


func test_every_reaction_has_a_clip_and_a_co_op_clip_that_sets_it_off() -> void:
	var scenarios: Array[Dictionary] = _all()
	var ids: Dictionary = {}
	for row in _table.rows:
		ids[row.reaction_id] = true
	check(ids.size() >= 6, "the reactions were found (%d)" % ids.size())
	for reaction: StringName in ids:
		var solo: Dictionary = _find(scenarios, "reaction_%s" % reaction)
		var coop: Dictionary = _find(scenarios, "reaction_%s_coop" % reaction)
		check(not solo.is_empty() and not coop.is_empty(), "%s has a clip and a co-op clip" % reaction)
		if solo.is_empty() or coop.is_empty():
			continue
		var players: Dictionary = {}
		for entry: Dictionary in coop["casts"]:
			players[entry["player"]] = true
		check_equal(players.size(), 2, "%s co-op has two players" % reaction)
		for scenario in [solo, coop]:
			var stage := StageScript.new(root, _registry)
			check(stage.start(scenario), "%s builds on the stage" % scenario["id"])
			for i in int(float(scenario["seconds"]) * 60.0):
				stage.tick()
			check((stage.reaction_ids() as Array).has(reaction), "%s sets off %s (saw %s)" % [scenario["id"], reaction, stage.reaction_ids()])
			stage.free_all()


func test_the_co_op_clip_shoots_from_two_places_with_two_player_indexes() -> void:
	var coop: Dictionary = _find(_all(), "reaction_shatter_coop")
	var casts: Array = coop["casts"]
	check(casts[0]["player"] != casts[1]["player"], "two different players")
	check(casts[0]["origin"] != casts[1]["origin"], "from two places")


func test_two_clips_have_four_players_firing_the_same_cards() -> void:
	for id in ["combo_four_players", "combo_spark_crowd"]:
		var scenario: Dictionary = _find(_all(), id)
		check(not scenario.is_empty(), "%s is a clip" % id)
		if scenario.is_empty():
			continue
		var players: Dictionary = {}
		var origins: Dictionary = {}
		var cards: Array = (scenario["casts"] as Array)[0]["cards"]
		for entry: Dictionary in scenario["casts"]:
			players[entry["player"]] = true
			origins[entry["origin"]] = true
			check_equal(entry["cards"], cards, "%s: everyone casts the same cards" % id)
		check_equal(players.size(), 4, "%s: four players" % id)
		check_equal(origins.size(), 4, "%s: from four places" % id)


func test_every_id_is_a_clip_id_the_pipeline_takes_and_used_once() -> void:
	var seen: Dictionary = {}
	for scenario in _all():
		var id: String = scenario["id"]
		check(ScenariosScript.valid_id(id), "%s is a valid clip id" % id)
		check(not seen.has(id), "%s is used once" % id)
		seen[id] = true
		check(["form", "element", "modifier", "trigger", "multicast", "combo", "reaction"].has(scenario["kind"]), "%s has a kind the pipeline knows" % id)
		check(str(scenario["title"]) != "", "%s has a title" % id)
		var frames: int = int(float(scenario["seconds"]) * RecordScript.FPS)
		check(frames >= 1 and frames <= RecordScript.MAX_FRAMES, "%s has %d frames, within the cap" % [id, frames])
	check(not ScenariosScript.valid_id("Bad Id"), "a bad id is refused")
	check(not ScenariosScript.valid_id("x".repeat(61)), "a 61-character id is refused")


func test_the_crop_fits_the_size_limit_and_the_frame_rate_is_a_whole_number_of_steps() -> void:
	check(RecordScript.CROP.x <= RecordScript.MAX_FRAME_SIZE.x and RecordScript.CROP.y <= RecordScript.MAX_FRAME_SIZE.y, "a frame is at most 640x360")
	check_equal(RecordScript.FPS * RecordScript.STEPS_PER_FRAME, 60, "a frame is a whole number of physics steps")


func test_the_same_scenario_twice_gives_the_same_simulation() -> void:
	var scenarios: Array[Dictionary] = _all()
	for id in ["combo_shatter", "reaction_shatter", "reaction_kindle_coop"]:
		var scenario: Dictionary = _find(scenarios, id)
		check(not scenario.is_empty(), "%s exists" % id)
		var runs: Array[PackedStringArray] = []
		for run in 2:
			var stage := StageScript.new(root, _registry)
			stage.start(scenario)
			var prints: PackedStringArray = PackedStringArray()
			for i in int(float(scenario["seconds"]) * 60.0):
				stage.tick()
				if i % 3 == 0:
					prints.append(stage.fingerprint())
			runs.append(prints)
			stage.free_all()
		check(runs[0] == runs[1], "%s: two runs agree at every frame" % id)
		check(runs[0][0] != runs[0][runs[0].size() - 1], "%s: something happens in the clip" % id)


func test_a_scenario_with_a_staff_that_casts_nothing_is_refused() -> void:
	var scenario: Dictionary = (_find(_all(), "combo_shatter")).duplicate(true)
	scenario["casts"] = [{"player": 0, "staff": 0, "cards": ["no_such_card"], "at": 0.0, "origin": Vector2.ZERO, "aim": Vector2.RIGHT}]
	var stage := StageScript.new(root, _registry)
	check(not stage.start(scenario), "start says no")
	stage.free_all()
