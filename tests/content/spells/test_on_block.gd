extends "res://tests/support/suite.gd"
## The On Block card (content/spells/triggers/on_block/, staffs C): a trigger that casts the group
## read after its carrier where the carrier's shield stops an enemy shot. Its combos do what they
## promise with the card and fail without it, without the shield, and with no enemy shot to block.
##
## godot --headless --path . --script res://tests/content/spells/test_on_block.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["on_block_dash_nova", "on_block_bolt_nova"]


func _card() -> TriggerBase:
	return load("res://content/spells/triggers/on_block/on_block.tres") as TriggerBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Plays `combo` without `drop` (every copy taken out of its cards) and, with `shot` false,
## without its enemy shots; returns whether every status check held.
func _holds(combo: Dictionary, drop: String = "", shot: bool = true) -> bool:
	var arena := ArenaScript.new(root)
	for at: Array in combo["imps"]:
		arena.add_imp(Vector2(float(at[0]), float(at[1])))
	arena.add_guard(0, Vector2.ZERO)
	var entry: Dictionary = combo["casts"][0]
	var cards: Array = []
	for id: Variant in entry["cards"]:
		if str(id) != drop:
			cards.append(id)
	arena.install_cards(0, int(entry["staff"]), cards)
	if shot:
		for foe: Array in combo.get("foes", []):
			arena.shoot_at(Vector2(float(foe[0]), float(foe[1])), Vector2.ZERO)
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
	check(card != null, "on_block.tres loads as a TriggerBase")
	if card == null:
		return
	check_equal(card.id, &"on_block", "its id is its folder")
	check_equal(card.event, TriggerBase.Event.BLOCK, "it fires at a block")
	check_equal(card.max_fires, 1, "once")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_hold_with_the_card_and_fail_without_it() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		check(not combo.is_empty(), "the combo %s exists" % id)
		if combo.is_empty():
			continue
		check(_holds(combo), "%s does what it promises" % id)
		check(not _holds(combo, "on_block"), "%s fails without On Block" % id)
		check(not _holds(combo, "shield"), "%s fails without the shield (nothing to block)" % id)
		check(not _holds(combo, "", false), "%s does nothing with no enemy shot to block" % id)
