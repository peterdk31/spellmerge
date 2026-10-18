extends SceneTree
## Tests for gameplay/player (animation): the wizard scene lists an idle, a walk
## and a dash strip for each of the four players, the sprite plays the strip that
## fits what the wizard does, and the staff art is set. Input goes through the
## input manager's virtual devices; time moves by fixed deltas.
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_animation.gd

const PlayerScript := preload("res://gameplay/player/player.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const WizardScene := preload("res://content/wizard/base/wizard.tscn")

const STEP: float = 0.0625

var _failures: Array[String] = []
var _bus: Node
var _input: Node
var _wizard: PlayerScript


func _initialize() -> void:
	await process_frame
	_test_scene_lists_the_strips()
	_test_idle_at_rest()
	_test_walking_plays_the_walk_strip()
	_test_dash_plays_once_then_idle()
	_test_every_player_shows_its_own_strips()
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


## A wizard of the scene for player `index` with a virtual device, after _ready().
func _setup(index: int = 0) -> void:
	_teardown()
	_bus = EventsScript.new()
	_input = InputManagerScript.new()
	_input.events = _bus
	_input.add_virtual_device(index)
	_wizard = WizardScene.instantiate() as PlayerScript
	_wizard.index = index
	_wizard.input = _input
	_wizard.events = _bus
	_wizard._ready()


func _teardown() -> void:
	if _wizard != null:
		_wizard.free()
		_wizard = null
	for node: Node in [_input, _bus]:
		if node != null:
			node.free()
	_input = null
	_bus = null


func _sprite() -> Sprite2D:
	return _wizard.get_node("Sprite") as Sprite2D


func _run(steps: int) -> void:
	for i in steps:
		_wizard.step(STEP)


# --- Tests ------------------------------------------------------------------

func _test_scene_lists_the_strips() -> void:
	_setup()
	_check(_wizard.walk_textures.size() == 4, "the wizard scene lists four walk strips")
	_check(_wizard.dash_textures.size() == 4, "the wizard scene lists four dash strips")
	_check(_wizard.staff_texture != null, "the wizard scene sets the staff art")
	for list: Array[Texture2D] in [_wizard.textures, _wizard.walk_textures, _wizard.dash_textures]:
		for texture in list:
			_check(texture != null and texture.get_height() == PlayerScript.FRAME_SIZE, "a strip is one frame high")
			_check(texture != null and texture.get_width() % PlayerScript.FRAME_SIZE == 0, "a strip is whole frames wide")
	_check(_wizard.walk_textures[0].get_width() > PlayerScript.FRAME_SIZE, "the walk strip has more than one frame")


func _test_idle_at_rest() -> void:
	_setup()
	_run(2)
	var sprite := _sprite()
	_check(sprite.texture == _wizard.textures[0], "a wizard at rest shows the idle strip")
	_check(sprite.hframes == int(sprite.texture.get_width() / PlayerScript.FRAME_SIZE), "the sprite cuts the strip into its frames")
	# The idle loops: after long enough the frame has moved on but stays inside the strip.
	_run(int(1.0 / STEP / PlayerScript.IDLE_FPS) + 1)
	_check(sprite.frame >= 0 and sprite.frame < sprite.hframes, "the idle frame stays inside the strip")


func _test_walking_plays_the_walk_strip() -> void:
	_setup()
	_input.send_virtual(0, &"move_right", 1.0)
	_run(1)
	var sprite := _sprite()
	_check(sprite.texture == _wizard.walk_textures[0], "a walking wizard shows the walk strip")
	_check(sprite.frame == 0, "the walk starts on its first frame")
	var seen: Dictionary = {}
	for i in 40:
		_run(1)
		seen[sprite.frame] = true
		_check(sprite.frame < sprite.hframes, "the walk frame stays inside the strip")
	_check(seen.size() == sprite.hframes, "the walk loop plays every frame, saw %s" % [seen.keys()])
	_input.send_virtual(0, &"move_right", 0.0)
	_run(1)
	_check(sprite.texture == _wizard.textures[0], "back to the idle strip when the wizard stops")


func _test_dash_plays_once_then_idle() -> void:
	_setup()
	_input.send_virtual(0, &"move_right", 1.0)
	_input.send_virtual(0, &"dodge", 1.0)
	_input.send_virtual(0, &"dodge", 0.0)
	_run(1)
	var sprite := _sprite()
	_check(_wizard.is_dodging(), "the wizard is dashing")
	_check(sprite.texture == _wizard.dash_textures[0], "a dashing wizard shows the dash strip")
	var last: int = sprite.hframes - 1
	var steps: int = 0
	while _wizard.is_dodging() and steps < 60:
		_run(1)
		steps += 1
		if _wizard.is_dodging():
			_check(sprite.frame <= last, "the dash frame stays inside the strip")
	# The dash is longer than its strip, so the last frame is held (not looped).
	_check(PlayerScript.DODGE_TIME * PlayerScript.DASH_FPS >= float(sprite.hframes), "the dash lasts as long as its strip")
	_input.send_virtual(0, &"move_right", 0.0)
	_run(2)
	_check(sprite.texture == _wizard.textures[0], "idle again after the dash")


func _test_every_player_shows_its_own_strips() -> void:
	for index in 4:
		_setup(index)
		_input.send_virtual(index, &"move_left", 1.0)
		_run(1)
		_check(_sprite().texture == _wizard.walk_textures[index], "player %d walks with its own strip" % index)
