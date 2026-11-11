extends "res://tests/support/suite.gd"
## A body hit as a box (props, docs/milestones/props.md: "box hurt shapes"): a `Hurtbox` with a
## `size` is a box to every hit test (`HitShape`), so a long body (a bench, a big boss) is hit where
## it is drawn and not past it, its touch reaches as far as its box, and the footprint the actor adds
## under it is the box's base. `set_size` scales the box with the body.
##
## godot --headless --path . --script res://tests/gameplay/actor/test_hurt_box.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")

## The bench: a box 80 by 16 whose bottom edge is at its feet.
const BENCH_SIZE: Vector2 = Vector2(80.0, 16.0)
const BENCH_CENTRE: Vector2 = Vector2(0.0, -8.0)

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


## A bench of the world's team at `at`: Health and a box hurt shape, no controller, no Mover, and
## no footprint of its own unless `footprint`.
func _bench(at: Vector2, footprint: Footprint = null) -> Actor:
	var body := Actor.new()
	body.name = "Bench"
	body.idle_team = ActorsScript.TEAM_WORLD
	body.body_offset = BENCH_CENTRE
	body.hand_offset = BENCH_CENTRE
	var health := Health.new()
	health.max_health = 50
	body.add_child(health)
	var hurtbox := Hurtbox.new()
	hurtbox.size = BENCH_SIZE
	hurtbox.offset = BENCH_CENTRE
	body.add_child(hurtbox)
	if footprint != null:
		body.add_child(footprint)
	return _world.add(body, at)


## A body of `team` with Health and a hurt circle, driven by a scripted controller that aims
## `aim`, with `cards` (none: no Caster).
func _body(at: Vector2, team: int, aim: Vector2 = Vector2.RIGHT, cards: Array = []) -> Actor:
	var brain := Fixture.Scripted.new()
	brain.team = team
	brain.aim = aim
	var kinds: Array[StringName] = [&"health", &"hurtbox"]
	if not cards.is_empty():
		kinds.append(&"caster")
	return _world.actor(at, kinds, brain, cards)


## The projectile manager's row of `body`'s target.
func _row(body: Actor) -> int:
	return _world.projectiles._target_row(body)


func test_a_box_hurtbox_is_a_box_target() -> void:
	var bench: Actor = _bench(Vector2(100.0, 0.0))
	check(bench.hurtbox.is_box(), "a hurtbox with a size is a box")
	var row: int = _row(bench)
	check(row >= 0, "registered as a target")
	if row >= 0:
		check_equal(_world.projectiles._target_half[row], BENCH_SIZE * 0.5, "half its size either way")
		check_equal(_world.projectiles._target_radius[row], 0.0, "with square corners")
	check(is_equal_approx(bench.hurtbox.outer_radius(), (BENCH_SIZE * 0.5).length()), "it reaches to its corner")
	var circle: Actor = _body(Vector2(300.0, 0.0), ActorsScript.TEAM_ENEMIES)
	check(not circle.hurtbox.is_box() and circle.hurtbox.outer_radius() == circle.hurtbox.radius, "a hurtbox without a size is its circle")
	check_equal(_world.projectiles._target_half[_row(circle)], Vector2.ZERO, "a target of no box")


func test_the_footprint_the_actor_adds_is_the_box_s_base() -> void:
	var bench: Actor = _bench(Vector2(100.0, 0.0))
	check_equal(bench.footprint.size, Vector2(80.0, 8.0), "as wide as the box, half as deep")
	check_equal(_world.projectiles.footprint_of(bench.id), Rect2(60.0, -8.0, 80.0, 8.0), "its bottom edge on the box's, at the feet")
	var own := Footprint.new()
	own.radius = 5.0
	var kept: Actor = _bench(Vector2(300.0, 0.0), own)
	check(kept.footprint == own and own.size == Vector2.ZERO, "a scene's own footprint is kept as it is")


func test_set_size_scales_the_box() -> void:
	var bench: Actor = _bench(Vector2(100.0, 0.0))
	bench.set_size(2.0)
	check_equal(bench.hurtbox.size, BENCH_SIZE * 2.0, "the box twice as big")
	check_equal(_world.projectiles._target_half[_row(bench)], BENCH_SIZE, "registered again so")


