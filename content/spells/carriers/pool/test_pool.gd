extends "res://tests/support/suite.gd"
## The Pool card (content/spells/carriers/pool/): a carrier that spreads a still patch ahead and strikes
## whatever stands in it every `SpellLimits.POOL_TICK` while it lives (`CarrierPool`). A body that
## stays is hit again and again, one beside it never, and the patch ends with its life.
##
## godot --headless --path . --script res://tests/support/run.gd -- res://content/spells/carriers/pool/test_pool.gd
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _card() -> CarrierCard:
	return load("res://content/spells/carriers/pool/pool.tres") as CarrierCard


func test_the_card_is_a_valid_carrier() -> void:
	var card: CarrierCard = _card()
	check(card != null, "pool.tres loads as a CarrierCard")
	if card == null:
		return
	check_equal(card.id, &"pool", "its id is its folder")
	check_equal(card.carrier, &"pool", "it fires the pool carrier")
	check(card.look_shader == preload("res://content/spells/carriers/pool/pool.gdshader"), "drawn as a puddle, by its folder's shader")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])
	check(card.look_problems().is_empty(), "its look is one the shaders draw: %s" % [card.look_problems()])
	check(card.look_on_floor, "it lies on the floor, under every body")
	check(card.look_merges, "and pools that overlap are drawn as one")
	check(card.look_light_intensity < 0.5 and card.look_light_reach < 1.0, "it lights the floor round it dimly, not the room (the owner, 2026-11-16)")
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
	var early: Array[int] = _losses(SpellLimits.POOL_LAND + SpellLimits.POOL_TICK * 0.5)
	check_equal(early[0], 1, "the first strike as it lands")
	var later: Array[int] = _losses(SpellLimits.POOL_LAND + SpellLimits.POOL_TICK * 4.5)
	check_equal(later[0], 5, "then one every tick: five in four and a half ticks")
	check_equal(later[1], 0, "a body beside it is never struck")


func test_it_hits_nothing_until_it_lands() -> void:
	# Thrown out of the staff, it is in the air first (the owner, 2026-11-16: "the pool should wait
	# for the landing before it hits").
	var flying: Array[int] = _losses(SpellLimits.POOL_LAND * 0.8)
	check_equal(flying[0], 0, "nothing struck while it is in the air")
	var landed: Array[int] = _losses(SpellLimits.POOL_LAND + 0.05)
	check_equal(landed[0], 1, "struck as it lands")


func test_it_ends_with_its_life() -> void:
	var card: CarrierCard = _card()
	var whole: Array[int] = _losses(card.lifetime + 1.0)
	var longer: Array[int] = _losses(card.lifetime + 3.0)
	check_equal(longer[0], whole[0], "nothing more once its %s s are over" % card.lifetime)


func test_it_is_spat_out_the_way_it_was_cast() -> void:
	# Its look spills ahead and throws its drops that way (the owner, 2026-11-16: "like the wand
	# spitting out the elements the pool is made of"): its shot faces the way it was cast.
	var arena := ArenaScript.new(root)
	arena.install_cards(0, 0, ["pool"])
	arena.cast(0, 0)
	arena.run(0.1)
	var found: int = 0
	for slot in arena.projectiles.get_cap():
		if arena.projectiles.is_alive(slot):
			found += 1
			check(arena.projectiles.get_facing_of(slot).is_equal_approx(Vector2.RIGHT), "cast along +x, it faces +x (%s)" % arena.projectiles.get_facing_of(slot))
	check_equal(found, 1, "one pool")
	arena.free_all()


func test_it_is_thrown_from_the_staff_to_where_it_lies() -> void:
	# The wizard spits it out of the wand like a water gun and it lies where that lands (the owner,
	# 2026-11-16): its `shown_cue` is played from the cast's origin, as far as the pool lies.
	check_equal(_card().shown_cue, &"pool_throw", "its throw is its shown cue")
	var arena := ArenaScript.new(root)
	var shown: Array = []
	arena.bus.carrier_shown.connect(func(_caster: int, card: StringName, origin: Vector2, direction: Vector2, length: float, _tint: Color, _look: int) -> void:
		shown.append([card, origin, direction, length]))
	arena.install_cards(0, 0, ["pool"])
	arena.cast(0, 0)
	arena.run(0.1)
	var lies: Vector2 = Vector2.INF
	for slot in arena.projectiles.get_cap():
		if arena.projectiles.is_alive(slot):
			lies = arena.projectiles.get_position_of(slot)
	check_equal(shown.size(), 1, "told once")
	if shown.size() == 1 and lies.is_finite():
		check_equal(shown[0][0], &"pool", "as the pool")
		var landed: Vector2 = (shown[0][1] as Vector2) + (shown[0][2] as Vector2) * float(shown[0][3])
		check(landed.distance_to(lies) < 0.5, "from where it was cast to where it lies (%s, %s)" % [landed, lies])
	arena.free_all()


func test_it_lies_there_once_the_throw_lands() -> void:
	# The puddle splashes in as the thrown blobs land: its shader waits the blobs' flight, and its
	# splash motes start then.
	var glob := load("res://content/motes/glob.tres") as MoteKind
	var code: String = (_card().look_shader as Shader).code
	var arrive: float = code.get_slice("const float ARRIVE = ", 1).get_slice(";", 0).to_float()
	check(arrive > 0.0 and arrive >= glob.life.x - 0.05 and arrive <= glob.life.y, "it lies there as the blobs land (%s s, they fly %s s)" % [arrive, glob.life])
	check(is_equal_approx(arrive, SpellLimits.POOL_LAND), "its look lands when it starts to hit (%s s, POOL_LAND %s s)" % [arrive, SpellLimits.POOL_LAND])
	for stream: CardMoteStream in _card().look_motes:
		check(is_equal_approx(stream.start, arrive), "its %s motes start as it lands" % stream.kind)


func test_two_combos_name_it() -> void:
	var found: int = 0
	for combo: Dictionary in preload("res://tests/support/combo_files.gd").read_all():
		if str(combo.get("needs", "")) == "pool":
			found += 1
	check(found >= 2, "two combos are about the pool (%d)" % found)
