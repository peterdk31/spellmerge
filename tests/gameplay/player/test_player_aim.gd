extends "res://tests/support/suite.gd"
## Tests for gameplay/player (aim) on the wizard actor (actors G7), one behaviour per test: shots
## go where the wizard aims, not where it walks. The right stick aims and holds for AIM_HOLD_TIME,
## the keyboard player aims at the mouse (from the hand), with no aim input the wizard aims the way
## it walks, and four players aim independently. The look (StaffLook) points the staff at the aim,
## draws the reticle on the shot's line in its seat's colour, and stretches and leans the sprite
## through a dash, its ghosts trailing behind.
##
## Each test gets a fresh world (wizard_fixture.gd: wizards from the real scene, the stand-in spell
## runtime, input through the world's own input manager's virtual devices), stepped by fixed deltas
## without moving the bodies. The mouse-aim flag itself (a brush is not aiming, the cast key leaves
## it) is the input manager's, tested in tests/core/test_input.gd.

const WizardFixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const FakeSpellsScript := preload("res://tests/gameplay/player/fixtures/fake_spells.gd")

const STEP: float = WizardFixture.STEP
## Staff 0 holds a card, so the wizard can cast it.
const BOLT_CARDS: Array = [[&"bolt"], [], [], []]

var _world: WizardFixture
var _players: Array[Actor] = []
var _input: InputManagerScript
var _fake: FakeSpellsScript


func before_each() -> void:
	_world = WizardFixture.new(root, true)
	_input = _world.input
	_fake = _world.fake
	_players.clear()


func after_each() -> void:
	_world.free_all()


## `count` wizards on virtual devices (staff 0 holds a bolt); with `keyboard` the first joins as
## the keyboard. Returns the first.
func _wizards(count: int, keyboard: bool = false) -> Actor:
	for index in count:
		if keyboard and index == 0:
			_input.join(InputManagerScript.KEYBOARD)
		_players.append(_world.wizard(index, Vector2.ZERO, BOLT_CARDS))
	return _players[0]


## Step every wizard `count` times without moving the bodies (the mouse checks need the hand where
## it was).
func _run(count: int) -> void:
	_world.run(count, false)


func _near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.001


func _mouse_move(distance: float) -> InputEventMouseMotion:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(distance, 0.0)
	return motion


