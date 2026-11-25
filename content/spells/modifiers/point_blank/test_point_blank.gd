extends "res://tests/support/suite.gd"
## The Point Blank card (content/spells/modifiers/point_blank/; docs/milestones/staff-language.md,
## L1): the next carrier lives at most 0.05 s (`ModifierBase.lifetime_most`), after every other life
## card, so it ends at the staff's tip and its blast and its `on expire` go off there.
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/point_blank/point_blank.tres") as ModifierBase


func _spell(cards: Array) -> CompiledSpell:
	var arena := ArenaScript.new(root)
	var cast: CompiledCast = arena.install_cards(0, 0, cards).casts[0]
	arena.free_all()
	return cast.group.spells[0]


func _wasted(cards: Array) -> Dictionary:
	var arena := ArenaScript.new(root)
	var cast: CompiledCast = arena.install_cards(0, 0, cards).casts[0]
	arena.free_all()
	return cast.wasted


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "point_blank.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"point_blank", "its id is its folder")
	check(card.lifetime_most > 0.0, "it caps the life")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_it_caps_a_bolt_s_life() -> void:
	var spell: CompiledSpell = _spell(["point_blank", "bolt"])
	check(is_equal_approx(spell.lifetime, _card().lifetime_most), "the bolt lives %s s" % spell.lifetime)


func test_no_life_card_lengthens_it_in_any_order() -> void:
	for cards: Array in [["point_blank", "slow", "bolt"], ["slow", "point_blank", "bolt"], ["reach", "point_blank", "reach", "bolt"], ["point_blank", "orbit", "bolt"]]:
		var spell: CompiledSpell = _spell(cards)
		check(spell.lifetime <= _card().lifetime_most + 0.0001, "%s lives %s s at most" % [cards, spell.lifetime])


func test_a_shorter_life_stays_shorter() -> void:
	# A most, never a set: a carrier already shorter than the cap keeps its own life.
	var arena := ArenaScript.new(root)
	var card: ModifierBase = _card().duplicate() as ModifierBase
	card.lifetime_most = 1.0
	var compiler := StaffCompiler.new(func(id: StringName) -> SpellComponent: return card if id == &"point_blank" else arena.spells.call("_component", id))
	var cards: Array[StringName] = [&"point_blank", &"atom"]
	var atom: CompiledSpell = compiler.compile(cards, ArenaScript.plain_staff(2)).casts[0].group.spells[0]
	arena.free_all()
	check(is_equal_approx(atom.lifetime, 0.3), "an atom's 0.3 s stays under a 1 s cap: %s" % atom.lifetime)


func test_it_works_where_life_matters() -> void:
	check(not _wasted(["point_blank", "bolt"]).has(0), "a bolt")
	check(not _wasted(["point_blank", "rune"]).has(0), "a rune lasts, so it ends at once")
	check(_wasted(["point_blank", "dash"]).has(0), "a dash's time is its move's, not its life")
	check(_wasted(["point_blank", "teleport"]).has(0), "a teleport's too")


func test_its_blast_goes_off_at_the_tip() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(30.0, 30.0))
	arena.install_cards(0, 0, ["point_blank", "blast", "bolt"])
	arena.cast(0, 0)
	arena.run(0.6)
	check(arena.lost(imp) > 0, "the imp at the shoulder is caught by the blast")
	arena.free_all()


func test_it_is_wasted_on_a_held_carrier() -> void:
	# A held carrier that lasts lives as long as it is held, whatever its life.
	check(_wasted(["point_blank", "hold", "beam"]).has(0), "a held beam")
	check(_wasted(["hold", "point_blank", "rune"]).has(1), "a held rune")
	check(not _wasted(["point_blank", "beam"]).has(0), "a beam let go of: it works")


func test_an_ai_knows_its_blast_catches_its_caster() -> void:
	var arena := ArenaScript.new(root)
	var blast: CompiledCast = arena.install_cards(0, 0, ["point_blank", "blast", "bolt"]).casts[0]
	var far: CompiledCast = arena.install_cards(0, 1, ["blast", "bolt"]).casts[0]
	arena.free_all()
	check(blast.sense.blast_on_caster, "a blast at the staff's tip is on its caster")
	check(not far.sense.blast_on_caster, "a flying blast bolt's is not")


func test_the_builder_says_it() -> void:
	var arena := ArenaScript.new(root)
	var lines: PackedStringArray = arena.spells.component_stats(&"point_blank")
	arena.free_all()
	check(lines.has("Life 0.05s at most"), "its numbers line: %s" % [lines])
