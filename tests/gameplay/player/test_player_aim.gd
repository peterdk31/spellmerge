extends SceneTree
## Tests for gameplay/player (aim) on the wizard actor (actors G7): shots go where the wizard
## aims, not where it walks. The right stick aims and holds for AIM_HOLD_TIME, the keyboard
## player aims at the mouse, with no aim input the wizard aims the way it walks, and four players
## aim independently. The look (WizardLook) turns the sprite, draws the reticle on the shot's line
## and stretches the sprite through a dash. Wizards are made from the real scene by the wizard
## fixture; input goes through the input manager's virtual devices; time moves by fixed deltas.
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_aim.gd

const WizardFixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const FakeSpellsScript := preload("res://tests/gameplay/player/fixtures/fake_spells.gd")

const STEP: float = WizardFixture.STEP
## Staff 0 holds a card, so the wizard can cast it.
const BOLT_CARDS: Array = [[&"bolt"], [], [], []]

var _failures: Array[String] = []
var _world: WizardFixture = null
var _players: Array[Actor] = []
var _input: InputManagerScript = null
var _fake: FakeSpellsScript = null


func _initialize() -> void:
	await process_frame
	_test_defaults_to_the_move_direction()
	_test_stick_aims_apart_from_walking()
	_test_stick_aim_holds_then_follows_the_move()
	_test_mouse_aim_for_the_keyboard_player()
	_test_mouse_aim_ignored_for_other_devices()
	_test_cast_goes_along_the_aim()
	_test_four_players_aim_alone()
	_test_sprite_turns_with_the_aim()
	_test_sprite_turn_has_a_band()
	_test_downed_wizard_hides_the_reticle()
	_test_mouse_jitter_is_not_aiming()
	_test_muzzle_is_the_staff_tip()
	_test_shot_and_reticle_line_up_with_the_mouse()
	_test_aim_at_a_point()
	_test_reticle_is_the_ramp_light_colour()
	_test_dash_look_applies_and_resets()
	_test_dash_look_follows_direction()
	_test_dash_ghosts_trail_the_wizard()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: gameplay/player (aim)")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## `count` wizards on virtual devices (staff 0 holds a bolt), on the stand-in spell runtime; with
## `keyboard` the first joins as the keyboard.
func _setup(count: int, keyboard: bool = false) -> void:
	_teardown()
	_world = WizardFixture.new(root, true)
	_input = _world.input
	_fake = _world.fake
	for index in count:
		if keyboard and index == 0:
			_input.join(InputManagerScript.KEYBOARD)
		_players.append(_world.wizard(index, Vector2.ZERO, BOLT_CARDS))


func _teardown() -> void:
	if _world != null:
		_world.free_all()
	_world = null
	_input = null
	_fake = null
	_players.clear()


## Step every wizard `count` times without moving the bodies (the old tests' wizards stood where
## they were put, and the mouse checks need the hand where it was).
func _run(count: int) -> void:
	_world.run(count, false)


func _controller(wizard: Actor) -> PlayerController:
	return WizardFixture.controller(wizard)


func _near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.001


func _test_defaults_to_the_move_direction() -> void:
	_setup(1)
	_run(1)
	_check(_near(_players[0].aim, Vector2.DOWN), "a wizard that has not moved aims down")
	_input.send_virtual(0, &"move_left", 1.0)
	_run(1)
	_check(_near(_players[0].aim, Vector2.LEFT), "with no aim input the wizard aims the way it walks")


func _test_stick_aims_apart_from_walking() -> void:
	_setup(1)
	_input.send_virtual(0, &"move_left", 1.0)
	_input.send_virtual_aim(0, Vector2.UP)
	_run(2)
	_check(_near(_players[0].aim, Vector2.UP), "the right stick aims up while walking left")
	# There is no `facing` any more; the walk shows in the velocity.
	_check(_players[0].velocity.x < 0.0 and is_zero_approx(_players[0].velocity.y), "the wizard still walks left")


func _test_stick_aim_holds_then_follows_the_move() -> void:
	_setup(1)
	_input.send_virtual(0, &"move_left", 1.0)
	_input.send_virtual_aim(0, Vector2.RIGHT)
	_run(1)
	_input.send_virtual_aim(0, Vector2.ZERO)
	_run(int(PlayerController.AIM_HOLD_TIME / STEP) - 2)
	_check(_near(_players[0].aim, Vector2.RIGHT), "the aim holds after the stick is let go")
	_run(4)
	_check(_near(_players[0].aim, Vector2.LEFT), "after the hold the aim follows the walk again")


