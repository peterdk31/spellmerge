extends "res://tests/support/suite.gd"
## The Triple card (content/spells/multicasts/triple/, staffs phase C): a multicast that pulls two
## more carriers into the group being read, so three carriers leave in one cast, fanned out. Each
## of its combos does what it promises with the card and fails without it.
##
## godot --headless --path . --script res://tests/content/spells/test_triple.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["triple_frost_fan", "triple_three_ways"]


func _card() -> MulticastBase:
	return load("res://content/spells/multicasts/triple/triple.tres") as MulticastBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Plays `combo` in the arena, with every copy of `drop` taken out when it is set, and returns
## whether every check held. The arena is freed.
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
		match str(row["kind"]):
			"status":
				for index: int in row["imps"]:
					held = held and arena.was_given(arena.imps[index], StringName(row["status"]))
			"status_count":
				var count: int = 0
				for imp in arena.imps:
					if arena.was_given(imp, StringName(row["status"])):
						count += 1
				held = held and count >= int(row["min"])
	arena.free_all()
	return held


func test_the_card_is_a_valid_multicast() -> void:
	var card: MulticastBase = _card()
	check(card != null, "triple.tres loads as a MulticastBase")
	if card == null:
		return
	check_equal(card.id, &"triple", "its id is its folder")
	check_equal(card.kind(), &"multicast", "a multicast card")
	check_equal(card.extra_draws, 2, "two more carriers")
	check_equal(card.mode, MulticastBase.Mode.TOGETHER, "they leave together")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_three_carriers_leave_in_one_cast() -> void:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, ["triple", "fire", "bolt", "beam", "nova"])
	check_equal(staff.casts.size(), 1, "one cast")
	if staff.casts.size() == 1:
		var group: CompiledGroup = staff.casts[0].group
		var forms: Array[StringName] = []
		for spell in group.spells:
			forms.append(spell.form_id)
		check_equal(forms, [&"bolt", &"beam", &"nova"] as Array[StringName], "three carriers in the group")
		if group.spells.size() == 3:
			check_equal(group.spells[0].element_id, &"fire", "a fire bolt first")
			check_equal(group.spells[1].element_id, &"", "the fire stays on the bolt")
	check(staff.wasted.is_empty(), "no card is wasted")
	arena.free_all()


func test_the_combos_hold_with_the_card_and_fail_without_it() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		check(not combo.is_empty(), "the combo %s exists" % id)
		if combo.is_empty():
			continue
		check(_holds(combo), "%s does what it promises" % id)
		check(not _holds(combo, "triple"), "%s fails without Triple" % id)


func test_four_players_triple_at_once() -> void:
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 150.0 * player)
		arena.place_caster(player, at)
		for offset: Vector2 in [Vector2(117.0, -25.0), Vector2(120.0, 0.0), Vector2(117.0, 25.0)]:
			imps.append(arena.add_imp(at + offset))
		arena.install_cards(player, 0, ["triple", "bolt", "bolt", "bolt"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(1.5)
	for imp in imps:
		check(arena.lost(imp) > 0, "every player's three bolts hit")
	arena.free_all()
