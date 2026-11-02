extends "res://tests/support/suite.gd"
## The swarm's native kernel against its GDScript (native/README.md): two swarms with their looks,
## one with `SwarmKernel` and one without (`Swarm.native`, `SwarmLook.native`), get the same seeded
## crowd and are stepped side by side for ten seconds. After every step each packed array of the
## two swarms and of the two looks must be equal byte for byte, as must the swarmers' node
## positions and every instance their batches hold. `test_swarm_steps.gd` holds both to its
## recording; this runs longer, so the looks' blinks come due, and with the hurt pose's flag on and
## the glancing face style for every kind. A second crowd has no wizard to chase, so it stands (a
## chasing one never does) and its idle habits (glances, raised brows) come due too.
##
## Without the native module the test only says so (SPELLMERGE_NATIVE=required fails it).
##
## godot --headless --path . --script res://tests/gameplay/horde/test_native_swarm.gd

const Fixture := preload("res://tests/gameplay/horde/swarm_fixture.gd")
const NativeScript := preload("res://core/native/native.gd")

const SWARMERS: int = 240
const STEPS: int = 600
const AREA: Rect2 = Rect2(-272.0, -132.0, 544.0, 264.0)
## Not compared: what holds nodes or their instance ids (each side has its own), and a clock reading.
const NOT_COMPARED: Array[StringName] = [&"_node_ids", &"_row_by_node", &"nodes", &"_slot_nodes", &"_cand_nodes", &"_ghost_of", &"_last_usec"]

var _runs: Array[Fixture] = []
var _looks: Array[SwarmLook] = []
## The crowd's size, and whether it stands (no wizards).
var _target: int = 0
var _standing: bool = false


func after_each() -> void:
	for look in _looks:
		if is_instance_valid(look):
			look.get_parent().remove_child(look)
			look.free()
	_looks.clear()
	for run in _runs:
		run.free_all()
	_runs.clear()


func test_the_native_swarm_steps_as_its_gdscript() -> void:
	_side_by_side(SWARMERS, STEPS, false)


func test_a_standing_crowd_idles_alike() -> void:
	_side_by_side(24, 720, true)
	var idled: bool = false
	for row in _runs[0].swarm.count:
		idled = idled or _looks[0]._still_for[row] >= Face.IDLE_AFTER
	check(idled, "swarmers stood long enough to idle")


## Two swarms, native and not, stepped side by side for `steps` and compared after each step:
## `swarmers` of them, spread over the area and kept at that number, round four wizards that hit
## them, or (`standing`) with no wizard at all.
func _side_by_side(swarmers: int, steps: int, standing: bool) -> void:
	if not NativeScript.loaded():
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
		return
	_target = swarmers
	_standing = standing
	for side in 2:
		var run: Fixture = Fixture.new(root)
		run.swarm.native = side == 1
		run.swarm.rng.seed = 11
		var look := SwarmLook.new()
		look.native = side == 1
		look.real_time = false
		look.setup(run.swarm)
		run.horde.add_child(look)
		run.swarm.look = look
		for seat in (0 if standing else 4):
			run.wizard(Vector2(-60.0 + 120.0 * float(seat % 2), -40.0 + 80.0 * float(seat / 2)), seat)
		run.wall(Rect2(-150.0, -20.0, 24.0, 90.0))
		run.swarm.start(run.horde, AREA)
		_runs.append(run)
		_looks.append(look)
	check(_runs[1].swarm._kernel != null and _runs[0].swarm._kernel == null, "one native swarm, one GDScript")
	check(_looks[1]._kernel != null and _looks[0]._kernel == null, "one native look, one GDScript")
	for side in 2:
		_spawn(side, swarmers, 3)
		# Every kind's hurt pose on, so its flag is written too, and the face style that glances and
		# raises its brows (today's strays do neither), so those habits run too.
		_looks[side]._take_kinds()
		_looks[side]._has_hurt.fill(1)
		_looks[side]._style.fill(0)
	for n in steps:
		for side in 2:
			_step(side, n)
		_compare(n)
		if _failures.size() > 6:
			return
	check(_runs[1].swarm.count > swarmers / 2, "the crowd stays (%d)" % _runs[1].swarm.count)


