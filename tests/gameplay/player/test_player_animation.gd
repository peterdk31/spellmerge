extends SceneTree
## Tests for gameplay/player (animation) on the wizard actor (actors G7): the wizard scene's
## look (WizardLook) lists an idle, a walk and a dash strip for each of the four players, the
## sprite plays the strip that fits what the wizard does, and the staff art is set. Wizards are
## made from the real scene by the wizard fixture; input goes through the input manager's
## virtual devices; time moves by fixed deltas.
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_animation.gd

const WizardFixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const ImpScene := preload("res://content/enemies/ember_imp/ember_imp.tscn")

const STEP: float = WizardFixture.STEP

var _failures: Array[String] = []
var _world: WizardFixture = null
var _input: InputManagerScript = null
var _wizard: Actor = null
var _look: WizardLook = null


func _initialize() -> void:
	await process_frame
	_test_scene_lists_the_strips()
	_test_idle_at_rest()
	_test_idle_blinks_glances_and_breathes()
	_test_players_do_not_idle_in_step()
	_test_glances_follow_the_facing()
	_test_walk_and_dash_move_the_body()
	_test_walking_plays_the_walk_strip()
	_test_dash_plays_once_then_idle()
	_test_invulnerable_look_follows_the_window()
	_test_every_player_shows_its_own_strips()
	_test_imp_plays_its_idle()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: gameplay/player (animation)")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## A wizard of the scene for seat `index` with a virtual device, in the tree and ready.
func _setup(index: int = 0) -> void:
	_teardown()
	_world = WizardFixture.new(root, true)
	_input = _world.input
	_wizard = _world.wizard(index)
	_look = WizardFixture.look(_wizard)


## The imp is a two-frame strip and its scene plays the idle animation on its own.
func _test_imp_plays_its_idle() -> void:
	var imp: Node = ImpScene.instantiate()
	var sprite: Sprite2D = imp.get_node("Sprite") as Sprite2D
	var animation: AnimationPlayer = imp.get_node("AnimationPlayer") as AnimationPlayer
	_check(sprite.hframes == 2, "the imp sprite has 2 frames")
	_check(animation.has_animation(&"idle") and animation.autoplay == "idle", "the imp scene autoplays idle")
	imp.free()


func _teardown() -> void:
	if _world != null:
		_world.free_all()
	_world = null
	_input = null
	_wizard = null
	_look = null


func _sprite() -> Sprite2D:
	return _wizard.get_node("Sprite") as Sprite2D


func _run(steps: int) -> void:
	_world.run(steps)


# --- Tests ------------------------------------------------------------------

func _test_scene_lists_the_strips() -> void:
	_setup()
	_check(_look.walk_textures.size() == 4, "the wizard scene lists four walk strips")
	_check(_look.dash_textures.size() == 4, "the wizard scene lists four dash strips")
	_check(_look.staff_texture != null, "the wizard scene sets the staff art")
	for list: Array[Texture2D] in [_look.textures, _look.walk_textures, _look.dash_textures]:
		for texture in list:
			_check(texture != null and texture.get_height() == WizardLook.FRAME_SIZE, "a strip is one frame high")
			_check(texture != null and texture.get_width() % WizardLook.FRAME_SIZE == 0, "a strip is whole frames wide")
	_check(_look.walk_textures[0].get_width() > WizardLook.FRAME_SIZE, "the walk strip has more than one frame")


func _test_idle_at_rest() -> void:
	_setup()
	_run(2)
	var sprite := _sprite()
	_check(sprite.texture == _look.textures[0], "a wizard at rest shows the idle strip")
	_check(sprite.hframes == int(sprite.texture.get_width() / WizardLook.FRAME_SIZE), "the sprite cuts the strip into its frames")
	# The idle loops: after long enough the frame has moved on but stays inside the strip.
	_run(int(1.0 / STEP / WizardLook.IDLE_FPS) + 1)
	_check(sprite.frame >= 0 and sprite.frame < sprite.hframes, "the idle frame stays inside the strip")


func _test_walking_plays_the_walk_strip() -> void:
	_setup()
	_input.send_virtual(0, &"move_right", 1.0)
	_run(1)
	var sprite := _sprite()
	_check(sprite.texture == _look.walk_textures[0], "a walking wizard shows the walk strip")
	_check(sprite.frame == 0, "the walk starts on its first frame")
	var seen: Dictionary = {}
	for i in 40:
		_run(1)
		seen[sprite.frame] = true
		_check(sprite.frame < sprite.hframes, "the walk frame stays inside the strip")
	_check(seen.size() == sprite.hframes, "the walk loop plays every frame, saw %s" % [seen.keys()])
	_input.send_virtual(0, &"move_right", 0.0)
	_run(1)
	_check(sprite.texture == _look.textures[0], "back to the idle strip when the wizard stops")


## What a dash card sends (staffs A6a): a dash of DASH_TIME seconds.
const DASH_TIME: float = 0.25


func _dash() -> void:
	# Tagged with the wizard's own caster number: the Mover acts only on its own cards.
	_world.bus.caster_move_requested.emit(0, &"dash", _wizard.muzzle_position() + Vector2(55.0, 0.0), DASH_TIME, SpellTag.make(_wizard.id, 0, 0, 0))


func _test_dash_plays_once_then_idle() -> void:
	_setup()
	_input.send_virtual(0, &"move_right", 1.0)
	_run(1)
	_dash()
	_run(1)
	var sprite := _sprite()
	_check(_wizard.mover.is_moving(), "the wizard is dashing")
	_check(sprite.texture == _look.dash_textures[0], "a dashing wizard shows the dash strip")
	var last: int = sprite.hframes - 1
	var steps: int = 0
	while _wizard.mover.is_moving() and steps < 60:
		_run(1)
		steps += 1
		if _wizard.mover.is_moving():
			_check(sprite.frame <= last, "the dash frame stays inside the strip")
	# The dash is longer than its strip, so the last frame is held (not looped).
	_check(DASH_TIME * WizardLook.DASH_FPS >= float(sprite.hframes), "the dash lasts as long as its strip")
	_input.send_virtual(0, &"move_right", 0.0)
	_run(2)
	_check(sprite.texture == _look.textures[0], "idle again after the dash")


