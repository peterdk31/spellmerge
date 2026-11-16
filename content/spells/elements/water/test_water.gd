extends "res://tests/support/suite.gd"
## The Water card (content/spells/elements/water/): an infusion that soaks what it hits. A soaked
## body does not catch fire (and a soak puts a burn out), a heal on it heals its soak's strength in
## per cent more, and its reactions (content/spells/reactions.tres) are Douse (water and fire put
## each other out), Rime (frost on a soaked body, or water on a chilled one, freezes it), Current
## (lightning on a soaked body runs through every soaked body near), Squall (storm blows the soak
## onto the bodies round it; water spreads a gust) and Drown (void or water on the other's status:
## bonus damage). Its combos show each reaction in play.
##
## godot --headless --path . --script res://content/spells/elements/water/test_water.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")


func _card() -> ElementBase:
	return load("res://content/spells/elements/water/water.tres") as ElementBase


func _rows_of(reaction_id: StringName) -> Array[ReactionRow]:
	var table := load("res://content/spells/reactions.tres") as ReactionTable
	var found: Array[ReactionRow] = []
	for row: ReactionRow in table.rows:
		if row.reaction_id == reaction_id:
			found.append(row)
	return found


func test_the_card_is_a_valid_infusion() -> void:
	var card: ElementBase = _card()
	check(card != null, "water.tres loads as an ElementBase")
	if card == null:
		return
	check_equal(card.id, &"water", "its id is its folder")
	check_equal(card.status_id, &"soak", "it soaks")
	check(not card.heals, "it does not heal on its own")
	check(card.icon != null, "it has an icon")
	check_equal(card.look_id, &"drops", "it sheds drops, a look no other card has")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])
	check(card.tint.is_equal_approx(Palette.shades_of(&"water")[1]), "its tint is the Water material's base")


func test_every_element_reacts_with_water() -> void:
	var pairs: Dictionary = {}
	for id: StringName in [&"douse", &"rime", &"current", &"squall", &"drown"]:
		var rows: Array[ReactionRow] = _rows_of(id)
		check(not rows.is_empty(), "%s has rows" % id)
		for row: ReactionRow in rows:
			var other: StringName = row.element_id if row.status_id == &"soak" else row.status_id
			pairs[other] = id
	for other: StringName in [&"fire", &"burn", &"frost", &"chill", &"lightning", &"storm", &"gust", &"void", &"hex"]:
		check(pairs.has(other), "water reacts with %s" % other)


func test_a_water_bolt_soaks_an_imp() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(100.0, 0.0))
	arena.install_cards(0, 0, ["water", "bolt"])
	arena.cast(0, 0)
	arena.run(1.0)
	check(arena.combat.has_status(imp, &"soak"), "the imp is soaked")
	check(arena.lost(imp) > 0, "and hurt a little (%d)" % arena.lost(imp))
	arena.free_all()


func test_a_soaked_body_does_not_catch_fire_and_a_soak_puts_a_burn_out() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(100.0, 0.0))
	check(arena.combat.apply_status(-1, imp, &"soak", 4.0, 50.0), "it is soaked")
	check(not arena.combat.apply_status(-1, imp, &"burn", 3.0, 2.0), "a burn does not take on it")
	check(not arena.combat.has_status(imp, &"burn"), "so it is not burning")
	arena.free_all()
	arena = ArenaScript.new(root)
	imp = arena.add_imp(Vector2(100.0, 0.0))
	arena.combat.apply_status(-1, imp, &"burn", 3.0, 2.0)
	check(arena.combat.has_status(imp, &"burn"), "a dry imp burns")
	arena.combat.apply_status(-1, imp, &"soak", 4.0, 50.0)
	check(not arena.combat.has_status(imp, &"burn"), "a soak puts the burn out (cover's water, a squall's spread)")
	arena.free_all()


func test_water_douses_a_burning_imp() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(100.0, 0.0))
	arena.install_cards(0, 0, ["fire", "bolt"])
	arena.install_cards(0, 1, ["water", "bolt"])
	arena.cast(0, 0)
	arena.run(0.6)
	check(arena.combat.has_status(imp, &"burn"), "the fire bolt set it burning")
	arena.cast(0, 1)
	arena.run(0.6)
	check(arena.reaction_ids().has(&"douse"), "the water bolt doused it: %s" % [arena.reaction_ids()])
	check(not arena.combat.has_status(imp, &"burn"), "it burns no more")
	check(not arena.combat.has_status(imp, &"soak"), "and the douse used the water up")
	var lost: int = arena.lost(imp)
	arena.run(2.0)
	check_equal(arena.lost(imp), lost, "it loses nothing more")
	arena.free_all()


func test_a_heal_on_a_soaked_body_heals_more() -> void:
	var dry: int = _mended(false)
	var wet: int = _mended(true)
	check(dry > 0, "a mend bolt heals a dry teammate (%d)" % dry)
	check(wet > dry, "and a soaked one more (%d against %d)" % [wet, dry])


## Health a mend bolt gives a teammate hurt by 40, soaked first or not.
func _mended(soaked: bool) -> int:
	var arena := ArenaScript.new(root)
	var ally: Node2D = arena.add_guard(1, Vector2(60.0, 0.0))
	arena.hurt(ally, 40)
	if soaked:
		arena.combat.apply_status(-1, ally, &"soak", 4.0, 50.0)
	arena.install_cards(0, 0, ["mend", "bolt"])
	arena.cast(0, 0)
	arena.run(1.0)
	var healed: int = arena.healed()
	arena.free_all()
	return healed


