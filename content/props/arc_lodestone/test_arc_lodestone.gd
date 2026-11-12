extends "res://tests/support/suite.gd"
## The arc lodestone (props W9c, content/props/arc_lodestone): a dark standing stone with lime veins
## that nothing hurts. A lightning hit charges it: it winds up half a second (its staff's wind-up,
## the charge), then casts Lightning · Pulse round itself and is idle again. Its pool never refills
## (a still body is never stepped), so it zaps its pool's worth, ZAPS, and then goes dark (`spent`)
## for good (owner, 2026-11-12: a `refused` row, `dry`). A charge while its staff is still in the
## delay after its last zap is refused too, and it is simply idle again.
##
## godot --headless --path . --script res://content/props/arc_lodestone/test_arc_lodestone.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const PropNames := preload("res://tests/content/props/prop_names.gd")
const LODESTONE: PropBase = preload("res://content/props/arc_lodestone/arc_lodestone.tres")

## Zaps its pool pays.
const ZAPS: int = 20
## Steps of its charge (0.5 s) and of its ring after (0.4 s), and a few more.
const ZAP_STEPS: int = 18

var _world: Fixture
## The casts that left, by caster number.
var _left: Array[int] = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)
	_left.clear()
	_world.bus.cast_left.connect(func(caster: int, _staff: int) -> void: _left.append(caster))


func after_each() -> void:
	_world.free_all()


## The zaps `stone` cast.
func _zaps(stone: Actor) -> int:
	return _left.count(stone.caster_number())


func _stone() -> Actor:
	return _world.add(PropBody.make(LODESTONE), Vector2(200, 200))


## A dummy that only stands and is hurt, `x` px right of the stone.
func _dummy(x: float) -> Actor:
	var body: Actor = _world.actor(Vector2(200.0 + x, 200.0), [&"health", &"hurtbox"], Fixture.Scripted.new())
	body.health.max_health = 1000.0
	body.health.reset(1000.0)
	return body


func test_it_is_sound() -> void:
	check_equal(LODESTONE.problems(PropNames.known(_world.registry)), PackedStringArray(), "its data")
	check_equal(LODESTONE.look_problems(), PackedStringArray(), "its looks")


func test_lightning_charges_it_and_it_zaps_what_is_near() -> void:
	var stone: Actor = _stone()
	var near: Actor = _dummy(24.0)
	check(stone.footprint.solid and stone.health.invincible, "it stands in the way, and nothing hurts it")
	check_equal(_world.shoot(stone, &"fire").slice(0, 1), [&"fire"] as Array[StringName], "a fire hit lands")
	check_equal(stone.state_triggers.state_id(), &"idle", "and does nothing")
	check_equal(_world.shoot(stone, &"lightning").slice(0, 1), [&"lightning"] as Array[StringName], "a lightning hit lands")
	check_equal(stone.state_triggers.state_id(), &"charged", "and charges it")
	check(stone.caster.is_winding(0), "its charge winds up")
	_world.run(ZAP_STEPS)
	check_equal(_zaps(stone), 1, "it zapped once")
	check_equal(stone.state_triggers.state_id(), &"idle", "and is idle again")
	check(near.health.health < near.health.max_health, "its pulse hurt what stood near")


func test_charged_while_its_staff_is_in_its_delay_it_is_idle_again() -> void:
	var stone: Actor = _stone()
	check(stone.state_triggers.enter(&"charged"), "charged")
	_world.run(8)
	check_equal(_zaps(stone), 1, "zapped")
	check(stone.state_triggers.enter(&"charged"), "charged again at once, its staff still in its delay")
	check_equal(stone.state_triggers.state_id(), &"idle", "refused, it is idle again, not dark")
	check_equal(_zaps(stone), 1, "with no zap")


func test_it_zaps_its_pools_worth_then_goes_dark() -> void:
	var stone: Actor = _stone()
	var cost: float = stone.caster.next_cast_mana(0)
	check(cost > 0.0, "a zap costs mana (%s)" % cost)
	check_equal(floori(stone.caster.max_mana_of(0) / cost + 0.001), ZAPS, "its pool pays %d zaps" % ZAPS)
	for i in ZAPS:
		check(stone.state_triggers.enter(&"charged"), "charged %d" % i)
		_world.run(ZAP_STEPS)
	check_equal(_zaps(stone), ZAPS, "%d zaps" % ZAPS)
	check_equal(stone.state_triggers.state_id(), &"idle", "idle after the last")
	check_equal(_world.shoot(stone, &"lightning").slice(0, 1), [&"lightning"] as Array[StringName], "another lightning hit")
	check_equal(stone.state_triggers.state_id(), &"spent", "its pool pays no more: it goes dark")
	check_equal(_zaps(stone), ZAPS, "with no zap")
	_world.shoot(stone, &"lightning")
	check_equal(stone.state_triggers.state_id(), &"spent", "and stays dark")


func _areas() -> Dictionary:
	var areas: Dictionary = {"Actors": _world.table, "Projectiles": _world.projectiles, "Spells": _world.spells, "Combat": _world.combat}
	for body in _world.actors:
		if is_instance_valid(body) and body.is_inside_tree() and body.id != ActorsScript.NONE:
			areas["actor %d" % body.id] = body
	return areas


func test_a_snapshot_while_it_charges_zaps_again() -> void:
	var stone: Actor = _stone()
	check(stone.state_triggers.enter(&"charged"), "charged")
	var snapshot := Snapshot.take(_areas(), root)
	check_equal(snapshot.problems, PackedStringArray(), "taken without problems")
	_world.run(ZAP_STEPS)
	check_equal(_zaps(stone), 1, "zapped")
	check_equal(snapshot.restore(_areas(), root, _world.prepare), PackedStringArray(), "restored without problems")
	check_equal(stone.state_triggers.state_id(), &"charged", "charged again")
	check(stone.caster.is_winding(0), "its charge winds up again")
	_world.run(ZAP_STEPS)
	check_equal(_zaps(stone), 2, "and it zaps as it did")
	check_equal(stone.state_triggers.state_id(), &"idle", "idle")
