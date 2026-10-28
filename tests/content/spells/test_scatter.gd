extends "res://tests/support/suite.gd"
## The Scatter card (content/spells/multicasts/scatter/, staffs C): the next group gets three
## carriers, each sent in its own random direction, seeded per cast. The engine side is tested in
## `tests/core/test_spells_multicast.gd`; here the card's data and its combos.
##
## godot --headless --path . --script res://tests/content/spells/test_scatter.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _lost(cards: Array, at: Vector2, seconds: float, player: int = 0) -> int:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(at)
	arena.install_cards(player, 0, cards)
	arena.cast(player, 0)
	arena.run(seconds)
	var lost: int = arena.lost(imp)
	arena.free_all()
	return lost


func test_the_card_is_a_valid_multicast() -> void:
	var card: MulticastBase = load("res://content/spells/multicasts/scatter/scatter.tres") as MulticastBase
	check(card != null, "scatter.tres loads as a MulticastBase")
	if card == null:
		return
	check_equal(card.id, &"scatter", "its id is its folder")
	check_equal(card.kind(), &"multicast", "a multicast card")
	check_equal(card.mode, MulticastBase.Mode.SCATTER, "it scatters")
	check_equal(card.extra_draws, 2, "two more carriers, three in all")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_three_carriers_leave_in_one_cast() -> void:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, ["scatter", "bolt", "bolt", "bolt"])
	check_equal(staff.casts.size(), 1, "one cast")
	if staff.casts.size() == 1:
		check_equal(staff.casts[0].group.spells.size(), 3, "three carriers in the group")
	arena.free_all()


func test_the_nova_rings_three_times() -> void:
	var one: int = _lost(["nova"], Vector2(20.0, 0.0), 1.0)
	check(one > 0, "a single nova hurts")
	check(one * 3 < ArenaScript.IMP_HEALTH, "the imp survives three rings")
	# Each ring is turned a random way, so how many of its eight shots reach the imp varies; but
	# every ring reaches it, so three rings hurt at least twice as much as one.
	check(_lost(["scatter", "nova", "nova", "nova"], Vector2(20.0, 0.0), 1.0) >= one * 2, "three rings hurt more than two")


func test_a_bolt_flies_off_aim_for_some_casts() -> void:
	# A scatter of three bolts at one imp ahead hits with a bolt only when one happens to point
	# at it, so over several casts it lands fewer bolts than three aimed ones would.
	var aimed: int = _lost(["triple", "bolt", "bolt", "bolt"], Vector2(100.0, 0.0), 1.5)
	check(aimed > 0, "three aimed bolts hurt")
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(100.0, 0.0), 100000)
	arena.install_cards(0, 0, ["scatter", "bolt", "bolt", "bolt"])
	var total: int = 0
	for cast_index in 4:
		arena.cast(0, 0)
		arena.run(1.5)
		total += arena.lost(imp)
	check(total < aimed * 4, "scattered bolts miss more than aimed ones (%d of %d)" % [total, aimed * 4])
	arena.free_all()


func test_the_scatter_costs_more_mana_than_one_carrier() -> void:
	var arena := ArenaScript.new(root)
	var plain: CompiledStaff = arena.install_cards(0, 0, ["nova"])
	var scatter: CompiledStaff = arena.install_cards(0, 1, ["scatter", "nova", "nova", "nova"])
	check(scatter.casts[0].mana >= plain.casts[0].mana + 4.0, "the card adds its 4 mana")
	arena.free_all()


func test_four_players_scatter_at_once() -> void:
	var one: int = _lost(["nova"], Vector2(20.0, 0.0), 1.0)
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 150.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(20.0, 0.0)))
		arena.install_cards(player, 0, ["scatter", "nova", "nova", "nova"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(1.0)
	for imp in imps:
		check(arena.lost(imp) >= one * 2, "every imp took three rings (%d)" % arena.lost(imp))
	arena.free_all()
