extends SceneTree
## The exactness test of the projectile step (shots stepped by behaviour, 2026-10-28): one busy,
## mixed scene stepped by hand, compared line by line with a recording of what the step did before
## it was split into passes (`fixtures/projectile_step/expected.json`, recorded on main c900bd4;
## recorded again 2026-10-29 when a piercing shot came to hit every target it passes in a step, and
## a target again after it has left it, owner's rule: the first change is a slow shot that pushes a
## target ahead of it and hits it again when it catches up; and again when the moves on a shot came
## to add up, rules R1e: the shots do the same, only the state line now shows the moves under way,
## added up, where it showed a finished move's stale numbers).
##
## The scene has every behaviour the manager knows: plain shots that pierce, homing shots (their
## searches included), orbit shots round wizards and round other shots (in lower and higher slots),
## returning shots (to a wizard and to a shot), spiral, linger, growth, sticky, shield, self-hit,
## bounce, ghost, still runes, a card's moves (a homing dash, a recoil, a blink), shots that leave
## the bounds, an anchor that is cleared, the cap dropping shots, and a crowd dense enough that the
## hit-work budget runs out and the next step resumes. Hit and expiry handlers spawn more shots,
## push the target they hit (so a stuck shot follows), and take some targets away after their twelfth hit,
## as `gameplay/combat` and the spell runtime do. Nothing is random.
##
## What is compared, step by step: every event in the order it was sent (`projectile_hit`,
## `projectile_impact`, `projectile_expired` with its wall flag, `shot_blocked`, `shot_ended`, with
## positions written in full float precision) and every live shot's state after the step
## (position, previous position, velocity, life, radius, pierce, flags, the newest point of its
## trail and more) with the manager's counters. The recording keeps one line a step: the number of
## events and hits, the live shots, and a digest of all of it. A changed number anywhere fails the
## test at the first step that differs.
##
## A change that is meant to change what shots do records the scene again and says why in its PR:
##     godot --headless --path . --script res://tests/core/test_projectiles_step_exact.gd -- --record
## prints the new JSON (between the RECORD lines) to paste into the fixture. `-- --full` prints the
## events and states in place of the digests: run it on both versions and diff the two to see
## what changed.
##
## godot --headless --path . --script res://tests/core/test_projectiles_step_exact.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const EXPECTED_PATH: String = "res://tests/core/fixtures/projectile_step/expected.json"
const DT: float = 1.0 / 60.0
const STEPS: int = 90
const ROOM: Vector2 = Vector2(640.0, 360.0)
const CROWD: Vector2 = Vector2(330.0, 170.0)
## Tags: what a handler does when a shot with it hits or expires.
const TAG_PLAIN: int = 1
const TAG_SPLITS: int = 2
const TAG_CHILD: int = 3
const TAG_KIT: int = 4
const TAG_ENEMY: int = 5

var _failures: Array[String] = []
var _bus: EventsScript
var _mgr: ManagerScript
var _table: ActorSeats.ActorsScript
var _imp: int = -1
var _wizards: Array[Node2D] = []
var _targets: Array[Node2D] = []
var _hits_on: Dictionary = {}
var _children: int = 0
## One line per step (see `_log_step`), and the events of the step being run.
var _log: PackedStringArray = PackedStringArray()
var _events: PackedStringArray = PackedStringArray()
var _full: bool = false


