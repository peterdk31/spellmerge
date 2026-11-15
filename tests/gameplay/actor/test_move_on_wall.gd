extends "res://tests/support/suite.gd"
## `on wall` for moves (boss plan OB12): a dash's `on wall` fires where a wall ends it head on (its
## Mover's `held_up`, OB10), and where a body its Plow carries is pinned (OB11), from the dash's end
## point; a dash that glances off a wall, or meets none, fires nothing; a teleport (over at once)
## wastes the card. Real actors (a Mover each) and the real cards, moved against the walls as the game
## moves them: `on_wall · dash · pulse` is a wall bounce that bursts.
##
## godot --headless --path . --script res://tests/gameplay/actor/test_move_on_wall.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

var _world: Fixture
## Where each pulse was shown going off.
var _pulses: Array[Vector2] = []


func before_each() -> void:
	_world = Fixture.new(root)
	_pulses.clear()
	_world.bus.carrier_shown.connect(func(_caster: int, card: StringName, origin: Vector2, _direction: Vector2, _length: float, _tint: Color, _look: int) -> void:
		if card == &"pulse":
			_pulses.append(origin))


func after_each() -> void:
	_world.free_all()


## A wizard at `at` aiming along `aim`, its staff `cards`.
func _dasher(at: Vector2, cards: Array[StringName], aim: Vector2 = Vector2.RIGHT) -> Actor:
	var controller := Fixture.Scripted.new()
	controller.team = ActorsScript.TEAM_WIZARDS
	controller.aim = aim
	return _world.actor(at, [&"health", &"hurtbox", &"mover", &"caster"], controller, [cards])


## An enemy at `at` that can be moved (a Mover).
func _target(at: Vector2) -> Actor:
	return _world.actor(at, [&"health", &"hurtbox", &"mover"], Fixture.Scripted.new())


func _walk(count: int) -> void:
	for i in count:
		for body in _world.actors:
			if is_instance_valid(body) and body.is_inside_tree():
				body.step(Fixture.STEP)
				body.move(Fixture.STEP)
		_world.projectiles.step(Fixture.STEP)
		_world.spells.step(Fixture.STEP)
		_world.combat.step(Fixture.STEP)


func test_a_dash_into_a_wall_head_on_fires_its_on_wall_there() -> void:
	_world.projectiles.set_walls([Rect2(50.0, -200.0, 40.0, 400.0)] as Array[Rect2])
	var dasher: Actor = _dasher(Vector2.ZERO, [&"on_wall", &"dash", &"pulse"])
	_walk(1)
	check(dasher.caster.cast(0), "it dashes at the wall")
	_walk(40)
	check_equal(_pulses.size(), 1, "its payload went off once: %s" % [_pulses])
	check(_pulses.size() == 1 and _pulses[0].x > 30.0 and _pulses[0].x <= 50.0, "where the wall stopped it: %s" % [_pulses])
	check(_pulses.size() == 1 and _pulses[0].distance_to(dasher.global_position) < 1.0, "round the dasher, which cast it: %s, %s" % [_pulses, dasher.global_position])


func test_a_dash_in_the_open_fires_no_on_wall() -> void:
	var dasher: Actor = _dasher(Vector2.ZERO, [&"on_wall", &"dash", &"pulse"])
	_walk(1)
	check(dasher.caster.cast(0), "it dashes")
	_walk(40)
	check(dasher.global_position.x > 70.0, "its whole way (%s)" % dasher.global_position)
	check(_pulses.is_empty(), "no wall, no payload: %s" % [_pulses])


func test_a_dash_glancing_off_a_wall_fires_no_on_wall() -> void:
	# 60 degrees off straight into the wall: it slides along it and ends when its time is up.
	_world.projectiles.set_walls([Rect2(20.0, -400.0, 40.0, 800.0)] as Array[Rect2])
	var dasher: Actor = _dasher(Vector2.ZERO, [&"on_wall", &"dash", &"pulse"], Vector2.from_angle(deg_to_rad(60.0)))
	_walk(1)
	check(dasher.caster.cast(0), "it dashes")
	_walk(40)
	check(dasher.global_position.y > 40.0, "it slid along the wall (%s)" % dasher.global_position)
	check(_pulses.is_empty(), "a glancing wall ends nothing: %s" % [_pulses])


func test_a_pinned_carried_body_fires_the_carriers_on_wall() -> void:
	# The broom's Sweep (boss plan OB12): what it carries pinned against the wall ends its dash there,
	# and its ring goes off round it, beside the pinned body.
	_world.projectiles.set_walls([Rect2(60.0, -200.0, 40.0, 400.0)] as Array[Rect2])
	var dasher: Actor = _dasher(Vector2.ZERO, [&"on_wall", &"plow", &"dash", &"pulse"])
	var target: Actor = _target(Vector2(30.0, 0.0))
	var pinned: Array[bool] = []
	_world.bus.carry_ended.connect(func(_caster: int, _body: Node, _carrier: int, _way: Vector2, was_pinned: bool, _tag: int) -> void:
		pinned.append(was_pinned))
	_walk(1)
	check(dasher.caster.cast(0), "it dashes at the wall")
	_walk(40)
	check_equal(pinned, [true] as Array[bool], "the carry ended pinned")
	check_equal(_pulses.size(), 1, "its payload went off once: %s" % [_pulses])
	check(_pulses.size() == 1 and _pulses[0].distance_to(dasher.global_position) < 1.0, "round the dasher, which cast it: %s, %s" % [_pulses, dasher.global_position])
	check(_pulses.size() == 1 and _pulses[0].distance_to(target.global_position) <= 30.0, "beside the pinned body: %s, %s" % [_pulses, target.global_position])


func test_a_pin_in_the_open_counts_as_the_wall() -> void:
	# A carried body held up head on is a wall met, wherever it is held (a prop's ground, a stone).
	var dasher: Actor = _dasher(Vector2.ZERO, [&"on_wall", &"plow", &"dash", &"pulse"])
	var target: Actor = _target(Vector2(20.0, 0.0))
	_walk(1)
	check(dasher.caster.cast(0), "it dashes")
	var steps: int = 0
	while _world.spells.plow().carried_count() == 0 and steps < 30:
		_walk(1)
		steps += 1
	check(_world.spells.plow().carrying(target.id, _world.tag_of(dasher)), "it carries the body")
	_world.spells.plow().pinned(target.id)
	_walk(30)
	check_equal(_pulses.size(), 1, "the pin fired its `on wall`: %s" % [_pulses])


func test_on_wall_works_on_a_dash_and_is_wasted_on_a_teleport() -> void:
	var dash: Dictionary = _world.spells.staff_view([&"on_wall", &"dash", &"pulse"] as Array[StringName], null)
	check_equal(dash.get("wasted"), {}, "a dash takes it: %s" % [dash.get("wasted")])
	var teleport: Dictionary = _world.spells.staff_view([&"on_wall", &"teleport", &"pulse"] as Array[StringName], null)
	check((teleport.get("wasted", {}) as Dictionary).has(0), "a teleport, over at once, wastes it: %s" % [teleport.get("wasted")])
	check(Carriers.of(&"dash").fires(TriggerBase.Event.WALL), "the needs row: a move along a way")
	check(not Carriers.of(&"teleport").fires(TriggerBase.Event.WALL), "not a teleport")
	check(Carriers.of(&"atom").fires(TriggerBase.Event.WALL) and Carriers.of(&"beam").fires(TriggerBase.Event.WALL), "a flying shot and a beam as before")
