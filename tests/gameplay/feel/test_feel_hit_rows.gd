extends "res://tests/support/suite.gd"
## Feel's hit, damage and death looks read from the projectile manager's hit table once a drawn
## frame (perf plan H2): the events of a row (`HitTable.told`) are left to the rows, which Feel
## shows at its step's start as their events showed before, in the order sent, every tick's since
## the last step, with what each row took from its body while it was there (a killed body is gone
## by the frame). A hand-sent event (no row) is still shown at once. The rows are written here as
## the manager and Combat write them: each row, then its events while it is told.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const DT: float = 1.0 / 60.0
## A drawn frame short enough that nothing shown in it ends.
const FRAME: float = 0.001

var bus: EventsScript
var feel: FeelScript
var mgr: ManagerScript
var actors: ActorSeats.ActorsScript


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.events = bus
	mgr.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	feel = own(FeelScript.new()) as FeelScript
	var preset := FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	feel.actors = actors
	feel.drive_engine = false
	feel.preset = preset
	feel.projectiles = mgr
	root.add_child(feel)


## An enemy of its own colour, an actor of the enemy ramp, not owned (a test frees it).
func _enemy(at: Vector2, colour: Color) -> Actor:
	var enemy := Actor.new()
	enemy.data = EnemyBase.new()
	enemy.data.hit_color = colour
	enemy.id = ActorSeats.enemy(actors)
	root.add_child(enemy)
	enemy.global_position = at
	return enemy


## A shot's hit on `target` as the manager and Combat send it: its row and impact, then its damage's
## row and events.
func _hit(caster: int, target: Actor, at: Vector2, way: Vector2, damage: float) -> void:
	var table: HitTable = mgr.hit_table
	table.told = table.write(caster, target, at, way, 0, -1, 1, &"", 0, Color.WHITE, 0)
	bus.projectile_impact.emit(caster, target, at, way)
	table.told = table.write_damage(caster, target, target.id, target.global_position, damage, &"shot", -1, &"", target.data.hit_color)
	bus.hit_landed.emit(caster, target, damage, target.global_position, &"shot", -1, &"")
	bus.damage_dealt.emit(caster, target, damage, target.global_position)
	table.told = -1


## Its death as Combat sends it: its row, then `enemy_died` while it is told.
func _death(killer: int, enemy: Actor) -> void:
	var table: HitTable = mgr.hit_table
	table.told = table.write_death(killer, enemy, enemy.global_position, -1, Color.WHITE, 0, enemy.data.hit_color)
	bus.enemy_died.emit(killer, enemy, enemy.global_position, -1)
	table.told = -1


func test_a_row_s_hit_shows_at_the_step_as_its_events_did() -> void:
	var enemy: Actor = _enemy(Vector2(100.0, 50.0), Color("3b9bd9"))
	_hit(0, enemy, Vector2(92.0, 50.0), Vector2.RIGHT, 5.0)
	check_equal(feel.flashes_of(&"spray"), 0, "nothing in the tick")
	feel.step(FRAME)
	check_equal(feel.flashes_of(&"spray"), 1, "one spray at the step")
	var spray: Dictionary = feel.flash_info(&"spray")
	check((spray["dir"] as Vector2).is_equal_approx(Vector2.RIGHT), "along the shot")
	check((spray["at"] as Vector2).is_equal_approx(Vector2(92.0, 50.0)), "from the point it struck")
	check_equal(spray["core"], Color("3b9bd9"), "in the body's own colour")
	check_equal(mgr.hit_table.rows, 0, "the rows forgotten once read")
	check(mgr.hit_table.held, "and kept for Feel from tick to tick")
	enemy.free()


func test_a_killed_body_s_look_shows_after_it_is_gone() -> void:
	var enemy: Actor = _enemy(Vector2(100.0, 50.0), Color("3b9bd9"))
	_hit(0, enemy, Vector2(92.0, 50.0), Vector2.RIGHT, 5.0)
	_death(0, enemy)
	# The tick frees the dead body before the frame is drawn.
	enemy.free()
	feel.step(FRAME)
	check_equal(feel.flashes_of(&"spray"), 1, "the killing hit's spray")
	check_equal(feel.flash_info(&"spray")["core"], Color("3b9bd9"), "in the body's own colour, though it is gone")
	check_equal(feel.flashes_of(&"puff"), 1, "the death cue's puff")
	check_equal(feel.flash_info(&"puff")["core"], Color("3b9bd9"), "in its colour too")
	check((feel.flash_info(&"puff")["at"] as Vector2).is_equal_approx(Vector2(100.0, 50.0)), "at the body")


func test_a_wall_row_lands_in_its_caster_s_ramp() -> void:
	for player in 4:
		var slot: int = mgr.spawn(player, Vector2(10.0 + 40.0 * float(player), 100.0), Vector2(0.0, -60.0), 5.0)
		mgr._emit_wall_impact(slot, Vector2(0.0, -60.0))
	for player in 4:
		check_equal(feel.flashes_of(&"burst", player), 0, "nothing in the tick")
	feel.step(FRAME)
	for player in 4:
		check_equal(feel.flashes_of(&"burst", player), 1, "player %d's burst at the step, in its hat ramp" % player)


func test_every_tick_s_rows_show_at_the_next_frame() -> void:
	var a: Actor = _enemy(Vector2(100.0, 50.0), Color.RED)
	var b: Actor = _enemy(Vector2(300.0, 50.0), Color.BLUE)
	_hit(0, a, Vector2(92.0, 50.0), Vector2.RIGHT, 5.0)
	# A frame that runs two ticks: the second tick begins before Feel reads.
	mgr.step(DT)
	_hit(1, b, Vector2(308.0, 50.0), Vector2.LEFT, 5.0)
	check_equal(mgr.hit_table.rows, 4, "both ticks' rows kept for the frame")
	feel.step(FRAME)
	check_equal(feel.flashes_of(&"spray"), 2, "both hits sprayed")
	a.free()
	b.free()


func test_a_hand_sent_hit_still_shows_at_once() -> void:
	var enemy: Actor = _enemy(Vector2(100.0, 50.0), Color.RED)
	bus.projectile_impact.emit(0, enemy, Vector2(92.0, 50.0), Vector2.RIGHT)
	bus.damage_dealt.emit(0, enemy, 5, enemy.global_position)
	check_equal(feel.flashes_of(&"spray"), 1, "no row stands for it: shown as it is heard")
	enemy.free()
