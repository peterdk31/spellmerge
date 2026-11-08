extends "res://tests/support/suite.gd"
## The Pool card (content/spells/forms/pool/): a carrier that spreads a still patch ahead and strikes
## whatever stands in it every `SpellLimits.POOL_TICK` while it lives (`CarrierPool`). A body that
## stays is hit again and again, one beside it never, and the patch ends with its life.
##
## godot --headless --path . --script res://content/spells/forms/pool/test_pool.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _card() -> FormBase:
	return load("res://content/spells/forms/pool/pool.tres") as FormBase


func test_the_card_is_a_valid_carrier() -> void:
	var card: FormBase = _card()
	check(card != null, "pool.tres loads as a FormBase")
	if card == null:
		return
	check_equal(card.id, &"pool", "its id is its folder")
	check_equal(card.carrier, &"pool", "it fires the pool carrier")
	check(card.shot_shader == preload("res://content/spells/forms/pool/pool.gdshader"), "drawn as a puddle, by its folder's shader")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])
	check(card.look_problems().is_empty(), "its look is one the shaders draw: %s" % [card.look_problems()])
	var pool: Carrier = Carriers.of(&"pool")
	check(pool.stays() and pool.hits() and pool.lasts(), "it stays, hits and lasts")
	check(not pool.flies() and not pool.has(Carrier.PIERCE), "it never flies, and its hits never spend it")


## Losses of a body standing in the pool and one beside it after `seconds`.
func _losses(seconds: float) -> Array[int]:
	var arena := ArenaScript.new(root)
	arena.add_imp(Vector2(56.0, 0.0))
	arena.add_imp(Vector2(56.0, 44.0))
	arena.install_cards(0, 0, ["pool"])
	arena.cast(0, 0)
	arena.run(seconds)
	var out: Array[int] = [arena.lost(arena.imps[0]), arena.lost(arena.imps[1])]
	arena.free_all()
	return out


func test_it_strikes_what_stands_in_it_every_tick() -> void:
	var early: Array[int] = _losses(SpellLimits.POOL_TICK * 0.5)
	check_equal(early[0], 1, "the first strike as it spreads")
	var later: Array[int] = _losses(SpellLimits.POOL_TICK * 4.5)
	check_equal(later[0], 5, "then one every tick: five in four and a half ticks")
	check_equal(later[1], 0, "a body beside it is never struck")


func test_it_ends_with_its_life() -> void:
	var card: FormBase = _card()
	var whole: Array[int] = _losses(card.lifetime + 1.0)
	var longer: Array[int] = _losses(card.lifetime + 3.0)
	check_equal(longer[0], whole[0], "nothing more once its %s s are over" % card.lifetime)


func test_two_combos_name_it() -> void:
	var found: int = 0
	for combo: Dictionary in preload("res://tests/support/combo_files.gd").read_all():
		if str(combo.get("needs", "")) == "pool":
			found += 1
	check(found >= 2, "two combos are about the pool (%d)" % found)
