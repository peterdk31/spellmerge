extends "res://tests/support/suite.gd"
## A body's ground and a prop in the game (props W4, docs/milestones/props.md). Every actor has a
## Footprint (its scene's, or one the actor adds); a body that walks slides as its circle and lays
## nothing; a body that cannot move (no Mover: a prop, a training dummy) is solid ground to the bodies
## that walk while it stands and is solid (`set_solid`), and stands still, driven or not. Shots pass
## over the ground and hit the body as any other: a piercing bolt hits a prop and goes on; a prop's
## own spells start from it as anyone's. The world is nobody's foe (`Actors.is_foe`): nothing aims at
## a prop or hurts it by touch, its death is no enemy's, and a heavy hit on it is one hit (it is never
## knocked into a wall). A stand-in prop (`ActorFixture.prop_body`).
##
## godot --headless --path . --script res://tests/gameplay/actor/test_footprint.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


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


## A target that stands: Health and a hurt circle, nothing more.
func _target(at: Vector2) -> Actor:
	return _world.actor(at, [&"health", &"hurtbox"])


## The box a prop standing at `at` lays.
func _box(at: Vector2) -> Rect2:
	return Rect2(at - Fixture.PROP_SIZE * 0.5, Fixture.PROP_SIZE)


func test_every_actor_has_a_footprint_and_only_one_that_cannot_move_lays_it() -> void:
	var walker: Actor = _world.actor(Vector2(-100.0, 0.0), [&"health", &"mover"])
	check(walker.footprint != null and walker.footprint.radius == 6.0, "the actor added the default circle")
	check_equal(walker.wall_radius(), 6.0, "and slides as it")
	check_equal(_world.projectiles.footprint_of(walker.id), Rect2(), "a body that walks lays nothing")
	var prop: Actor = _world.prop(Vector2(100.0, 0.0))
	check(prop.footprint == Fixture.footprint_of(prop), "a scene's own footprint is used, not doubled")
	check_equal(_world.projectiles.footprint_of(prop.id), _box(Vector2(100.0, 0.0)), "a prop lays its box where it stands")
	var dummy: Actor = _world.actor(Vector2(200.0, 0.0), [&"health", &"hurtbox"], Fixture.Scripted.new())
	check_equal(_world.projectiles.footprint_of(dummy.id), Rect2(194.0, -6.0, 12.0, 12.0), "a driven body with no Mover (a dummy) lays its circle: the one rule")


func test_it_is_lifted_when_the_prop_leaves_and_laid_when_it_comes_back() -> void:
	var prop: Actor = _world.prop(Vector2(100.0, 0.0))
	var id: int = prop.id
	prop.get_parent().remove_child(prop)
	check_equal(_world.projectiles.footprint_of(id), Rect2(), "lifted when it leaves the tree")
	root.add_child(prop)
	check_equal(_world.projectiles.footprint_of(prop.id), _box(Vector2(100.0, 0.0)), "laid again when it comes back")


func test_set_solid_lifts_and_lays_it_in_the_tree_or_out() -> void:
	var prop: Actor = _world.prop(Vector2(100.0, 0.0))
	prop.footprint.set_solid(false)
	check_equal(_world.projectiles.footprint_of(prop.id), Rect2(), "off: nothing blocks (rubble)")
	prop.footprint.set_solid(true)
	check_equal(_world.projectiles.footprint_of(prop.id), _box(Vector2(100.0, 0.0)), "on again")
	prop.get_parent().remove_child(prop)
	prop.footprint.set_solid(false)
	root.add_child(prop)
	check_equal(_world.projectiles.footprint_of(prop.id), Rect2(), "turned off out of the tree, it comes back off")


