extends "res://tests/support/suite.gd"
## The On Reaction card (content/spells/triggers/on_reaction/, staffs C): a trigger that casts the
## group read after its carrier from the target when the carrier's hit sets off a reaction. Its
## combos do what they promise with the card and fail without it, and when nothing sets up the
## reaction.
##
## godot --headless --path . --script res://tests/content/spells/test_on_reaction.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["on_reaction_thaw_hex", "on_reaction_shatter_fire"]


func _card() -> TriggerBase:
	return load("res://content/spells/triggers/on_reaction/on_reaction.tres") as TriggerBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Plays `combo` without `drop` (every copy taken out of its cards) and, with `primed` false,
## without the cast that sets the reaction up (the staff that is not the one holding the card);
## returns whether every status check held.
func _holds(combo: Dictionary, drop: String = "", primed: bool = true) -> bool:
	var arena := ArenaScript.new(root)
	for at: Array in combo["imps"]:
		arena.add_imp(Vector2(float(at[0]), float(at[1])))
	arena.add_guard(0, Vector2.ZERO)
	var casts: Array = []
	for entry: Dictionary in combo["casts"]:
		var cards: Array = []
		for id: Variant in entry["cards"]:
			if str(id) != drop:
				cards.append(id)
		var holds_card: bool = (entry["cards"] as Array).has("on_reaction")
		if primed or holds_card:
			arena.install_cards(0, int(entry["staff"]), cards)
			casts.append([float(entry.get("at", 0.0)), int(entry["staff"])])
	casts.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for cast_at: Array in casts:
		if float(cast_at[0]) > arena.time:
			arena.run(float(cast_at[0]) - arena.time)
		arena.cast(0, int(cast_at[1]))
	arena.run(maxf(float(combo["seconds"]) - arena.time, 0.0))
	var held: bool = true
	for row: Dictionary in combo["checks"]:
		for index: int in row["imps"]:
			held = held and arena.was_given(arena.imps[index], StringName(row["status"]))
	arena.free_all()
	return held


## True when `_holds` replays every part of `combo`: only status checks.
func _understood(combo: Dictionary) -> bool:
	if (combo["checks"] as Array).is_empty():
		return false
	for row: Dictionary in combo["checks"]:
		if str(row["kind"]) != "status":
			return false
	return true


func test_the_card_is_a_valid_trigger() -> void:
	var card: TriggerBase = _card()
	check(card != null, "on_reaction.tres loads as a TriggerBase")
	if card == null:
		return
	check_equal(card.id, &"on_reaction", "its id is its folder")
	check_equal(card.event, TriggerBase.Event.REACTION, "it fires when the carrier's hit sets off a reaction")
	check_equal(card.max_fires, 1, "once")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_hold_with_the_card_and_fail_without_it() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		check(not combo.is_empty(), "the combo %s exists" % id)
		if combo.is_empty():
			continue
		check(_understood(combo), "%s only uses what this test replays: status checks" % id)
		check(_holds(combo), "%s does what it promises" % id)
		check(not _holds(combo, "on_reaction"), "%s fails without On Reaction" % id)
		check(not _holds(combo, "", false), "%s does nothing while no reaction is set up" % id)
