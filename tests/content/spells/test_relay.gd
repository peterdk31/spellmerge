extends "res://tests/support/suite.gd"
## The Relay card (content/spells/modifiers/relay/, staffs C): the next shot takes on the infusions of the last cast of the actor it
## hits. Each of its combos does what it promises with the card and fails without it.
##
## godot --headless --path . --script res://tests/content/spells/test_relay.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["relay_teammate_frost", "relay_teammate_fire"]


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/relay/relay.tres") as ModifierBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Plays `combo` (teammate bodies, imps, then its casts in order of `at`) with every copy of `drop` taken out of the cards.
## Returns the arena; the caller frees it. Kept apart from test_combos.gd's player on purpose: it also drops a card and moves the
## whole scene (the four-player test), which the shared player has no use for.
func _play(combo: Dictionary, drop: String = "", offset: Vector2 = Vector2.ZERO, first_player: int = 0) -> ArenaScript:
	var arena := ArenaScript.new(root)
	for mate: Array in combo["mates"]:
		arena.add_mate(offset + Vector2(float(mate[0]), float(mate[1])), int(mate[2]))
	for at: Array in combo["imps"]:
		arena.add_imp(offset + Vector2(float(at[0]), float(at[1])))
	var casts: Array = (combo["casts"] as Array).duplicate()
	for entry: Dictionary in casts:
		var cards: Array = []
		for id: Variant in entry["cards"]:
			if str(id) != drop:
				cards.append(id)
		var player: int = int(entry["player"]) + first_player
		arena.place_caster(player, offset)
		arena.install_cards(player, int(entry["staff"]), cards)
	casts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("at", 0.0)) < float(b.get("at", 0.0)))
	for entry: Dictionary in casts:
		if float(entry.get("at", 0.0)) > arena.time:
			arena.run(float(entry["at"]) - arena.time)
		var dir: Array = entry.get("dir", [1, 0])
		arena.cast(int(entry["player"]) + first_player, int(entry["staff"]), Vector2(float(dir[0]), float(dir[1])))
	arena.run(float(combo["seconds"]) - arena.time)
	return arena


## True when `status` was put on the first imp of `combo` played without `drop`.
func _holds(combo: Dictionary, drop: String = "") -> bool:
	var arena: ArenaScript = _play(combo, drop)
	var held: bool = arena.was_given(arena.imps[0], StringName(combo["checks"][0]["status"]))
	arena.free_all()
	return held


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "relay.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"relay", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.RELAY, "the relay behaviour")
	check(card.behaviour_strength > 0.0, "with a strength")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_hold_with_the_card_and_fail_without_it() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		check(not combo.is_empty(), "the combo %s exists" % id)
		if combo.is_empty():
			continue
		check(_holds(combo), "%s does what it promises" % id)
		check(not _holds(combo, "relay"), "%s fails without Relay" % id)


func test_the_status_is_the_donors_not_the_casters() -> void:
	# The frost combo chills; it must not burn, and the fire combo must not chill.
	var frost: ArenaScript = _play(_combo(COMBOS[0]))
	check(not frost.was_given(frost.imps[0], &"burn"), "the frost relay does not burn")
	frost.free_all()
	var fire: ArenaScript = _play(_combo(COMBOS[1]))
	check(not fire.was_given(fire.imps[0], &"chill"), "the fire relay does not chill")
	fire.free_all()


func test_four_players_at_once() -> void:
	# Two pairs (donor and relayer) far apart: player 1 donates frost to player 0, player 3 donates fire to player 2.
	var combo: Dictionary = _combo(COMBOS[0])
	if combo.is_empty():
		return
	var arena := ArenaScript.new(root)
	var imps: Array = []
	for pair in 2:
		var at := Vector2(0.0, 300.0 * pair)
		var first: int = pair * 2
		arena.place_caster(first, at)
		arena.place_caster(first + 1, at)
		arena.add_mate(at + Vector2(60.0, 0.0), first + 1)
		imps.append(arena.add_imp(at + Vector2(130.0, 0.0)))
		arena.install_cards(first + 1, 0, [["frost", "fire"][pair], "bolt"])
		arena.install_cards(first, 0, ["relay", "pierce", "bolt"])
	for pair in 2:
		check(arena.cast(pair * 2 + 1, 0, Vector2.DOWN), "donor %d casts" % (pair * 2 + 1))
	arena.run(0.1)
	for pair in 2:
		check(arena.cast(pair * 2, 0), "player %d casts" % (pair * 2))
	arena.run(2.0)
	check(arena.was_given(imps[0], &"chill"), "pair 0's relay bolt chills its imp")
	check(not arena.was_given(imps[0], &"burn"), "pair 0's imp does not burn")
	check(arena.was_given(imps[1], &"burn"), "pair 1's relay bolt burns its imp")
	check(not arena.was_given(imps[1], &"chill"), "pair 1's imp does not chill")
	arena.free_all()
