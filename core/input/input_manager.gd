extends Node
## The input manager: one autoload ("PlayerInput") that gives every player
## their own device.
##
## Devices join by a button press (the `join` action): a gamepad takes the
## lowest free player index, the keyboard and mouse only ever take player 0
## (P1), so P2-P4 are gamepads. The `leave` action, or unplugging a gamepad,
## frees the slot. Bots use virtual devices, one per player index, that feed the
## same handle_event() path real devices use.
##
## Device ids: KEYBOARD (keys and mouse), a gamepad's own id (0 and up), and
## VIRTUAL_BASE + player index for a virtual device. Gameplay never reads
## `Input` directly; it asks this manager by player index:
##
##     var move: Vector2 = PlayerInput.get_move(player)
##     if PlayerInput.is_action_just_pressed(player, &"dodge"):
##
## Joins and leaves are announced as `device_joined` and `device_left` on the
## Events bus. Nothing here allocates per frame; events allocate only when a
## bot sends one.
##
## A player's input can be captured (set_captured) while one of their UI panels
## is open: the gameplay questions below (get_move, get_strength,
## is_action_pressed, is_action_just_pressed) then answer "nothing" for the
## actions in CAPTURED_ACTIONS, so a wizard does not walk, cast or dodge while
## their player works a menu. Gameplay needs no extra check. core/ui_focus reads
## get_press_count instead, which is never captured.
##
## Several inputs can feed one action (W and Up, the d-pad and the stick). Each
## input is tracked as its own source and the action takes the strongest one, so
## letting go of one input never cancels another that is still held.

const EventsScript := preload("res://core/events/events.gd")

## The keyboard and mouse as one device.
const KEYBOARD: int = -1
## Virtual device ids are VIRTUAL_BASE + player index, far above any gamepad id.
const VIRTUAL_BASE: int = 1000
## Returned where there is no device.
const NO_DEVICE: int = -100
## Returned by player_of() for a device that has not joined.
const NO_PLAYER: int = -1
const MAX_PLAYERS: int = 4
## Stick values below this count as zero; above it they are rescaled to 0..1.
const DEADZONE: float = 0.25
## Gamepad axes (Godot's JoyAxis values).
const AXIS_LEFT_X: int = 0
const AXIS_LEFT_Y: int = 1
const AXIS_TRIGGER_RIGHT: int = 5
## A trigger counts as pressed above this value.
const TRIGGER_PRESSED: float = 0.5

## The per-player actions, defined in project.godot. `join` and `leave` are
## handled here and are not per-player state.
const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down", &"dodge", &"cast", &"overlay",
]
## Source ids: keys use their keycode; the other kinds sit in separate ranges.
const SOURCE_MOUSE: int = 1 << 40
const SOURCE_BUTTON: int = 2 << 40
const SOURCE_AXIS: int = 3 << 40
const SOURCE_VIRTUAL: int = 4 << 40
## The actions hidden from gameplay while a player is captured. `overlay` stays
## readable so the overlay can close itself with its own button.
const CAPTURED_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down", &"dodge", &"cast",
]
const JOIN: StringName = &"join"
const LEAVE: StringName = &"leave"

## The Events bus. Only tests set this, before adding the node, to use their own
## bus; otherwise the "Events" autoload is used.
var events: EventsScript = null

var _devices: Array[int] = []
## Per player: action -> strength 0..1 (the strongest of its held sources).
var _strength: Array[Dictionary] = []
## Per player: action -> {source id -> strength} for the sources held right now.
var _sources: Array[Dictionary] = []
## Per player: action -> the process or physics frame of the last press.
var _pressed_process: Array[Dictionary] = []
var _pressed_physics: Array[Dictionary] = []
## Per player: action -> how many times it went down since the start. Unlike the
## press frames, a tap that is released within the same frame still counts.
var _press_count: Array[Dictionary] = []
var _captured: Array[bool] = []


func _init() -> void:
	for player in MAX_PLAYERS:
		_devices.append(NO_DEVICE)
		var strength: Dictionary = {}
		var sources: Dictionary = {}
		var process: Dictionary = {}
		var physics: Dictionary = {}
		var counts: Dictionary = {}
		for action in ACTIONS:
			strength[action] = 0.0
			sources[action] = {}
			process[action] = -1
			physics[action] = -1
			counts[action] = 0
		_strength.append(strength)
		_sources.append(sources)
		_pressed_process.append(process)
		_pressed_physics.append(physics)
		_press_count.append(counts)
		_captured.append(false)