func _test_mouse_aim_for_the_keyboard_player() -> void:
	_setup(1, true)
	var wizard: Actor = _players[0]
	var controller: PlayerController = _controller(wizard)
	var hand_height: float = -wizard.hand_offset.y
	wizard.global_position = Vector2(100, 100)
	controller.mouse_world_override = Vector2(100, 40)
	_run(1)
	_check(_near(wizard.aim, Vector2.DOWN), "the mouse is not used before it moves")
	_input.handle_event(_mouse_move(20.0))
	_run(1)
	_check(_near(wizard.aim, Vector2.UP), "the keyboard player aims at the mouse")
	# The aim is measured from the hand, the hand height above the feet.
	controller.mouse_world_override = Vector2(160, 100 - hand_height)
	var walk := InputEventKey.new()
	walk.physical_keycode = KEY_S
	walk.pressed = true
	_input.handle_event(walk)
	_run(1)
	# There is no `facing` any more; the walk shows in the velocity.
	_check(wizard.velocity.y > 0.0 and is_zero_approx(wizard.velocity.x), "the keyboard player walks down")
	_check(_near(wizard.aim, Vector2.RIGHT), "the mouse aim does not follow the walk")
	controller.mouse_world_override = Vector2(101, 100 - hand_height)
	_run(1)
	_check(_near(wizard.aim, Vector2.RIGHT), "a mouse on top of the wizard keeps the last aim")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	key.pressed = true
	_input.handle_event(key)
	_check(not _input.is_mouse_aiming(0), "the J key leaves mouse aim")


func _test_mouse_aim_ignored_for_other_devices() -> void:
	_setup(2, true)
	_controller(_players[1]).mouse_world_override = Vector2(500, 500)
	_input.handle_event(InputEventMouseMotion.new())
	_run(1)
	_check(_near(_players[1].aim, Vector2.DOWN), "a bot ignores the mouse")


func _test_cast_goes_along_the_aim() -> void:
	_setup(1)
	_input.send_virtual(0, &"move_left", 1.0)
	_input.send_virtual_aim(0, Vector2.UP)
	_run(1)
	_check(_players[0].caster.cast(0), "the wizard casts")
	_check(_fake.directions.size() == 1 and _near(_fake.directions[0], Vector2.UP), "the spell got the aim, not the walk direction")


func _test_four_players_aim_alone() -> void:
	_setup(4)
	var aims: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	for index in 4:
		_input.send_virtual_aim(index, aims[index])
	_run(1)
	for index in 4:
		_check(_near(_players[index].aim, aims[index]), "player %d aims their own way" % index)
	_input.send_virtual_aim(2, Vector2.ZERO)
	_run(1)
	_check(_near(_players[0].aim, Vector2.UP) and _near(_players[3].aim, Vector2.LEFT), "letting go of one stick leaves the others")


func _test_sprite_turns_with_the_aim() -> void:
	_setup(1)
	var wizard: Actor = _players[0]
	var sprite := wizard.get_node("Sprite") as Sprite2D
	_input.send_virtual_aim(0, Vector2.LEFT)
	_run(1)
	_check(sprite.flip_h, "the sprite turns left when aiming left")
	_check(WizardFixture.look(wizard).faces_left(), "the look says it faces left")
	_input.send_virtual_aim(0, Vector2.RIGHT)
	_run(1)
	_check(not sprite.flip_h, "the sprite turns back when aiming right")


func _mouse_move(distance: float) -> InputEventMouseMotion:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(distance, 0.0)
	return motion


func _test_sprite_turn_has_a_band() -> void:
	_setup(1)
	var wizard: Actor = _players[0]
	var sprite := wizard.get_node("Sprite") as Sprite2D
	_input.send_virtual_aim(0, Vector2.LEFT)
	_run(1)
	_input.send_virtual_aim(0, Vector2(0.2, 1.0).normalized())
	_run(1)
	_check(sprite.flip_h, "a small wobble past straight down does not unflip the sprite")
	_input.send_virtual_aim(0, Vector2(0.9, 0.4).normalized())
	_run(1)
	_check(not sprite.flip_h, "aiming clearly right unflips the sprite")


## The look draws the reticle only while the wizard stands (down, it draws only the revive ring).
## The look picks this up on its step, so each change is followed by one.
func _test_downed_wizard_hides_the_reticle() -> void:
	_setup(1)
	var wizard: Actor = _players[0]
	var look: WizardLook = WizardFixture.look(wizard)
	_run(1)
	_check(not wizard.is_down() and wizard.aim != Vector2.ZERO and not look._drawn_down, "a standing wizard shows the reticle")
	wizard.health.take(wizard.health.max_health)
	_run(1)
	_check(wizard.is_down() and look._drawn_down, "a downed wizard hides the reticle")
	WizardFixture.downed(wizard).revive(1)
	_run(1)
	_check(not wizard.is_down() and not look._drawn_down, "a revived wizard shows the reticle again")


