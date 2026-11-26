extends "res://tests/support/suite.gd"
## The field carrier (docs/milestones/field.md): a still circle that hits nothing, whose cards every
## shot that comes into it takes (anyone's, an enemy's too), once each time it comes in; the dam (its
## Linger) holding shots until it ends, and letting them go early when it ends early; Growth widening
## it; its own shot wearing none of the cards it gives; its own payloads not taking it.
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const FIELD: CarrierCard = preload("res://content/spells/carriers/field/field.tres")

const STEP: float = 1.0 / 60.0

var _arena: ArenaScript = null


func after_each() -> void:
	if _arena != null:
		_arena.free_all()
		_arena = null


func _fields() -> CarrierField:
	return CarrierField.of(_arena.spells)


## The live shots that are no field.
func _shots() -> Array[int]:
	var out: Array[int] = []
	var pm: ManagerScript = _arena.projectiles
	for slot in pm._high:
		if pm.is_alive(slot) and not pm.has_flags(slot, ManagerScript.F_FIELD):
			out.append(slot)
	return out


func _cast_field(cards: Array) -> void:
	_arena.install_cards(0, 0, cards)
	check(_arena.cast(0, 0), "the field is cast")
	_arena.run(STEP)
	check_equal(_fields().field_count(), 1, "one field is open")


func test_the_card() -> void:
	check_equal(FIELD.carrier, &"field", "the card names the field carrier")
	var carrier: Carrier = Carriers.of(&"field")
	check(carrier.has(CarrierTraits.GIVES) and not carrier.hits() and not carrier.has(CarrierTraits.SPEED), "it gives, hits nothing and does not travel")
	for behaviour: int in [ModifierBase.Behaviour.HOMING, ModifierBase.Behaviour.LINGER, ModifierBase.Behaviour.BOUNCE, ModifierBase.Behaviour.GHOST, ModifierBase.Behaviour.SPIRAL, ModifierBase.Behaviour.RETURN, ModifierBase.Behaviour.STICKY, ModifierBase.Behaviour.SHIELD, ModifierBase.Behaviour.DEFLECT]:
		check(carrier.works(behaviour), "behaviour %d works on it (it gives it)" % behaviour)
	for behaviour: int in [ModifierBase.Behaviour.CHAIN, ModifierBase.Behaviour.HEAVY, ModifierBase.Behaviour.PULL]:
		check(not carrier.works(behaviour), "behaviour %d does nothing on it" % behaviour)


func test_a_field_lies_ahead_and_hits_nothing() -> void:
	_arena = ArenaScript.new(root)
	var imp: Node2D = _arena.add_imp(Vector2(FIELD.ray_length, 0.0))
	_cast_field(["fire", "field"])
	var slot: int = _fields().field_slot(0)
	var at: Vector2 = _arena.projectiles.get_position_of(slot)
	check(at.distance_to(Vector2(FIELD.ray_length, 0.0)) < 1.0, "it lies ray_length ahead (%s)" % at)
	check_equal(_arena.projectiles.get_radius_of(slot), FIELD.radius, "as big as its card")
	_arena.run(1.0)
	check_equal(_arena.lost(imp), 0, "the imp standing in it is not hurt")
	check(not _arena.was_given(imp, &"burn"), "nor set burning")


func test_a_shot_through_it_takes_its_infusion() -> void:
	_arena = ArenaScript.new(root)
	var imp: Node2D = _arena.add_imp(Vector2(200.0, 0.0))
	_cast_field(["fire", "field"])
	_arena.install_cards(0, 1, ["bolt"])
	check(_arena.cast(0, 1), "a plain bolt is fired through it")
	_arena.run(1.5)
	check(_arena.was_given(imp, &"burn"), "the imp beyond burns")


