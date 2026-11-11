extends "res://tests/support/suite.gd"
## Still bodies (props W2, docs/milestones/props.md): a body that no controller drives and that has
## no Mover is still (`Actor.is_still`, `Actors.still`), and the Tick never steps it. It takes no
## hold or protection (its step would spend them); a slowed one's wind-ups are held back by Combat,
## not by its step. The state hash sums up a still body that is as it was made as a few values
## (`Actor.rest_leaf`). A stand-in prop is an actor with Health, a Hurtbox and a Caster.
##
## godot --headless --path . --script res://tests/gameplay/actor/test_actor_still.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


## A stand-in prop: one staff of `bolt`, its pool filling at `regen` a second, its cast winding up
## for `wind_up` seconds.
func _prop(at: Vector2 = Vector2.ZERO, regen: float = 5.0, wind_up: float = 0.0) -> Actor:
	var staff := StaffBase.new()
	staff.max_mana = 20.0
	staff.mana_regen = regen
	staff.wind_up = wind_up
	return _world.actor(at, [&"health", &"hurtbox", &"caster"], null, [[&"bolt"]], staff)


func test_a_body_with_no_controller_and_no_mover_is_still() -> void:
	var prop: Actor = _prop()
	check(prop.is_still(), "a prop is still")
	check(_world.table.is_still(prop.id), "and the table says so, for the Tick")
	var walker: Actor = _world.actor(Vector2(40.0, 0.0), [&"health", &"hurtbox", &"mover"])
	check(not _world.table.is_still(walker.id), "a Mover moves it")
	var driven: Actor = _world.actor(Vector2(80.0, 0.0), [&"health", &"hurtbox"], Fixture.Scripted.new())
	check(not _world.table.is_still(driven.id), "a controller thinks for it")


func test_a_driver_makes_it_stepped_and_leaving_makes_it_still_again() -> void:
	var prop: Actor = _prop()
	var driver := Fixture.Scripted.new()
	prop.drive(driver)
	check(not _world.table.is_still(prop.id), "possessed: stepped while it lasts")
	prop.drive(null)
	check(_world.table.is_still(prop.id), "still again when the driver goes")
	driver.free()


func test_a_still_body_takes_no_hold_and_no_protection() -> void:
	var prop: Actor = _prop()
	check(not _world.table.hold(prop.id, 0.5), "no hold: no step would spend it")
	check_equal(_world.table.held_count, 0, "nothing held")
	prop.health.protect(1.0)
	check(not prop.health.is_protected(), "no protection: no step would count it down")
	check(prop.health.take(5.0), "so a hit lands")


func test_a_hold_ends_when_its_body_becomes_still() -> void:
	var prop: Actor = _prop()
	var driver := Fixture.Scripted.new()
	prop.drive(driver)
	check(_world.table.hold(prop.id, 0.5), "held while driven")
	prop.drive(null)
	check_equal(_world.table.held_left(prop.id), 0.0, "the hold ends with the driver: no step would spend it")
	check_equal(_world.table.held_count, 0, "nothing held")
	driver.free()


func test_a_chilled_still_prop_winds_up_slower() -> void:
	var prop: Actor = _prop(Vector2.ZERO, 0.0, 1.0)
	var plain: Actor = _prop(Vector2(40.0, 0.0), 0.0, 1.0)
	check(_world.combat.apply_status(0, prop, &"chill", 30.0, 50.0), "chilled")
	check(prop.caster.cast(0) and plain.caster.cast(0), "both fuses lit")
	var number: int = prop.caster_number()
	var other: int = plain.caster_number()
	var before: float = _world.spells.cooldown_left(number, 0)
	check_equal(_world.spells.cooldown_left(other, 0), before, "lit alike")
	# Combat's step holds the chilled one's wind-up back; neither body is stepped.
	_world.combat.step(Fixture.STEP)
	check(_world.spells.cooldown_left(number, 0) > _world.spells.cooldown_left(other, 0), "the chilled fuse is held back by Combat")
	check(_world.spells.is_winding(number, 0), "and still winds")


func test_a_resting_body_hashes_as_its_rest_values_alone() -> void:
	var body: Actor = _prop()
	var leaves: Array[String] = []
	StateWalk.new().walk("body", body, func(path: String, _value: Variant) -> void: leaves.append(path))
	var rest: Array = body.rest_leaf()
	check_equal(leaves.size(), rest.size() + 1, "its rest values and their count, while at rest")
	check(leaves.all(func(path: String) -> bool: return path.begins_with("body.rest")), "nothing of its members")
	var other: Actor = _prop(Vector2(16.0, 0.0))
	check(SimHash.of(body) != SimHash.of(other), "two at rest apart hash apart")


func test_a_touched_body_is_walked_whole() -> void:
	var hit: Actor = _prop()
	check(hit.health.take(5.0), "the hit lands")
	check_equal(hit.rest_leaf(), null, "a hit one is no longer as made")
	var spent: Actor = _prop(Vector2(16.0, 0.0), 0.0)
	spent.caster.set_mana(0, 1.0)
	check_equal(spent.rest_leaf(), null, "a spent pool")
	var rebuilt: Actor = _prop(Vector2(32.0, 0.0))
	check(rebuilt.caster.set_staff(0, [&"bolt", &"bolt"] as Array[StringName]), "rebuilt")
	check_equal(rebuilt.rest_leaf(), null, "new cards")
	var driven: Actor = _world.actor(Vector2(48.0, 0.0), [&"health", &"hurtbox"], Fixture.Scripted.new())
	check_equal(driven.rest_leaf(), null, "a driven body")
	var leaves: Array[String] = []
	StateWalk.new().walk("body", hit, func(path: String, _value: Variant) -> void: leaves.append(path))
	check(leaves.size() > 10 and not leaves.has("body.rest"), "walked member by member")


func test_a_pool_whose_most_a_float32_cannot_hold_still_counts_as_full() -> void:
	var staff := StaffBase.new()
	staff.max_mana = 12.3
	staff.mana_regen = 4.0
	var body: Actor = _world.actor(Vector2.ZERO, [&"health", &"hurtbox", &"caster"], null, [[&"bolt"]], staff)
	check(body.rest_leaf() != null, "full at 12.3 (held as a float32 a little above it): as made")
