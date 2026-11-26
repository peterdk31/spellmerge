extends "res://tests/support/suite.gd"
## The field carrier (docs/milestones/field.md, the owner's design of 2026-11-26): a still circle that
## hits nothing and catches every shot that comes into it (anyone's, an enemy's too), draws it in and
## grows with it, then lets them all go at once when it ends, each the way it came in and with the
## field's cards; at most HOLD_MOST a field; Growth widening it; its own shot wearing none of the cards
## it gives; its own payloads not caught.
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


func test_its_own_payload_is_not_caught() -> void:
	_arena = ArenaScript.new(root)
	_cast_field(["fire", "timer", "field", "bolt"])
	_arena.run(1.5)
	check(not _shots().is_empty(), "its timer fired")
	check_equal(_fields().held_count(), 0, "the bolts born in its middle are not caught")


func test_a_field_cast_at_a_wall_opens_short_of_it() -> void:
	_arena = ArenaScript.new(root)
	_arena.add_wall(Rect2(40.0, -80.0, 8.0, 160.0))
	_cast_field(["field"])
	var at: Vector2 = _arena.projectiles.get_position_of(_fields().field_slot(0))
	check(at.x < 40.0, "it lies short of the wall (%s)" % at)
	_arena.run(0.5)
	check_equal(_fields().field_count(), 1, "and stays open")


## A field hits nothing and meets nothing: an enemy's shot that takes its shield or deflect does not
## stop or turn the field itself (it would end it, or make it the enemy's).
func test_an_enemy_shot_given_its_guard_leaves_the_field_be() -> void:
	for guard: StringName in [&"shield", &"deflect"]:
		_arena = ArenaScript.new(root)
		_cast_field([guard, "field"])
		var pm: ManagerScript = _arena.projectiles
		var slot: int = _fields().field_slot(0)
		var seq: int = pm.get_seq_of(slot)
		var actor: int = pm.get_actor_of(slot)
		for n in 3:
			_arena.shoot_at(Vector2(220.0, -10.0 + 10.0 * n), Vector2.ZERO)
		_arena.run(1.5)
		check(pm.is_alive(slot) and pm.get_seq_of(slot) == seq, "%s: the field is still there" % guard)
		check_equal(pm.get_actor_of(slot), actor, "%s: and still its caster's" % guard)
		check_equal(_fields().field_count(), 1, "%s: one field open" % guard)
		_arena.free_all()
		_arena = null




## Fires a plain bolt from the caster along +x, through a field ahead.
func _bolt(staff: int = 1) -> void:
	_arena.install_cards(0, staff, ["bolt"])
	check(_arena.cast(0, staff), "a bolt is fired into it")


func test_a_shot_is_caught_drawn_in_and_the_field_grows() -> void:
	_arena = ArenaScript.new(root)
	var imp: Node2D = _arena.add_imp(Vector2(200.0, 0.0))
	_cast_field(["field"])
	var pm: ManagerScript = _arena.projectiles
	var slot: int = _fields().field_slot(0)
	var centre: Vector2 = pm.get_position_of(slot)
	_bolt()
	_arena.run(1.0)
	check_equal(_fields().held_count(), 1, "the field holds the bolt")
	var held: Array[int] = _shots()
	check_equal(held.size(), 1, "one bolt alive")
	check(pm.get_position_of(held[0]).distance_to(centre) < 1.0, "drawn in to its middle (%s)" % pm.get_position_of(held[0]))
	check(pm.get_radius_of(slot) > FIELD.radius, "the field grew (%.1f)" % pm.get_radius_of(slot))
	check_equal(_arena.lost(imp), 0, "the imp beyond is not hit while it holds the bolt")


