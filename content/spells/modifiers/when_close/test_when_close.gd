extends "res://tests/support/suite.gd"
## The When Close card (content/spells/modifiers/when_close/; docs/milestones/staff-language.md, L2):
## a condition. The cast it is in leaves only while a foe of its caster stands within 96 px of the
## caster's body; otherwise it is skipped as a cast the pool cannot pay. A teammate does not count.
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/when_close/when_close.tres") as ModifierBase


func _next(foe: Vector2, mate: Vector2 = Vector2.INF) -> int:
	var arena := ArenaScript.new(root)
	if foe.is_finite():
		arena.add_imp(foe)
	if mate.is_finite():
		arena.add_mate(mate, 1)
	arena.install_cards(0, 0, ["when_close", "slam", "bolt"])
	arena.projectiles.set_anchor(0, Vector2.ZERO)
	arena.run(0.05)
	var at: int = arena.spells.firing_cast(0, 0, 100.0)
	arena.free_all()
	return at


func test_the_card_is_a_valid_condition() -> void:
	var card: ModifierBase = _card()
	check(card != null, "when_close.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"when_close", "its id is its folder")
	check_equal(card.when_id, &"close", "it asks for close")
	check(is_equal_approx(card.behaviour_strength, 96.0), "within 96 px")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_it_leaves_only_with_a_foe_close() -> void:
	check_equal(_next(Vector2.INF), 1, "no foe: the slam is skipped")
	check_equal(_next(Vector2(60.0, 0.0)), 0, "a foe at 60 px: the slam leaves")
	check_equal(_next(Vector2(0.0, -80.0)), 0, "on any side")
	check_equal(_next(Vector2(160.0, 0.0)), 1, "a foe at 160 px is not close")


func test_a_teammate_is_no_foe() -> void:
	check_equal(_next(Vector2.INF, Vector2(40.0, 0.0)), 1, "a teammate beside the wizard does not count")


func test_the_builder_says_it() -> void:
	var arena := ArenaScript.new(root)
	var lines: PackedStringArray = arena.spells.component_stats(&"when_close")
	arena.free_all()
	check(lines.has("Only when close"), "its numbers line: %s" % [lines])


func test_asking_changes_no_state() -> void:
	# The corner panel asks `firing_cast` every drawn frame, between ticks: a `close` cast must be
	# a pure read there, or a frame drawn on one machine and not another parts their state hashes.
	var arena := ArenaScript.new(root)
	arena.add_imp(Vector2(60.0, 0.0))
	arena.install_cards(0, 0, ["when_close", "slam", "bolt"])
	arena.projectiles.set_anchor(0, Vector2.ZERO)
	arena.run(0.05)
	arena.projectiles.nearest_point = Vector2(-7.0, -7.0)
	var fill: Variant = arena.projectiles.get(&"_grid_fill")
	var stale: Variant = arena.projectiles.get(&"_grid_stale")
	check_equal(arena.spells.firing_cast(0, 0, 100.0), 0, "the foe is close")
	check(arena.spells.cast_ready(0, 0, 1.0, 100.0), "ready")
	check_equal(arena.projectiles.nearest_point, Vector2(-7.0, -7.0), "nearest_point is not written")
	check_equal(arena.projectiles.get(&"_grid_fill"), fill, "the grid is not refilled")
	check_equal(arena.projectiles.get(&"_grid_stale"), stale, "nor marked")
	arena.free_all()
