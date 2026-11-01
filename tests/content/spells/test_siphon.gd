extends "res://tests/support/suite.gd"
## The Siphon card (content/spells/modifiers/siphon/, staffs C): each hit of the next shot gives
## mana back, through `mana_refund_requested`. Its combos hurt what they promise, and the mana
## comes back with the card and not without it.
##
## godot --headless --path . --script res://tests/content/spells/test_siphon.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["siphon_split_bolts", "siphon_chain_bolt"]


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/siphon/siphon.tres") as ModifierBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Plays `combo` (without every copy of `drop`) and returns [mana refunded to player 0, whether
## every imp named by its damaged check was hurt].
func _play(combo: Dictionary, drop: String = "") -> Array:
	var arena := ArenaScript.new(root)
	var refunded: Array[float] = [0.0]
	arena.bus.mana_refund_requested.connect(func(actor: int, _at: int, amount: float) -> void:
		if actor == 0:
			refunded[0] += amount)
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
	var hurt: bool = true
	for row: Dictionary in combo["checks"]:
		for index: int in row["imps"]:
			hurt = hurt and arena.lost(arena.imps[index]) > 0
	arena.free_all()
	return [refunded[0], hurt]


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "siphon.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"siphon", "its id is its folder")
	check_equal(card.kind(), &"modifier", "a modifier card")
	check_equal(card.behaviour, ModifierBase.Behaviour.SIPHON, "the siphon behaviour")
	check(card.behaviour_strength > 0.0, "with a strength")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_hurt_and_refund_only_with_the_card() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		check(not combo.is_empty(), "the combo %s exists" % id)
		if combo.is_empty():
			continue
		var with_card: Array = _play(combo)
		check(with_card[1] as bool, "%s hurts what it promises" % id)
		check((with_card[0] as float) >= _card().behaviour_strength * 2.0, "%s refunds mana for several hits (%s)" % [id, with_card[0]])
		# Siphon softens a cast's cost and never pays it: even a volley refunds less than the
		# bolt alone costs, so no combo is free to repeat.
		var bolt_cost: float = (load("res://content/spells/forms/bolt/bolt.tres") as FormBase).mana_cost
		check((with_card[0] as float) < bolt_cost, "%s refunds less than a bolt costs (%s < %s)" % [id, with_card[0], bolt_cost])
		var without: Array = _play(combo, "siphon")
		check_equal(without[0], 0.0, "%s refunds nothing without Siphon" % id)


func test_four_players_are_refunded_each() -> void:
	var arena := ArenaScript.new(root)
	var refunded: Dictionary = {}
	arena.bus.mana_refund_requested.connect(func(actor: int, _at: int, amount: float) -> void:
		refunded[actor] = float(refunded.get(actor, 0.0)) + amount)
	for player in 4:
		var at := Vector2(0.0, 150.0 * player)
		arena.place_caster(player, at)
		arena.add_imp(at + Vector2(100.0, 0.0))
		arena.install_cards(player, 0, ["siphon", "bolt"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(1.0)
	for player in 4:
		check_equal(refunded.get(player, 0.0), _card().behaviour_strength, "player %d got one hit's mana back" % player)
	arena.free_all()