func test_it_bursts_when_it_ends_each_shot_the_way_it_came_with_its_cards() -> void:
	_arena = ArenaScript.new(root)
	var imp: Node2D = _arena.add_imp(Vector2(200.0, 0.0))
	_cast_field(["fire", "field"])
	_bolt()
	_arena.run(FIELD.lifetime - 0.2)
	check_equal(_arena.lost(imp), 0, "nothing reaches the imp while the field lasts")
	_arena.run(1.5)
	check_equal(_fields().field_count(), 0, "the field ended")
	check_equal(_fields().held_count(), 0, "and let the bolt go")
	check(_arena.was_given(imp, &"burn"), "the bolt went on the way it came in, burning, and hit the imp beyond")


func test_a_field_switched_off_early_bursts_then() -> void:
	_arena = ArenaScript.new(root)
	var imp: Node2D = _arena.add_imp(Vector2(200.0, 0.0))
	_cast_field(["field"])
	_bolt()
	_arena.run(1.0)
	_arena.projectiles.remove_by_tag(_arena.projectiles.get_tag_of(_fields().field_slot(0)))
	_arena.run(1.0)
	check_equal(_fields().held_count(), 0, "the shots it held are let go")
	check(_arena.lost(imp) > 0, "and go on to hit the imp")


func test_an_enemy_shot_is_caught_and_sent_on_with_the_players_cards() -> void:
	_arena = ArenaScript.new(root)
	var guard: Node2D = _arena.add_guard(0, Vector2.ZERO)
	_cast_field(["frost", "field"])
	_arena.shoot_at(Vector2(220.0, 0.0), Vector2.ZERO)
	_arena.run(1.0)
	check_equal(_fields().held_count(), 1, "the enemy's bolt is caught")
	_arena.run(FIELD.lifetime + 1.0)
	check(_arena.was_given(guard, &"chill"), "it went on at the caster, frost, and chilled them")


func test_a_shot_keeps_more_of_a_card_than_the_field_gives() -> void:
	_arena = ArenaScript.new(root)
	_cast_field(["bounce", "ghost", "field"])
	var pm: ManagerScript = _arena.projectiles
	var centre: Vector2 = pm.get_position_of(_fields().field_slot(0))
	var shot: int = pm.spawn(0, centre - Vector2(60.0, 0.0), Vector2(200.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_ENEMY)
	pm.set_bounce(shot, 30)
	_arena.run(0.5)
	check_equal(_fields().held_count(), 1, "caught")
	_arena.run(FIELD.lifetime)
	check(pm.has_flags(shot, ManagerScript.F_GHOST), "it left with the field's ghost")
	check_equal(pm.get_bounce_of(shot), 30, "and kept its own bounces, more than the field's")


func test_a_shot_that_goes_through_it_in_one_step_is_caught() -> void:
	_arena = ArenaScript.new(root)
	_cast_field(["field"])
	var pm: ManagerScript = _arena.projectiles
	var centre: Vector2 = pm.get_position_of(_fields().field_slot(0))
	# Faster than the field is wide in a step: before it, then past it.
	pm.spawn(0, centre - Vector2(FIELD.radius + 10.0, 0.0), Vector2((FIELD.radius * 2.0 + 20.0) * 60.0, 0.0), 3.0, 1.0, ManagerScript.LAYER_ENEMY)
	_arena.run(STEP)
	check_equal(_fields().held_count(), 1, "it caught the shot that went through it")


func test_a_field_holds_at_most_its_cap() -> void:
	_arena = ArenaScript.new(root)
	_cast_field(["field"])
	var pm: ManagerScript = _arena.projectiles
	var centre: Vector2 = pm.get_position_of(_fields().field_slot(0))
	for n in CarrierField.HOLD_MOST + 10:
		pm.spawn(0, centre - Vector2(FIELD.radius + 5.0, 0.0), Vector2(300.0, 0.0), 3.0, 1.0, ManagerScript.LAYER_ENEMY)
	_arena.run(0.3)
	check_equal(_fields().held_count(), CarrierField.HOLD_MOST, "it holds its cap and lets the rest through")
	check(pm.get_radius_of(_fields().field_slot(0)) <= FIELD.radius * CarrierField.GROW_MOST + 0.01, "and grows no more than its most")
