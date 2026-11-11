extends "res://tests/support/suite.gd"
## Dormant and resting bodies (props W2, docs/milestones/props.md): a body whose tick would change
## nothing is not stepped (`Actor.dormant`, `tick_step`), and the state hash sums one that is also
## as it was made up as one leaf (`Actor.rest_leaf`). The rule's own check: whenever a body says it
## is dormant, a step and a move change nothing of it or of the systems. A stand-in prop is an actor
## with Health, a Hurtbox and a Caster, no controller and no Mover.
##
## godot --headless --path . --script res://tests/gameplay/actor/test_actor_dormant.gd

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


## Everything a step could change: the body's own state (its components walked one by one, so a
## resting body is not summed up), and each system's hash.
func _state(body: Actor) -> Dictionary:
	var out: Dictionary = {}
	var sink := func(path: String, value: Variant) -> void: out[path] = value
	var walk := StateWalk.new()
	for part: Object in [body.caster, body.health, body.hurtbox, body.intent]:
		walk.walk(str(part), part, sink)
	out["body"] = [body.position, body.velocity, body.aim, body.get(&"_hold_shown")]
	for system: Object in [_world.table, _world.spells, _world.projectiles, _world.combat]:
		out[str(system)] = SimHash.of(system)
	return out


## A step and a move of `body`, outside the tick.
func _force_step(body: Actor) -> void:
	body.step(Fixture.STEP)
	body.move(Fixture.STEP)


func test_a_standing_prop_is_dormant_and_its_step_changes_nothing() -> void:
	var body: Actor = _prop()
	check(body.dormant(), "a stand-in with nothing to do is dormant from the start")
	var before: Dictionary = _state(body)
	_force_step(body)
	check_equal(_state(body), before, "a step of a dormant body changes nothing")


func test_a_hit_prop_stays_dormant_and_its_step_still_changes_nothing() -> void:
	var body: Actor = _prop()
	check(body.health.take(10.0), "the hit lands")
	check(body.dormant(), "a hit leaves it nothing to do")
	var before: Dictionary = _state(body)
	_force_step(body)
	check_equal(_state(body), before, "a step changes nothing")


func test_what_keeps_a_body_awake() -> void:
	var body: Actor = _prop()
	body.health.protect(0.25)
	check(not body.dormant(), "a protection counting down")
	for i in 8:
		body.tick_step(Fixture.STEP)
	check(body.dormant(), "dormant again once it has run out")

	body.caster.set_mana(0, 10.0)
	check(not body.dormant(), "a pool filling")
	for i in 80:
		body.tick_step(Fixture.STEP)
	check_equal(body.caster.mana_of(0), 20.0, "the tick fills it")
	check(body.dormant(), "dormant again once it is full")

	check(_world.table.hold(body.id, 0.25), "held")
	check(not body.dormant(), "a local stop to spend")
	for i in 8:
		body.tick_step(Fixture.STEP)
	check(body.dormant(), "dormant again once it is spent")

	body.position += Vector2(4.0, 0.0)
	check(not body.dormant(), "a place not yet sent to the systems")
	body.tick_step(Fixture.STEP)
	check(body.dormant(), "dormant again once it is sent")

	body.intent.move = Vector2.RIGHT
	check(not body.dormant(), "an intent to clear")
	body.tick_step(Fixture.STEP)
	check(body.dormant(), "dormant again once it is cleared")


func test_an_empty_pool_that_never_fills_does_not_keep_it_awake() -> void:
	var body: Actor = _prop(Vector2.ZERO, 0.0)
	body.caster.set_mana(0, 5.0)
	check(body.dormant(), "a pool that does not fill leaves nothing to do")
	var before: Dictionary = _state(body)
	_force_step(body)
	check_equal(_state(body), before, "a step changes nothing")


func test_a_winding_cast_keeps_it_awake() -> void:
	var body: Actor = _prop(Vector2.ZERO, 5.0, 1.0)
	check(body.caster.cast(0), "the fuse is lit")
	check(_world.spells.is_winding(body.caster_number(), 0), "it winds up")
	check(not body.dormant(), "a winding cast (a chill would hold it back each step)")


func test_a_controller_or_a_mover_keeps_it_awake() -> void:
	var driven: Actor = _world.actor(Vector2.ZERO, [&"health", &"hurtbox"], Fixture.Scripted.new())
	check(not driven.dormant(), "a controller thinks every step")
	var walker: Actor = _world.actor(Vector2(40.0, 0.0), [&"health", &"hurtbox", &"mover"])
	check(not walker.dormant(), "a Mover moves it")


func test_a_body_without_a_mover_never_moves() -> void:
	var body: Actor = _prop()
	body.velocity = Vector2(30.0, 0.0)
	body.move(Fixture.STEP)
	check_equal(body.position, Vector2.ZERO, "no Mover, no move")


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


func test_a_dormant_tick_puts_it_to_sleep_and_each_change_wakes_it() -> void:
	var body: Actor = _prop()
	var asleep := func() -> bool: return _world.table.asleep[body.id] != 0
	var nap := func() -> void:
		body.tick_step(Fixture.STEP)
		check(asleep.call(), "a tick that leaves it dormant puts it to sleep")
	nap.call()
	body.health.protect(0.1)
	check(not asleep.call(), "a protection wakes it")
	for i in 4:
		body.tick_step(Fixture.STEP)
	check(asleep.call(), "asleep again once the protection ran out")
	body.caster.set_mana(0, 1.0)
	check(not asleep.call(), "a mana change wakes it")
	for i in 80:
		body.tick_step(Fixture.STEP)
	check(asleep.call(), "asleep again once full")
	check(_world.table.hold(body.id, 0.1), "held")
	check(not asleep.call(), "a hold wakes it")
	for i in 4:
		body.tick_step(Fixture.STEP)
	check(asleep.call(), "asleep again once the hold is spent")
	body.position = Vector2(8.0, 0.0)
	check(not asleep.call(), "a move of the body wakes it")
	nap.call()
	check(body.caster.cast(0), "a cast")
	check(not asleep.call(), "a cast wakes it")
	for i in 80:
		body.tick_step(Fixture.STEP)
		_world.spells.step(Fixture.STEP)
	check(asleep.call(), "asleep again once the pool is full")
	body.set_down(true)
	check(not asleep.call(), "going down wakes it")
	body.set_down(false)
	nap.call()
	var driver := Fixture.Scripted.new()
	body.drive(driver)
	check(not asleep.call(), "a driver wakes it")
	body.tick_step(Fixture.STEP)
	check(not asleep.call(), "and it stays awake while driven")
	body.drive(null)
	driver.free()


func test_a_restored_snapshot_wakes_every_body() -> void:
	var body: Actor = _prop()
	body.tick_step(Fixture.STEP)
	check(_world.table.asleep[body.id] != 0, "asleep after a dormant tick")
	_world.table.rebuild_derived()
	check_equal(_world.table.asleep[body.id], 0, "awake after a restore (the body under the id may be another)")


func test_a_pool_whose_most_a_float32_cannot_hold_still_counts_as_full() -> void:
	var staff := StaffBase.new()
	staff.max_mana = 12.3
	staff.mana_regen = 4.0
	var body: Actor = _world.actor(Vector2.ZERO, [&"health", &"hurtbox", &"caster"], null, [[&"bolt"]], staff)
	check(body.dormant(), "full at 12.3 (held as a float32 a little below it): nothing to fill")
	check(body.rest_leaf() != null, "and as made")
	var before: Dictionary = _state(body)
	_force_step(body)
	check_equal(_state(body), before, "a step changes nothing")
