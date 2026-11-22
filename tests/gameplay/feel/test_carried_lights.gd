extends "res://tests/support/suite.gd"
## Carried lights (docs/milestones/atmosphere.md, A; gameplay/feel/carried_lights.gd): every seat's
## wizard carries a light at its staff tip, in its hat's light shade, dimmer while downed and out
## as it falls; a possessing seat's light goes with the body it drives, in its own hat colour; a
## body no seat drives carries none; every change eases over at least 3 frames (docs/STYLE.md,
## "Smooth"); a frame allocates nothing; and the game's Feel hands the rows to the spell light.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const CarriedLightsScript := preload("res://gameplay/feel/carried_lights.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## One frame of Feel's clock (s).
const FRAME: float = 1.0 / 60.0

var _world: Fixture
var _lights: CarriedLightsScript
var _clock: float = 0.0


func before_each() -> void:
	_world = Fixture.new(root)
	_lights = CarriedLightsScript.new()
	_clock = 0.0


func after_each() -> void:
	_world.free_all()


## A body at `at`, seat `seat`'s own (-1: no seat's).
func _body(at: Vector2, seat: int) -> Actor:
	var body: Actor = _world.add(Actor.new(), at)
	if seat >= 0:
		_world.table.set_home(body.id, seat)
	return body


## `frames` frames of Feel's clock.
func _frames(frames: int, table: ActorsScript = null) -> void:
	for i in frames:
		_lights.step(table if table != null else _world.table, _clock)
		_clock += FRAME


## Frames enough for any change to have eased all the way.
func _settle() -> void:
	_frames(ceili(CarriedLightsScript.EASE_SECONDS / FRAME) + 2)


## The row `at`'s light: where, how far, its colour and strength.
func _row(at: int) -> Array:
	var i: int = at * SpellLightScript.STRIDE
	var rows: PackedFloat32Array = _lights.rows
	return [Vector2(rows[i + 3], rows[i + 7]), rows[i], Color(rows[i + 8], rows[i + 9], rows[i + 10]), rows[i + 11]]


func test_a_seats_wizard_carries_a_light_at_its_staff_tip() -> void:
	var wizard: Actor = _body(Vector2(100.0, 80.0), 0)
	wizard.aim = Vector2.RIGHT
	_body(Vector2(300.0, 80.0), -1)
	_settle()
	check_equal(_lights.count, 1, "the seat's wizard carries one, the seatless body none")
	var row: Array = _row(0)
	check((row[0] as Vector2).is_equal_approx(wizard.muzzle_position()), "at its staff tip")
	check(is_equal_approx(float(row[1]), CarriedLightsScript.CARRIED_REACH), "as far as a carried light reaches")
	var hat: Color = ProjectileManagerScript.ramp_light(_world.table.ramp_of(wizard.id))
	check((row[2] as Color).is_equal_approx(Color(hat.r, hat.g, hat.b)), "in its hat's light shade")
	check(is_equal_approx(float(row[3]), CarriedLightsScript.CARRIED_STRENGTH), "at a carried light's strength")


func test_it_eases_in_over_at_least_three_frames() -> void:
	_body(Vector2(100.0, 80.0), 0)
	var seen: Array[float] = []
	for i in 12:
		_frames(1)
		seen.append(_lights.strength[0])
	var between: int = 0
	for s: float in seen:
		if s > 0.0 and s < CarriedLightsScript.CARRIED_STRENGTH:
			between += 1
	check(between >= 3, "at least 3 frames between dark and lit, got %s" % [seen])
	check(is_equal_approx(seen[-1], CarriedLightsScript.CARRIED_STRENGTH), "then lit")


func test_the_light_follows_the_staff() -> void:
	var wizard: Actor = _body(Vector2(100.0, 80.0), 0)
	_settle()
	wizard.position = Vector2(180.0, 40.0)
	wizard.aim = Vector2.UP
	_frames(1)
	check((_row(0)[0] as Vector2).is_equal_approx(wizard.muzzle_position()), "where the staff tip is now")


func test_a_downed_wizards_light_dims_over_frames() -> void:
	var wizard: Actor = _body(Vector2(100.0, 80.0), 0)
	_settle()
	wizard.set_down(true)
	var between: int = 0
	var dim: float = CarriedLightsScript.CARRIED_STRENGTH * CarriedLightsScript.DOWNED_SHARE
	for i in 12:
		_frames(1)
		if _lights.strength[0] > dim + 0.0001 and _lights.strength[0] < CarriedLightsScript.CARRIED_STRENGTH - 0.0001:
			between += 1
	check(between >= 3, "it dims over at least 3 frames, got %d" % between)
	check(is_equal_approx(_lights.strength[0], dim), "to a downed staff's share")


