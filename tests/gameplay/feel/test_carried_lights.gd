extends "res://tests/support/suite.gd"
## Carried lights (docs/milestones/atmosphere.md, A; gameplay/feel/carried_lights.gd): every seat's
## own wizard in the tree carries a light at its staff tip, in its hat's light shade, dimmer while
## downed; a body no seat calls its own carries none; a frame allocates nothing; and the game's Feel
## hands the rows to the spell light while it is on.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const CarriedLightsScript := preload("res://gameplay/feel/carried_lights.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

var _world: Fixture
var _lights: CarriedLightsScript


func before_each() -> void:
	_world = Fixture.new(root)
	_lights = CarriedLightsScript.new()


func after_each() -> void:
	_world.free_all()


## A body at `at`, seat `seat`'s own (-1: no seat's).
func _body(at: Vector2, seat: int) -> Actor:
	var body: Actor = _world.add(Actor.new(), at)
	if seat >= 0:
		_world.table.set_home(body.id, seat)
	return body


## The row `at`'s light: where, how far, its colour and strength.
func _row(at: int) -> Array:
	var i: int = at * SpellLightScript.STRIDE
	var rows: PackedFloat32Array = _lights.rows
	return [Vector2(rows[i + 3], rows[i + 7]), rows[i], Color(rows[i + 8], rows[i + 9], rows[i + 10]), rows[i + 11]]


func test_a_seats_wizard_carries_a_light_at_its_staff_tip() -> void:
	var wizard: Actor = _body(Vector2(100.0, 80.0), 0)
	wizard.aim = Vector2.RIGHT
	_body(Vector2(300.0, 80.0), -1)
	_lights.step(_world.table)
	check_equal(_lights.count, 1, "the seat's wizard carries one, the seatless body none")
	var row: Array = _row(0)
	check((row[0] as Vector2).is_equal_approx(wizard.muzzle_position()), "at its staff tip")
	check(is_equal_approx(float(row[1]), CarriedLightsScript.CARRIED_REACH), "as far as a carried light reaches")
	var hat: Color = ProjectileManagerScript.ramp_light(_world.table.ramp_of(wizard.id))
	check((row[2] as Color).is_equal_approx(Color(hat.r, hat.g, hat.b)), "in its hat's light shade")
	check(is_equal_approx(float(row[3]), CarriedLightsScript.CARRIED_STRENGTH), "at a carried light's strength")


func test_the_light_follows_the_staff() -> void:
	var wizard: Actor = _body(Vector2(100.0, 80.0), 0)
	_lights.step(_world.table)
	wizard.position = Vector2(180.0, 40.0)
	wizard.aim = Vector2.UP
	_lights.step(_world.table)
	check((_row(0)[0] as Vector2).is_equal_approx(wizard.muzzle_position()), "where the staff tip is now")


func test_a_downed_wizards_light_dims() -> void:
	var wizard: Actor = _body(Vector2(100.0, 80.0), 0)
	wizard.set_down(true)
	_lights.step(_world.table)
	check(is_equal_approx(float(_row(0)[3]), CarriedLightsScript.CARRIED_STRENGTH * CarriedLightsScript.DOWNED_SHARE), "a downed wizard's staff dims")


func test_every_seat_carries_one_and_none_without_a_table() -> void:
	for seat in ActorsScript.SEATS:
		_body(Vector2(40.0 * seat, 0.0), seat)
	_lights.step(_world.table)
	check_equal(_lights.count, ActorsScript.SEATS, "one a seat")
	check_equal(_lights.rows.size(), ActorsScript.SEATS * SpellLightScript.STRIDE, "in rows made once")
	_lights.step(null)
	check_equal(_lights.count, 0, "none with no table")


func test_a_hidden_wizard_carries_none() -> void:
	var wizard: Actor = _body(Vector2(100.0, 80.0), 0)
	wizard.visible = false
	_lights.step(_world.table)
	check_equal(_lights.count, 0, "a body not drawn lights nothing")


func test_a_frame_allocates_nothing() -> void:
	_body(Vector2(100.0, 80.0), 0)
	_body(Vector2(140.0, 80.0), 1)
	_lights.step(_world.table)
	var rows: PackedFloat32Array = _lights.rows
	var size: int = rows.size()
	for i in 10:
		_lights.step(_world.table)
	check_equal(_lights.rows.size(), size, "the rows keep their size")


## The spell light draws the rows it is handed in a spot batch of its own, as many as it is told.
func test_the_spell_light_draws_what_it_is_handed() -> void:
	var light: SpellLightScript = own(SpellLightScript.new(null, 0)) as SpellLightScript
	root.add_child(light)
	_body(Vector2(100.0, 80.0), 0)
	_body(Vector2(140.0, 80.0), 2)
	_lights.step(_world.table)
	light.light_carried(_lights.rows, _lights.count)
	check_equal(light.carried_count(), 2, "two lit")
	check_equal(int((light.carried.material as ShaderMaterial).get_shader_parameter(&"rows")), SpellLightScript.ROWS_SPOT, "read as spots")
	_lights.step(null)
	light.light_carried(_lights.rows, _lights.count)
	check_equal(light.carried_count(), 0, "none when none are carried")
