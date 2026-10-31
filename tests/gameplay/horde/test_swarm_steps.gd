extends "res://tests/support/suite.gd"
## The swarm's step made cheaper (Horde swarm S4, docs/milestones/horde-swarm.md, "S4: scale"): every
## row's local stop, pace and push asked once for all rows (`Actors.spend_holds`,
## `Combat.own_paces_and_pushes`), the move folded into the spacing hash and the push, floor, walls
## and node writes into one pass. It must move every swarmer exactly as before: a scripted crowd
## (mites and husks round four wizards, a wall in the way, hits with knockback, frost bolts that
## chill and freeze, local stops, kills and new swarmers) ends with the very rows and look it ended
## with before the change. The fingerprint below was recorded on the swarm before S4.
##
## godot --headless --path . --script res://tests/gameplay/horde/test_swarm_steps.gd

const Fixture := preload("res://tests/gameplay/horde/swarm_fixture.gd")

## Rows, steps run, and a hash of every row's numbers and of every look value, before S4.
const RECORDED: Array[int] = [160, 90, 802667918, 180775624]
const SWARMERS: int = 160
const STEPS: int = 90
## The stress room's enemy area round the fixture's origin.
const AREA: Rect2 = Rect2(-272.0, -132.0, 544.0, 264.0)

var _run: Fixture = null


func after_each() -> void:
	if _run != null:
		_run.free_all()
	_run = null


func test_a_scripted_crowd_moves_and_looks_as_before() -> void:
	var found: Array[int] = _play()
	check_equal(found, RECORDED, "the rows and the look end as they did before S4")


## The scripted crowd (see the class doc); its fingerprint.
func _play() -> Array[int]:
	_run = Fixture.new(root)
	var look := SwarmLook.new()
	look.real_time = false
	look.setup(_run.swarm)
	_run.horde.add_child(look)
	_run.swarm.look = look
	for seat in 4:
		_run.wizard(Vector2(-60.0 + 120.0 * float(seat % 2), -40.0 + 80.0 * float(seat / 2)), seat)
	_run.wall(Rect2(-150.0, -20.0, 24.0, 90.0))
	_run.swarm.start(_run.horde, AREA)
	var frost: int = _run.tag(_run.wizards[0].id, &"frost")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in SWARMERS:
		_run.swarmer(AREA.position + Vector2(rng.randf() * AREA.size.x, rng.randf() * AREA.size.y), Fixture.MiteData if i % 2 == 0 else Fixture.HuskData)
	var swarm: Swarm = _run.swarm
	for n in STEPS:
		for k in 6:
			var row: int = (n * 37 + k * 101) % swarm.count
			var node: Node2D = swarm.nodes[row]
			if k % 3 == 0:
				_run.bus.projectile_hit.emit(_run.wizards[0].id, node, node.global_position + Vector2(-6.0, 0.0), frost, -1)
			else:
				_run.combat.hit(_run.wizards[1].id, node, 1, Vector2.RIGHT, 120.0)
			if k % 2 == 0:
				_run.actors.hold(swarm.actor_ids[row], 0.05)
		if n % 7 == 0:
			_run.combat.hit(_run.wizards[2].id, swarm.nodes[(n * 13) % swarm.count], 100000)
		swarm.step(1.0 / 60.0)
		look.step_feel(1.0 / 60.0)
		_run.combat.step(1.0 / 60.0)
		_run.projectiles.step(1.0 / 60.0)
		_run.spells.step(1.0 / 60.0)
		while swarm.count < SWARMERS:
			_run.swarmer(AREA.position + Vector2(rng.randf() * AREA.size.x, rng.randf() * AREA.size.y), Fixture.MiteData if swarm.count % 2 == 0 else Fixture.HuskData)
	var rows: Array = []
	for row in swarm.count:
		rows.append([swarm.positions[row], swarm.velocities[row], swarm.aims[row], swarm.hurt_left[row], swarm.ran[row], swarm.kinds[row], swarm.nodes[row].position, look.row_look(row)])
	var batches: Array = []
	for kind in swarm.kinds_list.size():
		var shown: int = look.batch(kind).multimesh.visible_instance_count
		for slot in shown:
			batches.append(look.instance_data(kind, slot))
	_run.horde.remove_child(look)
	look.free()
	return [swarm.count, swarm.moved, hash(var_to_str(rows)), hash(var_to_str(batches))] as Array[int]
