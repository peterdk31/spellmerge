extends "res://tests/support/suite.gd"
## The portal carrier (docs/milestones/portal.md): its gates in the projectile manager, beams that
## go on from every exit, shots that go through (a copy at every further exit), both ways, the jump
## cap, bodies moved and given its infusion's status, and what it does nothing with.
##
## godot --headless --path . --script res://tests/core/test_portal.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const STEP: float = 1.0 / 60.0

var _arena: ArenaScript = null


func after_each() -> void:
	if _arena != null:
		_arena.free_all()
		_arena = null


func _portals() -> CarrierPortal:
	return CarrierPortal.of(_arena.spells)


func _beams() -> CarrierBeam:
	return CarrierBeam.of(_arena.spells)


## The open gates: [mouths, exits].
func _gates() -> Vector2i:
	var counted: Vector2i = Vector2i.ZERO
	var pm: ManagerScript = _arena.projectiles
	for gate in pm.gate_rows():
		if pm.gate_open(gate):
			if pm.gate_is_mouth(gate):
				counted.x += 1
			else:
				counted.y += 1
	return counted


func _live_shots() -> Array[int]:
	var out: Array[int] = []
	for slot in _arena.projectiles._high:
		if _arena.projectiles.is_alive(slot):
			out.append(slot)
	return out


func test_a_gate_is_met_where_a_segment_goes_into_it() -> void:
	var pm := ManagerScript.new()
	var gate: int = pm.open_gate(1, 0, Vector2(100, 0), Vector2.RIGHT, 10.0, true)
	check(gate >= 0 and pm.has_gates(), "a gate opens")
	check(is_equal_approx(pm.gate_cut(Vector2.ZERO, Vector2(200, 0)), 0.45), "a segment through it meets it at its edge (%s)" % pm.gate_cut(Vector2.ZERO, Vector2(200, 0)))
	check_equal(pm.gate_hit, gate, "and says which gate")
	check(pm.gate_cut(Vector2(100, 0), Vector2(200, 0)) < 0.0, "a segment that starts inside is leaving it")
	check(pm.gate_cut(Vector2(0, 20), Vector2(200, 20)) < 0.0, "a segment that passes by misses it")
	pm.close_gate(gate)
	check(not pm.has_gates(), "it closes")
	pm.free()


func test_one_cast_opens_a_mouth_and_its_exits() -> void:
	_arena = ArenaScript.new(root)
	_arena.install_cards(0, 0, ["split", "portal"])
	check(_arena.cast(0, 0), "the portal is cast")
	check_equal(_gates(), Vector2i(1, 3), "one mouth and three exits (split)")
	var pm: ManagerScript = _arena.projectiles
	for gate in pm.gate_rows():
		if pm.gate_open(gate) and pm.gate_is_mouth(gate):
			check(pm.gate_position(gate).x > 0.0 and pm.gate_position(gate).x < 40.0, "the mouth opens a step ahead (%s)" % pm.gate_position(gate))
	_arena.run(4.5)
	check_equal(_gates(), Vector2i.ZERO, "it closes at its life's end")
	check_equal(_portals().portal_count(), 0, "and its row with it")


func test_split_fans_the_exits_each_facing_its_own_way() -> void:
	_arena = ArenaScript.new(root)
	_arena.add_imp(Vector2(150, 0))
	_arena.install_cards(0, 0, ["homing", "split", "portal"])
	check(_arena.cast(0, 0), "the portal is cast")
	var pm: ManagerScript = _arena.projectiles
	var faces: Array[float] = []
	for gate in pm.gate_rows():
		if pm.gate_open(gate) and not pm.gate_is_mouth(gate):
			var at: Vector2 = pm.gate_position(gate)
			check(is_equal_approx(at.length(), 160.0), "an exit opens its reach ahead (%s), homing or not" % at)
			check(pm.gate_face(gate).dot(at.normalized()) > 0.999, "facing out along its own way")
			faces.append(pm.gate_face(gate).angle())
	check_equal(faces.size(), 3, "three exits")
	faces.sort()
	if faces.size() == 3:
		check(faces[0] < -0.1 and absf(faces[1]) < 0.01 and faces[2] > 0.1, "fanned either side of the aim, as a split fans shots: %s" % [faces])