func test_a_gone_body_fades_where_it_was() -> void:
	var wizard: Actor = _body(Vector2(100.0, 80.0), 0)
	_settle()
	var at: Vector2 = wizard.muzzle_position()
	_world.table.set_node(wizard.id, null)
	_frames(1)
	check_equal(_lights.count, 1, "still lit the frame after its body is gone")
	check((_row(0)[0] as Vector2).is_equal_approx(at), "where it last was")
	check(_lights.strength[0] < CarriedLightsScript.CARRIED_STRENGTH, "and fading")
	_settle()
	check_equal(_lights.count, 0, "then out")


func test_a_freed_body_fades_too() -> void:
	var wizard: Actor = _body(Vector2(100.0, 80.0), 0)
	_settle()
	_world.actors.erase(wizard)
	wizard.free()
	_settle()
	check_equal(_lights.count, 0, "a freed wizard's light goes out")


func test_a_possessing_seat_lights_the_body_it_drives_in_its_own_colour() -> void:
	var wizard: Actor = _body(Vector2(100.0, 80.0), 0)
	var puppet: Actor = _body(Vector2(300.0, 80.0), -1)
	_world.table.set_driver(puppet.id, ActorsScript.TEAM_WIZARDS, 0)
	_settle()
	check_equal(_lights.count, 1, "one light for the seat")
	check((_row(0)[0] as Vector2).is_equal_approx(puppet.muzzle_position()), "on the body the seat drives")
	var hat: Color = ProjectileManagerScript.ramp_light(_world.table.ramp_of(wizard.id))
	check((_row(0)[2] as Color).is_equal_approx(Color(hat.r, hat.g, hat.b)), "in the seat's own hat colour")


func test_a_falling_wizards_light_goes_out_with_it() -> void:
	var wizard: Actor = _body(Vector2(100.0, 80.0), 0)
	_settle()
	wizard.fall_left = HoleRules.FALL_SECONDS * 0.25
	_settle()
	check(_lights.strength[0] < CarriedLightsScript.CARRIED_STRENGTH * 0.3, "three quarters through its fall, a quarter lit")


func test_every_seat_carries_one_and_all_fade_without_a_table() -> void:
	for seat in ActorsScript.SEATS:
		_body(Vector2(40.0 * seat, 0.0), seat)
	_settle()
	check_equal(_lights.count, ActorsScript.SEATS, "one a seat")
	check_equal(_lights.rows.size(), ActorsScript.SEATS * SpellLightScript.STRIDE, "in rows made once")
	for i in 30:
		_lights.step(null, _clock)
		_clock += FRAME
	check_equal(_lights.count, 0, "all out with no table")


func test_a_hidden_wizard_carries_none() -> void:
	var wizard: Actor = _body(Vector2(100.0, 80.0), 0)
	wizard.visible = false
	_settle()
	check_equal(_lights.count, 0, "a body not drawn lights nothing")


func test_a_frame_allocates_nothing() -> void:
	var light: SpellLightScript = own(SpellLightScript.new(null, 0)) as SpellLightScript
	root.add_child(light)
	var a: Actor = _body(Vector2(100.0, 80.0), 0)
	_body(Vector2(140.0, 80.0), 1)
	_settle()
	light.light_carried(_lights.rows, _lights.count)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for frame in 100:
		a.set_down(frame % 20 < 10)
		_frames(1)
		light.light_carried(_lights.rows, _lights.count)
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "100 frames of carried lights make no object")


## The spell light draws the rows it is handed in a spot batch of its own, as many as it is told.
func test_the_spell_light_draws_what_it_is_handed() -> void:
	var light: SpellLightScript = own(SpellLightScript.new(null, 0)) as SpellLightScript
	root.add_child(light)
	_body(Vector2(100.0, 80.0), 0)
	_body(Vector2(140.0, 80.0), 2)
	_settle()
	light.light_carried(_lights.rows, _lights.count)
	check_equal(light.carried_count(), 2, "two lit")
	light.follow()
	var lit: float = 0.0
	for v in light.grid.rgb:
		lit += v
	check(lit > 0.0, "read as spots: the grid is lit round them")
	for i in 30:
		_lights.step(null, _clock)
		_clock += FRAME
	light.light_carried(_lights.rows, _lights.count)
	check_equal(light.carried_count(), 0, "none when none are carried")