func test_a_walking_body_slides_along_a_prop() -> void:
	_world.prop(Vector2(100.0, 0.0))
	var walker: Actor = _world.actor(Vector2(60.0, 0.0), [&"mover"])
	walker.velocity = Vector2(200.0, 0.0)
	for i in 8:
		walker.move(Fixture.STEP)
	check(walker.global_position.x < 92.0 - walker.wall_radius() + 0.01, "stopped at the prop: %s" % walker.global_position)
	walker.velocity = Vector2(0.0, 200.0)
	walker.move(Fixture.STEP)
	check(walker.global_position.y > 0.0, "and free to go round it: %s" % walker.global_position)


func test_set_size_scales_the_footprint() -> void:
	var prop: Actor = _world.prop(Vector2(100.0, 0.0))
	prop.set_size(2.0)
	check_equal(_world.projectiles.footprint_of(prop.id), Rect2(Vector2(84.0, -16.0), Fixture.PROP_SIZE * 2.0), "twice as big, laid again")


func test_a_piercing_bolt_hits_a_prop_and_goes_on() -> void:
	var prop: Actor = _world.prop(Vector2(100.0, 4.0))
	var behind: Actor = _target(Vector2(160.0, 0.0))
	var shooter: Actor = _body(Vector2.ZERO, ActorsScript.TEAM_WIZARDS, Vector2.RIGHT, [[&"pierce", &"bolt"]])
	_world.run(1)
	check(shooter.caster.cast(0), "cast")
	_world.run(16)
	check(prop.health.health < prop.health.max_health, "the prop is hurt: %s" % prop.health.health)
	check(behind.health.health < behind.health.max_health, "and the body behind it: %s" % behind.health.health)


func test_a_plain_bolt_ends_on_the_prop() -> void:
	var prop: Actor = _world.prop(Vector2(100.0, 4.0))
	var behind: Actor = _target(Vector2(160.0, 0.0))
	var shooter: Actor = _body(Vector2.ZERO, ActorsScript.TEAM_WIZARDS, Vector2.RIGHT, [[&"bolt"]])
	_world.run(1)
	check(shooter.caster.cast(0), "cast")
	_world.run(16)
	check(prop.health.health < prop.health.max_health, "the prop is hurt")
	check_equal(behind.health.health, behind.health.max_health, "a bolt hits one body, as on any body")


func test_a_props_own_bolt_flies_out_of_it() -> void:
	var prop: Actor = _world.prop(Vector2.ZERO, [[&"bolt"]])
	prop.aim = Vector2.RIGHT
	var target: Actor = _target(Vector2(80.0, 8.0))
	_world.run(1)
	check(prop.caster.cast(0), "the prop casts (a reaction's cast, W6)")
	_world.run(16)
	check(target.health.health < target.health.max_health, "its bolt hit: %s" % target.health.health)
	check_equal(prop.health.health, prop.health.max_health, "sparing the prop")


func test_a_prop_places_its_pool_ahead_of_it() -> void:
	var prop: Actor = _world.prop(Vector2.ZERO, [[&"pool"]])
	prop.aim = Vector2.RIGHT
	_world.run(1)
	check(prop.caster.cast(0), "cast")
	_world.run(2)
	var farthest: float = -INF
	for slot in _world.projectiles._high:
		if _world.projectiles.is_alive(slot) and _world.projectiles._actor[slot] == prop.id:
			farthest = maxf(farthest, _world.projectiles.get_position_of(slot).x)
	check(farthest > Fixture.PROP_SIZE.x * 0.5, "its pool lies past its ground: %s" % farthest)