## Homing on a portal steers what comes out of it: a plain bolt through it bends onto an imp off
## its line, which it misses through a portal without homing.
func test_homing_steers_what_comes_out() -> void:
	check(_bolt_through_hits(["homing", "portal"]), "a bolt out of a homing portal finds the imp off its line")
	check(not _bolt_through_hits(["portal"]), "without homing it flies past")


func _bolt_through_hits(portal: Array) -> bool:
	_arena = ArenaScript.new(root)
	var imp: Node2D = _arena.add_imp(Vector2(260, 60))
	_arena.install_cards(0, 0, portal)
	_arena.install_cards(0, 1, ["bolt"])
	_arena.cast(0, 0)
	_arena.run(0.1)
	_arena.cast(0, 1)
	_arena.run(1.4)
	var hit: bool = _arena.lost(imp) > 0
	_arena.free_all()
	_arena = null
	return hit


func test_a_beam_into_the_mouth_goes_on_from_every_exit() -> void:
	_arena = ArenaScript.new(root)
	_arena.install_cards(0, 0, ["split", "portal"])
	_arena.install_cards(0, 1, ["hold", "beam"])
	check(_arena.cast(0, 0), "the portal is cast")
	check(_arena.cast(0, 1), "the beam is cast")
	_arena.run(0.2)
	check_equal(_beams().beam_count(), 4, "the beam and a leg from each of the three exits")


func test_a_beam_leg_out_of_a_homing_frost_portal_bends_onto_a_target_and_chills() -> void:
	_arena = ArenaScript.new(root)
	# Off the beam's line, within the homing card's reach (160) of the exit at (160, 0).
	var imp: Node2D = _arena.add_imp(Vector2(240, 50))
	_arena.install_cards(0, 0, ["frost", "homing", "portal"])
	_arena.install_cards(0, 1, ["beam"])
	check(_arena.cast(0, 0), "the portal is cast")
	check(_arena.cast(0, 1), "the beam is cast")
	_arena.run(0.4)
	check(_arena.lost(imp) > 0, "the leg out of the portal bends onto the imp off its line")
	check(_arena.was_given(imp, &"chill"), "and takes the portal's frost on the way")


func test_beams_through_portals_that_lead_into_each_other_stop_at_the_jump_cap() -> void:
	_arena = ArenaScript.new(root)
	# Player 1's portal faces player 0's: what leaves one exit walks into the other's mouth.
	_arena.place_caster(1, Vector2(300, 0))
	_arena.install_cards(0, 0, ["portal"])
	_arena.install_cards(1, 0, ["portal"])
	_arena.install_cards(0, 1, ["hold", "reach", "reach", "beam"])
	check(_arena.cast(0, 0), "the first portal")
	check(_arena.cast(1, 0, Vector2.LEFT), "the second, facing it")
	check(_arena.cast(0, 1), "the beam")
	_arena.run(0.6)
	check(_beams().beam_count() >= 3, "the beam goes through more than one portal (%d rows)" % _beams().beam_count())
	check(_beams().beam_count() <= 1 + SpellLimits.PORTAL_JUMPS, "and no more than the cap (%d rows)" % _beams().beam_count())


func test_a_shot_into_the_mouth_comes_out_of_every_exit() -> void:
	_arena = ArenaScript.new(root)
	_arena.install_cards(0, 0, ["split", "portal"])
	_arena.install_cards(0, 1, ["bolt"])
	check(_arena.cast(0, 0), "the portal is cast")
	check(_arena.cast(0, 1), "the bolt is cast")
	_arena.run(0.25)
	var shots: Array[int] = _live_shots()
	check_equal(shots.size(), 3, "the bolt and two copies, one out of each exit")
	for slot in shots:
		check(_arena.projectiles.get_position_of(slot).length() > 150.0, "each out past its exit (%s)" % _arena.projectiles.get_position_of(slot))