func _ready() -> void:
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _input(event: InputEvent) -> void:
	handle_event(event)


## The device id of the virtual device for `player`.
static func virtual_device_id(player: int) -> int:
	return VIRTUAL_BASE + player


static func is_virtual(device: int) -> bool:
	return device >= VIRTUAL_BASE and device < VIRTUAL_BASE + MAX_PLAYERS


## The device of `player`, or NO_DEVICE if the slot is free.
func device_of(player: int) -> int:
	if not _valid(player):
		return NO_DEVICE
	return _devices[player]


## The player a device belongs to, or NO_PLAYER if it has not joined.
func player_of(device: int) -> int:
	return _devices.find(device) if device != NO_DEVICE else NO_PLAYER


func is_joined(player: int) -> bool:
	return _valid(player) and _devices[player] != NO_DEVICE


func joined_count() -> int:
	var count: int = 0
	for device in _devices:
		if device != NO_DEVICE:
			count += 1
	return count


## Join a real device (the keyboard or a gamepad). Returns the player index, or
## NO_PLAYER if the device already joined, is not allowed that slot, or the game
## is full.
func join(device: int) -> int:
	if device == NO_DEVICE or is_virtual(device) or player_of(device) != NO_PLAYER:
		return NO_PLAYER
	var player: int = NO_PLAYER
	if device == KEYBOARD:
		if _devices[0] == NO_DEVICE:
			player = 0
	else:
		player = _devices.find(NO_DEVICE)
	if player != NO_PLAYER:
		_assign(player, device)
	return player


## Add the virtual device for `player` (a bot). Returns its device id, or
## NO_DEVICE if that slot is taken.
func add_virtual_device(player: int) -> int:
	if not _valid(player) or _devices[player] != NO_DEVICE:
		return NO_DEVICE
	var device: int = virtual_device_id(player)
	_assign(player, device)
	return device


## Free the slot of `player`. Returns false if nobody was there.
func leave(player: int) -> bool:
	if not is_joined(player):
		return false
	var device: int = _devices[player]
	_devices[player] = NO_DEVICE
	_captured[player] = false
	for action in ACTIONS:
		_strength[player][action] = 0.0
		_sources[player][action].clear()
	if events != null:
		events.device_left.emit(player, device)
	return true


## Send an action from the virtual device of `player`, through the same path as
## real events. Strength 0 releases the action. Does nothing if that player's
## virtual device was not added.
func send_virtual(player: int, action: StringName, strength: float = 1.0) -> void:
	if not _valid(player) or _devices[player] != virtual_device_id(player):
		return
	var event := InputEventAction.new()
	event.device = virtual_device_id(player)
	event.action = action
	event.pressed = strength > 0.0
	event.strength = strength
	handle_event(event)


## Route one input event: join, leave, or update the state of its owner.
func handle_event(event: InputEvent) -> void:
	var device: int = _device_of_event(event)
	if device == NO_DEVICE or event.is_echo():
		return
	var player: int = player_of(device)
	if player == NO_PLAYER:
		if event.is_action_pressed(JOIN):
			join(device)
		return
	if event.is_action_pressed(LEAVE):
		leave(player)
		return
	if event is InputEventJoypadMotion:
		_handle_motion(player, event)
		return
	for action in ACTIONS:
		if event.is_action(action):
			_set_source(player, action, _source_of(event), event.get_action_strength(action))


## The move direction of `player`, length 0 to 1 (a diagonal is not faster).
func get_move(player: int) -> Vector2:
	if not _valid(player) or _captured[player]:
		return Vector2.ZERO
	var strength: Dictionary = _strength[player]
	var move := Vector2(
		float(strength[&"move_right"]) - float(strength[&"move_left"]),
		float(strength[&"move_down"]) - float(strength[&"move_up"]))
	return move.limit_length(1.0)


## How far `action` is held by `player`, 0 to 1.
func get_strength(player: int, action: StringName) -> float:
	if not _valid(player) or not _strength[player].has(action) or _is_hidden(player, action):
		return 0.0
	return _strength[player][action]


func is_action_pressed(player: int, action: StringName) -> bool:
	return get_strength(player, action) > 0.0