func _initialize() -> void:
	await process_frame
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_full = args.has("--full")
	_run_scene()
	if args.has("--record") or _full:
		if _full:
			print("\n".join(_log))
		else:
			print("RECORD BEGIN")
			print(JSON.stringify({"lines": _log}, "\t"))
			print("RECORD END")
		_teardown()
		quit(0)
		return
	_compare()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: core/projectiles step exactness")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _compare() -> void:
	var file: FileAccess = FileAccess.open(EXPECTED_PATH, FileAccess.READ)
	if file == null:
		_failures.append("no recording at " + EXPECTED_PATH)
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or not (data as Dictionary).get("lines") is Array:
		_failures.append("the recording is not {\"lines\": [...]}")
		return
	var expected: Array = (data as Dictionary)["lines"]
	_check(_log.size() == STEPS, "a line for every step (%d)" % _log.size())
	for i in mini(expected.size(), _log.size()):
		if str(expected[i]) != _log[i]:
			_failures.append("step %d differs (run with -- --full on both versions and diff):\n  expected %s\n  got      %s" % [i, expected[i], _log[i]])
			return
	_check(expected.size() == _log.size(), "as many lines as recorded (%d, recorded %d)" % [_log.size(), expected.size()])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _teardown() -> void:
	for node in _targets + _wizards:
		if is_instance_valid(node):
			node.free()
	_targets.clear()
	_wizards.clear()
	for node: Node in [_mgr, _bus, _table]:
		if node != null and is_instance_valid(node):
			node.free()


func _f(value: float) -> String:
	return var_to_str(value)


func _v(value: Vector2) -> String:
	return var_to_str(value)


func _name_of(node: Variant) -> String:
	if node == null:
		return "wall"
	if not is_instance_valid(node):
		return "freed"
	return (node as Node).name


func _run_scene() -> void:
	_bus = EventsScript.new()
	_mgr = ManagerScript.new()
	_table = ActorSeats.table()
	_imp = ActorSeats.enemy(_table)
	_mgr.actors = _table
	_mgr.events = _bus
	_mgr.set_cap(700)
	_mgr.set_bounds(Rect2(Vector2.ZERO, ROOM))
	var walls: Array[Rect2] = [
		Rect2(0, 0, 640, 32), Rect2(0, 328, 640, 32), Rect2(0, 0, 32, 360), Rect2(608, 0, 16, 120),
		Rect2(160, 128, 32, 32), Rect2(448, 128, 32, 32), Rect2(160, 224, 32, 32), Rect2(448, 240, 32, 32),
	]
	_mgr.set_walls(walls)
	# Thirty enemies packed round the crowd's centre (some owned by the imp actor, so its shots
	# skip them), and the four wizards' bodies.
	for i in 30:
		var at: Vector2 = CROWD + Vector2(float(i % 6) * 14.0 - 35.0, float(i / 6) * 14.0 - 28.0)
		var owner: int = _imp if i % 7 == 0 else EventsScript.NO_PLAYER
		_targets.append(_add_body("enemy%d" % i, at, 9.0 + float(i % 3), ManagerScript.LAYER_ENEMY, owner))
	for seat in 4:
		_wizards.append(_add_body("wizard%d" % seat, Vector2(120.0 + float(seat) * 120.0, 290.0), 8.0, ManagerScript.LAYER_PLAYER, seat))
	_bus.projectile_hit.connect(_on_hit)
	_bus.projectile_impact.connect(_on_impact)
	_bus.projectile_expired.connect(_on_expired)
	_bus.shot_blocked.connect(_on_blocked)
	_mgr.shot_ended.connect(_on_ended)
	for step in STEPS:
		_place_wizards(step)
		if step == 0:
			_spawn_kit()
		if step % 10 == 0:
			_spawn_wave(step)
		if step == 30 or step == 32:
			_spawn_flood()
		if step == 50:
			_mgr.clear_anchor(3)
		_events.clear()
		_mgr.step(DT)
		_log_step(step)


func _add_body(name: String, at: Vector2, radius: float, layer: int, owner: int) -> Node2D:
	var node := Node2D.new()
	node.name = name
	root.add_child(node)
	node.global_position = at
	_mgr.add_target(node, radius, layer, owner)
	return node


## The wizards walk in small circles and tell the manager where they are, as bodies do.
func _place_wizards(step: int) -> void:
	for seat in 4:
		var node: Node2D = _wizards[seat]
		if seat == 3 and step >= 50:
			continue
		node.global_position = Vector2(120.0 + float(seat) * 120.0, 290.0) + Vector2.from_angle(float(step) * 0.1 + float(seat)) * 12.0
		_mgr.set_anchor(seat, node.global_position)