## A gate is a sphere (owner, 2026-11-05): a shot that hits the mouth from the side, across the
## portal's aim, leaves the exit on its far side still going the way it went.
func test_a_gate_is_a_sphere_what_hits_it_goes_on_the_way_it_went() -> void:
	_arena = ArenaScript.new(root)
	_arena.install_cards(0, 0, ["portal"])
	check(_arena.cast(0, 0), "the portal is cast")
	# An enemy bolt falling straight down onto the mouth at (24, 0).
	_arena.shoot_at(Vector2(24, -100), Vector2(24, 0))
	_arena.run(0.6)
	var through: bool = false
	for slot in _live_shots():
		var at: Vector2 = _arena.projectiles.get_position_of(slot)
		var way: Vector2 = _arena.projectiles.get_velocity_of(slot).normalized()
		if absf(at.x - 160.0) < 2.0 and at.y > 12.0 and way.dot(Vector2.DOWN) > 0.999:
			through = true
	check(through, "the bolt came out under the exit at (160, 0), still falling straight down")


func test_a_shot_into_an_exit_comes_out_of_the_mouth_back_at_its_caster() -> void:
	_arena = ArenaScript.new(root)
	_arena.install_cards(0, 0, ["portal"])
	check(_arena.cast(0, 0), "the portal is cast")
	# An enemy bolt at the exit (160, 0) from further along the aim.
	_arena.shoot_at(Vector2(320, 0), Vector2.ZERO)
	_arena.run(0.8)
	var back: bool = false
	for slot in _live_shots():
		var at: Vector2 = _arena.projectiles.get_position_of(slot)
		if at.x < 24.0 and _arena.projectiles.get_velocity_of(slot).x < 0.0:
			back = true
	check(back, "the enemy's bolt came out of the mouth by the caster, still flying at it, far sooner than it could have flown there")


func test_a_body_in_a_gate_comes_out_of_the_other_side_with_its_status() -> void:
	_arena = ArenaScript.new(root)
	var imp: Node2D = _arena.add_imp(Vector2(160, 0))
	var moves: Array = []
	_arena.bus.target_move_requested.connect(func(_caster: int, target: Node, to: Vector2) -> void: moves.append([target, to]))
	_arena.install_cards(0, 0, ["frost", "portal"])
	check(_arena.cast(0, 0), "the portal is cast")
	_arena.run(0.1)
	check_equal(moves.size(), 1, "the imp standing in the exit is moved once (it rests after)")
	if moves.size() > 0:
		check(moves[0][0] == imp, "the imp")
		check((moves[0][1] as Vector2).x < 80.0, "to the mouth's side (%s)" % moves[0][1])
	check(_arena.was_given(imp, &"chill"), "and the portal's frost chills it, with no hit")
	check_equal(_arena.lost(imp), 0, "it is not hurt")


func test_mend_does_nothing_on_a_portal_but_frost_does() -> void:
	_arena = ArenaScript.new(root)
	var mended: CompiledStaff = _arena.install_cards(0, 0, ["mend", "portal"])
	check(mended.wasted.has(0), "mend has no status to pass on: wasted")
	var frosted: CompiledStaff = _arena.install_cards(0, 1, ["frost", "portal"])
	check(not frosted.wasted.has(0), "frost passes its chill on")
	check(not StaffCompiler.card_works(_arena.registry.call("get_resource", &"spells", &"mend") as SpellComponent, &"portal"), "the builder says so before it is placed")
	check(StaffCompiler.card_works(_arena.registry.call("get_resource", &"spells", &"frost") as SpellComponent, &"portal"), "and that frost works")


func test_the_same_casts_open_the_same_gates() -> void:
	var first: Array = _cast_and_read()
	var second: Array = _cast_and_read()
	check_equal(first, second, "the same casts give the same gates, in the same rows")


func _cast_and_read() -> Array:
	_arena = ArenaScript.new(root)
	_arena.add_imp(Vector2(150, 10))
	_arena.install_cards(0, 0, ["homing", "split", "portal"])
	_arena.cast(0, 0)
	_arena.run(0.3)
	var out: Array = []
	var pm: ManagerScript = _arena.projectiles
	for gate in pm.gate_rows():
		if pm.gate_open(gate):
			out.append([gate, pm.gate_position(gate), pm.gate_face(gate), pm.gate_is_mouth(gate)])
	_arena.free_all()
	_arena = null
	return out