func _test_mouse_jitter_is_not_aiming() -> void:
	_setup(1, true)
	_input.handle_event(_mouse_move(1.0))
	_input.handle_event(_mouse_move(-2.0))
	_check(not _input.is_mouse_aiming(0), "a tiny mouse brush does not turn mouse aim on")
	_input.handle_event(_mouse_move(20.0))
	_check(_input.is_mouse_aiming(0), "a real mouse move does")


## Regression (issue #102): shots left the wizard's feet; they start at the staff tip.
func _test_muzzle_is_the_staff_tip() -> void:
	_setup(1)
	var wizard: Actor = _players[0]
	wizard.global_position = Vector2(100, 100)
	_input.send_virtual_aim(0, Vector2.RIGHT)
	_input.send_virtual(0, &"staff_1", 1.0)
	_run(1)
	var expected := Vector2(100.0 + wizard.staff_reach, 100.0 + wizard.hand_offset.y)
	_check(wizard.staff_reach > 0.0 and wizard.hand_offset.y < 0.0, "the wizard's hand is above its feet and its staff reaches out")
	_check(_fake.origins.size() > 0 and _near(_fake.origins[0], expected), "the shot starts at the staff tip, got %s" % [_fake.origins])
	_check(_near(wizard.muzzle_position(), expected), "muzzle_position is hand height plus the reach along the aim")


## A fresh wizard that has started a dash (as a dash card asks) with `action` held, and has had a
## step since. Bodies are not moved, so a test moves the wizard itself.
func _dashing_wizard(action: StringName) -> Actor:
	_setup(1)
	var wizard: Actor = _players[0]
	_input.send_virtual(0, action, 1.0)
	_run(1)
	# What a dash card sends (staffs A6a): 55 px over a quarter of a second, tagged with the
	# wizard's own caster number (the Mover acts only on its own cards).
	_world.bus.caster_move_requested.emit(0, &"dash", wizard.muzzle_position() + Vector2(55.0, 0.0), 0.25, SpellTag.make(wizard.id, 0, 0, 0))
	_run(1)
	return wizard


## Regression: the aim was measured from the feet, the reticle drawn from the feet
## and the shot fired from the hand, so the three pointed different ways. Now the
## shot's line passes through the mouse and the reticle lies on it.
func _test_shot_and_reticle_line_up_with_the_mouse() -> void:
	_setup(1, true)
	var wizard: Actor = _players[0]
	var look: WizardLook = WizardFixture.look(wizard)
	wizard.global_position = Vector2(100, 100)
	_input.handle_event(_mouse_move(20.0))
	for mouse: Vector2 in [Vector2(220, 60), Vector2(40, 150), Vector2(130, 20), Vector2(160, 104)]:
		_controller(wizard).mouse_world_override = mouse
		_run(1)
		_fake.origins.clear()
		_fake.directions.clear()
		_check(wizard.caster.cast(0), "the wizard casts at %s" % mouse)
		if _fake.origins.is_empty():
			continue
		var origin: Vector2 = _fake.origins[0]
		var direction: Vector2 = _fake.directions[0]
		var to_mouse: Vector2 = mouse - origin
		_check(absf(direction.cross(to_mouse)) < 0.01 and direction.dot(to_mouse) > 0.0,
				"the shot from %s along %s passes through the mouse at %s" % [origin, direction, mouse])
		var to_reticle: Vector2 = look.reticle_position() - origin
		_check(absf(direction.cross(to_reticle)) < 0.01, "the reticle at %s is on the shot's line" % look.reticle_position())


## aim_at() is the one way to aim at a point: the shot from the staff tip along it
## passes the point, and a point on the hand gives no direction.
func _test_aim_at_a_point() -> void:
	_setup(1)
	var wizard: Actor = _players[0]
	var controller: PlayerController = _controller(wizard)
	wizard.global_position = Vector2(100, 100)
	for point: Vector2 in [Vector2(300, 100), Vector2(100, 300), Vector2(20, 40), Vector2(108, 70)]:
		wizard.aim = controller.aim_at(wizard, point)
		var to_point: Vector2 = point - wizard.muzzle_position()
		_check(_near(wizard.aim, wizard.aim.normalized()) and absf(wizard.aim.cross(to_point)) < 0.01 and wizard.aim.dot(to_point) > 0.0,
				"the shot along aim_at(%s) passes the point" % point)
	_check(controller.aim_at(wizard, wizard.aim_pivot() + Vector2(1, 1)) == Vector2.ZERO, "a point on the hand gives no direction")


