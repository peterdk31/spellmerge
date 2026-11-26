extends "res://tests/support/suite.gd"
## The On Any Cast card (content/spells/triggers/on_any_cast/; docs/milestones/staff-language.md,
## L3): while its carrier lasts, every cast of any staff of its caster fires its payload from where
## the carrier is. Never for the cast that made it, never for another actor's casts, and never for a
## payload (no cast), so two of them cannot set each other off.
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const SpellsScript := preload("res://core/spells/spells.gd")


func _card() -> TriggerBase:
	return load("res://content/spells/triggers/on_any_cast/on_any_cast.tres") as TriggerBase


## Payload launches of the rune `on any cast · rune · bolt` on staff 0, counted by the shots alive
## after each of `presses` (staff, seconds) is made, as [shots after the rune, after each press...].
func _counts(presses: Array) -> PackedInt32Array:
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["on_any_cast", "rune", "bolt"])
	arena.install_cards(0, 1, ["rune"])
	arena.install_cards(1, 0, ["rune"])
	var out := PackedInt32Array()
	check(arena.cast(0, 0), "the rune is laid")
	arena.run(0.05)
	out.append(arena.projectiles.get_count())
	for press: Array in presses:
		arena.run(float(press[2]))
		arena.cast(int(press[0]), int(press[1]), Vector2.LEFT)
		arena.run(0.02)
		out.append(arena.projectiles.get_count())
	arena.free_all()
	return out


func test_the_card_is_a_valid_trigger() -> void:
	var card: TriggerBase = _card()
	check(card != null, "on_any_cast.tres loads as a TriggerBase")
	if card == null:
		return
	check_equal(card.id, &"on_any_cast", "its id is its folder")
	check_equal(card.event, TriggerBase.Event.ANY_CAST, "it hears any cast")
	check(TriggerBase.LIVE.has(TriggerBase.Event.ANY_CAST), "it listens while its carrier lives")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_cast_that_made_it_does_not_set_it_off() -> void:
	var counts: PackedInt32Array = _counts([])
	check_equal(counts[0], 1, "only the rune: its own cast fired no bolt")


func test_another_staff_s_cast_sets_it_off() -> void:
	# Staff 1 lays a rune of its own (one shot) and the first rune fires its bolt (one more).
	var counts: PackedInt32Array = _counts([[0, 1, 0.1]])
	check_equal(counts[1], counts[0] + 2, "a rune of staff 1 and the answering bolt: %s" % [counts])


func test_another_actor_s_cast_does_not() -> void:
	var counts: PackedInt32Array = _counts([[1, 0, 0.1]])
	check_equal(counts[1], counts[0] + 1, "only the other actor's rune: %s" % [counts])


func test_it_fires_every_time() -> void:
	var counts: PackedInt32Array = _counts([[0, 1, 0.1], [0, 1, 0.5]])
	check(counts[2] >= counts[1] + 2, "a second cast fires it again: %s" % [counts])


func test_its_own_staff_s_next_cast_sets_it_off() -> void:
	var counts: PackedInt32Array = _counts([[0, 0, 0.5]])
	check(counts[1] >= counts[0] + 2, "the staff's own next rune and the first rune's answer: %s" % [counts])


func test_a_payload_is_no_cast() -> void:
	# Two runes that answer with a payload of their own On Any Cast rune never set each other off.
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["on_any_cast", "rune", "on_any_cast", "rune", "bolt"])
	arena.install_cards(0, 1, ["atom"])
	check(arena.cast(0, 0), "the first rune")
	arena.run(0.1)
	check(arena.cast(0, 1, Vector2.LEFT), "another staff casts")
	arena.run(0.05)
	var after_one: int = arena.projectiles.get_count()
	arena.run(0.5)
	check(arena.projectiles.get_count() <= after_one, "the answering rune fires nothing by itself: %d then %d" % [after_one, arena.projectiles.get_count()])
	arena.free_all()


func test_a_cast_that_never_leaves_sets_nothing_off() -> void:
	# Every shot of staff 1 would start inside a wall: no cast left, no mana paid, so no answer.
	var arena := ArenaScript.new(root)
	arena.add_wall(Rect2(-200.0, 20.0, 400.0, 200.0))
	arena.install_cards(0, 0, ["on_any_cast", "rune", "bolt"])
	arena.install_cards(0, 1, ["atom"])
	check(arena.cast(0, 0), "the rune is laid ahead, clear of the wall")
	arena.run(0.1)
	var before: int = arena.projectiles.get_count()
	var origin := Vector2(0.0, 60.0)
	arena.projectiles.set_anchor(0, origin)
	var spent: float = arena.spells.cast_staff(0, 1, origin, Vector2.DOWN, 100.0)
	arena.run(0.02)
	check_equal(spent, SpellsScript.REFUSED, "the cast in the wall is refused")
	check_equal(arena.projectiles.get_count(), before, "and the rune does not answer it")
	arena.free_all()


func test_it_works_on_a_carrier_that_lasts() -> void:
	var arena := ArenaScript.new(root)
	var lasting: CompiledStaff = arena.install_cards(0, 1, ["on_any_cast", "familiar", "bolt"])
	arena.free_all()
	check(not lasting.wasted.has(0), "a familiar lasts")


func test_the_builder_says_it() -> void:
	var arena := ArenaScript.new(root)
	var lines: PackedStringArray = arena.spells.component_stats(&"on_any_cast")
	arena.free_all()
	check(lines.has("On any cast"), "its numbers line: %s" % [lines])
