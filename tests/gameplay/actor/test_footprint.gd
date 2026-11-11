extends "res://tests/support/suite.gd"
## A prop in the game (props W4, docs/milestones/props.md): an actor of the world's team with no
## controller and no Mover, a Footprint laid in the wall grid while it stands (`Footprint`,
## `ProjectileManager.set_footprint`) and a hurt circle that covers it. Bodies slide along it; a
## shot that meets it hits it and ends there; its own spells leave it. The world is nobody's foe
## (`Actors.is_foe`): nothing aims at a prop or hurts it by touch, and its death is no enemy's.
## A body with no Mover never moves, driven or not. A stand-in prop (`ActorFixture.prop_body`).
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


func test_it_is_laid_where_the_prop_stands_while_it_is_in_the_tree() -> void:
	var prop: Actor = _world.prop(Vector2(100.0, 0.0))
	var id: int = prop.id
	var rect := Rect2(Vector2(100.0, 0.0) + Fixture.PROP_CENTRE - Fixture.PROP_SIZE * 0.5, Fixture.PROP_SIZE)
	check_equal(_world.projectiles.footprint_of(id), rect, "laid round its centre")
	check(not _world.projectiles.line_clear(Vector2(60.0, -8.0), Vector2(140.0, -8.0)), "a line through it is blocked")
	prop.get_parent().remove_child(prop)
	check_equal(_world.projectiles.footprint_of(id), Rect2(), "lifted when it leaves the tree")
	check(_world.projectiles.line_clear(Vector2(60.0, -8.0), Vector2(140.0, -8.0)), "and the way is open")
	root.add_child(prop)
	check_equal(_world.projectiles.footprint_of(prop.id), rect, "laid again when it comes back")


func test_set_blocks_lifts_and_lays_it() -> void:
	var prop: Actor = _world.prop(Vector2(100.0, 0.0))
	var footprint: Footprint = Fixture.footprint_of(prop)
	footprint.set_blocks(false)
	check_equal(_world.projectiles.footprint_of(prop.id), Rect2(), "off: nothing blocks (rubble)")
	footprint.set_blocks(true)
	check_equal(_world.projectiles.footprint_of(prop.id), footprint.rect(), "on again")


func test_a_walking_body_slides_along_it() -> void:
	_world.prop(Vector2(100.0, 0.0))
	var walker: Actor = _world.actor(Vector2(60.0, -8.0), [&"mover"])
	walker.velocity = Vector2(200.0, 0.0)
	for i in 8:
		walker.move(Fixture.STEP)
	check(walker.global_position.x < 92.0 - walker.mover.body_radius + 0.01, "stopped at the prop: %s" % walker.global_position)
	walker.velocity = Vector2(0.0, 200.0)
	walker.move(Fixture.STEP)
	check(walker.global_position.y > -8.0, "and free to go round it: %s" % walker.global_position)


func test_a_piercing_bolt_that_meets_a_prop_hurts_it_and_ends_there() -> void:
	var prop: Actor = _world.prop(Vector2(100.0, 4.0))
	var behind: Actor = _target(Vector2(160.0, 0.0))
	var shooter: Actor = _body(Vector2.ZERO, ActorsScript.TEAM_WIZARDS, Vector2.RIGHT, [[&"pierce", &"bolt"]])
	_world.run(1)
	check(shooter.caster.cast(0), "cast")
	_world.run(16)
	check(prop.health.health < prop.health.max_health, "the prop is hurt: %s" % prop.health.health)
	check_equal(behind.health.health, behind.health.max_health, "nothing passed it to the body behind")