## The reticle, gem and rings are drawn in the ramp's base colour lightened toward white (actors
## G7: the projectile manager's `ramp_color`, lightened), one per seat and all different.
func _test_reticle_is_the_ramp_light_colour() -> void:
	_setup(4)
	var seen: Array[Color] = []
	for index in 4:
		var look: WizardLook = WizardFixture.look(_players[index])
		var expected: Color = ProjectilesScript.ramp_light(index)
		_check(look.light_color().is_equal_approx(expected), "seat %d's reticle is its ramp colour lightened" % index)
		for other in seen:
			_check(not other.is_equal_approx(look.light_color()), "seat %d's reticle colour differs from the others" % index)
		seen.append(look.light_color())


## The dash stretches and leans the sprite, and the look is gone when the dash ends.
func _test_dash_look_applies_and_resets() -> void:
	var wizard := _dashing_wizard(&"move_right")
	var sprite := wizard.get_node("Sprite") as Sprite2D
	var look: WizardLook = WizardFixture.look(wizard)
	_check(wizard.mover.is_moving(), "the wizard is dashing")
	_check(look.is_dash_look(), "the dash look is on")
	_check(sprite.scale == WizardLook.DASH_STRETCH, "the sprite stretches during the dash")
	_check(sprite.rotation > 0.0, "the sprite leans into a dash to the right")
	var steps: int = 0
	while wizard.mover.is_moving() and steps < 60:
		_run(1)
		steps += 1
	_check(not wizard.mover.is_moving(), "the dash is over")
	_check(not look.is_dash_look(), "the dash look is off")
	_check(sprite.scale == Vector2.ONE and sprite.rotation == 0.0, "the sprite is back to normal after the dash")


## The stretch follows the dash axis and the lean follows its side, also for a
## sprite that faces left.
func _test_dash_look_follows_direction() -> void:
	var wizard := _dashing_wizard(&"move_left")
	var sprite := wizard.get_node("Sprite") as Sprite2D
	_check(sprite.scale == WizardLook.DASH_STRETCH and sprite.rotation < 0.0, "a dash to the left stretches sideways and leans left")
	var vertical := Vector2(WizardLook.DASH_STRETCH.y, WizardLook.DASH_STRETCH.x)
	wizard = _dashing_wizard(&"move_up")
	sprite = wizard.get_node("Sprite") as Sprite2D
	_check(sprite.scale == vertical, "a dash up stretches upright, got %s" % [sprite.scale])
	_check(is_zero_approx(sprite.rotation), "a dash straight up does not lean")
	wizard = _dashing_wizard(&"move_down")
	sprite = wizard.get_node("Sprite") as Sprite2D
	_check(sprite.scale == vertical, "a dash down stretches upright, got %s" % [sprite.scale])
	# A left-facing sprite (aim left) dashing right: flip and lean are independent.
	wizard = _dashing_wizard(&"move_right")
	sprite = wizard.get_node("Sprite") as Sprite2D
	_input.send_virtual_aim(0, Vector2.LEFT)
	_run(1)
	_check(sprite.flip_h and sprite.rotation > 0.0, "a left-facing wizard dashing right still leans right")


## The ghosts start on the wizard and fall behind it as it moves, newest first.
func _test_dash_ghosts_trail_the_wizard() -> void:
	var wizard := _dashing_wizard(&"move_right")
	var look: WizardLook = WizardFixture.look(wizard)
	_check(look._trail[0] == wizard.global_position and look._trail[2] == wizard.global_position, "the ghosts start on the wizard")
	for i in 4:
		wizard.global_position += Vector2(10.0, 0.0)
		_run(1)
	_check(look._trail[0].x > look._trail[1].x or look._trail[1].x > look._trail[2].x, "the ghosts fall behind as the wizard moves")
	_check(look._trail[0].x <= wizard.global_position.x, "no ghost is ahead of the wizard")
	# Solid copies drawn by the shot shader (the glow look): never see-through, falling apart
	# pixel by pixel, the older the more, and gone when the dash ends.
	look._apply_dash_look(true)
	var ghosts: Array[Sprite2D] = look.ghosts()
	_check(ghosts.size() == 3, "three ghosts")
	var dissolves: Array[float] = []
	for ghost: Sprite2D in ghosts:
		_check(ghost.visible and ghost.modulate.a == 1.0 and ghost.self_modulate.a == 1.0, "a ghost is solid while dashing")
		var material := ghost.material as ShaderMaterial
		dissolves.append(material.get_shader_parameter(&"dissolve") as float)
		_check((material.get_shader_parameter(&"sprite_glow") as float) > 0.0, "and glows")
		_check(ghost.get_index() < wizard.get_node("Sprite").get_index(), "under the wizard's own sprite")
	_check(dissolves.size() == 3 and dissolves[0] < dissolves[1] and dissolves[1] < dissolves[2], "the older the more fallen apart")
	look._apply_dash_look(false)
	_check(ghosts.size() > 0 and not ghosts[0].visible, "hidden when the dash ends")
