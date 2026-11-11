extends "res://tests/support/suite.gd"
## Possess on a prop (props W4, docs/milestones/props.md; owner, 2026-11-10: "Possess would actually
## be cool. So keep it."), by today's one rule: every hit possesses. The seat that possesses a prop
## drives it but cannot walk it (no Mover: a body with no Mover never moves), its buttons cast the
## prop's staffs with the prop as caster (its actor id, as every actor's: `Spells.open_caster`), the
## prop is on the seat's team while it lasts and the world's after, and the prop's death ends the
## possession and the seat goes home. Real wizard scene, real Spells and registry (the `possess`
## card); a stand-in prop (`ActorFixture.prop_body`).
##
## godot --headless --path . --script res://tests/gameplay/actor/test_possess_prop.gd

const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const ActorFixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

var _world: Fixture
var _staff_casts: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)
	_staff_casts.clear()
	_world.bus.staff_cast.connect(func(p: int, s: int, _o: Vector2, _d: Vector2) -> void: _staff_casts.append([p, s]))


func after_each() -> void:
	_world.free_all()


func _tap(seat: int, action: StringName) -> void:
	_world.hold(seat, action)
	_world.release(seat, action)


## A stand-in prop at `at` with one staff of `bolt`, stepped with the wizards.
func _prop(at: Vector2) -> Actor:
	var body: Actor = ActorFixture.prop_body([[&"bolt"]])
	body.position = at
	return _world.add(body)


func test_a_prop_is_a_caster_by_its_actor_id() -> void:
	var prop: Actor = _prop(Vector2(0.0, 60.0))
	check(prop.id != ActorsScript.NONE, "it has an actor id")
	check_equal(prop.caster_number(), prop.id, "and casts under it")
	_world.run(1)
	check(prop.caster.cast(0), "a cast of its own (a reaction's, W6)")
	check(_world.projectiles.get_count_for(prop.id) > 0, "makes shots of its actor id")


func test_a_seat_that_possesses_a_prop_casts_its_staff_but_cannot_walk_it_and_goes_home_when_it_breaks() -> void:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO, [[&"possess", &"bolt"], [], [], []])
	var seat: PlayerController = Fixture.controller(wizard)
	var prop: Actor = _prop(Vector2(0.0, 60.0))
	var at: Vector2 = prop.global_position
	_tap(0, &"staff_1")
	_world.run(8)
	check(prop.controller == seat, "the possess bolt's hit hands the prop to the seat")
	check_equal(_world.table.team_of(prop.id), ActorsScript.TEAM_WIZARDS, "on the seat's team while it lasts")
	check(not _world.table.is_still(prop.id), "driven, so stepped")
	# The stick walks nothing.
	_world.hold(0, &"move_right")
	_world.run(4)
	prop.move(Fixture.STEP)
	check_equal(prop.global_position, at, "the prop stands")
	_world.release(0, &"move_right")
	# Its button casts the prop's staff, as the prop.
	_staff_casts.clear()
	var mana: float = prop.caster.mana_of(0)
	var shots: int = _world.projectiles.get_count_for(prop.id)
	_tap(0, &"staff_1")
	_world.run(1)
	check_equal(_staff_casts, [[0, 0]], "the seat's button casts the prop's staff")
	check(prop.caster.mana_of(0) < mana, "with the prop's mana")
	check(_world.projectiles.get_count_for(prop.id) > shots, "its bolt is the prop's")
	# Shot apart: the possession ends and the seat goes home.
	_world.hurt(prop, 100, 1)
	check(prop.is_dying(), "the prop breaks")
	check(wizard.controller == seat and seat.driving == wizard, "the seat is home")
	check_equal(_world.table.actor_of_seat(0), wizard.id, "on its wizard")


func test_a_possession_that_runs_out_leaves_the_prop_on_the_worlds_team_and_still() -> void:
	var wizard: Actor = _world.wizard(0)
	var prop: Actor = _prop(Vector2(0.0, 60.0))
	var possession: Possession = Possession.begin(wizard, prop, 0.5)
	check(possession != null, "possessed")
	_world.run(12)
	check(prop.controller == null, "the time ran out")
	check_equal(_world.table.team_of(prop.id), ActorsScript.TEAM_WORLD, "the prop is the world's again")
	check(_world.table.is_still(prop.id), "and still")
	check(wizard.controller == Fixture.controller(wizard), "the seat is home")