func test_current_runs_only_through_the_soaked() -> void:
	var arena := ArenaScript.new(root)
	var struck: Node2D = arena.add_imp(Vector2(100.0, 0.0))
	var wet: Node2D = arena.add_imp(Vector2(130.0, 40.0))
	var dry: Node2D = arena.add_imp(Vector2(130.0, -40.0))
	var far: Node2D = arena.add_imp(Vector2(300.0, 0.0))
	for imp: Node2D in [struck, wet, far]:
		arena.combat.apply_status(-1, imp, &"soak", 4.0, 50.0)
	var arcs: Array = []
	arena.bus.discharge_arc.connect(func(_by: int, _from: Vector2, to: Vector2) -> void: arcs.append(to))
	arena.install_cards(0, 0, ["lightning", "bolt"])
	arena.cast(0, 0)
	arena.run(0.8)
	check(arena.reaction_ids().has(&"current"), "the lightning bolt set a current off: %s" % [arena.reaction_ids()])
	check(arena.lost(wet) > 0, "the soaked imp beside it was struck (%d)" % arena.lost(wet))
	check(not arena.combat.has_status(wet, &"soak"), "and lost its soak")
	check_equal(arena.lost(dry), 0, "the dry one beside it was not")
	check_equal(arena.lost(far), 0, "nor the soaked one out of reach")
	check(arena.combat.has_status(far, &"soak"), "which keeps its soak")
	check_equal(arcs.size(), 1, "one arc, to the soaked imp")
	arena.free_all()


func test_frost_on_a_soaked_imp_freezes_it_at_once() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(100.0, 0.0))
	arena.combat.apply_status(-1, imp, &"soak", 4.0, 50.0)
	arena.install_cards(0, 0, ["frost", "bolt"])
	arena.cast(0, 0)
	arena.run(0.6)
	check(arena.reaction_ids().has(&"rime"), "rime: %s" % [arena.reaction_ids()])
	check(arena.combat.has_status(imp, &"freeze"), "it is frozen by one frost hit")
	check(not arena.combat.has_status(imp, &"soak"), "its water froze")
	arena.free_all()


func test_storm_blows_the_soak_onto_the_bodies_round_it() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(100.0, 0.0))
	var near: Node2D = arena.add_imp(Vector2(120.0, 30.0))
	var far: Node2D = arena.add_imp(Vector2(220.0, 90.0))
	arena.combat.apply_status(-1, imp, &"soak", 4.0, 50.0)
	arena.install_cards(0, 0, ["storm", "bolt"])
	arena.cast(0, 0)
	arena.run(0.6)
	check(arena.reaction_ids().has(&"squall"), "squall: %s" % [arena.reaction_ids()])
	check(arena.combat.has_status(near, &"soak"), "the imp beside it is soaked")
	check(not arena.combat.has_status(far, &"soak"), "the one far off is not")
	arena.free_all()


func test_drown_does_bonus_damage() -> void:
	var arena := ArenaScript.new(root)
	var plain: Node2D = arena.add_imp(Vector2(100.0, 60.0))
	var soaked: Node2D = arena.add_imp(Vector2(100.0, -60.0))
	arena.combat.apply_status(-1, soaked, &"soak", 4.0, 50.0)
	arena.install_cards(0, 0, ["void", "bolt"])
	arena.install_cards(0, 1, ["void", "bolt"])
	arena.cast(0, 0, Vector2(100.0, 60.0).normalized())
	arena.cast(0, 1, Vector2(100.0, -60.0).normalized())
	arena.run(0.8)
	check(arena.reaction_ids().has(&"drown"), "drown: %s" % [arena.reaction_ids()])
	check(arena.lost(soaked) > arena.lost(plain), "the soaked imp lost more (%d against %d)" % [arena.lost(soaked), arena.lost(plain)])
	arena.free_all()


func test_a_resisted_soak_is_shorter() -> void:
	var stats := ActorStats.new()
	stats.resist_soak = 0.5
	check_equal(stats.resist_of(&"soak"), 0.5, "soak can be resisted, as every status")
	check(stats.problems().is_empty(), "and the share is in range")
	check(CombatScript.STATUS_AT.has(&"soak"), "Combat knows the status")


func test_water_on_a_charged_imp_runs_its_charge_through_the_soaked() -> void:
	var arena := ArenaScript.new(root)
	var charged: Node2D = arena.add_imp(Vector2(100.0, 0.0))
	var wet: Node2D = arena.add_imp(Vector2(130.0, 40.0))
	arena.combat.apply_status(-1, charged, &"static", 4.0, 50.0)
	arena.combat.apply_status(-1, wet, &"soak", 4.0, 50.0)
	arena.install_cards(0, 0, ["water", "bolt"])
	arena.cast(0, 0)
	arena.run(0.6)
	check(arena.reaction_ids().has(&"current"), "current: %s" % [arena.reaction_ids()])
	check(not arena.combat.has_status(wet, &"soak"), "the soaked imp beside it was run through")
	arena.free_all()