func test_a_shot_takes_it_once_and_again_when_it_comes_back() -> void:
	_arena = ArenaScript.new(root)
	_cast_field(["bounce", "bounce", "field"])
	var pm: ManagerScript = _arena.projectiles
	var centre: Vector2 = pm.get_position_of(_fields().field_slot(0))
	var shot: int = pm.spawn(0, centre - Vector2(60.0, 0.0), Vector2(200.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_ENEMY)
	var came_in: int = 0
	for step in 40:
		_arena.run(STEP)
		if pm.get_bounce_of(shot) > 0:
			came_in += 1
			pm.set_bounce(shot, 0)
	check_equal(came_in, 1, "it took the field once on its way through")
	# Back the other way: it comes in again.
	pm.pass_shot(shot, centre + Vector2(60.0, 0.0), Vector2.LEFT)
	pm._vel[shot] = Vector2(-200.0, 0.0)
	for step in 40:
		_arena.run(STEP)
		if pm.get_bounce_of(shot) > 0:
			came_in += 1
			pm.set_bounce(shot, 0)
	check_equal(came_in, 2, "and again when it came back into it")


func test_what_it_gives_is_at_least_its_own() -> void:
	_arena = ArenaScript.new(root)
	_cast_field(["bounce", "field"])
	var pm: ManagerScript = _arena.projectiles
	var centre: Vector2 = pm.get_position_of(_fields().field_slot(0))
	var shot: int = pm.spawn(0, centre - Vector2(60.0, 0.0), Vector2(200.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_ENEMY)
	pm.set_bounce(shot, 3)
	_arena.run(0.4)
	check_equal(pm.get_bounce_of(shot), 3, "a shot with more bounces than the field keeps its own")


func test_an_enemy_shot_takes_a_players_field() -> void:
	_arena = ArenaScript.new(root)
	var guard: Node2D = _arena.add_guard(0, Vector2.ZERO)
	_cast_field(["frost", "field"])
	_arena.shoot_at(Vector2(220.0, 0.0), Vector2.ZERO)
	_arena.run(2.0)
	check(_arena.was_given(guard, &"chill"), "the enemy's bolt took the frost and chilled the caster")


func test_the_dam_holds_shots_until_it_ends() -> void:
	_arena = ArenaScript.new(root)
	var imp: Node2D = _arena.add_imp(Vector2(200.0, 0.0))
	_cast_field(["linger", "field"])
	_arena.install_cards(0, 1, ["bolt"])
	check(_arena.cast(0, 1), "a bolt is fired into it")
	_arena.run(1.0)
	check_equal(_fields().held_count(), 1, "the field holds it")
	check_equal(_arena.lost(imp), 0, "it has not reached the imp")
	_arena.run(FIELD.lifetime)
	check_equal(_fields().field_count(), 0, "the field ended")
	check_equal(_fields().held_count(), 0, "and let it go")
	check(_arena.lost(imp) > 0, "it went on and hit the imp")


func test_a_dam_ended_early_lets_its_shots_go() -> void:
	_arena = ArenaScript.new(root)
	var imp: Node2D = _arena.add_imp(Vector2(200.0, 0.0))
	_cast_field(["linger", "field"])
	_arena.install_cards(0, 1, ["bolt"])
	check(_arena.cast(0, 1), "a bolt is fired into it")
	_arena.run(1.0)
	check_equal(_fields().held_count(), 1, "the field holds it")
	var tag: int = _arena.projectiles.get_tag_of(_fields().field_slot(0))
	_arena.projectiles.remove_by_tag(tag)
	_arena.run(1.0)
	check_equal(_fields().held_count(), 0, "the shots it held are let go")
	check(_arena.lost(imp) > 0, "and go on to hit the imp")


func test_its_own_shot_wears_none_of_its_cards_but_growth() -> void:
	_arena = ArenaScript.new(root)
	_cast_field(["shield", "deflect", "homing", "growth", "field"])
	var pm: ManagerScript = _arena.projectiles
	var slot: int = _fields().field_slot(0)
	check_equal(pm.get_shield_of(slot), 0, "it is no ward itself")
	check(not pm.is_deflecting(slot), "and turns no shot itself")
	check(not pm.is_homing(slot), "and does not creep")
	_arena.run(1.0)
	check(pm.get_radius_of(slot) > FIELD.radius, "growth widens it (%.1f)" % pm.get_radius_of(slot))


func test_its_own_payload_does_not_take_it() -> void:
	_arena = ArenaScript.new(root)
	_cast_field(["fire", "timer", "field", "bolt"])
	_arena.run(1.5)
	var pm: ManagerScript = _arena.projectiles
	var bolts: int = 0
	for slot in _shots():
		bolts += 1
		check_equal(pm.get_core_of(slot), Color.WHITE, "a bolt its timer fired from its middle is plain")
	check(bolts > 0, "its timer fired")


func test_a_field_cast_at_a_wall_opens_short_of_it() -> void:
	_arena = ArenaScript.new(root)
	_arena.add_wall(Rect2(40.0, -80.0, 8.0, 160.0))
	_cast_field(["field"])
	var at: Vector2 = _arena.projectiles.get_position_of(_fields().field_slot(0))
	check(at.x < 40.0, "it lies short of the wall (%s)" % at)
	_arena.run(0.5)
	check_equal(_fields().field_count(), 1, "and stays open")


func test_a_shot_that_goes_through_it_in_one_step_takes_it() -> void:
	_arena = ArenaScript.new(root)
	_cast_field(["bounce", "field"])
	var pm: ManagerScript = _arena.projectiles
	var centre: Vector2 = pm.get_position_of(_fields().field_slot(0))
	# Faster than the field is wide in a step: before it, then past it.
	var shot: int = pm.spawn(0, centre - Vector2(FIELD.radius + 10.0, 0.0), Vector2((FIELD.radius * 2.0 + 20.0) * 60.0, 0.0), 3.0, 1.0, ManagerScript.LAYER_ENEMY)
	_arena.run(STEP)
	check(pm.get_bounce_of(shot) > 0, "it took the field it went through")
