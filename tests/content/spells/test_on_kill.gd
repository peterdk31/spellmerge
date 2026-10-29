extends "res://tests/support/suite.gd"
## The On Kill card (content/spells/triggers/on_kill/, staffs C): a trigger that casts the group
## read after its carrier where the carrier's hit kills. Its combos do what they promise with the
## card and fail without it, and when the imp ahead is too sturdy to die.
##
## godot --headless --path . --script res://tests/content/spells/test_on_kill.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["on_kill_bolt_nova", "on_kill_bolt_frost"]


func _card() -> TriggerBase:
	return load("res://content/spells/triggers/on_kill/on_kill.tres") as TriggerBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Plays `combo` without `drop` (every copy taken out of its cards) and, with `sturdy` true, with
## the imp the bolt meets given full health so it does not die; returns whether the imp died and
## every status check held.
func _holds(combo: Dictionary, drop: String = "", sturdy: bool = false) -> bool:
	var arena := ArenaScript.new(root)
	for at: Array in combo["imps"]:
		var health: int = int(at[2]) if at.size() > 2 and not sturdy else ArenaScript.IMP_HEALTH
		arena.add_imp(Vector2(float(at[0]), float(at[1])), health)
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
		if str(row["kind"]) == "killed":
			for index: int in row["imps"]:
				held = held and arena.died(arena.imps[index])
		elif str(row["kind"]) == "status":
			for index: int in row["imps"]:
				held = held and arena.was_given(arena.imps[index], StringName(row["status"]))
	arena.free_all()
	return held


func test_the_card_is_a_valid_trigger() -> void:
	var card: TriggerBase = _card()
	check(card != null, "on_kill.tres loads as a TriggerBase")
	if card == null:
		return
	check_equal(card.id, &"on_kill", "its id is its folder")
	check_equal(card.event, TriggerBase.Event.KILL, "it fires at a kill")
	check_equal(card.max_fires, 1, "once")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_hold_with_the_card_and_fail_without_it() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		check(not combo.is_empty(), "the combo %s exists" % id)
		if combo.is_empty():
			continue
		check(_holds(combo), "%s does what it promises" % id)
		check(not _holds(combo, "on_kill"), "%s fails without On Kill" % id)
		check(not _holds(combo, "", true), "%s does nothing when the imp survives the hit" % id)