func _key(keycode: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	key.pressed = true
	return key


func _sprite(wizard: Actor) -> Sprite2D:
	return wizard.get_node("Sprite") as Sprite2D


# --- Where the wizard aims ---------------------------------------------------------------------


func test_a_wizard_that_has_not_moved_aims_down() -> void:
	var wizard: Actor = _wizards(1)
	_run(1)
	check(_near(wizard.aim, Vector2.DOWN), "a wizard that has not moved aims down: %s" % wizard.aim)


func test_with_no_aim_input_the_wizard_aims_the_way_it_walks() -> void:
	var wizard: Actor = _wizards(1)
	_input.send_virtual(0, &"move_left", 1.0)
	_run(1)
	check(_near(wizard.aim, Vector2.LEFT), "the wizard aims the way it walks: %s" % wizard.aim)


func test_the_right_stick_aims_apart_from_the_walk() -> void:
	var wizard: Actor = _wizards(1)
	_input.send_virtual(0, &"move_left", 1.0)
	_input.send_virtual_aim(0, Vector2.UP)
	_run(2)
	check(_near(wizard.aim, Vector2.UP), "the right stick aims up while walking left: %s" % wizard.aim)


func test_aiming_with_the_stick_leaves_the_walk_alone() -> void:
	# There is no `facing` any more; the walk shows in the velocity.
	var wizard: Actor = _wizards(1)
	_input.send_virtual(0, &"move_left", 1.0)
	_input.send_virtual_aim(0, Vector2.UP)
	_run(2)
	check(wizard.velocity.x < 0.0 and is_zero_approx(wizard.velocity.y), "the wizard still walks left: %s" % wizard.velocity)


## A wizard walking left that aimed right with the stick, then let it go and stepped for `steps`.
func _stick_let_go(steps: int) -> Actor:
	var wizard: Actor = _wizards(1)
	_input.send_virtual(0, &"move_left", 1.0)
	_input.send_virtual_aim(0, Vector2.RIGHT)
	_run(1)
	_input.send_virtual_aim(0, Vector2.ZERO)
	_run(steps)
	return wizard


func test_the_stick_aim_holds_after_the_stick_is_let_go() -> void:
	var wizard: Actor = _stick_let_go(int(LocalInput.AIM_HOLD_TIME / STEP) - 2)
	check(_near(wizard.aim, Vector2.RIGHT), "the aim holds after the stick is let go: %s" % wizard.aim)


func test_after_the_hold_the_aim_follows_the_walk_again() -> void:
	var wizard: Actor = _stick_let_go(int(LocalInput.AIM_HOLD_TIME / STEP) + 2)
	check(_near(wizard.aim, Vector2.LEFT), "after the hold the aim follows the walk again: %s" % wizard.aim)


func test_the_cast_goes_along_the_aim_not_the_walk() -> void:
	var wizard: Actor = _wizards(1)
	_input.send_virtual(0, &"move_left", 1.0)
	_input.send_virtual_aim(0, Vector2.UP)
	_run(1)
	check(wizard.caster.cast(0), "the wizard casts")
	check(_fake.directions.size() == 1 and _near(_fake.directions[0], Vector2.UP), "the spell got the aim, not the walk direction: %s" % [_fake.directions])


func test_four_players_aim_their_own_way() -> void:
	_wizards(4)
	var aims: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	for index in 4:
		_input.send_virtual_aim(index, aims[index])
	_run(1)
	for index in 4:
		check(_near(_players[index].aim, aims[index]), "player %d aims their own way" % index)


func test_letting_go_of_one_stick_leaves_the_others_aims() -> void:
	_wizards(4)
	var aims: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	for index in 4:
		_input.send_virtual_aim(index, aims[index])
	_run(1)
	_input.send_virtual_aim(2, Vector2.ZERO)
	_run(1)
	check(_near(_players[0].aim, Vector2.UP) and _near(_players[3].aim, Vector2.LEFT), "letting go of one stick leaves the others")


# --- The mouse ---------------------------------------------------------------------------------


## The keyboard player at (100, 100), the mouse in the world at `mouse`, moved for real when `moved`.
func _mouse_wizard(mouse: Vector2, moved: bool = true) -> Actor:
	var wizard: Actor = _wizards(1, true)
	wizard.global_position = Vector2(100, 100)
	_world.frames.mouse_world_override = mouse
	if moved:
		_input.handle_event(_mouse_move(20.0))
	return wizard


func test_the_mouse_is_not_used_before_it_moves() -> void:
	var wizard: Actor = _mouse_wizard(Vector2(100, 40), false)
	_run(1)
	check(_near(wizard.aim, Vector2.DOWN), "the mouse is not used before it moves: %s" % wizard.aim)


func test_the_keyboard_player_aims_at_the_mouse() -> void:
	var wizard: Actor = _mouse_wizard(Vector2(100, 40))
	_run(1)
	check(_near(wizard.aim, Vector2.UP), "the keyboard player aims at the mouse: %s" % wizard.aim)


func test_the_mouse_aim_is_measured_from_the_hand() -> void:
	var wizard: Actor = _wizards(1, true)
	var hand_height: float = -wizard.hand_offset.y
	wizard.global_position = Vector2(100, 100)
	_world.frames.mouse_world_override = Vector2(160, 100 - hand_height)
	_input.handle_event(_mouse_move(20.0))
	_run(1)
	check(_near(wizard.aim, Vector2.RIGHT), "a mouse level with the hand aims straight right: %s" % wizard.aim)


func test_the_mouse_aim_does_not_follow_the_walk() -> void:
	var wizard: Actor = _wizards(1, true)
	wizard.global_position = Vector2(100, 100)
	_world.frames.mouse_world_override = Vector2(160, 100 + wizard.hand_offset.y)
	_input.handle_event(_mouse_move(20.0))
	_input.handle_event(_key(KEY_S))
	_run(1)
	check(wizard.velocity.y > 0.0 and is_zero_approx(wizard.velocity.x), "the keyboard player walks down: %s" % wizard.velocity)
	check(_near(wizard.aim, Vector2.RIGHT), "the mouse aim does not follow the walk: %s" % wizard.aim)


func test_a_mouse_on_top_of_the_wizard_keeps_the_last_aim() -> void:
	var wizard: Actor = _wizards(1, true)
	wizard.global_position = Vector2(100, 100)
	_world.frames.mouse_world_override = Vector2(160, 100 + wizard.hand_offset.y)
	_input.handle_event(_mouse_move(20.0))
	_run(1)
	_world.frames.mouse_world_override = Vector2(101, 100 + wizard.hand_offset.y)
	_run(1)
	check(_near(wizard.aim, Vector2.RIGHT), "a mouse on top of the wizard keeps the last aim: %s" % wizard.aim)


func test_a_bot_ignores_the_mouse() -> void:
	_wizards(2, true)
	_world.frames.mouse_world_override = Vector2(500, 500)
	_input.handle_event(InputEventMouseMotion.new())
	_run(1)
	check(_near(_players[1].aim, Vector2.DOWN), "a bot ignores the mouse: %s" % _players[1].aim)


## Regression: the aim was measured from the feet, the reticle drawn from the feet and the shot
## fired from the hand, so the three pointed different ways. Now the shot's line passes through
## the mouse and the reticle lies on it. Casts at each mouse point; calls `check_one` with the
## shot's origin and direction and the mouse.
func _cast_at_mice(check_one: Callable) -> void:
	var wizard: Actor = _mouse_wizard(Vector2(220, 60))
	for mouse: Vector2 in [Vector2(220, 60), Vector2(40, 150), Vector2(130, 20), Vector2(160, 104)]:
		_world.frames.mouse_world_override = mouse
		_run(1)
		_fake.origins.clear()
		_fake.directions.clear()
		check(wizard.caster.cast(0), "the wizard casts at %s" % mouse)
		if not _fake.origins.is_empty():
			check_one.call(_fake.origins[0], _fake.directions[0], mouse)


func test_the_shots_line_passes_through_the_mouse() -> void:
	_cast_at_mice(func(origin: Vector2, direction: Vector2, mouse: Vector2) -> void:
		var to_mouse: Vector2 = mouse - origin
		check(absf(direction.cross(to_mouse)) < 0.01 and direction.dot(to_mouse) > 0.0,
				"the shot from %s along %s passes through the mouse at %s" % [origin, direction, mouse]))


func test_the_reticle_lies_on_the_shots_line() -> void:
	_cast_at_mice(func(origin: Vector2, direction: Vector2, _mouse: Vector2) -> void:
		var reticle: Vector2 = WizardFixture.look(_players[0]).reticle_position()
		check(absf(direction.cross(reticle - origin)) < 0.01, "the reticle at %s is on the shot's line" % reticle))


## aim_at() is the one way to aim at a point: the shot from the staff tip along it passes the
## point, and a point on the hand gives no direction.
func test_a_shot_along_aim_at_passes_the_point() -> void:
	var wizard: Actor = _wizards(1)
	wizard.global_position = Vector2(100, 100)
	for point: Vector2 in [Vector2(300, 100), Vector2(100, 300), Vector2(20, 40), Vector2(108, 70)]:
		wizard.aim = LocalInput.aim_at(wizard.aim_pivot(), point)
		var to_point: Vector2 = point - wizard.muzzle_position()
		check(_near(wizard.aim, wizard.aim.normalized()) and absf(wizard.aim.cross(to_point)) < 0.01 and wizard.aim.dot(to_point) > 0.0,
				"the shot along aim_at(%s) passes the point" % point)


func test_aim_at_a_point_on_the_hand_gives_no_direction() -> void:
	var wizard: Actor = _wizards(1)
	wizard.global_position = Vector2(100, 100)
	check(LocalInput.aim_at(wizard.aim_pivot(), wizard.aim_pivot() + Vector2(1, 1)) == Vector2.ZERO, "a point on the hand gives no direction")


# --- The muzzle --------------------------------------------------------------------------------


## A wizard at (100, 100) aiming right that pressed its first staff, and where its staff tip is.
func _aiming_right() -> Array:
	var wizard: Actor = _wizards(1)
	wizard.global_position = Vector2(100, 100)
	_input.send_virtual_aim(0, Vector2.RIGHT)
	_input.send_virtual(0, &"staff_1", 1.0)
	_run(1)
	check(wizard.staff_reach > 0.0 and wizard.hand_offset.y < 0.0, "the wizard's hand is above its feet and its staff reaches out")
	return [wizard, Vector2(100.0 + wizard.staff_reach, 100.0 + wizard.hand_offset.y)]


## Regression (issue #102): shots left the wizard's feet; they start at the staff tip.
func test_the_shot_starts_at_the_staff_tip() -> void:
	var expected: Vector2 = _aiming_right()[1]
	check(_fake.origins.size() > 0 and _near(_fake.origins[0], expected), "the shot starts at the staff tip %s, got %s" % [expected, _fake.origins])


func test_the_muzzle_is_the_hand_plus_the_reach_along_the_aim() -> void:
	var at: Array = _aiming_right()
	check(_near((at[0] as Actor).muzzle_position(), at[1]), "muzzle_position is hand height plus the reach along the aim")


# --- The look ----------------------------------------------------------------------------------


## The staff points where it aims: the head sheet's column is the direction nearest the aim.
func test_the_sprite_turns_with_the_aim() -> void:
	var sprite: Sprite2D = _sprite(_wizards(1))
	var cases: Array = [[Vector2.RIGHT, 0], [Vector2.DOWN, 4], [Vector2.LEFT, 8], [Vector2.UP, 12], [Vector2(1.0, -1.0).normalized(), 14]]
	for case: Array in cases:
		_input.send_virtual_aim(0, case[0])
		_run(1)
		check(sprite.frame_coords.x == case[1], "aiming %s shows column %d, got %d" % [case[0], case[1], sprite.frame_coords.x])


## Between two directions the nearer one shows (16 directions, 22.5 degrees each).
func test_between_two_directions_the_nearer_one_shows() -> void:
	var sprite: Sprite2D = _sprite(_wizards(1))
	for case: Array in [[10.0, 0], [13.0, 1], [-170.0, 8]]:
		_input.send_virtual_aim(0, Vector2.from_angle(deg_to_rad(case[0])))
		_run(1)
		check(sprite.frame_coords.x == case[1], "%s degrees shows column %d, got %d" % [case[0], case[1], sprite.frame_coords.x])


## The look draws the reticle only while the wizard stands (down, it draws only the revive ring).
## The look picks this up on its step, so each change is followed by one.
func test_a_standing_wizard_shows_the_reticle() -> void:
	var wizard: Actor = _wizards(1)
	_run(1)
	check(not wizard.is_down() and wizard.aim != Vector2.ZERO and not WizardFixture.look(wizard)._drawn_down, "a standing wizard shows the reticle")


func test_a_downed_wizard_hides_the_reticle() -> void:
	var wizard: Actor = _wizards(1)
	_run(1)
	wizard.health.take(wizard.health.max_health)
	_run(1)
	check(wizard.is_down() and WizardFixture.look(wizard)._drawn_down, "a downed wizard hides the reticle")


func test_a_revived_wizard_shows_the_reticle_again() -> void:
	var wizard: Actor = _wizards(1)
	_run(1)
	wizard.health.take(wizard.health.max_health)
	_run(1)
	WizardFixture.downed(wizard).revive(1)
	_run(1)
	check(not wizard.is_down() and not WizardFixture.look(wizard)._drawn_down, "a revived wizard shows the reticle again")


## The reticle, gem and rings are drawn in the ramp's base colour lightened toward white (actors
## G7: the projectile manager's `ramp_color`, lightened), one per seat and all different.
func test_each_seats_reticle_is_its_ramp_colour_lightened() -> void:
	_wizards(4)
	for index in 4:
		check(WizardFixture.look(_players[index]).light_color().is_equal_approx(ProjectilesScript.ramp_light(index)), "seat %d's reticle is its ramp colour lightened" % index)


func test_every_seats_reticle_colour_differs() -> void:
	_wizards(4)
	var seen: Array[Color] = []
	for index in 4:
		var colour: Color = WizardFixture.look(_players[index]).light_color()
		for other in seen:
			check(not other.is_equal_approx(colour), "seat %d's reticle colour differs from the others" % index)
		seen.append(colour)


# --- The dash look -----------------------------------------------------------------------------


## A wizard that has started a dash (as a dash card asks) with `action` held, and has had a step
## since. Bodies are not moved, so a test moves the wizard itself.
func _dashing_wizard(action: StringName) -> Actor:
	var wizard: Actor = _wizards(1)
	_input.send_virtual(0, action, 1.0)
	_run(1)
	# What a dash card sends: 55 px the way the wizard walks over a quarter of a second, tagged
	# with the wizard's own caster number (the Mover acts only on its own cards).
	var ways: Dictionary = {&"move_right": Vector2.RIGHT, &"move_left": Vector2.LEFT, &"move_up": Vector2.UP, &"move_down": Vector2.DOWN}
	_world.bus.caster_move_requested.emit(0, &"dash", ways[action] * 55.0, 0.25, SpellTag.make(wizard.id, 0, 0, 0))
	_run(1)
	return wizard


## A wizard whose dash ran out (60 steps at most).
func _dashed_wizard() -> Actor:
	var wizard: Actor = _dashing_wizard(&"move_right")
	var steps: int = 0
	while wizard.mover.is_moving() and steps < 60:
		_run(1)
		steps += 1
	check(not wizard.mover.is_moving(), "the dash is over")
	return wizard


## Upright: the dash stretch turned a quarter.
func _vertical_stretch() -> Vector2:
	return Vector2(StaffLook.DASH_STRETCH.y, StaffLook.DASH_STRETCH.x)


func test_the_dash_look_is_on_while_dashing() -> void:
	var wizard: Actor = _dashing_wizard(&"move_right")
	check(wizard.mover.is_moving(), "the wizard is dashing")
	check(WizardFixture.look(wizard).is_dash_look(), "the dash look is on")


func test_the_sprite_stretches_during_a_dash() -> void:
	check_equal(_stretch(_sprite(_dashing_wizard(&"move_right"))), StaffLook.DASH_STRETCH, "the sprite stretches during the dash")


func test_the_sprite_leans_into_a_dash_to_the_right() -> void:
	check(_sprite(_dashing_wizard(&"move_right")).rotation > 0.0, "the sprite leans into a dash to the right")


func test_the_dash_look_goes_off_when_the_dash_ends() -> void:
	check(not WizardFixture.look(_dashed_wizard()).is_dash_look(), "the dash look is off")


func test_the_sprite_is_back_to_normal_after_the_dash() -> void:
	var sprite: Sprite2D = _sprite(_dashed_wizard())
	check(_stretch(sprite) == Vector2.ONE and sprite.rotation == 0.0, "the sprite is back to normal after the dash: %s, %s" % [_stretch(sprite), sprite.rotation])


## The stretch follows the dash axis and the lean follows its side, also for a sprite that faces
## left.
func test_a_dash_to_the_left_stretches_sideways() -> void:
	check_equal(_stretch(_sprite(_dashing_wizard(&"move_left"))), StaffLook.DASH_STRETCH, "a dash to the left stretches sideways")


func test_a_dash_to_the_left_leans_left() -> void:
	check(_sprite(_dashing_wizard(&"move_left")).rotation < 0.0, "a dash to the left leans left")


func test_a_dash_up_stretches_upright() -> void:
	check_equal(_stretch(_sprite(_dashing_wizard(&"move_up"))), _vertical_stretch(), "a dash up stretches upright")


func test_a_dash_straight_up_does_not_lean() -> void:
	check(is_zero_approx(_sprite(_dashing_wizard(&"move_up")).rotation), "a dash straight up does not lean")


func test_a_dash_down_stretches_upright() -> void:
	check_equal(_stretch(_sprite(_dashing_wizard(&"move_down"))), _vertical_stretch(), "a dash down stretches upright")


func test_a_staff_aimed_left_dashing_right_still_leans_right() -> void:
	# The way it points and the lean are independent.
	var sprite: Sprite2D = _sprite(_dashing_wizard(&"move_right"))
	_input.send_virtual_aim(0, Vector2.LEFT)
	_run(1)
	check(sprite.frame_coords.x == 8, "the staff points left")
	check(sprite.rotation > 0.0, "the sprite still leans right")


## The ghosts start on the wizard and fall behind it as it moves, newest first.
func test_the_dash_ghosts_start_on_the_wizard() -> void:
	var wizard: Actor = _dashing_wizard(&"move_right")
	var look: StaffLook = WizardFixture.look(wizard)
	check(look._trail[0] == wizard.global_position and look._trail[2] == wizard.global_position, "the ghosts start on the wizard")


func test_the_dash_ghosts_fall_behind_the_moving_wizard() -> void:
	var wizard: Actor = _dashing_wizard(&"move_right")
	var look: StaffLook = WizardFixture.look(wizard)
	for i in 4:
		wizard.global_position += Vector2(10.0, 0.0)
		_run(1)
	check(look._trail[0].x > look._trail[1].x or look._trail[1].x > look._trail[2].x, "the ghosts fall behind as the wizard moves")
	check(look._trail[0].x <= wizard.global_position.x, "no ghost is ahead of the wizard")


## The ghosts of a dashing wizard: solid copies drawn by the shot shader (the glow look), never
## see-through, falling apart pixel by pixel, the older the more, and gone when the dash ends.
func _ghosts(wizard: Actor) -> Array[Sprite2D]:
	var look: StaffLook = WizardFixture.look(wizard)
	look._apply_dash_look(true)
	return look.ghosts()


func test_a_dash_ghost_is_solid_while_dashing() -> void:
	for ghost: Sprite2D in _ghosts(_dashing_wizard(&"move_right")):
		check(ghost.visible and ghost.modulate.a == 1.0 and ghost.self_modulate.a == 1.0, "a ghost is solid while dashing")


func test_a_dash_ghost_glows() -> void:
	for ghost: Sprite2D in _ghosts(_dashing_wizard(&"move_right")):
		check(((ghost.material as ShaderMaterial).get_shader_parameter(&"sprite_glow") as float) > 0.0, "a ghost glows")


func test_the_dash_ghosts_are_under_the_wizards_own_sprite() -> void:
	var wizard: Actor = _dashing_wizard(&"move_right")
	for ghost: Sprite2D in _ghosts(wizard):
		check(ghost.get_index() < _sprite(wizard).get_index(), "a ghost is under the wizard's own sprite")


func test_the_older_dash_ghost_is_the_more_fallen_apart() -> void:
	var ghosts: Array[Sprite2D] = _ghosts(_dashing_wizard(&"move_right"))
	check(ghosts.size() > 1, "a trail of ghosts")
	for i in range(1, ghosts.size()):
		var newer: float = (ghosts[i - 1].material as ShaderMaterial).get_shader_parameter(&"dissolve") as float
		var older: float = (ghosts[i].material as ShaderMaterial).get_shader_parameter(&"dissolve") as float
		check(newer < older, "ghost %d is more fallen apart than ghost %d" % [i, i - 1])


func test_the_dash_ghosts_hide_when_the_dash_ends() -> void:
	var wizard: Actor = _dashing_wizard(&"move_right")
	var ghosts: Array[Sprite2D] = _ghosts(wizard)
	WizardFixture.look(wizard)._apply_dash_look(false)
	check(ghosts.size() > 0 and not ghosts[0].visible, "hidden when the dash ends")


## The sprite's stretch: its scale without its art's detail (a 2x head is drawn at half, ArtDetail).
func _stretch(sprite: Sprite2D) -> Vector2:
	return sprite.scale * float(ArtDetail.of(sprite.texture))
