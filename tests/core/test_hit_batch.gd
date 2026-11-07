extends "res://tests/support/suite.gd"
## Bundled hits (shot scale H3b, the first part: the manager's `batch_hits`; core/events/hit_batch.gd).
## The hit pass fills one batch and sends it in phases; a hit on a body an earlier hit of the batch
## killed is lost, and its shot flies on and hits what is behind, so the same shots hit the same
## bodies as with each hit sent at once. A shot a hit spends ends between the damage and the cards,
## and the slots that end are not taken by a shot spawned while the batch is sent. With the real
## Spells and Combat, a crowd that dies takes the same damage, body by body, batched or not. Each
## manager case runs on the GDScript and on the native kernel (when built).
##
## godot --headless --path . --script res://tests/core/test_hit_batch.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const StaffKit := preload("res://tests/support/staff_kit.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ComboArena := preload("res://tests/content/spells/combo_arena.gd")

const DT: float = 1.0 / 60.0


class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


## A manager on a bus of its own, with a stand-in for Combat: each hit takes one point, a body at
## none is removed (as Combat removes a body it kills).
class Scene:
	extends RefCounted
	var bus: EventsScript
	var table: Node
	var mgr: ManagerScript
	var bodies: Array[Node2D] = []
	var health: Dictionary = {}
	## The bodies each shot hit, in order, by its slot.
	var hit_by_shot: Dictionary = {}
	## What the test saw of the phases, in order.
	var seen: Array = []

	func damage(target: Node, shot: int) -> void:
		var list: Array = hit_by_shot.get(shot, [])
		list.append(bodies.find(target as Node2D))
		hit_by_shot[shot] = list
		var left: int = int(health[target]) - 1
		health[target] = left
		if left <= 0:
			mgr.remove_target(target as Node2D)

	func on_hit(_caster: int, target: Node, _point: Vector2, _tag: int, shot: int) -> void:
		damage(target, shot)

	func on_hits(batch: HitBatch, phase: int) -> void:
		for i in batch.count:
			if not mgr.batch_turn(i):
				continue
			if phase == HitBatch.PHASE_COMBAT:
				damage(batch.target[i], batch.shot[i])
			seen.append([phase, batch.shot[i], mgr.is_alive(batch.shot[i])])


## Two shots on one line at a body that dies of one hit: the first kills it; the second's hit on it
## is lost, and the shot flies on to the body behind, as it does with each hit sent at once.
func test_a_shot_whose_body_died_in_the_batch_hits_the_one_behind() -> void:
	var results: Array = []
	for native: bool in _modes():
		for batched: bool in [false, true]:
			var scene := _scene(native, batched)
			_body(scene, Vector2(40.0, 0.0), 4.0, 1)
			_body(scene, Vector2(200.0, 0.0), 4.0, 100)
			var first: int = scene.mgr.spawn(_caster(scene), Vector2.ZERO, Vector2(1200.0, 0.0), 1.0, 2.0, ManagerScript.LAYER_ENEMY, 0, 0)
			var second: int = scene.mgr.spawn(_caster(scene), Vector2(-1.0, 0.0), Vector2(1200.0, 0.0), 1.0, 2.0, ManagerScript.LAYER_ENEMY, 0, 0)
			var label: String = _label(scene)
			# 20 px a step: both reach the first body in the second step.
			scene.mgr.step(DT)
			scene.mgr.step(DT)
			check_equal(scene.hit_by_shot.get(first, []), [0], "%s: the first shot killed the first body" % label)
			if batched:
				check(scene.mgr.is_alive(second), "%s: the second shot's hit was lost, and it lives on" % label)
				check(not scene.hit_by_shot.has(second), "%s: and it dealt no damage to the dead body" % label)
			for i in 20:
				scene.mgr.step(DT)
			check_equal(scene.hit_by_shot.get(second, []), [1], "%s: the second shot hit the body behind" % label)
			results.append(scene.hit_by_shot)
			_free(scene)
	_all_alike(results)