## Plain shots from the four wizards and the imp, fanned out, some piercing, some leaving the room.
func _spawn_wave(step: int) -> void:
	for i in 40:
		var caster: int = _imp if i % 5 == 4 else i % 4
		var from: Vector2 = Vector2(120.0 + float(i % 4) * 120.0, 280.0) if caster != _imp else CROWD + Vector2(0.0, -100.0)
		var angle: float = -PI * 0.5 + (float(i) - 20.0) * 0.06 + float(step) * 0.01
		var speed: float = 90.0 + float(i % 6) * 60.0
		var tag: int = TAG_SPLITS if i % 9 == 0 else (TAG_ENEMY if caster == _imp else TAG_PLAIN)
		_mgr.spawn(caster, from, Vector2.from_angle(angle) * speed, 0.6 + float(i % 5) * 0.3, 3.0 + float(i % 3), ManagerScript.LAYER_ENEMY, i % 4, tag)


## A flood of piercing shots inside the crowd: enough hit work to spend the step's budget.
func _spawn_flood() -> void:
	for i in 420:
		var at: Vector2 = CROWD + Vector2(float(i * 37 % 80) - 40.0, float(i * 53 % 80) - 40.0)
		_mgr.spawn(i % 4, at, Vector2.from_angle(float(i) * 0.7) * (40.0 + float(i % 4) * 15.0), 0.4, 4.0, ManagerScript.LAYER_ENEMY, 1000, TAG_PLAIN)


