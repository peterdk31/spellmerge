extends "res://tests/support/suite.gd"
## Tests for the swarm (gameplay/horde/swarm.gd, docs/milestones/horde-swarm.md part S1): kinds
## read from the enemy, a swarmer as a bare node and a plain Combat body, the rows through many
## deaths, chase and retargeting, pace (chill, freeze), knockback, pull, swap, spacing, the floor
## and wall bodies, touch, every element's status and the shock jump between swarmers, the hurt
## pose, grudges, death by bolts with its gem through the director, the director's routing and its
## break, and no growth of memory over many steps. On a fixture of its own (swarm_fixture.gd: the
## real Combat, projectile manager and Spells); time moves by fixed steps.
##
## godot --headless --path . --script res://tests/gameplay/horde/test_swarm.gd

const Fixture := preload("res://tests/gameplay/horde/swarm_fixture.gd")
const SwarmScript := preload("res://gameplay/horde/swarm.gd")
const HordeScript := preload("res://gameplay/horde/horde.gd")
const HordeFixture := preload("res://tests/gameplay/horde/horde_fixture.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ImpData: EnemyBase = preload("res://content/enemies/ember_imp/ember_imp.tres")

var _run: Fixture = null
var _director: HordeScript = null


func after_each() -> void:
	if _director != null and is_instance_valid(_director):
		_director.stop()
		root.remove_child(_director)
		_director.free()
	_director = null
	if _run != null:
		_run.free_all()
	_run = null


func _make() -> Fixture:
	_run = Fixture.new(root)
	return _run


## Every row holds a live, registered node that knows its row, and nothing else is kept.
func _check_rows(run: Fixture, label: String) -> void:
	var swarm: SwarmScript = run.swarm
	var standing: int = 0
	for child: Node in run.horde.get_children():
		if not child.is_queued_for_deletion():
			standing += 1
	check_equal(swarm.count, standing, "%s: a row for every swarmer standing" % label)
	check_equal(swarm._row_by_node.size(), swarm.count, "%s: the node index holds the rows only" % label)
	for row in swarm.count:
		var node: Node2D = swarm.nodes[row]
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			check(false, "%s: row %d holds a dead node" % [label, row])
			continue
		check_equal(swarm.row_of(node), row, "%s: row %d is found by its node" % [label, row])
		check_equal(swarm.actor_ids[row], run.combat.actor_of(node), "%s: row %d keeps its Combat id" % [label, row])
		check(swarm.kinds[row] >= 0 and swarm.kinds[row] < swarm.kinds_list.size(), "%s: row %d has a kind" % [label, row])
		check(run.combat.health_of(node) > 0, "%s: row %d is alive in Combat" % [label, row])
		check_equal(node.position, swarm.positions[row], "%s: row %d's node stands where its row says" % [label, row])


# --- Kinds --------------------------------------------------------------------------------------

func test_a_kind_reads_its_numbers_from_the_enemy_and_its_scene() -> void:
	for data: EnemyBase in [Fixture.MiteData, Fixture.HuskData]:
		var kind: SwarmKind = SwarmScript.kind_for(data)
		check(kind != null, "%s is a swarm kind" % data.id)
		if kind == null:
			continue
		check_equal(kind.health, data.max_health, "%s: health from its data" % data.id)
		check_equal(kind.speed, data.move_speed, "%s: speed from its data" % data.id)
		check_equal(kind.contact_damage, data.contact_damage, "%s: touch from its data" % data.id)
		check(kind.scene == data.scene, "%s: the full scene to promote to" % data.id)
		var body: Actor = own(data.scene.instantiate()) as Actor
		var hurtbox := body.get_node(^"Hurtbox") as Hurtbox
		check_equal(kind.hurt_radius, hurtbox.radius, "%s: the hurt circle's radius from the scene" % data.id)
		check_equal(kind.hurt_offset, hurtbox.offset, "%s: the hurt circle's offset from the scene" % data.id)
		var circle := (body.get_node(^"CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
		check_equal(kind.body_radius, circle.radius, "%s: the body's radius from the scene" % data.id)
		check_equal(kind.body_offset, body.body_offset, "%s: the body offset from the scene" % data.id)
		var sprite := body.get_node(^"Sprite") as Sprite2D
		check(kind.texture == sprite.texture and kind.sprite_offset == sprite.position, "%s: the body sprite from the scene" % data.id)
		var face := body.get_node(^"Face") as Face
		check(kind.has_face and kind.face_style == face.style and kind.face_mood == face.resting_mood and kind.face_anchor == face.anchor, "%s: the face from the scene" % data.id)


func test_only_the_swarm_kinds_are_swarmers() -> void:
	check(SwarmScript.kind_for(ImpData) == null, "a staff enemy is no swarmer")
	check(SwarmScript.kind_for(null) == null, "no data, no kind")


# --- Bodies and rows ----------------------------------------------------------------------------

func test_a_swarmer_is_a_bare_node_and_a_plain_combat_body() -> void:
	var run: Fixture = _make()
	var targets: int = run.projectiles.get_target_count()
	var node: Node2D = run.swarmer(Vector2(10.0, 20.0))
	check(node != null and node.get_parent() == run.horde, "the swarmer stands under the Horde node")
	check_equal(node.get_child_count(), 0, "no children")
	check(node.get_script() == null, "no script")
	check(run.combat.is_registered(node), "registered with Combat")
	check_equal(run.combat.health_of(node), Fixture.MiteData.max_health, "with its kind's health")
	var id: int = run.combat.actor_of(node)
	check_equal(run.actors.team_of(id), ActorsScript.TEAM_ENEMIES, "on the enemies' team")
	check_equal(run.projectiles.get_target_count(), targets + 1, "a target every spell can hit")
	check_equal(run.swarm.positions[0], Vector2(10.0, 20.0), "its row starts where it appeared")


func test_rows_stay_consistent_through_many_deaths() -> void:
	var run: Fixture = _make()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var died: Array[Node] = []
	run.bus.enemy_died.connect(func(_k: int, enemy: Node, _at: Vector2, _s: int) -> void: died.append(enemy))
	for i in 120:
		run.swarmer(Vector2(rng.randf_range(-400.0, 400.0), rng.randf_range(-200.0, 200.0)), Fixture.MiteData if i % 3 != 0 else Fixture.HuskData)
	_check_rows(run, "after spawning")
	for n in 100:
		var row: int = rng.randi_range(0, run.swarm.count - 1)
		var node: Node2D = run.swarm.nodes[row]
		run.combat.hit(ActorsScript.NONE, node, 1000)
		if n == 50:
			for i in 30:
				run.swarmer(Vector2(rng.randf_range(-400.0, 400.0), 0.0))
			_check_rows(run, "after spawning in the middle")
		if n % 10 == 0:
			run.run(Fixture.STEP)
			_check_rows(run, "after %d deaths" % (n + 1))
	check_equal(died.size(), 100, "every death was an enemy_died")
	check_equal(run.swarm.count, 50, "120 + 30 - 100 rows")
	run.run(Fixture.STEP)
	_check_rows(run, "at the end")


func test_a_node_freed_from_outside_loses_its_row_at_the_next_step() -> void:
	var run: Fixture = _make()
	for i in 5:
		run.swarmer(Vector2(30.0 * i, 0.0))
	var gone: Node2D = run.swarm.nodes[1]
	run.horde.remove_child(gone)
	gone.free()
	run.run(Fixture.STEP)
	check_equal(run.swarm.count, 4, "the freed one's row went")
	_check_rows(run, "after a free")


# --- Chase --------------------------------------------------------------------------------------

func test_a_swarmer_chases_the_nearest_wizard() -> void:
	var run: Fixture = _make()
	run.wizard(Vector2(200.0, 0.0), 0)
	run.wizard(Vector2(-400.0, 0.0), 1)
	var node: Node2D = run.swarmer(Vector2.ZERO)
	run.run(1.0)
	var speed: float = Fixture.MiteData.move_speed
	check(absf(node.position.x - speed) < 2.0 and absf(node.position.y) < 1.0, "it walked a second at its speed toward the nearer wizard (at %s)" % node.position)
	check(run.swarm.aims[0].dot(Vector2.RIGHT) > 0.99, "it looks at the wizard")
	check(run.swarm.velocities[0].length() > speed * 0.99, "its velocity is its walk")


func test_retargets_are_staggered_and_a_lost_target_is_dropped_at_once() -> void:
	var run: Fixture = _make()
	var near: Actor = run.wizard(Vector2(150.0, 0.0), 0)
	var far: Actor = run.wizard(Vector2(-400.0, 0.0), 1)
	for i in 64:
		run.swarmer(Vector2(-20.0 + float(i % 8) * 6.0, -20.0 + float(i >> 3) * 6.0))
	run.run(Fixture.STEP)
	check_equal(run.swarm.lookup_count, 64, "every new swarmer looks at its first step")
	var most: int = 0
	for i in 16:
		var before: int = run.swarm.lookup_count
		run.run(Fixture.STEP)
		most = maxi(most, run.swarm.lookup_count - before)
	check(most < 32, "later looks are spread over the steps (at most %d in one)" % most)
	# The near wizard goes down: everyone turns to the other at once.
	near.set_down(true)
	run.bus.player_downed.emit(0)
	run.run(Fixture.STEP * 2.0)
	for row in run.swarm.count:
		check(run.swarm.aims[row].x < 0.0, "row %d turned to the standing wizard" % row)
	check(far != null, "the far wizard stands")


func test_a_teammate_that_hurts_it_earns_a_grudge() -> void:
	var run: Fixture = _make()
	run.wizard(Vector2(300.0, 0.0))
	var victim: Node2D = run.swarmer(Vector2.ZERO)
	var attacker: Node2D = run.swarmer(Vector2(-100.0, 0.0), Fixture.HuskData)
	run.run(Fixture.STEP)
	run.combat.hit(run.combat.actor_of(attacker), victim, 1)
	run.run(0.5)
	check(victim.position.x < 0.0, "it turned on the teammate that hurt it (at %s)" % victim.position)
	run.run(SwarmScript.GRUDGE_TIME + 1.0)
	check(run.swarm.aims[run.swarm.row_of(victim)].x > 0.0, "after the grudge it chases the wizard again")


# --- Pace, push, swap ---------------------------------------------------------------------------

func test_chill_slows_and_freeze_stops() -> void:
	var run: Fixture = _make()
	run.wizard(Vector2(400.0, 0.0))
	var free_one: Node2D = run.swarmer(Vector2(0.0, -100.0))
	var chilled: Node2D = run.swarmer(Vector2(0.0, 0.0))
	var frozen: Node2D = run.swarmer(Vector2(0.0, 100.0))
	run.combat.apply_status(ActorsScript.NONE, chilled, CombatScript.CHILL, 5.0, 50.0)
	for i in CombatScript.CHILL_STACKS_TO_FREEZE:
		run.combat.apply_status(ActorsScript.NONE, frozen, CombatScript.CHILL, 5.0, 50.0)
	check(run.combat.has_status(frozen, CombatScript.FREEZE), "three chills froze it")
	run.run(0.5)
	var walked: float = free_one.position.x
	check(walked > 30.0, "the free one walked (%.1f px)" % walked)
	check(absf(chilled.position.x - walked * 0.5) < 1.5, "the chilled one walked half as far (%.1f of %.1f)" % [chilled.position.x, walked])
	check_equal(frozen.position, Vector2(0.0, 100.0), "the frozen one stood still")


func test_knockback_and_pull_move_swarmers() -> void:
	var run: Fixture = _make()
	var pushed: Node2D = run.swarmer(Vector2(0.0, -150.0))
	var pulled: Node2D = run.swarmer(Vector2(0.0, 150.0))
	run.run(Fixture.STEP)
	run.combat.hit(ActorsScript.NONE, pushed, 1, Vector2.RIGHT, 300.0)
	run.combat.pull(ActorsScript.NONE, Vector2(-100.0, 150.0), 120.0, 300.0)
	run.run(0.5)
	check(pushed.position.x > 20.0, "the knocked one flew along the hit (at %s)" % pushed.position)
	check(pulled.position.x < -20.0, "the pulled one moved toward the pull (at %s)" % pulled.position)


func test_a_swap_puts_a_swarmer_where_it_says() -> void:
	var run: Fixture = _make()
	var node: Node2D = run.swarmer(Vector2.ZERO)
	run.bus.target_move_requested.emit(0, node, Vector2(120.0, -40.0))
	check_equal(node.position, Vector2(120.0, -40.0), "the node moved")
	check_equal(run.swarm.positions[0], Vector2(120.0, -40.0), "and its row")


## A stand-in for the look (part S2) that records what the swarm tells it.
class FakeLook:
	extends Node
	var calls: Array = []

	func step(delta: float) -> void:
		calls.append([&"step", delta])

	func on_hit(row: int) -> void:
		calls.append([&"on_hit", row])

	func on_row_removed(row: int) -> void:
		calls.append([&"on_row_removed", row])

	func clear() -> void:
		calls.append([&"clear"])


func test_a_local_stop_holds_a_swarmer_and_ran_says_so() -> void:
	var run: Fixture = _make()
	run.wizard(Vector2(300.0, 0.0))
	var held: Node2D = run.swarmer(Vector2(0.0, -50.0))
	var free_one: Node2D = run.swarmer(Vector2(0.0, 50.0))
	run.run(Fixture.STEP)
	var at: Vector2 = held.position
	run.actors.hold(run.combat.actor_of(held), Fixture.STEP * 2.5)
	run.run(Fixture.STEP * 2.0)
	check_equal(held.position, at, "a held swarmer stands")
	check_equal(run.swarm.ran[run.swarm.row_of(held)], 0.0, "and ran no time")
	check_equal(run.swarm.ran[run.swarm.row_of(free_one)], Fixture.STEP, "the other ran the whole step")
	run.run(Fixture.STEP)
	check_equal(run.swarm.ran[run.swarm.row_of(held)], Fixture.STEP * 0.5, "the step the stop ends in runs for what is left")
	check(held.position.x > at.x, "and it walks again")


func test_the_look_hears_steps_hits_removals_and_the_end() -> void:
	var run: Fixture = _make()
	var look := own(FakeLook.new()) as FakeLook
	run.swarm.look = look
	var first: Node2D = run.swarmer(Vector2.ZERO)
	run.swarmer(Vector2(50.0, 0.0))
	run.swarm.step(Fixture.STEP)
	check(look.calls.has([&"step", Fixture.STEP]), "a step is told")
	look.calls.clear()
	run.combat.hit(ActorsScript.NONE, first, 1)
	check(look.calls.has([&"on_hit", 0]), "a hit is told with its row")
	look.calls.clear()
	run.combat.hit(ActorsScript.NONE, first, 1000)
	check(look.calls.has([&"on_row_removed", 0]), "a death is told with the row the last one moved into")
	check_equal(run.swarm.count, 1, "one row left")
	run.swarm.stop()
	check(look.calls.has([&"clear"]), "a stop empties the look")


# --- Spacing and walls --------------------------------------------------------------------------

func test_swarmers_do_not_stack() -> void:
	var run: Fixture = _make()
	for i in 40:
		run.swarmer(Vector2(1.0, 2.0), Fixture.MiteData if i % 2 == 0 else Fixture.HuskData)
	run.run(3.0)
	var closest: float = INF
	var swarm: SwarmScript = run.swarm
	for a in swarm.count:
		for b in range(a + 1, swarm.count):
			var reach: float = swarm.kinds_list[swarm.kinds[a]].body_radius + swarm.kinds_list[swarm.kinds[b]].body_radius
			closest = minf(closest, swarm.positions[a].distance_to(swarm.positions[b]) / reach)
	check(closest > 0.8, "no two overlap by more than a fifth of their bodies (closest %.2f of touching)" % closest)


func test_the_floor_holds_them() -> void:
	var run: Fixture = _make()
	var node: Node2D = run.swarmer(Vector2(Fixture.ARENA.position.x + 10.0, 0.0))
	run.run(Fixture.STEP)
	run.combat.hit(ActorsScript.NONE, node, 1, Vector2.LEFT, 2000.0)
	for i in 30:
		run.run(Fixture.STEP)
		check(Fixture.ARENA.has_point(node.position) or node.position.x == Fixture.ARENA.position.x, "it stays on the floor (at %s)" % node.position)


func test_a_wall_body_stops_them() -> void:
	var run: Fixture = _make()
	var block := Rect2(60.0, -40.0, 32.0, 80.0)
	run.wall(block)
	run.swarm.start(run.horde, Fixture.ARENA)
	run.wizard(Vector2(200.0, 0.0))
	var node: Node2D = run.swarmer(Vector2(0.0, 0.0))
	for i in 80:
		run.run(Fixture.STEP)
		check(not block.has_point(node.position), "it never stands in the wall (at %s)" % node.position)
	check(node.position.x < block.position.x, "it waits at the wall's near side (at %s)" % node.position)


# --- Combat rules -------------------------------------------------------------------------------

func test_touch_hurts_a_wizard() -> void:
	var run: Fixture = _make()
	var wizard: Actor = run.wizard(Vector2(40.0, 0.0))
	var start: int = wizard.health.health
	run.swarmer(Vector2.ZERO)
	run.run(1.0)
	check_equal(wizard.health.health, start - Fixture.MiteData.contact_damage, "one touch hurt the wizard (then Combat's wait)")
	run.run(1.0)
	check_equal(wizard.health.health, start - 2 * Fixture.MiteData.contact_damage, "and the next after the wait")


func test_every_element_puts_its_status_on_a_swarmer() -> void:
	var run: Fixture = _make()
	var wizard: Actor = run.wizard(Vector2(400.0, 0.0))
	var wanted: Dictionary = {&"fire": &"burn", &"frost": &"chill", &"storm": &"shock", &"void": &"hex", &"lightning": &"static"}
	var y: float = -200.0
	for element: StringName in wanted:
		var node: Node2D = run.swarmer(Vector2(0.0, y), Fixture.HuskData)
		y += 80.0
		run.hit(wizard.id, node, run.tag(wizard.id, element))
		check(run.combat.has_status(node, wanted[element]), "%s put %s on the swarmer" % [element, wanted[element]])
		check(run.combat.health_of(node) < Fixture.HuskData.max_health, "%s hurt it" % element)


func test_burn_kills_a_swarmer_and_its_row_goes() -> void:
	var run: Fixture = _make()
	var died: Array[Node] = []
	run.bus.enemy_died.connect(func(_k: int, enemy: Node, _at: Vector2, _s: int) -> void: died.append(enemy))
	var node: Node2D = run.swarmer(Vector2.ZERO)
	run.combat.apply_status(ActorsScript.NONE, node, CombatScript.BURN, 5.0, 20.0)
	run.run(2.0)
	check(died.has(node), "the burn killed it (enemy_died)")
	check_equal(run.swarm.count, 0, "and its row went")


func test_frost_freezes_a_swarmer_where_it_stands() -> void:
	var run: Fixture = _make()
	var wizard: Actor = run.wizard(Vector2(300.0, 0.0))
	var node: Node2D = run.swarmer(Vector2.ZERO, Fixture.HuskData)
	var frost: int = run.tag(wizard.id, &"frost")
	for i in CombatScript.CHILL_STACKS_TO_FREEZE:
		run.hit(wizard.id, node, frost)
		run.combat.step(0.0)
	check(run.combat.has_status(node, CombatScript.FREEZE), "three frost hits froze it")
	# The hits' push is not slowed by a freeze (as for any actor): let it fade first.
	run.run(0.25)
	var at: Vector2 = node.position
	run.run(0.5)
	check(node.position.distance_to(at) < 1.0, "frozen, it does not walk (moved %.1f px)" % node.position.distance_to(at))


func test_a_shock_jumps_between_swarmers() -> void:
	var run: Fixture = _make()
	var wizard: Actor = run.wizard(Vector2(900.0, 900.0))
	var struck: Node2D = run.swarmer(Vector2.ZERO, Fixture.HuskData)
	var near: Node2D = run.swarmer(Vector2(30.0, 0.0), Fixture.HuskData)
	run.hit(wizard.id, struck, run.tag(wizard.id, &"storm"))
	check(run.combat.has_status(struck, CombatScript.SHOCK), "the storm hit shocked it")
	var before: int = run.combat.health_of(near)
	run.hit(wizard.id, struck, run.tag(wizard.id))
	check(run.combat.health_of(near) < before, "the next hit jumped to the swarmer beside it")


func test_a_hit_shows_the_hurt_pose() -> void:
	var run: Fixture = _make()
	var node: Node2D = run.swarmer(Vector2.ZERO, Fixture.HuskData)
	run.combat.hit(ActorsScript.NONE, node, 1)
	check_equal(run.swarm.hurt_left[0], SwarmScript.HURT_TIME, "a hit starts the hurt pose")
	run.run(SwarmScript.HURT_TIME + Fixture.STEP)
	check_equal(run.swarm.hurt_left[0], 0.0, "it ends after HURT_TIME")
	check_equal(run.swarm.down[0], 0, "a swarmer is never down")


# --- With the director --------------------------------------------------------------------------

## A director on the fixture's world, with the fixture's swarm, spawning `weights` (by id).
func _director_on(run: Fixture, weights: Dictionary) -> HordeScript:
	_director = HordeScript.new()
	_director.events = run.bus
	_director.actors = run.actors
	_director.projectiles = run.projectiles
	_director.registry = run.registry
	_director.view_size = Vector2(640.0, 360.0)
	_director.curve = HordeFixture.curve([[0.0, 30.0, 200]], weights)
	_director.rng.seed = 3
	_director.swarm = run.swarm
	root.add_child(_director)
	_director.set_process(false)
	_director.set_physics_process(false)
	_director.start(run.world)
	return _director


func test_the_director_spawns_swarm_kinds_into_the_swarm_and_the_rest_as_actors() -> void:
	var run: Fixture = _make()
	run.wizard(Vector2.ZERO)
	run.registry.folders[&"enemies"][ImpData.id] = ImpData
	var director: HordeScript = _director_on(run, {Fixture.MiteData.id: 1.0, Fixture.HuskData.id: 1.0, ImpData.id: 1.0})
	director.step(0.5)
	var actors_made: int = 0
	var bare: int = 0
	for child: Node in director.horde_node().get_children():
		if child is Actor:
			actors_made += 1
		elif child.get_script() == null and child.get_child_count() == 0:
			bare += 1
	check(bare > 0 and bare == run.swarm.count, "the swarmers are bare nodes in the swarm (%d)" % bare)
	check(actors_made > 0, "the imps are full actors (%d)" % actors_made)
	check_equal(director.alive, bare + actors_made, "alive counts both")
	for child: Node in director.horde_node().get_children():
		if child is Actor:
			child.free()


func test_a_swarmer_dies_to_bolts_and_drops_a_gem() -> void:
	var run: Fixture = _make()
	var wizard: Actor = run.wizard(Vector2.ZERO)
	var director: HordeScript = _director_on(run, {Fixture.MiteData.id: 1.0})
	director.step(Fixture.STEP)
	check(run.swarm.count > 0, "a swarmer appeared")
	var node: Node2D = run.swarm.nodes[0]
	var died: Array[Node] = []
	run.bus.enemy_died.connect(func(_k: int, enemy: Node, _at: Vector2, _s: int) -> void: died.append(enemy))
	var alive: int = director.alive
	var bolt: int = run.tag(wizard.id)
	for i in ceili(float(Fixture.MiteData.max_health) / float(Fixture.BOLT_DAMAGE)):
		run.hit(wizard.id, node, bolt)
	check(died.has(node), "the bolts killed it (enemy_died)")
	check_equal(director.kills, 1, "the director counted the kill")
	check_equal(director.alive, alive - 1, "and one less alive")
	check_equal(director.gems().count, 1, "a gem where it died")
	check(run.swarm.row_of(node) < 0, "its row went")


func test_the_break_freezes_the_swarm() -> void:
	var run: Fixture = _make()
	run.wizard(Vector2.ZERO)
	var director: HordeScript = _director_on(run, {Fixture.MiteData.id: 1.0})
	director.step(Fixture.STEP)
	check(run.swarm.count > 0, "a swarmer appeared")
	var before: Vector2 = run.swarm.nodes[0].position
	director.horde_node().process_mode = Node.PROCESS_MODE_DISABLED
	for i in 10:
		director.physics_step(Fixture.STEP)
	check_equal(run.swarm.nodes[0].position, before, "it stands while the Horde node is off")
	director.horde_node().process_mode = Node.PROCESS_MODE_INHERIT
	run.projectiles.step(Fixture.STEP)
	for i in 10:
		director.physics_step(Fixture.STEP)
	check(run.swarm.nodes[0].position != before, "and walks again after it")


func test_a_restart_forgets_the_swarm() -> void:
	var run: Fixture = _make()
	run.wizard(Vector2.ZERO)
	var director: HordeScript = _director_on(run, {Fixture.MiteData.id: 1.0})
	director.step(0.5)
	check(run.swarm.count > 0, "swarmers appeared")
	director.stop()
	check_equal(run.swarm.count, 0, "a stop forgets every row")
	director.start(run.world)
	director.step(0.25)
	check(run.swarm.count > 0, "the next run spawns into the swarm again")
	check(run.swarm.nodes[0].get_parent() == director.horde_node(), "under the new Horde node")


# --- Cost ---------------------------------------------------------------------------------------

func test_no_memory_growth_over_many_steps() -> void:
	var run: Fixture = _make()
	run.wizard(Vector2(0.0, 0.0))
	run.wizard(Vector2(200.0, 100.0), 1)
	for i in 300:
		run.swarmer(Vector2(-400.0 + float(i % 30) * 25.0, -250.0 + floorf(float(i) / 30.0) * 20.0), Fixture.MiteData if i % 2 == 0 else Fixture.HuskData)
	# Warm up: every row has looked, the slots and the scratch lists are made.
	for i in 30:
		run.swarm.step(Fixture.STEP)
		run.projectiles.step(Fixture.STEP)
	var before: int = OS.get_static_memory_usage()
	for i in 300:
		run.swarm.step(Fixture.STEP)
		run.projectiles.step(Fixture.STEP)
	var grown: int = OS.get_static_memory_usage() - before
	check(grown < 16 * 1024, "300 steps of 300 swarmers grew memory by %d bytes" % grown)