## A piercing shot whose first hit of a step is lost gets that pierce back: it hits the body after
## it in the same batch, and the one after that later, as it would with the dead body gone.
func test_a_lost_hit_gives_its_pierce_back() -> void:
	var results: Array = []
	for native: bool in _modes():
		for batched: bool in [false, true]:
			var scene := _scene(native, batched)
			_body(scene, Vector2(40.0, 0.0), 4.0, 1)
			_body(scene, Vector2(50.0, 0.0), 4.0, 100)
			_body(scene, Vector2(120.0, 0.0), 4.0, 100)
			# 50 px a step: both shots touch the first two bodies in their first step.
			var first: int = scene.mgr.spawn(_caster(scene), Vector2.ZERO, Vector2(3000.0, 0.0), 1.0, 2.0, ManagerScript.LAYER_ENEMY, 0, 0)
			var second: int = scene.mgr.spawn(_caster(scene), Vector2(-1.0, 0.0), Vector2(3000.0, 0.0), 1.0, 2.0, ManagerScript.LAYER_ENEMY, 1, 0)
			var label: String = _label(scene)
			scene.mgr.step(DT)
			check_equal(scene.hit_by_shot.get(first, []), [0], "%s: the first shot killed the first body" % label)
			check_equal(scene.hit_by_shot.get(second, []), [1], "%s: the second hit the next body in the same step" % label)
			check(scene.mgr.is_alive(second), "%s: and lives on, its pierce spent on it" % label)
			for i in 10:
				scene.mgr.step(DT)
			check_equal(scene.hit_by_shot.get(second, []), [1, 2], "%s: then it hit the last body, and only once the one it passed" % label)
			check(not scene.mgr.is_alive(second), "%s: which spent it" % label)
			results.append(scene.hit_by_shot)
			_free(scene)
	_all_alike(results)


## A shot a hit spends is alive while the batch's damage is dealt and has ended when its cards run,
## and its tag's `shot_ended` comes after them.
func test_a_spent_shot_ends_between_the_damage_and_the_cards() -> void:
	for native: bool in _modes():
		var scene := _scene(native, true)
		_body(scene, Vector2(30.0, 0.0), 4.0, 100)
		var shot: int = scene.mgr.spawn(_caster(scene), Vector2.ZERO, Vector2(1200.0, 0.0), 1.0, 2.0, ManagerScript.LAYER_ENEMY, 0, 7)
		scene.mgr.shot_ended.connect(func(tag: int) -> void: scene.seen.append(["ended", tag]))
		for i in 3:
			scene.mgr.step(DT)
		var label: String = _label(scene)
		check_equal(scene.seen, [[HitBatch.PHASE_PRE, shot, true], [HitBatch.PHASE_COMBAT, shot, true], [HitBatch.PHASE_SPELLS, shot, false], ["ended", 7]], "%s: alive for the damage, ended for the cards, then shot_ended" % label)
		_free(scene)


## A shot spawned while the batch is sent never takes the slot of a shot a later hit of the batch
## spent: that hit's listeners still read their own shot.
func test_a_shot_spawned_in_the_batch_takes_no_spent_shots_slot() -> void:
	for native: bool in _modes():
		var scene := _scene(native, true)
		for i in 3:
			_body(scene, Vector2(30.0, -40.0 + 40.0 * float(i)), 4.0, 100)
		var shots: Array[int] = []
		for i in 3:
			shots.append(scene.mgr.spawn(_caster(scene), Vector2(0.0, -40.0 + 40.0 * float(i)), Vector2(1200.0, 0.0), 1.0, 2.0, ManagerScript.LAYER_ENEMY, 0, 0))
		var spawned: Array[int] = []
		var mgr: ManagerScript = scene.mgr
		scene.bus.projectile_hits.connect(func(batch: HitBatch, phase: int) -> void:
			if phase != HitBatch.PHASE_SPELLS:
				return
			for i in batch.count:
				if mgr.batch_turn(i):
					spawned.append(mgr.spawn(0, Vector2(0.0, 300.0), Vector2.ZERO, 1.0, 2.0, 0, 0, 0)))
		for i in 3:
			scene.mgr.step(DT)
		var label: String = _label(scene)
		check_equal(spawned.size(), 3, "%s: a shot was spawned at each hit's cards" % label)
		for slot in spawned:
			check(not shots.has(slot), "%s: slot %d is none of the spent shots'" % [label, slot])
		_free(scene)