## One or more shots with each behaviour of the kit.
func _spawn_kit() -> void:
	var m: ManagerScript = _mgr
	var low: int = m.spawn(0, Vector2(100.0, 200.0), Vector2(70.0, -20.0), 1.4, 4.0, ManagerScript.LAYER_ENEMY, 50, TAG_KIT)
	# Homing shots, in and out of reach of the crowd.
	for i in 12:
		var s: int = m.spawn(i % 4, Vector2(80.0 + float(i) * 40.0, 300.0), Vector2.from_angle(-PI * 0.5 + float(i - 6) * 0.2) * 160.0, 1.3, 4.0, ManagerScript.LAYER_ENEMY, i % 3, TAG_SPLITS if i % 4 == 0 else TAG_KIT)
		m.set_homing(s, 3.0, 160.0 if i % 2 == 0 else 60.0)
	# Orbit shots round the wizards (wizard 3's anchor is cleared at step 50).
	for i in 8:
		m.spawn_orbit(i % 4, 24.0 + float(i) * 3.0, float(i) * 0.8, 2.5 if i % 2 == 0 else -3.0, 1.4, 4.0, ManagerScript.LAYER_ENEMY, 1000, TAG_KIT)
	# Returning shots: to the wizard, with a spiral, with homing, with linger.
	for i in 4:
		var s: int = m.spawn(i, Vector2(140.0 + float(i) * 110.0, 270.0), Vector2.from_angle(-PI * 0.5 + float(i - 2) * 0.3) * 200.0, 1.2, 4.0, ManagerScript.LAYER_ENEMY, 5, TAG_KIT)
		m.set_return(s)
		if i == 1:
			m.set_spiral(s, 12.0)
		if i == 2:
			m.set_homing(s, 2.0, 120.0)
		if i == 3:
			m.set_linger(s, 0.2)
	# Spiral, linger, growth, sticky, self-hit, bounce and ghost shots.
	for i in 6:
		var from: Vector2 = Vector2(60.0 + float(i) * 90.0, 250.0)
		var s: int = m.spawn(i % 4, from, Vector2.from_angle(-PI * 0.5 + float(i - 3) * 0.25) * (150.0 + float(i) * 20.0), 1.4, 3.0, ManagerScript.LAYER_ENEMY, i % 2, TAG_KIT)
		match i % 3:
			0:
				m.set_spiral(s, 10.0 + float(i))
				m.set_growth(s, 1.8)
			1:
				m.set_linger(s, 0.25)
				m.set_bounce(s, 2)
			2:
				m.set_sticky(s, 0.5)
				m.set_ghost(s)
	for i in 6:
		var s: int = m.spawn(i % 4, Vector2(300.0 + float(i) * 20.0, 100.0), Vector2.from_angle(float(i) * 1.1) * 380.0, 1.5, 3.0, ManagerScript.LAYER_ENEMY, 1, TAG_KIT)
		m.set_bounce(s, 3)
		if i % 2 == 0:
			m.set_growth(s, 1.5)
		if i == 3:
			m.set_sticky(s, 0.3)
	for i in 3:
		var s: int = m.spawn(i, _wizards[i].global_position, Vector2(0.0, -40.0), 1.0, 4.0, ManagerScript.LAYER_ENEMY, 2, TAG_KIT)
		m.set_self_hit(s)
		m.move_shot(s, Vector2(0.0, 60.0), 0.4)
	# Shields of the wizards, and the imp's shots that run into them.
	for i in 3:
		var s: int = m.spawn(i, Vector2(200.0 + float(i) * 100.0, 230.0), Vector2(0.0, -30.0), 1.5, 8.0, ManagerScript.LAYER_ENEMY, 0, TAG_KIT)
		m.set_shield(s, 2)
	for i in 9:
		m.spawn(_imp, Vector2(200.0 + float(i % 3) * 100.0, 130.0 + float(i / 3) * 8.0), Vector2(0.0, 160.0), 1.2, 3.0, ManagerScript.LAYER_PLAYER, 0, TAG_ENEMY)
	# Still runes in the crowd and beside it.
	for i in 4:
		m.spawn(i, CROWD + Vector2(float(i) * 30.0 - 45.0, 40.0), Vector2.ZERO, 0.9, 12.0, ManagerScript.LAYER_ENEMY, 3, TAG_KIT, ManagerScript.MOTION_STILL)
	# A card's moves: a homing dash, a recoil and a blink.
	for i in 3:
		var s: int = m.spawn(i, Vector2(240.0 + float(i) * 60.0, 300.0), Vector2(0.0, -90.0), 1.4, 4.0, ManagerScript.LAYER_ENEMY, 2, TAG_KIT)
		match i:
			0:
				m.move_shot(s, Vector2(0.0, -150.0), 0.5, 4.0, 150.0)
			1:
				m.move_shot(s, Vector2(40.0, 30.0), 0.3)
			2:
				m.move_shot(s, Vector2(10.0, -80.0), 0.0)
	# Shots cast by shots: orbits and a return round a carrier in a lower slot and in a higher one.
	var high: int = m.spawn(1, Vector2(500.0, 220.0), Vector2(-60.0, -15.0), 1.4, 4.0, ManagerScript.LAYER_ENEMY, 50, TAG_KIT)
	for carrier: int in [low, high]:
		var around: Vector2 = m.get_position_of(carrier)
		var o: int = m.spawn_orbit(2, 18.0, 0.5, 4.0, 1.2, 4.0, ManagerScript.LAYER_ENEMY, 1000, TAG_KIT, around)
		m.set_caster_shot(o, carrier)
		var r: int = m.spawn(3, around + Vector2(5.0, 0.0), Vector2(90.0, 40.0), 0.8, 4.0, ManagerScript.LAYER_ENEMY, 5, TAG_KIT)
		m.set_return(r)
		m.set_caster_shot(r, carrier)


func _on_hit(caster: int, target: Node, position: Vector2, tag: int) -> void:
	var slot: int = _mgr.event_slot
	_events.append("hit c%d %s %s t%d slot%d seq%d v%s g%s" % [caster, _name_of(target), _v(position), tag, slot, _mgr.get_seq_of(slot), _v(_mgr.get_velocity_of(slot)), _f(_mgr.get_growth_of(slot))])
	# Combat pushes what it hits a little (a stuck shot rides along), and some enemies are gone
	# after their twelfth hit.
	var node := target as Node2D
	if node != null and is_instance_valid(node):
		node.global_position += position.direction_to(node.global_position) * 1.5
		var count: int = int(_hits_on.get(node.name, 0)) + 1
		_hits_on[node.name] = count
		if count == 12 and node.name.begins_with("enemy") and (node.name.ends_with("0") or node.name.ends_with("5")):
			_mgr.remove_target(node)
	if tag == TAG_SPLITS and _children < 120:
		# A payload: two children from the hit point that skip the target for a moment.
		for k in 2:
			_children += 1
			var child: int = _mgr.spawn(caster, position, Vector2.from_angle(float(_children) * 2.3) * 140.0, 0.5, 3.0, ManagerScript.LAYER_ENEMY, 0, TAG_CHILD)
			_mgr.exclude(child, target, 0.1)
			_events.append("  child slot%d" % child)