## `count` swarmers of both kinds at seeded places.
func _spawn(side: int, count: int, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var run: Fixture = _runs[side]
	for i in count:
		var at: Vector2 = AREA.position + Vector2(rng.randf() * AREA.size.x, rng.randf() * AREA.size.y)
		run.swarmer(at, Fixture.MiteData if i % 2 == 0 else Fixture.HuskData)


## One step of the scripted crowd: hits, frost that chills and freezes part of it (so swarmers stand
## long enough for their idle habits), local stops, a kill now and then, new swarmers.
func _step(side: int, n: int) -> void:
	var run: Fixture = _runs[side]
	var swarm: Swarm = run.swarm
	if n % 4 == 0 and swarm.count > 0 and not _standing:
		var frost: int = run.tag(run.wizards[0].id, &"frost")
		for k in 24:
			var row: int = (k * 7) % swarm.count
			var node: Node2D = swarm.nodes[row]
			run.bus.projectile_hit.emit(run.wizards[0].id, node, node.global_position + Vector2(-6.0, 0.0), frost, -1)
	if n % 5 == 0 and swarm.count > 0 and not _standing:
		for k in 3:
			var row: int = (n * 37 + k * 101) % swarm.count
			var node: Node2D = swarm.nodes[row]
			run.combat.hit(run.wizards[k].id, node, 1, Vector2.from_angle(float(n + k)), 90.0)
			if k == 0:
				run.actors.hold(swarm.actor_ids[row], 0.05)
	if n % 40 == 0 and swarm.count > 0 and not _standing:
		run.combat.hit(run.wizards[2].id, swarm.nodes[(n * 13) % swarm.count], 100000)
	swarm.step(1.0 / 60.0)
	_looks[side].step_feel(1.0 / 60.0)
	run.combat.step(1.0 / 60.0)
	run.projectiles.step(1.0 / 60.0)
	run.spells.step(1.0 / 60.0)
	if n % 60 == 30 and swarm.count < _target:
		_spawn(side, _target - swarm.count, 100 + n)


func _compare(n: int) -> void:
	for pair: Array in [[_runs[0].swarm, _runs[1].swarm], [_looks[0], _looks[1]]]:
		var a: Object = pair[0]
		var b: Object = pair[1]
		for prop: Dictionary in a.get_property_list():
			var name: StringName = prop["name"]
			var type: int = prop["type"]
			if (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or name in NOT_COMPARED:
				continue
			if type < TYPE_PACKED_BYTE_ARRAY and type != TYPE_INT and type != TYPE_FLOAT:
				continue
			if var_to_bytes(a.get(name)) != var_to_bytes(b.get(name)):
				check(false, "step %d: %s.%s differs" % [n, "SwarmLook" if a is SwarmLook else "Swarm", name])
	var s0: Swarm = _runs[0].swarm
	var s1: Swarm = _runs[1].swarm
	for row in mini(s0.count, s1.count):
		if s0.nodes[row].position != s1.nodes[row].position:
			check(false, "step %d: row %d's node is elsewhere (%s / %s)" % [n, row, s0.nodes[row].position, s1.nodes[row].position])
			break
	for kind in s0.kinds_list.size():
		var shown: int = _looks[0].batch(kind).multimesh.visible_instance_count
		check(shown == _looks[1].batch(kind).multimesh.visible_instance_count, "step %d: kind %d shows as many" % [n, kind])
		for slot in shown:
			if _looks[0].instance_data(kind, slot) != _looks[1].instance_data(kind, slot):
				check(false, "step %d: kind %d instance %d differs" % [n, kind, slot])
				break