## True during the frame `action` went down for `player`. Call it from _process
## or _physics_process only: it answers for the process frame in _process and
## for the physics frame in _physics_process. From anywhere else (a signal
## handler, a deferred call) it uses the process frame. When several physics
## steps run in one frame, a press can be missed there; read presses in
## _process when none may be lost.
func is_action_just_pressed(player: int, action: StringName) -> bool:
	if not _valid(player) or not _strength[player].has(action) or _is_hidden(player, action):
		return false
	if Engine.is_in_physics_frame():
		return _pressed_physics[player][action] == Engine.get_physics_frames()
	return _pressed_process[player][action] == Engine.get_process_frames()


## How many times `action` went down for `player` since the start, captured or
## not. Compare it with the value you saw last to find presses without losing a
## tap that was released again before you looked.
func get_press_count(player: int, action: StringName) -> int:
	if not _valid(player) or not _press_count[player].has(action):
		return 0
	return _press_count[player][action]


## Capture or free the gameplay input of `player` (see the class comment). Keys
## stay tracked meanwhile, so a direction still held when the capture ends
## carries on. A player who leaves is freed.
func set_captured(player: int, captured: bool) -> void:
	if _valid(player):
		_captured[player] = captured


func is_captured(player: int) -> bool:
	return _valid(player) and _captured[player]


func _is_hidden(player: int, action: StringName) -> bool:
	return _captured[player] and CAPTURED_ACTIONS.has(action)


func _valid(player: int) -> bool:
	return player >= 0 and player < MAX_PLAYERS


func _assign(player: int, device: int) -> void:
	_devices[player] = device
	if events != null:
		events.device_joined.emit(player, device)


## Which device an event came from. Keys and mouse are one device; a virtual
## device is an action event with a virtual id; other events have no device.
func _device_of_event(event: InputEvent) -> int:
	if event is InputEventKey or event is InputEventMouseButton:
		return KEYBOARD
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return event.device
	if event is InputEventAction and is_virtual(event.device):
		return event.device
	return NO_DEVICE


func _handle_motion(player: int, event: InputEventJoypadMotion) -> void:
	var value: float = event.axis_value
	var scaled: float = clampf((absf(value) - DEADZONE) / (1.0 - DEADZONE), 0.0, 1.0)
	var source: int = _source_of(event)
	match event.axis:
		AXIS_LEFT_X:
			_set_source(player, &"move_left", source, scaled if value < 0.0 else 0.0)
			_set_source(player, &"move_right", source, scaled if value > 0.0 else 0.0)
		AXIS_LEFT_Y:
			_set_source(player, &"move_up", source, scaled if value < 0.0 else 0.0)
			_set_source(player, &"move_down", source, scaled if value > 0.0 else 0.0)
		AXIS_TRIGGER_RIGHT:
			_set_source(player, &"cast", source, 1.0 if value > TRIGGER_PRESSED else 0.0)


## An id for the physical input behind an event (one key, one mouse button, one
## gamepad button, one axis), so each can be held and released on its own.
func _source_of(event: InputEvent) -> int:
	if event is InputEventKey:
		var key: InputEventKey = event
		return key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if event is InputEventMouseButton:
		return SOURCE_MOUSE + (event as InputEventMouseButton).button_index
	if event is InputEventJoypadButton:
		return SOURCE_BUTTON + (event as InputEventJoypadButton).button_index
	if event is InputEventJoypadMotion:
		return SOURCE_AXIS + (event as InputEventJoypadMotion).axis
	return SOURCE_VIRTUAL


## Record how hard one source holds `action`, then give the action the strongest
## of its sources.
func _set_source(player: int, action: StringName, source: int, strength: float) -> void:
	var sources: Dictionary = _sources[player][action]
	if strength > 0.0:
		sources[source] = strength
	else:
		sources.erase(source)
	var strongest: float = 0.0
	for held in sources:
		strongest = maxf(strongest, float(sources[held]))
	_set_strength(player, action, strongest)


func _set_strength(player: int, action: StringName, strength: float) -> void:
	var was_down: bool = float(_strength[player][action]) > 0.0
	_strength[player][action] = strength
	if strength > 0.0 and not was_down:
		_press_count[player][action] = int(_press_count[player][action]) + 1
		_pressed_process[player][action] = Engine.get_process_frames()
		_pressed_physics[player][action] = Engine.get_physics_frames()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected:
		var player: int = player_of(device)
		if player != NO_PLAYER:
			leave(player)