## While the wizard is protected (join or revive) the sprite is translucent and the ring shows;
## both are gone as soon as the protection ends. A dash gives none (staffs A6a).
func _test_invulnerable_look_follows_the_window() -> void:
	_setup()
	_check(_sprite().modulate.a == 1.0 and not _look.is_invulnerable_look(), "a wizard at rest is opaque with no ring")
	_dash()
	_run(1)
	_check(_wizard.mover.is_moving(), "the wizard is dashing")
	_check(not _wizard.health.is_protected() and not _look.is_invulnerable_look(), "a dash does not protect")
	_setup()
	WizardFixture.downed(_wizard).protect(1.0)
	_run(1)
	_check(_look.is_invulnerable_look(), "protection (join or revive) shows the same look")
	_check(_sprite().modulate.a < 1.0, "the protected sprite is translucent")
	_wizard.health._protect_left = 0.0
	_wizard.health.take(_wizard.health.max_health)
	# The look follows the body on its step (it reads the actor, changing nothing).
	_run(1)
	_check(_wizard.is_down(), "the wizard is down")
	_check(_sprite().modulate.a == 1.0 and not _look.is_invulnerable_look(), "a downed wizard is opaque with no ring")


func _test_every_player_shows_its_own_strips() -> void:
	for index in 4:
		_setup(index)
		_input.send_virtual(index, &"move_left", 1.0)
		_run(1)
		_check(_sprite().texture == _look.walk_textures[index], "player %d walks with its own strip" % index)
		var hat: Sprite2D = _sprite().get_node("Hat") as Sprite2D
		_check(hat.texture == _look.hat_textures[index], "player %d wears its own hat" % index)


## The idle blinks, glances both ways and breathes within one loop of its sequence, and the
## hat always sits where the body does.
func _test_idle_blinks_glances_and_breathes() -> void:
	_setup()
	var sprite: Sprite2D = _sprite()
	var hat: Sprite2D = sprite.get_node("Hat") as Sprite2D
	var poses: Dictionary = {}
	var bobs: Dictionary = {}
	var loop_steps: int = int(float(WizardLook.IDLE_SEQUENCE.size()) / WizardLook.IDLE_FPS / STEP) + 1
	for i in loop_steps:
		_run(1)
		poses[sprite.frame] = true
		bobs[int(sprite.offset.y)] = true
		_check(is_equal_approx(hat.position.y, sprite.offset.y), "the hat sits where the body does")
	_check(poses.size() == sprite.hframes, "the idle loop shows every pose, saw %s" % [poses.keys()])
	_check(bobs.size() == 2, "the body breathes between two heights, saw %s" % [bobs.keys()])
	# Most of the time the eyes are open: a blink is a moment, not a state.
	var open: int = WizardLook.IDLE_SEQUENCE.count(0)
	_check(open * 4 >= WizardLook.IDLE_SEQUENCE.size() * 3, "the eyes are open most of the time")


## Two wizards standing side by side are not on the same beat of the idle.
func _test_players_do_not_idle_in_step() -> void:
	var first: Array[int] = []
	var second: Array[int] = []
	for index in 2:
		_setup(index)
		for i in 160:
			_run(1)
			var shown: int = _sprite().frame * 10 + int(_sprite().offset.y)
			if index == 0:
				first.append(shown)
			else:
				second.append(shown)
	_check(first != second, "two players show different idle poses at the same moment")


## "Glance left" is on screen: the sprite is mirrored when facing left, so the poses swap.
func _test_glances_follow_the_facing() -> void:
	_setup()
	var glance_step: int = WizardLook.IDLE_SEQUENCE.find(2)
	_check(glance_step >= 0, "the sequence has a glance left")
	_check(_look.anim() == WizardLook.Anim.IDLE, "a fresh wizard shows the idle")
	_look._faces_left = true
	_look._anim_time = (float(glance_step) + 0.5) / WizardLook.IDLE_FPS
	_look._update_animation(0.0, false)
	_check(_sprite().frame == 3, "a left glance uses the right-glancing pose when the sprite is mirrored")
	_look._faces_left = false
	_look._update_animation(0.0, false)
	_check(_sprite().frame == 2, "a left glance uses the left pose when facing right")


## The walk dips the body on its stride frames and the dash crouches, then lifts it; the
## bob is gone again once the wizard stands still.
func _test_walk_and_dash_move_the_body() -> void:
	_setup()
	_input.send_virtual(0, &"move_right", 1.0)
	var sprite: Sprite2D = _sprite()
	var bobs: Dictionary = {}
	for i in 40:
		_run(1)
		bobs[int(sprite.offset.y)] = true
	_check(bobs.size() == 2, "the walk dips the body on alternate frames, saw %s" % [bobs.keys()])
	_dash()
	_run(1)
	_check(_wizard.mover.is_moving(), "the wizard is dashing")
	_check(sprite.offset.y > 0.0, "the dash starts in a crouch")
	_run(1)
	_check(_wizard.mover.is_moving() and sprite.offset.y < 0.0, "the dash then lifts the body off the ground")
	_input.send_virtual(0, &"move_right", 0.0)
	_run(int(DASH_TIME / STEP) + 4)
	_check(not _wizard.mover.is_moving() and sprite.frame == 0, "standing still again")
