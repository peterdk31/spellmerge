extends SceneTree
## Tests for gameplay/player (aim): shots go where the wizard aims, not where it
## walks. The right stick aims and holds for AIM_HOLD_TIME, the keyboard player
## aims at the mouse, with no aim input the wizard aims the way it walks, and
## four players aim independently. Input goes through the input manager's
## virtual devices; time moves by fixed deltas.
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_aim.gd

const PlayerScript := preload("res://gameplay/player/player.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const WizardScene := preload("res://content/wizard/base/wizard.tscn")
const AimSpell := preload("res://tests/gameplay/player/fixtures/aim_spell.gd")

const STEP: float = 0.0625

var _failures: Array[String] = []
var _bus: Node
var _input: Node
var _players: Array[PlayerScript] = []


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


## `count` wizards on virtual devices; with `keyboard` the first joins as the keyboard.
func _setup(count: int, keyboard: bool = false) -> void:
	_teardown()
	_bus = EventsScript.new()
	_input = InputManagerScript.new()
	_input.events = _bus
	for index in count:
		if keyboard and index == 0:
			_input.join(InputManagerScript.KEYBOARD)
		else:
			_input.add_virtual_device(index)
		var player := PlayerScript.new()
		player.index = index
		player.input = _input
		player.events = _bus
		player.spell = AimSpell.new()
		player._ready()
		_players.append(player)


func _teardown() -> void:
	for player in _players:
		player.free()
	_players.clear()
	for node: Node in [_input, _bus]:
		if node != null:
			node.free()
	_input = null
	_bus = null


func _run(count: int) -> void:
	for i in count:
		for player in _players:
			player.step(STEP)


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
	_check(_near(_players[0].facing, Vector2.LEFT), "walking still sets facing")


func _test_stick_aim_holds_then_follows_the_move() -> void:
	_setup(1)
	_input.send_virtual(0, &"move_left", 1.0)
	_input.send_virtual_aim(0, Vector2.RIGHT)
	_run(1)
	_input.send_virtual_aim(0, Vector2.ZERO)
	_run(int(PlayerScript.AIM_HOLD_TIME / STEP) - 2)
	_check(_near(_players[0].aim, Vector2.RIGHT), "the aim holds after the stick is let go")
	_run(4)
	_check(_near(_players[0].aim, Vector2.LEFT), "after the hold the aim follows the walk again")


func _test_mouse_aim_for_the_keyboard_player() -> void:
	_setup(1, true)
	_players[0].global_position = Vector2(100, 100)
	_players[0].mouse_world_override = Vector2(100, 40)
	_run(1)
	_check(_near(_players[0].aim, Vector2.DOWN), "the mouse is not used before it moves")
	_input.handle_event(InputEventMouseMotion.new())
	_run(1)
	_check(_near(_players[0].aim, Vector2.UP), "the keyboard player aims at the mouse")
	_players[0].mouse_world_override = Vector2(160, 100)
	var walk := InputEventKey.new()
	walk.physical_keycode = KEY_S
	walk.pressed = true
	_input.handle_event(walk)
	_run(1)
	_check(_near(_players[0].facing, Vector2.DOWN), "the keyboard player walks down")
	_check(_near(_players[0].aim, Vector2.RIGHT), "the mouse aim does not follow the walk")
	_players[0].mouse_world_override = Vector2(101, 100)
	_run(1)
	_check(_near(_players[0].aim, Vector2.RIGHT), "a mouse on top of the wizard keeps the last aim")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	key.pressed = true
	_input.handle_event(key)
	_check(not _input.is_mouse_aiming(0), "the J key leaves mouse aim")


func _test_mouse_aim_ignored_for_other_devices() -> void:
	_setup(2, true)
	_players[1].mouse_world_override = Vector2(500, 500)
	_input.handle_event(InputEventMouseMotion.new())
	_run(1)
	_check(_near(_players[1].aim, Vector2.DOWN), "a bot ignores the mouse")


func _test_cast_goes_along_the_aim() -> void:
	_setup(1)
	_input.send_virtual(0, &"move_left", 1.0)
	_input.send_virtual_aim(0, Vector2.UP)
	_run(1)
	_check(_players[0].cast(), "the wizard casts")
	var spell: AimSpell = _players[0].spell
	_check(spell.directions.size() == 1 and _near(spell.directions[0], Vector2.UP), "the spell got the aim, not the walk direction")


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
	_teardown()
	_bus = EventsScript.new()
	_input = InputManagerScript.new()
	_input.events = _bus
	_input.add_virtual_device(0)
	var wizard := WizardScene.instantiate() as PlayerScript
	wizard.input = _input
	wizard.events = _bus
	wizard._ready()
	_players.append(wizard)
	var sprite := wizard.get_node("Sprite") as Sprite2D
	_input.send_virtual_aim(0, Vector2.LEFT)
	wizard.step(STEP)
	_check(sprite.flip_h, "the sprite turns left when aiming left")
	_input.send_virtual_aim(0, Vector2.RIGHT)
	wizard.step(STEP)
	_check(not sprite.flip_h, "the sprite turns back when aiming right")