## A relay shot that pierces two donors in one step, each the body of a player whose last cast was
## infused (frost, then fire): the first hit takes on only the first donor's element, the second
## both, batched as when each hit is sent at once (Combat reads each hit's profile as it was right
## after its own relay, not after the later hit's: `HitBatch.profile`).
func test_a_relay_hit_reads_its_profile_before_a_later_hits_relay() -> void:
	var records: Array = []
	for batched: bool in [false, true]:
		var arena := ComboArena.new(root)
		arena.projectiles.batch_hits = batched
		# Two donors on the line, 6 px apart across it: one step of the bolt touches both.
		var first := arena.add_imp(Vector2(60.0, -3.0), 1000.0)
		var second := arena.add_imp(Vector2(60.0, 3.0), 1000.0)
		arena.projectiles.set_target_owner(first, 1)
		arena.projectiles.set_target_owner(second, 2)
		for player in 3:
			arena.place_caster(player, Vector2.ZERO)
		arena.install_cards(1, 0, ["frost", "bolt"])
		arena.install_cards(2, 0, ["fire", "bolt"])
		arena.install_cards(0, 0, ["relay", "pierce", "bolt"])
		check(arena.cast(1, 0, Vector2.DOWN) and arena.cast(2, 0, Vector2.DOWN), "the donors cast")
		arena.run(0.1)
		var before: int = arena.statuses.size()
		var reacted: int = arena.reactions.size()
		check(arena.cast(0, 0), "the relay bolt is cast")
		arena.run(1.0)
		# Each donor's statuses and reactions from the relay bolt (a reaction by where it was).
		var seen: Array = []
		for k in range(before, arena.statuses.size()):
			var row: Array = arena.statuses[k]
			if row[0] == 0:
				seen.append([[first, second].find(row[1]), row[2]])
		for k in range(reacted, arena.reactions.size()):
			var row: Array = arena.reactions[k]
			if row[0] == 0:
				seen.append([0 if (row[2] as Vector2).y < 0.0 else 1, row[1]])
		records.append(seen)
		arena.free_all()
	var label: String = str(records[0])
	check(records[0].size() >= 2, "the relay bolt put statuses on the donors: %s" % label)
	var on_first: Array = []
	var on_second: Array = []
	for row: Array in records[0]:
		(on_first if row[0] == 0 else on_second).append(row[1])
	check(on_first.size() < on_second.size() or on_second.size() < on_first.size(), "one donor's hit had one element, the other's both: %s" % label)
	check_equal(records[1], records[0], "batched, each hit read its profile as when sent at once")


## The real Spells and Combat, a crowd under a stream of bolts that kills its front rows: every body
## takes the same damage, from as many hits, and the same bodies die, with the hits batched or sent
## one by one. Batched, some hits are lost (two shots on a body in one step, the first killing it),
## and their shots go on to the rows behind.
func test_a_dying_crowd_takes_the_same_damage_batched() -> void:
	var by_mode: Array = []
	for native: bool in _modes():
		for batched: bool in [false, true]:
			var lost: Array[int] = [0]
			by_mode.append(_crowd_damage(native, batched, lost))
			if batched:
				check(lost[0] > 0, "native %s: hits were lost in the batches (%d)" % [native, lost[0]])
	var kills: int = int((by_mode[0] as Dictionary)["kills"])
	check(kills > 5 and kills < CROWD_BODIES, "some bodies died and some lived (%d of %d died)" % [kills, CROWD_BODIES])
	for i in range(1, by_mode.size()):
		check_equal(by_mode[i], by_mode[0], "run %d: the same damage from as many hits on every body, and the same kills" % i)


const CROWD_BODIES: int = 30


