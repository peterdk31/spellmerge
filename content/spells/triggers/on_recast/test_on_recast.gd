extends "res://tests/support/suite.gd"
## The On Recast card (content/spells/triggers/on_recast/): a trigger that casts the group read
## after its carrier from where that carrier is when its staff casts again, while it lives. Its
## combos do what they promise with the card, fail without it, and fail when the staff is cast
## only once: the second press is what sets it off.
##
## godot --headless --path . --script res://content/spells/triggers/on_recast/test_on_recast.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["on_recast_rune_blast", "on_recast_slow_frost"]


func _card() -> TriggerBase:
	return load("res://content/spells/triggers/on_recast/on_recast.tres") as TriggerBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Plays `combo` without `drop` (every copy taken out of its cards) and, with `again` false, with
## only its first cast; returns whether every status check held.
func _holds(combo: Dictionary, drop: String = "", again: bool = true) -> bool:
	var arena := ArenaScript.new(root)
	for at: Array in combo["imps"]:
		arena.add_imp(Vector2(float(at[0]), float(at[1])))
	var casts: Array = combo["casts"]
	for n in casts.size() if again else 1:
		var entry: Dictionary = casts[n]
		var cards: Array = []
		for id: Variant in entry["cards"]:
			if str(id) != drop:
				cards.append(id)
		arena.install_cards(0, int(entry["staff"]), cards)
		var at: float = float(entry.get("at", 0.0))
		if at > arena.time:
			arena.run(at - arena.time)
		arena.cast(0, int(entry["staff"]))
	arena.run(maxf(float(combo["seconds"]) - arena.time, 0.0))
	var held: bool = true
	for row: Dictionary in combo["checks"]:
		if str(row["kind"]) == "status":
			for index: int in row["imps"]:
				held = held and arena.was_given(arena.imps[index], StringName(row["status"]))
	arena.free_all()
	return held


func test_the_card_is_a_valid_trigger() -> void:
	var card: TriggerBase = _card()
	check(card != null, "on_recast.tres loads as a TriggerBase")
	if card == null:
		return
	check_equal(card.id, &"on_recast", "its id is its folder")
	check_equal(card.event, TriggerBase.Event.RECAST, "it fires when its staff casts again")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_it_needs_a_carrier_that_lasts() -> void:
	check(_card_works(&"on_recast", &"rune"), "a rune lasts, so a recast can find it")
	check(not _card_works(&"on_recast", &"slam"), "a slam is over at once: nothing is left to recast")


func _card_works(card: StringName, carrier: StringName) -> bool:
	var arena := ArenaScript.new(root)
	var works: bool = arena.spells.card_works(card, carrier)
	arena.free_all()
	return works


func test_the_combos_hold_with_the_card_and_fail_without_it() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		check(not combo.is_empty(), "the combo %s exists" % id)
		if combo.is_empty():
			continue
		check(_holds(combo), "%s does what it promises" % id)
		check(not _holds(combo, "on_recast"), "%s fails without On Recast" % id)
		check(not _holds(combo, "", false), "%s does nothing when the staff is cast only once" % id)
