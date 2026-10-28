extends "res://tests/support/suite.gd"
## The On Cast card (content/spells/triggers/on_cast/, staffs C): a trigger that casts the group
## read after its carrier at once, from the caster. Its combo does what it promises with the card
## and fails without it.
##
## godot --headless --path . --script res://tests/content/spells/test_on_cast.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["on_cast_rune_bolt", "on_cast_bolt_nova"]


func _card() -> TriggerBase:
	return load("res://content/spells/triggers/on_cast/on_cast.tres") as TriggerBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Plays `combo` without `drop` (every copy taken out of its cards) and returns whether every check held.
func _holds(combo: Dictionary, drop: String = "") -> bool:
	var arena := ArenaScript.new(root)
	for at: Array in combo["imps"]:
		arena.add_imp(Vector2(float(at[0]), float(at[1])))
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
		elif str(row["kind"]) == "damaged":
			for index: int in row["imps"]:
				held = held and arena.lost(arena.imps[index]) > 0
	arena.free_all()
	return held


func test_the_card_is_a_valid_trigger() -> void:
	var card: TriggerBase = _card()
	check(card != null, "on_cast.tres loads as a TriggerBase")
	if card == null:
		return
	check_equal(card.id, &"on_cast", "its id is its folder")
	check_equal(card.event, TriggerBase.Event.CAST, "it fires on the cast")
	check_equal(card.max_fires, 1, "once")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_hold_with_the_card_and_fail_without_it() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		check(not combo.is_empty(), "the combo %s exists" % id)
		if combo.is_empty():
			continue
		check(_holds(combo), "%s does what it promises" % id)
		check(not _holds(combo, "on_cast"), "%s fails without On Cast" % id)
