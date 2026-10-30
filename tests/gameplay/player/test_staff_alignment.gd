extends "res://tests/support/suite.gd"
## Staff animations line up with their spell's look (2026-10-30, the slam's staff missed its floor
## crack): every carrier card whose `staff_pose` has a `land` key is cast by a real wizard (its
## StaffLook, the real runtime) along every one of the head sheet's 16 directions, and in between,
## and short of a wall. While it lands fully, the drawn tip (`StaffLook.tip_position`) is on the
## point its carrier strikes (`Carrier.strike_point`, from the hand), and the carrier's look of its
## strike (`form_shown`) is drawn there too. A new card that lands is checked here without a line
## added; a new carrier that strikes a point says so in `traits()` (`STRIKES_POINT`).
##
## godot --headless --path . --script res://tests/gameplay/player/test_staff_alignment.gd

const WizardFixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
## How far the drawn tip may be from the point struck: the body is placed on whole pixels.
const SLACK: float = 1.0
## Steps to wait for a cast to land and come back to rest, at most.
const STEPS: int = 40

var _world: WizardFixture
## The looks `form_shown` drew for the wizard's casts: their points.
var _shown: Array[Vector2] = []


func before_each() -> void:
	_world = WizardFixture.new(root)
	_shown.clear()
	_world.bus.form_shown.connect(func(caster: int, _form: StringName, at: Vector2, _dir: Vector2, _length: float, _tint: Color, _look: int) -> void:
		if caster == 0:
			_shown.append(at))


func after_each() -> void:
	_world.free_all()


## The ids of the carrier cards whose staff animation lands.
func _landing_cards() -> Array[StringName]:
	var found: Array[StringName] = []
	for id: StringName in _world.registry.get_ids(&"spells"):
		var form: FormBase = _world.registry.get_resource(&"spells", id) as FormBase
		if form != null and form.lands():
			found.append(id)
	return found


## Casts `card`'s staff along `aim` and checks every step its staff is fully landed. Returns how
## many steps it was.
func _check_cast(body: Actor, aim: Vector2, what: String) -> int:
	var look: StaffLook = WizardFixture.look(body)
	var poses: StaffPoses = _world.spells.poses()
	_shown.clear()
	_world.input.send_virtual_aim(0, aim)
	_world.run(2, false)
	_world.hold(0, &"staff_1")
	var landed: int = 0
	var struck: Vector2 = Vector2.INF
	for n in STEPS:
		# The look steps before the runtime does: it draws the pose of the clock read here.
		var land: float = poses.staff_land(body.id)
		var point: Vector2 = poses.staff_land_point(body.id)
		var hand: Vector2 = body.aim_pivot()
		_world.run(1, false)
		if n == 0:
			_world.release(0, &"staff_1")
		if land < 0.999:
			continue
		landed += 1
		struck = hand + point
		var tip: Vector2 = look.tip_position()
		check(tip.distance_to(struck) <= SLACK, "%s aiming %s: the drawn tip %s is on the point struck %s" % [what, aim, tip, struck])
	check(landed > 0, "%s aiming %s: its staff lands" % [what, aim])
	if struck.is_finite() and not _shown.is_empty():
		var nearest: float = INF
		for at: Vector2 in _shown:
			nearest = minf(nearest, at.distance_to(struck))
		check(nearest <= SLACK, "%s aiming %s: its strike is drawn where the tip lands (%s, the looks at %s)" % [what, aim, struck, _shown])
	_world.run(STEPS, false)
	return landed


func test_some_card_lands_its_staff() -> void:
	check(not _landing_cards().is_empty(), "the slam does, so this suite checks something")


func test_every_landing_card_puts_the_tip_on_its_strike_in_every_direction() -> void:
	for card: StringName in _landing_cards():
		var body: Actor = _world.wizard(0, Vector2(100.0, 100.0), [[card], [], [], []])
		for n in StaffLook.DIRECTIONS * 2:
			_check_cast(body, Vector2.RIGHT.rotated(n * TAU / (StaffLook.DIRECTIONS * 2)), String(card))
		body.free()
		_world.wizards.clear()


func test_every_landing_card_lands_on_a_wall_in_its_way() -> void:
	_world.projectiles.set_walls([Rect2(110.0, 60.0, 20.0, 80.0)] as Array[Rect2])
	for card: StringName in _landing_cards():
		var body: Actor = _world.wizard(0, Vector2(100.0, 100.0), [[card], [], [], []])
		_check_cast(body, Vector2.RIGHT, "%s by a wall" % card)
		check(_world.spells.poses().staff_land_point(body.id) == Vector2.INF, "and lets go after")
		body.free()
		_world.wizards.clear()