func test_the_world_is_nobodys_foe() -> void:
	var prop: Actor = _world.prop(Vector2(40.0, 0.0))
	check_equal(prop.team(), ActorsScript.TEAM_WORLD, "a prop is on the world's team")
	check_equal(_world.table.team_of(prop.id), ActorsScript.TEAM_WORLD, "in the table too")
	var enemy: Actor = _body(Vector2(100.0, 0.0), ActorsScript.TEAM_ENEMIES)
	var near: Node2D = _world.projectiles.nearest_target(Vector2(40.0, -8.0), 100.0, ProjectilesScript.ACTOR_LAYERS, null, null, ActorsScript.TEAM_WIZARDS)
	check(near == enemy, "a wizard's aim finds the enemy past the prop: %s" % near)
	var found: Array[Node2D] = []
	var centres := PackedVector2Array()
	var radii := PackedFloat32Array()
	var count: int = _world.projectiles.targets_near(Vector2(40.0, -8.0), 30.0, ProjectilesScript.ACTOR_LAYERS, ActorsScript.NONE, found, centres, radii)
	check_equal(count, 0, "even with no team of its own, aim never finds the prop")
	var world_aim: Node2D = _world.projectiles.nearest_target(Vector2(40.0, -8.0), 100.0, ProjectilesScript.ACTOR_LAYERS, null, null, ActorsScript.TEAM_WORLD)
	check(world_aim == enemy, "and the world's own aim goes for everyone else: %s" % world_aim)


func test_a_touch_never_hurts_a_prop() -> void:
	var prop: Actor = _world.prop(Vector2.ZERO)
	var toucher := Actor.new()
	toucher.add_child(Health.new())
	toucher.add_child(Hurtbox.new())
	var contact := Contact.new()
	contact.damage = 5
	toucher.add_child(contact)
	toucher.add_child(Fixture.Scripted.new())
	_world.add(toucher, Vector2(2.0, 0.0))
	var wizard: Actor = _body(Vector2(-2.0, 0.0), ActorsScript.TEAM_WIZARDS)
	_world.run(4)
	check(wizard.health.health < wizard.health.max_health, "the enemy's touch hurts a wizard on the spot")
	check_equal(prop.health.health, prop.health.max_health, "not the prop beside it")


func test_a_props_death_is_no_enemys() -> void:
	var deaths: Array[Node] = []
	_world.bus.enemy_died.connect(func(_by: int, body: Node, _at: Vector2, _shot: int) -> void: deaths.append(body))
	var prop: Actor = _world.prop(Vector2.ZERO)
	var enemy: Actor = _body(Vector2(60.0, 0.0), ActorsScript.TEAM_ENEMIES)
	_world.combat.hit(0, prop, 100)
	check(prop.is_dying(), "the prop is shot apart")
	_world.combat.hit(0, enemy, 100)
	check_equal(deaths, [enemy] as Array[Node], "only the enemy's death is an enemy's")


## Review of W4: a prop is never moved, so a push never wears off; it would slam into the nearest
## wall (a heavy hit's slam: a second hit that never happened).
func test_a_heavy_hit_on_a_prop_by_a_wall_is_one_hit() -> void:
	_world.projectiles.set_walls([Rect2(112.0, -40.0, 8.0, 80.0)] as Array[Rect2])
	var prop: Actor = _world.prop(Vector2(100.0, 4.0))
	var hits: Array[float] = []
	_world.bus.damage_dealt.connect(func(_by: int, target: Node, amount: float, _at: Vector2) -> void:
		if target == prop:
			hits.append(amount))
	var shooter: Actor = _body(Vector2.ZERO, ActorsScript.TEAM_WIZARDS, Vector2.RIGHT, [[&"heavy", &"bolt"]])
	_world.run(1)
	check(shooter.caster.cast(0), "cast")
	_world.run(24)
	check_equal(hits.size(), 1, "the bolt's hit alone, no slam: %s" % [hits])


func test_a_body_with_no_mover_never_moves_driven_or_not() -> void:
	var prop: Actor = _world.prop(Vector2(20.0, 0.0), [[&"bolt"]])
	var driver := Fixture.Scripted.new()
	driver.move = Vector2.RIGHT
	prop.drive(driver)
	_world.run(4)
	prop.velocity = Vector2(300.0, 0.0)
	prop.move(Fixture.STEP)
	check_equal(prop.global_position, Vector2(20.0, 0.0), "it stands on its own ground")
	prop.drive(null)
	driver.free()


func test_a_standing_prop_rests() -> void:
	var prop: Actor = _world.prop(Vector2.ZERO, [[&"bolt"]])
	check(prop.rest_leaf() != null, "a footprint keeps nothing a resting body would differ by")