func _on_impact(caster: int, target: Node, position: Vector2, direction: Vector2) -> void:
	_events.append("impact c%d %s %s %s %s" % [caster, _name_of(target), _v(position), _v(direction), _mgr.impact_form])


func _on_expired(caster: int, position: Vector2, tag: int) -> void:
	var slot: int = _mgr.event_slot
	_events.append("expired c%d %s t%d slot%d wall%s h%s" % [caster, _v(position), tag, slot, _mgr.expired_on_wall, _v(_mgr.impact_heading)])
	if tag == TAG_SPLITS and _children < 120:
		_children += 1
		var child: int = _mgr.spawn(caster, position, Vector2.from_angle(float(_children)) * 120.0, 0.5, 3.0, ManagerScript.LAYER_ENEMY, 1, TAG_CHILD)
		_events.append("  child slot%d" % child)


func _on_blocked(caster: int, position: Vector2, tag: int) -> void:
	_events.append("blocked c%d %s t%d slot%d" % [caster, _v(position), tag, _mgr.event_slot])


func _on_ended(tag: int) -> void:
	_events.append("ended t%d" % tag)


## The seconds left of the moves under way of the shot in `slot`, added up (0 for none).
func _moves_left(slot: int) -> float:
	var total: float = 0.0
	var at: int = _mgr._move_head[slot]
	while at >= 0:
		total += _mgr._move_left[at]
		at = _mgr._move_next[at]
	return total


## The velocity the moves under way of the shot in `slot` add, added up.
func _moves_velocity(slot: int) -> Vector2:
	var total: Vector2 = Vector2.ZERO
	var at: int = _mgr._move_head[slot]
	while at >= 0:
		total += _mgr._move_vel[at]
		at = _mgr._move_next[at]
	return total


## The step's line: how many events it sent and a digest of them and of every live shot's state and
## the counters (with `--full`, all of that in full instead).
func _log_step(step: int) -> void:
	var m: ManagerScript = _mgr
	var parts: PackedStringArray = PackedStringArray()
	parts.append("count %d dropped %d walls %d work %d resume %d high %d trails %d" % [m.get_count(), m.dropped, m.wall_hits, m._work_left, m._resume, m._high, m.get_trail_count()])
	for slot in m._high:
		if not m.is_alive(slot):
			continue
		var row: int = m.get_trail_of(slot)
		var newest: Vector4 = m.get_trail_point(row, 0) if row >= 0 else Vector4.ZERO
		parts.append("%d seq%d p%s q%s v%s l%s r%s pi%d f%d b%d sh%d h%s ha%s ht%d c%s ml%s mv%s tr%d k%d n%s" % [
			slot, m.get_seq_of(slot), _v(m._pos[slot]), _v(m._prev[slot]), _v(m._vel[slot]), _f(m._life[slot]),
			_f(m._radius[slot]), m._pierce[slot], m._flags[slot], m._bounce[slot], m._shield[slot],
			_f(m._hold[slot]), _v(m._home_at[slot]), int(m._home_target[slot] != 0), _v(m._caster_at[slot]),
			_f(_moves_left(slot)), _v(_moves_velocity(slot)), int(row >= 0), m.get_trail_kept(row), var_to_str(newest)])
	var events: String = "\n".join(_events)
	var state: String = "\n".join(parts)
	if _full:
		_log.append("step %d\n%s\n%s" % [step, events, state])
		return
	var hits: int = 0
	for line in _events:
		if line.begins_with("hit "):
			hits += 1
	_log.append("step %d: %d events, %d hits, %d live, %s" % [step, _events.size(), hits, m.get_count(), (events + "\n" + state).md5_text()])