## Each body's damage taken and hits, and the kills: a stream of plain bolts (4 damage) for 40 steps
## through rows of bodies of 24 health, a third of the bolts piercing two. `lost` counts the lost hits.
func _crowd_damage(native: bool, batched: bool, lost: Array[int]) -> Dictionary:
	var bus := EventsScript.new()
	var table := ActorSeats.table()
	var mgr := ManagerScript.new()
	mgr.actors = table
	mgr.events = bus
	mgr.set_native(native)
	mgr.set_cap(2048)
	mgr.set_bounds(Rect2(-100.0, -300.0, 900.0, 600.0))
	mgr.batch_hits = batched
	var fake := FakeRegistry.new()
	var bolt := FormBase.new()
	bolt.id = &"bolt"
	bolt.base_damage = 4
	bolt.speed = 300.0
	bolt.lifetime = 2.0
	fake.items[&"bolt"] = bolt
	var spells := SpellsScript.new()
	spells.registry = fake
	spells.bind(mgr, bus)
	var combat := CombatScript.new()
	combat.events = bus
	combat.projectiles = mgr
	combat.spells = spells
	combat._ready()
	var caster: int = (table as ActorSeats.ActorsScript).actor_of_seat(0)
	var tag: int = StaffKit.build(spells, caster, 0, [&"bolt"] as Array[StringName])
	var bodies: Array[Node2D] = []
	for i in CROWD_BODIES:
		var body := Node2D.new()
		body.position = Vector2(120.0 + 40.0 * float(i % 10), -60.0 + 40.0 * float(i / 10) + float(i % 3) * 3.0)
		root.add_child(body)
		combat.register_actor(body, 24.0, 8.0)
		bodies.append(body)
	var taken: Dictionary = {}
	var hits: Dictionary = {}
	var kills: Array[int] = [0]
	bus.damage_dealt.connect(func(_by: int, target: Node, amount: float, _at: Vector2) -> void:
		var i: int = bodies.find(target as Node2D)
		taken[i] = float(taken.get(i, 0.0)) + amount
		hits[i] = int(hits.get(i, 0)) + 1)
	bus.kill_landed.connect(func(_by: int, _target: Node, _at: Vector2, _tag: int, _shot: int) -> void: kills[0] += 1)
	bus.projectile_hits.connect(func(batch: HitBatch, phase: int) -> void:
		if phase == HitBatch.PHASE_SPELLS:
			for i in batch.count:
				lost[0] += batch.lost[i])
	var fired: int = 0
	for step in 150:
		if step < 40:
			for k in 6:
				var aim := Vector2(1.0, (float((fired * 7) % 13) - 6.0) * 0.05).normalized()
				mgr.spawn(caster, Vector2(0.0, -60.0 + float((fired * 11) % 100)), aim * 300.0, 2.0, 3.0, ManagerScript.LAYER_ENEMY, 2 if fired % 3 == 0 else 0, tag)
				fired += 1
		mgr.step(DT)
		spells.step(DT)
		combat.step(DT)
	var result: Dictionary = {"damage": taken, "hits": hits, "kills": kills[0]}
	for body in bodies:
		if is_instance_valid(body):
			body.free()
	combat.free()
	spells.free()
	fake.free()
	mgr.free()
	table.free()
	bus.free()
	return result


func _all_alike(results: Array) -> void:
	for i in range(1, results.size()):
		check_equal(results[i], results[0], "run %d hit as the first did (GDScript and native, batched or not)" % i)


## GDScript, and the native kernel when the module is built.
func _modes() -> Array[bool]:
	var probe := ManagerScript.new()
	probe.set_native(true)
	var native: bool = probe.is_native()
	probe.free()
	return [false, true] if native else [false]


func _scene(native: bool, batched: bool) -> Scene:
	var scene := Scene.new()
	scene.bus = EventsScript.new()
	scene.table = ActorSeats.table()
	scene.mgr = ManagerScript.new()
	scene.mgr.actors = scene.table
	scene.mgr.events = scene.bus
	scene.mgr.set_native(native)
	scene.mgr.set_cap(256)
	scene.mgr.set_bounds(Rect2(-400.0, -400.0, 800.0, 800.0))
	scene.mgr.batch_hits = batched
	scene.bus.projectile_hit.connect(scene.on_hit)
	scene.bus.projectile_hits.connect(scene.on_hits)
	return scene


func _body(scene: Scene, at: Vector2, radius: float, health: int) -> void:
	var body := Node2D.new()
	root.add_child(body)
	body.global_position = at
	scene.mgr.add_target(body, radius)
	scene.bodies.append(body)
	scene.health[body] = health


func _caster(scene: Scene) -> int:
	return (scene.table as ActorSeats.ActorsScript).actor_of_seat(0)


func _label(scene: Scene) -> String:
	return "%s%s" % ["native" if scene.mgr.is_native() else "GDScript", ", batched" if scene.mgr.batch_hits else ""]


func _free(scene: Scene) -> void:
	for body in scene.bodies:
		body.free()
	scene.mgr.free()
	scene.table.free()
	scene.bus.free()