func test_a_props_own_bolt_leaves_it() -> void:
	var prop: Actor = _world.prop(Vector2.ZERO, [[&"bolt"]])
	prop.aim = Vector2.RIGHT
	var target: Actor = _target(Vector2(80.0, 0.0))
	_world.run(1)
	check(prop.caster.cast(0), "the prop casts (a reaction's cast, W6)")
	_world.run(16)
	check(target.health.health < target.health.max_health, "its bolt flew out of its footprint and hit: %s" % target.health.health)
	check_equal(prop.health.health, prop.health.max_health, "sparing the prop")


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
	var health := Health.new()
	toucher.add_child(health)
	toucher.add_child(Hurtbox.new())
	var contact := Contact.new()
	contact.damage = 5
	toucher.add_child(contact)
	toucher.add_child(Fixture.Scripted.new())
	_world.add(toucher, Vector2(2.0, 0.0))
	var wizard: Actor = _body(Vector2(-2.0, 0.0), ActorsScript.TEAM_WIZARDS)
	_world.run(4)
	check(wizard.health.health < wizard.health.max_health, "the enemy's touch hurts a wizard on the spot")
	check_equal(prop.health.health, prop.health.max_health, "not the prop it stands on")


func test_a_props_death_is_no_enemys() -> void:
	var deaths: Array[Node] = []
	_world.bus.enemy_died.connect(func(_by: int, body: Node, _at: Vector2, _shot: int) -> void: deaths.append(body))
	var prop: Actor = _world.prop(Vector2.ZERO)
	var enemy: Actor = _body(Vector2(60.0, 0.0), ActorsScript.TEAM_ENEMIES)
	_world.combat.hit(0, prop, 100)
	check(prop.is_dying(), "the prop is shot apart")
	_world.combat.hit(0, enemy, 100)
	check_equal(deaths, [enemy] as Array[Node], "only the enemy's death is an enemy's")


func test_a_body_with_no_mover_never_moves_driven_or_not() -> void:
	var prop: Actor = _world.prop(Vector2(20.0, 0.0), [[&"bolt"]])
	var driver := Fixture.Scripted.new()
	driver.move = Vector2.RIGHT
	prop.drive(driver)
	_world.run(4)
	prop.velocity = Vector2(300.0, 0.0)
	prop.move(Fixture.STEP)
	check_equal(prop.global_position, Vector2(20.0, 0.0), "it stands, in its own footprint")
	prop.drive(null)
	driver.free()


func test_a_standing_prop_rests() -> void:
	var prop: Actor = _world.prop(Vector2.ZERO, [[&"bolt"]])
	check(prop.rest_leaf() != null, "a footprint keeps nothing a resting body would differ by")


func test_its_problems_are_named() -> void:
	var prop: Actor = _world.prop(Vector2.ZERO)
	check_equal(Fixture.footprint_of(prop).problems(), PackedStringArray(), "the stand-in has none")
	var small := Fixture.prop_body()
	for child in small.get_children():
		if child is Hurtbox:
			(child as Hurtbox).radius = 10.0
	small.add_child(Mover.new())
	_world.add(small, Vector2(100.0, 0.0))
	var problems: PackedStringArray = Fixture.footprint_of(small).problems()
	check_equal(problems.size(), 2, "a Mover and a hurt circle that does not cover it: %s" % [problems])


## Review of W4: a prop is never moved, so a push never wears off; it used to slam into its own
## footprint (a heavy hit's slam: a second hit that never happened).
func test_a_heavy_hit_on_a_prop_is_one_hit() -> void:
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


## Review of W4: what a prop places ahead of it (a pool, a rune, a wall) is placed ahead, not at its
## own centre: its own footprint does not stop the way there.
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
	check(farthest > Fixture.PROP_SIZE.x * 0.5 + ProjectilesScript.WALL_CELL * 0.5, "its pool lies past its footprint: %s" % farthest)


func test_set_blocks_out_of_the_tree_is_kept_for_its_return() -> void:
	var prop: Actor = _world.prop(Vector2(100.0, 0.0))
	prop.get_parent().remove_child(prop)
	Fixture.footprint_of(prop).set_blocks(false)
	root.add_child(prop)
	check_equal(_world.projectiles.footprint_of(prop.id), Rect2(), "back without blocking")
	check(_world.projectiles.line_clear(Vector2(60.0, -8.0), Vector2(140.0, -8.0)), "and nothing laid")
