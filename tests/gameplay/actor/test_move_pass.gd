extends "res://tests/support/suite.gd"
## A dash's pass is as wide as its body (boss plan OB10, `CarrierDash._pass_reach`): a big body's
## dash strikes what the body meets, a wizard-sized one only what it passes close by (never under
## SpellLimits.PASS_REACH), `bigger` and the body's spell scale widen it, and a dash stopped by a
## wall head on strikes no more there once its move is over. Real actors (a Hurtbox each) and the
## real dash card, moved against the walls as the game moves them.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

const START: Vector2 = Vector2(0.0, 0.0)

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


## A dasher at `at` of hurt radius `radius`, its staff `cards`, aiming right.
func _dasher(at: Vector2, radius: float, cards: Array[StringName]) -> Actor:
	var controller := Fixture.Scripted.new()
	controller.team = ActorsScript.TEAM_WIZARDS
	controller.aim = Vector2.RIGHT
	var body: Actor = _world.actor(at, [&"health", &"hurtbox", &"mover", &"caster"], controller, [cards])
	# Registered again at its new size (a hurtbox registers its shape as it enters play).
	var hurtbox: Hurtbox = _hurtbox(body)
	hurtbox.set_enabled(false)
	hurtbox.radius = radius
	hurtbox.set_enabled(true)
	return body


func _hurtbox(body: Actor) -> Hurtbox:
	for child in body.get_children():
		if child is Hurtbox:
			return child as Hurtbox
	return null


## An enemy standing at `at` (hurt radius 8).
func _target(at: Vector2) -> Actor:
	return _world.actor(at, [&"health", &"hurtbox"], Fixture.Scripted.new())


func _hurt(body: Actor) -> bool:
	return body.health.health < body.health.max_health


func _walk(count: int) -> void:
	for i in count:
		for body in _world.actors:
			if is_instance_valid(body) and body.is_inside_tree():
				body.step(Fixture.STEP)
				body.move(Fixture.STEP)
		_world.projectiles.step(Fixture.STEP)
		_world.spells.step(Fixture.STEP)
		_world.combat.step(Fixture.STEP)


## The dasher's body centre's way runs along y = its centre's; a target `aside` px off it, 40 px ahead.
func _passes(radius: float, cards: Array[StringName], aside: float) -> bool:
	var dasher: Actor = _dasher(START, radius, cards)
	_walk(1)
	var centre: Vector2 = dasher.global_position + dasher.body_offset
	var target: Actor = _target(Vector2(0.0, 400.0))
	# The target's hurt circle sits at its feet + its offset: put that circle `aside` off the way.
	target.global_position = centre + Vector2(40.0, aside) - _hurtbox(target).offset
	check(dasher.caster.cast(0), "it dashes")
	_walk(30)
	var hurt: bool = _hurt(target)
	for body: Actor in [dasher, target]:
		_world.actors.erase(body)
		body.free()
	return hurt


func test_a_big_bodys_dash_strikes_what_the_body_meets() -> void:
	# A wizard's hurt circle is 8 px: its pass reaches 8 px, and a target's 8 px circle 16 px off its
	# way is out of reach; a body of 26 px reaches it.
	check(not _passes(8.0, [&"dash"], 22.0), "a wizard-sized dash passes a body 22 px aside")
	check(_passes(26.0, [&"dash"], 22.0), "a big body's dash strikes it")
	check(_passes(8.0, [&"dash"], 10.0), "a wizard-sized dash still strikes what it passes close by")


func test_a_tiny_bodys_pass_is_never_under_the_least() -> void:
	check(_passes(1.0, [&"dash"], 10.0), "a 1 px body still strikes within SpellLimits.PASS_REACH")


func test_bigger_widens_the_pass() -> void:
	# Bigger's radius (1.6x) on a 12 px body: 19 px, so a target's circle 25 px off is in reach.
	check(not _passes(12.0, [&"dash"], 25.0), "plain, a 12 px body passes it")
	check(_passes(12.0, [&"bigger", &"dash"], 25.0), "bigger, it strikes it")


func test_a_dash_stopped_at_a_wall_strikes_no_more_there() -> void:
	_world.projectiles.set_walls([Rect2(40.0, -200.0, 40.0, 400.0)] as Array[Rect2])
	# A slow dash: 80 px over about 0.9 s, the wall met after about 0.45 s.
	var dasher: Actor = _dasher(START, 8.0, [&"slow", &"dash"])
	_walk(1)
	check(dasher.caster.cast(0), "it dashes into the wall")
	_walk(9)
	check(not dasher.mover.is_dashing(), "the wall ended its move")
	# A body coming up to where it stopped, after the move and its grace but within the dash's time.
	var late: Actor = _target(dasher.global_position + Vector2(0.0, 6.0))
	_walk(4)
	check(not _hurt(late), "the stopped dash strikes nothing that comes by later")
