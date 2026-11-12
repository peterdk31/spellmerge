extends "res://tests/support/suite.gd"
## The barriers' shells (gameplay/feel/barriers.gd; the owner's pick of 2026-11-06, the mote
## shell): combat's `barrier_changed` puts a bubble of `ward` motes round the actor, a run a charge
## as dense on every size of body (a boss's shell is bigger and has more), that follows its body; a block knocks that charge's share off on the
## side the hit came from into the mote pool, the rest closing the gap; the last charge bursts it;
## a barrier that runs out fades, then goes. Played through Feel, as the game does.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_barriers.gd

const BarriersScript := preload("res://gameplay/feel/barriers.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const STEP: float = 1.0 / 60.0
## A wizard's hurt circle (content/wizard/base/wizard.tscn).
const HURT: float = 8.0
const AT: Vector2 = Vector2(100.0, 60.0)
## A wizard's shell's motes a charge.
var _per_charge: int = BarriersScript.motes_per_charge(BarriersScript.shell_radius(HURT))

var _bus: EventsScript
var _feel: FeelScript


func before_each() -> void:
	var registry: RegistryScript = own(RegistryScript.new()) as RegistryScript
	registry.scan()
	_bus = own(EventsScript.new()) as EventsScript
	_feel = own(FeelScript.new()) as FeelScript
	var preset := FeelPresetScript.new()
	preset.hit_sound = &""
	_feel.events = _bus
	_feel.registry = registry
	_feel.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_feel.projectiles = own(ProjectilesScript.new()) as ProjectilesScript
	_feel.drive_engine = false
	_feel.preset = preset
	root.add_child(_feel)
	_feel.projectiles.events = _bus
	_feel.projectiles.actors = _feel.actors
	_feel.projectiles.set_bounds(Rect2(0.0, 0.0, 320.0, 180.0))
	# Seat 0's actor has no body here: its shell follows its anchor.
	_feel.projectiles.set_anchor(0, AT)


func _barriers() -> BarriersScript:
	return _feel.spectacle().barriers


func _run(seconds: float) -> void:
	for i in roundi(seconds / STEP):
		_feel.step(STEP)


func _give(charges: int, seconds: float = 2.0) -> void:
	_bus.barrier_changed.emit(0, charges, seconds, 0, Vector2.ZERO, HURT)


## Both: Feel's frame and the projectile manager's step.
func _run_all(seconds: float) -> void:
	for i in roundi(seconds / STEP):
		_feel.projectiles.step(STEP)
		_feel.step(STEP)


## A shot of seat 0's actor at `at` with `charges` shield charges (still, or flying along `velocity`).
func _shielded_shot(at: Vector2, charges: int, velocity: Vector2 = Vector2.ZERO, radius: float = 3.0, life: float = 5.0) -> int:
	var motion: int = ProjectilesScript.MOTION_STILL if velocity == Vector2.ZERO else ProjectilesScript.MOTION_STRAIGHT
	var slot: int = _feel.projectiles.spawn(0, at, velocity, life, radius, ProjectilesScript.LAYER_ENEMY, 0, 0, motion)
	_feel.projectiles.set_shield(slot, charges)
	return slot


## Where the shell's rows are, as written last frame.
func _points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for row in _barriers().rows_written:
		var data: PackedFloat32Array = _barriers().row_data(row)
		out.append(Vector2(data[MotesScript.ROW_X], data[MotesScript.ROW_Y]))
	return out


func test_a_barrier_is_a_shell_of_motes_round_its_actor() -> void:
	_give(2)
	_run(0.3)
	check_equal(_barriers().rows_written, 2 * _per_charge, "a run of motes a charge")
	var radius: float = BarriersScript.shell_radius(HURT)
	var off: int = 0
	for p in _points():
		if absf(p.distance_to(AT) - radius) > 2.0:
			off += 1
	check_equal(off, 0, "every mote on the shell, %s px round the body" % radius)
	var data: PackedFloat32Array = _barriers().row_data(0)
	var pool: MotesScript = _feel.motes()
	check_equal(roundi(data[MotesScript.ROW_KIND] * MotesScript.KIND_CODE), pool.kind_index(BarriersScript.KIND), "ward motes")
	check_equal(roundi(data[MotesScript.ROW_SOURCE] * MotesScript.SOURCE_CODE), MotesScript.spell_source(_feel.actors.ramp_of(0), 0), "a plain Shield's in its caster's ramp")
	check_equal(data[MotesScript.ROW_VX], 0.0, "standing still on the shell")


func test_the_shell_follows_its_actor() -> void:
	_give(1)
	_run(0.2)
	var to: Vector2 = AT + Vector2(40.0, -20.0)
	_feel.projectiles.set_anchor(0, to)
	_run(STEP * 2.0)
	var sum: Vector2 = Vector2.ZERO
	var points: PackedVector2Array = _points()
	for p in points:
		sum += p
	check(points.size() > 0 and (sum / points.size()).distance_to(to) < 2.0, "the shell is round the body where it moved: %s" % [sum / maxi(points.size(), 1)])


func test_a_block_knocks_its_share_off_where_it_hit_and_the_rest_close_the_gap() -> void:
	_give(2)
	_run(0.3)
	var pool: MotesScript = _feel.motes()
	var before: int = pool.next_row()
	# A hit flying left struck the shell's right side.
	_bus.barrier_changed.emit(0, 1, 1.5, 0, Vector2.LEFT, HURT)
	var thrown: int = pool.next_row() - before
	check_equal(thrown, _per_charge, "that charge's share flies off")
	var right: int = 0
	for row in range(before, before + thrown):
		var data: PackedFloat32Array = pool.row_data(row)
		# Half the shell, the half facing the hit (its ends at the top and bottom, swaying a pixel).
		if data[MotesScript.ROW_X] > AT.x - 2.0:
			right += 1
	check_equal(right, thrown, "from the side the hit came from")
	check_equal(_barriers().motes_of(0), _per_charge, "the rest stay")
	_run(1.0)
	# The gap is closed: the motes are evenly round the shell again.
	var angles: Array[float] = []
	for p in _points():
		angles.append((p - AT).angle())
	angles.sort()
	var even: float = TAU / float(angles.size())
	var widest: float = angles[0] + TAU - angles[-1]
	for i in range(1, angles.size()):
		widest = maxf(widest, angles[i] - angles[i - 1])
	check(widest < even * 2.0, "no gap left: the widest is %.2f rad, even is %.2f" % [widest, even])


func test_the_last_charge_bursts_the_shell() -> void:
	_give(1)
	_run(0.3)
	var pool: MotesScript = _feel.motes()
	var before: int = pool.next_row()
	_bus.barrier_changed.emit(0, 0, 0.0, 0, Vector2.RIGHT, HURT)
	check_equal(pool.next_row() - before, _per_charge, "every mote flies off")
	_run(STEP)
	check_equal(_barriers().rows_written, 0, "the shell is gone")
	check_equal(_barriers().shown, 0, "nothing shown")


func test_a_barrier_that_runs_out_fades_then_goes() -> void:
	_give(1, 0.5)
	_run(0.3)
	var pool: MotesScript = _feel.motes()
	_bus.barrier_changed.emit(0, 0, 0.0, 0, Vector2.ZERO, HURT)
	_run(STEP)
	check_equal(_barriers().shown, 1, "still there while it fades")
	var before: int = pool.next_row()
	_run(BarriersScript.FADE + 0.05)
	check_equal(_barriers().shown, 0, "gone once faded")
	check(pool.next_row() - before > 0, "a few slow motes drift off as it goes")


func test_a_recast_adds_its_charges_to_the_shell() -> void:
	_give(1)
	_run(0.2)
	_give(2)
	_run(0.2)
	check_equal(_barriers().rows_written, 2 * _per_charge, "a run more for the new charge")


func test_a_shell_without_a_body_or_anchor_goes() -> void:
	_give(1)
	_run(0.1)
	_feel.projectiles.clear_anchor(0)
	_run(STEP)
	check_equal(_barriers().shown, 0, "no body, no shell")


func test_a_cast_on_yourself_plays_its_own_cue() -> void:
	check_equal(_feel._form_cues_of(&"pulse")[FeelScript.CUE_CAST], &"cast_self", "a Pulse card's cast cue")
	check_equal(_feel._form_cues_of(&"bolt")[FeelScript.CUE_CAST], (_feel.registry.get_resource(&"spells", &"bolt") as FormBase).cast_cue, "a carrier card's own stays")


## The shell's size and its motes follow the body's: a boss's is wider and has more motes a
## charge, a small thing's is tighter and has fewer, and every one is as dense round its rim.
func test_the_shell_scales_with_the_body() -> void:
	check_equal(_per_charge, 26, "a wizard's: 26 a charge")
	var sizes: Array[float] = [2.0, HURT, 32.0]
	var last_radius: float = 0.0
	var last_count: int = 0
	for hurt in sizes:
		var radius: float = BarriersScript.shell_radius(hurt)
		var count: int = BarriersScript.motes_per_charge(radius)
		check(radius > hurt and radius > last_radius, "a hurt circle of %s: a shell of %s round it, wider than a smaller body's" % [hurt, radius])
		check(count > last_count, "a hurt circle of %s: %d motes a charge, more than a smaller body's" % [hurt, count])
		var spacing: float = TAU * radius / float(count)
		check(count == BarriersScript.FEWEST_PER_CHARGE or absf(spacing - BarriersScript.SPACING) < 0.5, "as dense round its rim: %.2f px apart" % spacing)
		last_radius = radius
		last_count = count
	# Played: a boss's barrier of two charges.
	_bus.barrier_changed.emit(0, 2, 2.0, 0, Vector2.ZERO, 32.0)
	_run(0.3)
	var boss: float = BarriersScript.shell_radius(32.0)
	check_equal(_barriers().rows_written, 2 * BarriersScript.motes_per_charge(boss), "a boss's shell, every mote drawn")
	var off: int = 0
	for p in _points():
		if absf(p.distance_to(AT) - boss) > 2.0:
			off += 1
	check_equal(off, 0, "on its %s px shell" % boss)



# --- Shots with shield charges (the same rule as an actor's barrier) -----------------

func test_a_shielded_shot_has_a_shell_that_follows_it() -> void:
	var slot: int = _shielded_shot(AT, 2, Vector2(60.0, 0.0), 3.0)
	_run_all(0.3)
	var radius: float = BarriersScript.shell_radius(3.0)
	check_equal(_barriers().motes_of_shot(slot), 2 * BarriersScript.motes_per_charge(radius), "a run of motes a charge, as dense as any shell")
	var at: Vector2 = _feel.projectiles.get_position_of(slot)
	var off: int = 0
	for p in _points():
		if absf(p.distance_to(at) - radius) > 2.0:
			off += 1
	check_equal(off, 0, "round the shot where it flies now, %s px out" % radius)


func test_a_shot_s_shield_blocking_knocks_its_share_off_and_the_last_bursts_it() -> void:
	var slot: int = _shielded_shot(AT, 2)
	_run_all(0.2)
	var whole: int = _barriers().motes_of_shot(slot)
	var pool: MotesScript = _feel.motes()
	var before: int = pool.next_row()
	# An enemy shot flying into it from the right.
	var enemy: int = ActorSeats.enemy(_feel.actors)
	_feel.projectiles.spawn(enemy, AT + Vector2(20.0, 0.0), Vector2(-80.0, 0.0), 2.0, 2.0, ProjectilesScript.LAYER_PLAYER)
	_run_all(0.4)
	check_equal(_feel.projectiles.get_shield_of(slot), 1, "one charge spent")
	check_equal(_barriers().motes_of_shot(slot), whole / 2, "its shell lost that charge's share")
	check(pool.next_row() - before >= whole / 2, "and they flew off")
	_feel.projectiles.spawn(enemy, AT + Vector2(-20.0, 0.0), Vector2(80.0, 0.0), 2.0, 2.0, ProjectilesScript.LAYER_PLAYER)
	_run_all(0.4)
	check_equal(_feel.projectiles.get_shield_of(slot), 0, "the last charge spent")
	check_equal(_barriers().shown, 0, "the shell burst")


func test_a_shot_that_ends_with_charges_left_lets_its_shell_fade() -> void:
	var slot: int = _shielded_shot(AT, 1, Vector2.ZERO, 3.0, 0.3)
	_run_all(0.2)
	check_equal(_barriers().shown, 1, "shown while the shot lives")
	_run_all(0.15)
	check(not _feel.projectiles.is_alive(slot), "the shot ended")
	check_equal(_barriers().shown, 1, "its shell fades where it was")
	_run_all(BarriersScript.FADE + 0.05)
	check_equal(_barriers().shown, 0, "then goes")


func test_a_wall_s_shell_is_a_capsule_round_its_row() -> void:
	var slot: int = _shielded_shot(AT, 1, Vector2.ZERO, 3.0)
	check(_feel.projectiles.set_solid(slot, Vector2.UP, 5, 6.0), "a row of five stones, up and down")
	_run_all(0.3)
	var half: Vector2 = _feel.projectiles.get_solid_half_of(slot)
	check(half.length() > 5.0, "a row with length: %s" % half)
	var radius: float = BarriersScript.shell_radius(3.0)
	check_equal(_barriers().motes_of_shot(slot), BarriersScript.motes_per_charge(radius, half.length()), "as dense round its whole rim")
	var off: int = 0
	var tall: float = 0.0
	for p in _points():
		var on: Vector2 = Geometry2D.get_closest_point_to_segment(p, AT - half, AT + half)
		if absf(p.distance_to(on) - radius) > 2.0:
			off += 1
		tall = maxf(tall, absf(p.y - AT.y))
	check_equal(off, 0, "every mote %s px from the row" % radius)
	check(tall > half.length() + radius - 2.0, "round its ends too: %.1f" % tall)
