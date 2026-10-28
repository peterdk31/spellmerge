extends "res://tests/support/suite.gd"
## The poof (living staffs H4, docs/milestones/M2-living-staffs.md, "The poof: a personality
## swap"): a press of another staff button sends `staff_shown` before its cast, and the cast
## leaves on the press from the new staff's tip; the body and face keep the old staff until 35%
## of the poof, then change and the brows lift; holding one button, or pressing the one on show
## again, never poofs. The real wizard scene and the four starter heads, on the stand-in spells.
##
## godot --headless --path . --script res://tests/gameplay/player/test_poof.gd

const WizardFixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const HEAD_STAFFS: Array[StaffBase] = [
	preload("res://content/wizard/staffs/curl/curl.tres"),
	preload("res://content/wizard/staffs/star/star.tres"),
	preload("res://content/wizard/staffs/moon/moon.tres"),
	preload("res://content/wizard/staffs/crystal/crystal.tres"),
]
const BOLTS: Array = [[&"bolt"], [&"bolt"], [&"bolt"], [&"bolt"]]

var _world: WizardFixture
var _body: Actor
## Every staff_shown as [caster, staff, casts the stand-in had seen when it came].
var _shown: Array = []


func before_each() -> void:
	_world = WizardFixture.new(root, true)
	var heads: Array[StaffBase] = []
	heads.assign(HEAD_STAFFS)
	_body = _world.wizard(0, Vector2(100.0, 100.0), BOLTS, null, true, heads)
	_shown.clear()
	_world.bus.staff_shown.connect(func(caster: int, _actor: Node, staff: int) -> void: _shown.append([caster, staff, _world.fake.origins.size()]))
	_world.run(1, false)


func after_each() -> void:
	_world.free_all()


func _look() -> StaffLook:
	return WizardFixture.look(_body)


func test_another_button_poofs_and_casts_on_the_press_from_the_new_tip() -> void:
	_world.input.send_virtual_aim(0, Vector2.RIGHT)
	_world.fake.origins.clear()
	_world.hold(0, &"staff_2")
	_world.run(1, false)
	check_equal(_shown.size(), 1, "one staff_shown")
	if _shown.size() == 1:
		check_equal(_shown[0][0], _body.id, "naming the actor")
		check_equal(_shown[0][1], 1, "and the RT staff")
		check_equal(_shown[0][2], 0, "before its cast")
	var tip: Vector2 = _body.aim_pivot() + Vector2.RIGHT * HEAD_STAFFS[1].tip
	check(not _world.fake.origins.is_empty() and _world.fake.origins[0].distance_to(tip) < 0.01, "the cast left on the press from the star's tip, got %s" % [_world.fake.origins])
	check_equal(_look().shown_staff(), 0, "while the curl still shows under the cloud")
	check(_look().is_poofing(), "the poof is on")


func test_body_and_face_change_at_35_percent_and_the_brows_lift() -> void:
	var face := _body.get_node(^"Face") as Face
	_world.hold(0, &"staff_4")
	var swap_at: float = StaffLook.POOF_TIME * StaffLook.SWAP_AT
	var age: float = 0.0
	var swapped_at: float = -1.0
	_world.run(1, false)
	while age < StaffLook.POOF_TIME + WizardFixture.STEP:
		if _look().shown_staff() == 3 and swapped_at < 0.0:
			swapped_at = age
			check_equal(int(face.style), HEAD_STAFFS[3].face_style, "the Sergeant's eyes come with the crystal")
			check_equal(face.mood(), Face.Mood.RAISED, "and the brows lift")
		_world.run(1, false)
		age += WizardFixture.STEP
	check(swapped_at >= swap_at and swapped_at < swap_at + WizardFixture.STEP, "the body changes at the first step past 35%% of the poof (%.3f s), got %.3f s" % [swap_at, swapped_at])
	check(not _look().is_poofing(), "the poof is over")
	_world.run(roundi(StaffLook.BROW_LIFT / WizardFixture.STEP) + 1, false)
	check_equal(face.mood(), Face.Mood.ANGRY, "then the Sergeant's resting brows")


func test_holding_one_button_or_pressing_it_again_never_poofs() -> void:
	_world.hold(0, &"staff_1")
	_world.run(roundi(2.0 / WizardFixture.STEP), false)
	_world.release(0, &"staff_1")
	_world.run(1, false)
	check_equal(_shown.size(), 0, "holding the staff on show never poofs")
	check(not _look().is_poofing(), "no poof")
	_world.hold(0, &"staff_3")
	_world.run(roundi(2.0 / WizardFixture.STEP), false)
	check_equal(_shown.size(), 1, "holding another staff poofs once")
	_world.release(0, &"staff_3")
	_world.run(1, false)
	_world.hold(0, &"staff_3")
	_world.run(1, false)
	check_equal(_shown.size(), 1, "pressing the staff on show again does not")


func test_a_quick_second_swap_lands_on_the_newest_staff() -> void:
	_world.hold(0, &"staff_2")
	_world.run(1, false)
	_world.release(0, &"staff_2")
	_world.hold(0, &"staff_3")
	_world.run(1, false)
	check_equal(_shown.size(), 2, "two presses, two clouds")
	_world.run(roundi(StaffLook.POOF_TIME / WizardFixture.STEP) + 1, false)
	check_equal(_look().shown_staff(), 2, "the moon shows: the newest staff")