func test_a_bolt_hits_the_box_at_its_end_and_passes_beside_it() -> void:
	var bench: Actor = _bench(Vector2(100.0, 0.0))
	var below: Actor = _body(Vector2(135.0, 60.0), ActorsScript.TEAM_ENEMIES)
	var shooter: Actor = _body(Vector2(135.0, -100.0), ActorsScript.TEAM_WIZARDS, Vector2.DOWN, [[&"bolt"]])
	_world.run(1)
	check(shooter.caster.cast(0), "cast")
	_world.run(30)
	check(bench.health.health < bench.health.max_health, "a bolt down onto the bench's end, 35 off its centre, hurts it")
	check_equal(below.health.health, below.health.max_health, "and ends there")
	var past: Actor = _bench(Vector2(100.0, 200.0))
	var after: Actor = _body(Vector2(150.0, 260.0), ActorsScript.TEAM_ENEMIES)
	var second: Actor = _body(Vector2(150.0, 100.0), ActorsScript.TEAM_WIZARDS, Vector2.DOWN, [[&"bolt"]])
	_world.run(1)
	check(second.caster.cast(0), "cast again")
	_world.run(40)
	check_equal(past.health.health, past.health.max_health, "one 10 past a bench's end passes it")
	check(after.health.health < after.health.max_health, "and hits the body below")


## A toucher of the enemies' team hit as a box 60 wide (a big boss), with a touch of 5.
func _boss(at: Vector2) -> Actor:
	var boss := Actor.new()
	boss.add_child(Health.new())
	var hurtbox := Hurtbox.new()
	hurtbox.size = Vector2(60.0, 20.0)
	boss.add_child(hurtbox)
	var contact := Contact.new()
	contact.damage = 5
	boss.add_child(contact)
	boss.add_child(Fixture.Scripted.new())
	return _world.add(boss, at)


func test_a_box_touches_as_far_as_its_box() -> void:
	_boss(Vector2.ZERO)
	var at_end: Actor = _body(Vector2(36.0, 0.0), ActorsScript.TEAM_WIZARDS)
	# Within its corners' circle, but 12 off its long edge: no touch.
	var off_edge: Actor = _body(Vector2(-25.0, 22.0), ActorsScript.TEAM_WIZARDS)
	_world.run(4)
	check(at_end.health.health < at_end.health.max_health, "a wizard at the box's end, 36 off its centre, is touched")
	check_equal(off_edge.health.health, off_edge.health.max_health, "one off its long edge is not")


func test_a_crowd_is_touched_by_its_shapes_too() -> void:
	# More victims than Combat checks directly: each asks the grid (a box round its corners, each
	# toucher found checked against the box).
	for n in CombatScript.CONTACT_DIRECT:
		_body(Vector2(-300.0 + float(n) * 30.0, 300.0), ActorsScript.TEAM_WIZARDS)
	var touched: Actor = _wide_wizard(Vector2.ZERO)
	var spared: Actor = _wide_wizard(Vector2(300.0, 0.0))
	_toucher(Vector2(36.0, 0.0))
	_toucher(Vector2(325.0, 22.0))
	_world.run(4)
	check(touched.health.health < touched.health.max_health, "a toucher at a box victim's end touches it")
	check_equal(spared.health.health, spared.health.max_health, "one within its corners' circle but off its edge does not")


## A wizard hit as a box 60 by 20.
func _wide_wizard(at: Vector2) -> Actor:
	var brain := Fixture.Scripted.new()
	brain.team = ActorsScript.TEAM_WIZARDS
	var body := Actor.new()
	body.add_child(Health.new())
	var hurtbox := Hurtbox.new()
	hurtbox.size = Vector2(60.0, 20.0)
	body.add_child(hurtbox)
	body.add_child(brain)
	return _world.add(body, at)


## A plain toucher of the enemies' team (a circle of 8) with a touch of 5.
func _toucher(at: Vector2) -> Actor:
	var body := Actor.new()
	body.add_child(Health.new())
	body.add_child(Hurtbox.new())
	var contact := Contact.new()
	contact.damage = 5
	body.add_child(contact)
	body.add_child(Fixture.Scripted.new())
	return _world.add(body, at)
