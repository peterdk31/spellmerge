extends "res://tests/support/suite.gd"
## The Plow card (content/spells/modifiers/plow/, boss OB11; docs/milestones/boss-old-broom.md,
## "Plow (OB11)"): what its carrier hits rides along in front of what moves it instead of being
## passed (core/spells/plow.gd), pinned against a wall it takes twice the hit, and let go it is
## shoved on. It works on what moves along a way: a dash, and a flying shot (a battering ram whose
## carried bodies do not spend it); a teleport, over at once, and what strikes from the hand carry
## nothing. The carrying itself is held by tests/gameplay/actor/test_plow_carry.gd. Its combos
## (`combos/`, each with `needs: plow`) are held with and without it by
## tests/content/spells/test_combos.gd.
##
## godot --headless --path . --script res://content/spells/modifiers/plow/test_plow.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/plow/plow.tres") as ModifierBase


func _first(cards: Array) -> CompiledSpell:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, cards)
	var spell: CompiledSpell = null if staff.is_empty() else staff.casts[0].group.spells[0]
	arena.free_all()
	return spell


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "plow.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"plow", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.PLOW, "its behaviour is plow")
	check(card.mana_mult > 1.0, "it costs more mana (%s)" % card.mana_mult)
	check(card.description != "" and card.description.length() <= 60, "its builder line")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_its_hit_arms_a_pin_of_twice_the_hit() -> void:
	var dash: CompiledSpell = _first(["plow", "dash"])
	check_equal(dash.hit.pin, maxi(roundi(dash.damage * SpellLimits.PIN_SHARE), 1), "a pin of twice the hit (%s)" % dash.damage)
	check(dash.hit.pin >= roundi(dash.damage) * 2, "harder than heavy's slam (1x)")
	var heavy: CompiledSpell = _first(["heavy", "plow", "dash"])
	check(heavy.hit.pin > heavy.hit.slam, "with heavy too, the pin is the harder (%s, %s)" % [heavy.hit.pin, heavy.hit.slam])


func test_a_flying_shot_is_a_battering_ram() -> void:
	var plain: CompiledSpell = _first(["bolt"])
	var ram: CompiledSpell = _first(["plow", "bolt"])
	check_equal(ram.pierce, plain.pierce + SpellLimits.PLOW_MOST, "what it carries does not spend it")
	check(ram.hit.pin > 0, "and it pins")
	var dash: CompiledSpell = _first(["plow", "dash"])
	check_equal(dash.pierce, _first(["dash"]).pierce, "a dash's pass passes everything anyway")


func test_it_works_on_what_moves_along_a_way() -> void:
	var carriers: Dictionary = Carriers.make_all()
	for id: StringName in [&"dash", &"atom"]:
		check((carriers[id] as Carrier).works(ModifierBase.Behaviour.PLOW), "%s carries" % id)
	for id: StringName in [&"teleport", &"swing", &"slam", &"beam", &"pulse", &"rune", &"pool", &"wall"]:
		check(not (carriers[id] as Carrier).works(ModifierBase.Behaviour.PLOW), "%s carries nothing" % id)
