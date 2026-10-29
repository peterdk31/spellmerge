extends "res://tests/support/suite.gd"
## The floating staff (living staffs H3, docs/milestones/M2-living-staffs.md, "The player"): each
## staff button puts its own head and personality on show, and the shot leaves from that head's
## tip in every direction; pressing an empty staff still shows it; the staff hovers on the hand
## and the face goes with it; down, it lies flat with its eyes shut, and stands up again when
## revived; the hurt circle covers the face and the grip; while it swings (melee I2) the body
## shows the column of its swing, not of its aim. The real wizard scene and the four
## starter heads, on the stand-in spell runtime.
##
## godot --headless --path . --script res://tests/gameplay/player/test_staff_look.gd

const WizardFixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const HEADS: Array[StringName] = [&"curl", &"star", &"moon", &"crystal"]
const HEAD_STAFFS: Array[StaffBase] = [
	preload("res://content/wizard/staffs/curl/curl.tres"),
	preload("res://content/wizard/staffs/star/star.tres"),
	preload("res://content/wizard/staffs/moon/moon.tres"),
	preload("res://content/wizard/staffs/crystal/crystal.tres"),
]
const BUTTONS: Array[StringName] = [&"staff_1", &"staff_2", &"staff_3", &"staff_4"]
const BOLTS: Array = [[&"bolt"], [&"bolt"], [&"bolt"], [&"bolt"]]

var _world: WizardFixture
var _heads: Array[StaffBase] = []


func before_each() -> void:
	_world = WizardFixture.new(root, true)
	_heads.assign(HEAD_STAFFS)


func after_each() -> void:
	_world.free_all()


func _wizard(cards: Array = BOLTS) -> Actor:
	return _world.wizard(0, Vector2(100.0, 100.0), cards, null, true, _heads)


## Press and let go of staff button `at`, and wait out the poof (H4) that swaps the body.
func _press(at: int) -> void:
	_world.hold(0, BUTTONS[at])
	_world.run(1, false)
	_world.release(0, BUTTONS[at])
	_world.run(roundi(StaffLook.POOF_TIME / WizardFixture.STEP) + 1, false)


func _face(body: Actor) -> Face:
	return body.get_node(^"Face") as Face


func test_each_button_shows_its_head_and_personality() -> void:
	var body := _wizard()
	var look: StaffLook = WizardFixture.look(body)
	var sprite := body.get_node(^"Sprite") as Sprite2D
	_world.run(1, false)
	check_equal(look.shown_staff(), 0, "the RB staff shows first")
	for at in [1, 3, 2, 0]:
		_press(at)
		check_equal(body.caster.current, at, "staff %d is on show after its press" % at)
		check(sprite.texture == _heads[at].head, "the %s head shows" % HEADS[at])
		check_equal(int(_face(body).style), _heads[at].face_style, "with the %s personality's eyes" % HEADS[at])
		check_equal(int(_face(body).resting_mood), _heads[at].resting_mood, "and its resting brows")


func test_an_empty_staff_still_shows_when_pressed() -> void:
	var body := _wizard([[&"bolt"], [], [], []])
	_world.fake.origins.clear()
	_press(2)
	check_equal(body.caster.current, 2, "the empty LB staff is on show")
	check(_world.fake.origins.is_empty(), "and casts nothing")


func test_the_shot_leaves_from_the_tip_of_the_head_on_show_in_every_direction() -> void:
	var body := _wizard()
	for at in HEADS.size():
		for aim: Vector2 in [Vector2.RIGHT, Vector2.UP, Vector2(-1.0, 1.0).normalized()]:
			_world.input.send_virtual_aim(0, aim)
			_world.fake.origins.clear()
			_press(at)
			var expected: Vector2 = body.aim_pivot() + aim * _heads[at].tip
			check(not _world.fake.origins.is_empty() and _world.fake.origins[0].distance_to(expected) < 0.01,
					"%s aimed %s: the shot leaves its tip %s, got %s" % [HEADS[at], aim, expected, _world.fake.origins])
			check(body.muzzle_position().distance_to(expected) < 0.01, "and the muzzle is there")


func test_it_hovers_on_the_hand_and_the_face_goes_with_it() -> void:
	var body := _wizard()
	var sprite := body.get_node(^"Sprite") as Sprite2D
	var face := _face(body)
	var heights: Dictionary = {}
	for i in 40:
		_world.run(1, false)
		var lift: float = sprite.position.y - body.hand_offset.y
		check(absf(lift) <= ceilf(StaffLook.HOVER_BOB), "the grip stays on the hand, give or take the bob (got %.1f)" % lift)
		check_equal(face.body_offset, sprite.position - body.hand_offset, "the face is told where the body is")
		heights[lift] = true
	check(heights.size() > 1, "it bobs")


func test_down_it_lies_flat_with_its_eyes_shut_and_stands_up_when_revived() -> void:
	var body := _wizard()
	var look: StaffLook = WizardFixture.look(body)
	var sprite := body.get_node(^"Sprite") as Sprite2D
	_world.input.send_virtual_aim(0, Vector2.LEFT)
	_world.run(1, false)
	_world.hurt(body, body.health.max_health)
	_world.run(1, false)
	check(body.is_down(), "it is down")
	check_equal(sprite.position, Vector2(0.0, -StaffLook.DOWN_LIFT), "on the floor")
	check_equal(look.direction(), StaffLook.DIRECTIONS / 2, "lying flat the way it faced (left)")
	check(_face(body).is_shut() and _face(body).mood() == Face.Mood.WORRIED, "eyes shut, brows worried")
	WizardFixture.downed(body).revive(1)
	_world.run(1, false)
	check(not body.is_down(), "revived")
	check(absf(sprite.position.y - body.hand_offset.y) <= ceilf(StaffLook.HOVER_BOB), "back up on the hand")


func test_the_hurt_circle_covers_the_face_and_the_grip() -> void:
	var body := _wizard()
	var hurtbox: Hurtbox = body.hurtbox
	var face := _face(body)
	# The middle of the eyes (9 x 5 px from the anchor) and the grip.
	var eyes: Vector2 = face.anchor + Vector2(4.5, 2.5)
	check(eyes.distance_to(hurtbox.offset) <= hurtbox.radius, "the eyes are inside the hurt circle")
	check(body.hand_offset.distance_to(hurtbox.offset) <= hurtbox.radius, "and so is the grip")
	check(hurtbox.radius >= 8.0, "as big as the wizard's was")


func test_while_it_swings_the_body_shows_the_swing_not_the_aim() -> void:
	var body := _wizard()
	var look: StaffLook = WizardFixture.look(body)
	var sprite := body.get_node(^"Sprite") as Sprite2D
	_world.input.send_virtual_aim(0, Vector2.RIGHT)
	_world.run(1, false)
	check_equal(look.direction(), 0, "aimed right, the right column")
	_world.fake.swing_poses[body.id] = Vector2.from_angle(deg_to_rad(60.0))
	_world.run(1, false)
	check_equal(look.direction(), StaffLook.direction_of(Vector2.from_angle(deg_to_rad(60.0))), "mid-swing, the column of the swing")
	check_equal(sprite.frame_coords.x, look.direction(), "and the sprite shows it")
	_world.fake.swing_poses.erase(body.id)
	_world.run(1, false)
	check_equal(look.direction(), 0, "after the swing, the aim again")
