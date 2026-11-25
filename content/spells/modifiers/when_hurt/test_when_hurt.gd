extends "res://tests/support/suite.gd"
## The When Hurt card (content/spells/modifiers/when_hurt/; docs/milestones/staff-language.md, L2):
## a condition. The cast it is in leaves only while its caster is below half health; otherwise it
## is skipped as a cast the pool cannot pay, and the press, the corner panel and an enemy's AI all
## read it the same way (`Spells._firing_cast`). In a payload it is wasted.
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/when_hurt/when_hurt.tres") as ModifierBase


func test_the_card_is_a_valid_condition() -> void:
	var card: ModifierBase = _card()
	check(card != null, "when_hurt.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"when_hurt", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.WHEN, "a condition")
	check_equal(card.when_id, &"hurt", "it asks for hurt")
	check(is_equal_approx(card.behaviour_strength, 0.5), "below half")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_cast_carries_its_condition() -> void:
	var arena := ArenaScript.new(root)
	var compiled: CompiledStaff = arena.install_cards(0, 0, ["when_hurt", "nova", "bolt", "bolt"])
	arena.free_all()
	check_equal(compiled.casts.size(), 2, "two casts")
	check_equal(compiled.casts[0].when_ids, [&"hurt"] as Array[StringName], "the first is conditioned")
	check(compiled.casts[1].when_ids.is_empty(), "the second is plain")
	check(compiled.casts[0].description.begins_with("Only when hurt. "), "its plan says so: %s" % compiled.casts[0].description)
	check(not compiled.wasted.has(0), "it works")


func test_it_skips_while_whole_and_leaves_once_hurt() -> void:
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["when_hurt", "nova", "bolt", "bolt"])
	check_equal(arena.spells.firing_cast(0, 0, 100.0), 1, "whole: the plain bolt is next")
	arena.spells.sense_health(0, 0.6)
	check_equal(arena.spells.firing_cast(0, 0, 100.0), 1, "at 60% still whole enough")
	arena.spells.sense_health(0, 0.3)
	check_equal(arena.spells.firing_cast(0, 0, 100.0), 0, "below half the nova leaves")
	check(arena.cast(0, 0), "and the press casts it")
	arena.free_all()


func test_the_panel_the_ai_and_the_press_agree() -> void:
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["when_hurt", "bolt"])
	check_equal(arena.spells.firing_cast(0, 0, 100.0), -1, "nothing may leave while whole")
	check(not arena.spells.cast_ready(0, 0, 1.0, 100.0), "an AI is told it is not ready, so it never telegraphs it")
	check(not arena.cast(0, 0), "a staff of conditioned casts only fizzles")
	check(arena.spells.cooldown_left(0, 0) >= 0.0, "and its cooldown runs as a staff the pool cannot pay")
	arena.spells.sense_health(0, 0.2)
	arena.run(0.2)
	check(arena.spells.cast_ready(0, 0, 1.0, 100.0), "hurt: ready")
	check(arena.cast(0, 0), "hurt: it casts")
	arena.free_all()


func test_a_closed_caster_is_whole_again() -> void:
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["when_hurt", "bolt"])
	arena.spells.sense_health(0, 0.1)
	arena.spells.close_caster(0)
	arena.install_cards(0, 0, ["when_hurt", "bolt"])
	check_equal(arena.spells.firing_cast(0, 0, 100.0), -1, "an id opened again starts whole")
	arena.free_all()


func test_it_is_wasted_in_a_payload() -> void:
	var arena := ArenaScript.new(root)
	var compiled: CompiledStaff = arena.install_cards(0, 0, ["on_hit", "bolt", "when_hurt", "bolt"])
	arena.free_all()
	check(compiled.wasted.has(2), "a payload is never skipped")
	check(compiled.casts[0].when_ids.is_empty(), "and it does not condition the cast")


func test_the_builder_says_it() -> void:
	var arena := ArenaScript.new(root)
	var lines: PackedStringArray = arena.spells.component_stats(&"when_hurt")
	var cards: Array[StringName] = [&"when_hurt", &"pulse", &"bolt"]
	var view: Dictionary = arena.spells.staff_view(cards, ArenaScript.plain_staff(3))
	arena.free_all()
	check(lines.has("Only when hurt"), "its numbers line: %s" % [lines])
	var tree: Array = ((view["casts"] as Array)[0] as Dictionary)["tree"]
	check(str((tree[0] as Dictionary)["name"]).ends_with(", only when hurt"), "the tree's row: %s" % (tree[0] as Dictionary)["name"])
