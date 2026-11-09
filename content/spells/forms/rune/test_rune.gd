extends "res://tests/support/card_rig.gd"
## The Rune card (content/spells/forms/rune/, M2 part 10): it stays where it was placed and hits what walks in.
##
## godot --headless --path . --script res://content/spells/forms/rune/test_rune.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func test_the_card_is_a_rune() -> void:
	_check_card(&"rune", 2)
	check_equal(_form(&"rune").carrier, &"rune", "rune waits")


func test_it_works_for_all_four_players_at_once() -> void:
	_four_players_cast([&"rune"], false)
	for player in 4:
		check(_mgr.get_count_for(player) > 0, "player %d has shots" % player)


func test_the_rune_stays_where_it_was_cast_and_hits_what_walks_in() -> void:
	var tag: int = _cast_form(&"rune", 0, Vector2(50.0, 50.0))
	check_equal(_slots(tag).size(), 1, "one rune")
	_tick(90)
	# Placed a step ahead along the aim, twice its size (rules R4 F3).
	var placed: Vector2 = Vector2(50.0 + _form(&"rune").radius * 2.0, 50.0)
	check_equal(_mgr.get_position_of(_slots(tag)[0]), placed, "it did not move")
	check_equal(_hits.size(), 0, "nobody was near")
	var imp := _target(Vector2(300.0, 300.0))
	imp.global_position = placed + Vector2(5.0, 0.0)
	_tick(4)
	check_equal(_hit_targets(), [imp] as Array, "an imp that walks in is hit")


func test_the_rune_stays_when_the_caster_and_a_target_move_away() -> void:
	var tag: int = _cast_form(&"rune", 0, Vector2.ZERO)
	var imp := _target(Vector2(300.0, 0.0))
	_tick(30, {0: Vector2(200.0, 0.0)})
	imp.global_position = Vector2(400.0, 0.0)
	_tick(30, {0: Vector2(200.0, 0.0)})
	check_equal(_mgr.get_position_of(_slots(tag)[0]), Vector2(_form(&"rune").radius * 2.0, 0.0), "the rune stays where it was placed, a step ahead of the cast point")
	check_equal(_hits.size(), 0, "nobody was near it")


## Its looks (S6 2): the cue each moment plays (every cue a card names is a cue file:
## tests/content/spells/test_carrier_looks.gd).
func test_its_moments_have_their_cues() -> void:
	var card: FormBase = load("res://content/spells/forms/rune/rune.tres") as FormBase
	check_equal(card.impact_cue, &"rune_burst", "its impact plays rune_burst")
	check_equal(card.cast_cue, &"cast_rune", "its cast plays cast_rune")


## A rune arms (owner, 2026-11-06): for SpellLimits.RUNE_ARM it hits nothing, even a body on it,
## then it goes off.
func test_a_rune_hits_nothing_until_it_is_armed() -> void:
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["rune"])
	var placed: Vector2 = Vector2(_form(&"rune").radius * 2.0, 0.0)
	var imp: Node2D = arena.add_imp(placed)
	check(arena.cast(0, 0), "cast")
	arena.run(SpellLimits.RUNE_ARM - 0.2)
	check_equal(arena.lost(imp), 0, "an imp standing on it is not hit while it arms")
	arena.run(0.4)
	check(arena.lost(imp) > 0, "it goes off once armed")
	arena.free_all()


## The exception to a payload sparing the body whose hit fired it: a rune cast on a body arms and
## goes off on that body.
func test_a_rune_cast_on_a_hit_goes_off_on_that_body_once_armed() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(100, 0))
	arena.install_cards(0, 0, ["on_hit", "bolt", "rune"])
	check(arena.cast(0, 0), "cast")
	arena.run(0.3)
	var by_bolt: int = arena.lost(imp)
	check(by_bolt > 0, "the bolt hit")
	arena.run(SpellLimits.RUNE_ARM + 0.3)
	check(arena.lost(imp) > by_bolt, "and the rune it left goes off on the same imp")
	arena.free_all()


## Its look (the owner's pick, 2026-11-09: the hovering seal): its shader knows when it is armed from
## its still clock (`ProjectileManager.still_code`), which covers its arming, and arms when the rune
## does.
func test_its_look_arms_when_it_does() -> void:
	var card: FormBase = _form(&"rune")
	check(card.look_shader == preload("res://content/spells/forms/rune/rune.gdshader"), "drawn by its folder's shader")
	var code: String = card.look_shader.code
	check(code.contains("const float ARM = %s;" % String.num(SpellLimits.RUNE_ARM, 1)), "the shader arms at SpellLimits.RUNE_ARM")
	check(code.contains("still_since("), "it reads its time since it was placed")
	check(ManagerScript.STILL_START > SpellLimits.RUNE_ARM, "the still clock runs past its arming")
