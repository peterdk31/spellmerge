extends "res://tests/support/suite.gd"
## The Quick Hand card (content/spells/modifiers/quick_hand/; docs/milestones/staff-language.md, L1):
## a fixed quarter second off the next carrier's wind-down (`ModifierBase.wind_down_add`), for half
## again the mana. The floor at 0 is the cast's, not the carrier's; the staff's cooldown and every
## wind-up are out of its reach, and a payload, which adds no wind-down, wastes it.
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/quick_hand/quick_hand.tres") as ModifierBase


func _staff(cards: Array) -> CompiledStaff:
	var arena := ArenaScript.new(root)
	var compiled: CompiledStaff = arena.install_cards(0, 0, cards)
	arena.free_all()
	return compiled


func _cast(cards: Array) -> CompiledCast:
	return _staff(cards).casts[0]


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "quick_hand.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"quick_hand", "its id is its folder")
	check(card.wind_down_add < 0.0, "it takes a fixed amount off")
	check(card.mana_mult > 1.0, "at a price in mana")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_it_takes_a_quarter_second_off_a_bolt() -> void:
	var plain: CompiledCast = _cast(["bolt"])
	var quick: CompiledCast = _cast(["quick_hand", "bolt"])
	check(is_equal_approx(quick.wind_down, plain.wind_down - 0.25), "a quarter second off: %s of %s" % [quick.wind_down, plain.wind_down])
	check(is_equal_approx(quick.delay, quick.wind_down), "the staff waits that long (no cooldown on the plain staff)")
	check(not quick.wasted.has(0), "it works on a plain bolt")
	check(quick.mana > plain.mana, "for more mana: %s against %s" % [quick.mana, plain.mana])


func test_it_comes_after_the_factors() -> void:
	# Lumber's factor first, then the quarter second comes off: a fixed amount, whatever the order.
	var before: CompiledCast = _cast(["quick_hand", "lumber", "bolt"])
	var after: CompiledCast = _cast(["lumber", "quick_hand", "bolt"])
	var plain: CompiledCast = _cast(["lumber", "bolt"])
	check(is_equal_approx(before.wind_down, plain.wind_down - 0.25), "in front: %s of %s" % [before.wind_down, plain.wind_down])
	check(is_equal_approx(after.wind_down, before.wind_down), "behind: the same, %s" % after.wind_down)


func test_two_take_it_all_and_never_below_nothing() -> void:
	var two: CompiledCast = _cast(["quick_hand", "quick_hand", "bolt"])
	var three: CompiledCast = _cast(["quick_hand", "quick_hand", "quick_hand", "bolt"])
	check_equal(two.wind_down, 0.0, "a bolt's 0.35 s is gone with two")
	check_equal(three.wind_down, 0.0, "a third leaves it at 0, never below")
	check(three.delay >= 0.0, "the staff never waits less than nothing")


func test_the_floor_is_the_cast_s() -> void:
	# In a multicast cast, the card takes from the whole cast: its own bolt's wind-down may go below
	# 0 and the other bolt's pays for it.
	var plain: CompiledCast = _cast(["double", "bolt", "bolt"])
	var quick: CompiledCast = _cast(["double", "quick_hand", "quick_hand", "bolt", "bolt"])
	check(is_equal_approx(quick.wind_down, maxf(plain.wind_down - 0.5, 0.0)), "the cast's: %s of %s" % [quick.wind_down, plain.wind_down])
	check(quick.wind_down > 0.0, "the other bolt still waits some")


func test_it_leaves_the_staff_s_cooldown() -> void:
	var staff := StaffBase.new()
	staff.id = &"slow"
	staff.slots = 3
	staff.cooldown = 0.4
	var cards: Array[StringName] = [&"quick_hand", &"quick_hand", &"bolt"]
	var compiled: CompiledStaff = _compile(cards, staff)
	check_equal(compiled.casts[0].wind_down, 0.0, "the cast's wind-down is gone")
	check(is_equal_approx(compiled.casts[0].delay, 0.4), "the cooldown after the cycle stays: %s" % compiled.casts[0].delay)


func test_it_is_wasted_on_a_payload() -> void:
	# A payload adds no wind-down to its staff: nothing to take away.
	var cast: CompiledCast = _cast(["on_hit", "bolt", "quick_hand", "bolt"])
	check(cast.wasted.has(2), "on a payload's bolt it does nothing")


func test_the_builder_says_it() -> void:
	var arena := ArenaScript.new(root)
	var lines: PackedStringArray = arena.spells.component_stats(&"quick_hand")
	arena.free_all()
	check(lines.has("Delay -0.25s"), "its numbers line: %s" % [lines])


func _compile(cards: Array[StringName], staff: StaffBase) -> CompiledStaff:
	var arena := ArenaScript.new(root)
	var compiled: CompiledStaff = arena.spells.compile_staff(cards, staff)
	arena.free_all()
	return compiled
