extends "res://tests/support/suite.gd"
## The On Wall card (content/spells/triggers/on_wall/, staffs C): a trigger that casts the group
## read after its carrier where the carrier strikes a wall. Its combos do what they promise with
## the card and fail without it, and with no wall in the way nothing fires.
##
## godot --headless --path . --script res://tests/content/spells/test_on_wall.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["on_wall_bolt_nova", "on_wall_bolt_rune"]


func _card() -> TriggerBase:
	return load("res://content/spells/triggers/on_wall/on_wall.tres") as TriggerBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Plays `combo` without `drop` (every copy taken out of its cards) and, with `walled` false,
## without its walls; returns whether every check held.
func _holds(combo: Dictionary, drop: String = "", walled: bool = true) -> bool:
	var arena := ArenaScript.new(root)
	for at: Array in combo["imps"]:
		arena.add_imp(Vector2(float(at[0]), float(at[1])))
	if walled:
		for rect: Array in combo.get("walls", []):
			arena.add_wall(Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])))
	var entry: Dictionary = combo["casts"][0]
	var cards: Array = []
	for id: Variant in entry["cards"]:
		if str(id) != drop:
			cards.append(id)
	arena.install_cards(0, int(entry["staff"]), cards)
	arena.cast(0, int(entry["staff"]))
	arena.run(float(combo["seconds"]))
	var held: bool = true
	for row: Dictionary in combo["checks"]:
		if str(row["kind"]) == "status":
			for index: int in row["imps"]:
				held = held and arena.was_given(arena.imps[index], StringName(row["status"]))
	arena.free_all()
	return held


func test_the_card_is_a_valid_trigger() -> void:
	var card: TriggerBase = _card()
	check(card != null, "on_wall.tres loads as a TriggerBase")
	if card == null:
		return
	check_equal(card.id, &"on_wall", "its id is its folder")
	check_equal(card.event, TriggerBase.Event.WALL, "it fires at a wall")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_hold_with_the_card_and_fail_without_it() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		check(not combo.is_empty(), "the combo %s exists" % id)
		if combo.is_empty():
			continue
		check(_holds(combo), "%s does what it promises" % id)
		check(not _holds(combo, "on_wall"), "%s fails without On Wall" % id)
		check(not _holds(combo, "", false), "%s does nothing with no wall to strike" % id)
