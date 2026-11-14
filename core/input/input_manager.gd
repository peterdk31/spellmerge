extends Node
## The input manager: one autoload ("PlayerInput") that gives every player
## their own device.
##
## Devices join by a button press (the `join` action): a gamepad takes the
## lowest free player index, the keyboard and mouse only ever take player 0
## (P1), so P2-P4 are gamepads. The pause menu's "Leave game" (`seat_leave_requested`; items I2:
## it replaced the `leave` action, whose Select is the inventory's) frees the slot.
##
## **An unplugged gamepad keeps its seat** (owner, 2026-11-13): the seat waits for it
## (`is_waiting`), holding nothing, and the game is asked to stop for everyone meanwhile (the
## command `pad_wait_requested(player, 1)`, which co-op hears; asked again in every room entered
## while it waits, since a run's start lets every stop go). The seat takes its gamepad back when
## that one connects again (the same device id, which Godot usually gives a pad plugged back in) or
## presses something (a release or a stick at rest is no sign of life: a pad pulled out may still
## flush them); else the first gamepad not seated that presses `join` takes the waiting seat (the
## lowest, before any free slot), and the keyboard's `join` takes this machine's first seat when
## that one waits (so a player alone whose only pad died is never stuck). Then the game is asked to
## go on (`pad_wait_requested(player, 0)`). "Leave game" frees a waiting seat like any other. The
## keyboard and virtual devices never wait.
##
## **This machine's seats** (`set_own_seats(first, count)`; all four, from P1, unless told): the
## slots its real devices may take from then on. The keyboard takes only the first of them and a gamepad the
## lowest free one, so a machine told its seats are "P2 alone" (one that plays a run with another
## machine, which holds P1) seats its keyboard or its first gamepad as P2 and no second device. A
## virtual device takes whatever slot it is added for. This layer knows nothing of why.
##
## A keyboard that joined only because P1's Play was clicked with the mouse (flow calls
## `join(KEYBOARD, true)`) holds P1 provisionally: the first gamepad to press `join` takes P1 over
## as long as the keyboard has not been used since (a key press or a mouse click). So one player
## with a controller on the web, who clicks Play with the mouse because the browser shows no
## gamepad before its first press, plays as P1 (owner, 2026-10-27). The handover keeps P1's
## wizard: no `device_left` or `device_joined`, only `glyph_kind_changed(0)`. Bots join with virtual devices, one per player index,
## and fill their seat's input frames (core/sim/frames.gd); a virtual device's buttons (a menu's) feed the same handle_event() path
## real devices use. The simulation never asks this manager: a seat's local input layer (`LocalInput`) turns it into input frames.
##
## Device ids: KEYBOARD (keys and mouse), a gamepad's own id (0 and up), and
## VIRTUAL_BASE + player index for a virtual device. Gameplay never reads
## `Input` directly; it asks this manager by player index:
##
##     var move: Vector2 = PlayerInput.get_move(player)
##     if PlayerInput.is_action_just_pressed(player, &"staff_1"):
##
## Joins and leaves are announced as `device_joined` and `device_left` on the
## Events bus. Nothing here allocates per frame; events allocate only when a
## bot sends one.
##
## A player's input can be captured (set_captured) while one of their UI panels
## is open: the gameplay questions below (get_move, get_strength,
## is_action_pressed, is_action_just_pressed) then answer "nothing" for the
## actions in CAPTURED_ACTIONS, so a wizard does not walk or cast a staff while
## their player works a menu. Gameplay needs no extra check. core/ui_focus reads
## get_press_count instead, which is never captured.
##
## Aim: get_aim() is the right stick (zero in its dead zone) and is_mouse_aiming()
## says whether the keyboard player aims with the mouse (set by a mouse move or
## click, cleared by a press of the keyboard `staff_2` key, J). The mouse is only a flag
## here: turning the pointer into a direction needs the world, so the wizard does it.
##
## Menus that steer with the sticks (the radial builder) read menu_move() and menu_aim(), which
## answer while the player is captured: their own panel is open, so the sticks are theirs.
## menu_move() is the left stick alone on a gamepad (so the d-pad stays free for the menu's own
## buttons), and the move keys or a virtual device's move actions otherwise.
##
## Rumble: rumble(player, weak, strong, seconds) shakes that player's gamepad (nothing for the
## keyboard); `vibrator` does the shaking, so tests can listen in.
##
## Glyphs: glyph_kind(player) says what that player holds (keyboard, keyboard with the mouse
## aiming, or a gamepad of one family) so the HUD can draw the button to press instead of
## naming an action. `glyph_kind_changed(player)` fires when it changes: a device joins or
## leaves, or the keyboard player turns the mouse aim on or off (core/input/input_glyphs.gd).
##
## Several inputs can feed one action (W and Up, the d-pad and the stick). Each
## input is tracked as its own source and the action takes the strongest one, so
## letting go of one input never cancels another that is still held.

const EventsScript := preload("res://core/events/events.gd")
const GlyphsScript := preload("res://core/input/input_glyphs.gd")

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
const AXIS_RIGHT_X: int = 2
const AXIS_RIGHT_Y: int = 3
const AXIS_TRIGGER_LEFT: int = 4
const AXIS_TRIGGER_RIGHT: int = 5
## A trigger counts as pressed above this value.
const TRIGGER_PRESSED: float = 0.5
## Pixels the mouse must travel before the keyboard player aims with it.
const MOUSE_AIM_TRAVEL: float = 8.0

## The per-player actions, defined in project.godot. `join` is handled here and is not per-player
## state. `staff_1` to `staff_4` cast the four staffs from
## the shoulder buttons (owner, 2026-10-26): RB, RT, LB, LT on a pad; Space, the left and right
## mouse buttons and Q on the keyboard. The face buttons are the menus' (core/ui_focus):
## `accept` (A), `back` (B; in play it opens the builder, `hud/panels`) and `alternate` (X);
## `pause` (Start, Escape) opens the pause menu; `page_prev` and `page_next` (LB, RB; Z, C)
## page menus such as the builder's staff tabs. `extra` (Y; R) is a menu's third action (the
## radial builder's clear, held), and `kind_prev` / `kind_next` (d-pad left and right only, not
## the stick; Page Up, Page Down) flip the radial builder's kind of card.
const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down", &"staff_1", &"staff_2", &"staff_3", &"staff_4",
	&"accept", &"back", &"alternate", &"pause", &"page_prev", &"page_next", &"extra", &"kind_prev", &"kind_next",
]
## The staff cast actions, by staff index (0 to 3: RB, RT, LB, LT).
const CAST_ACTIONS: Array[StringName] = [&"staff_1", &"staff_2", &"staff_3", &"staff_4"]
## Source ids: keys use their keycode; the other kinds sit in separate ranges.
const SOURCE_MOUSE: int = 1 << 40
const SOURCE_BUTTON: int = 2 << 40
const SOURCE_AXIS: int = 3 << 40
const SOURCE_VIRTUAL: int = 4 << 40
## The actions hidden from gameplay while a player is captured (walking and the four
## staffs). The menu actions stay readable, so menus work and close with their own buttons.
const CAPTURED_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down", &"staff_1", &"staff_2", &"staff_3", &"staff_4",
]
const JOIN: StringName = &"join"

## The kind of device of `player` changed: the glyphs for that player must be drawn again.
signal glyph_kind_changed(player: int)

## The Events bus. Only tests set this, before adding the node, to use their own
## bus; otherwise the "Events" autoload is used.
var events: EventsScript = null

## Gives the name of a gamepad by device id; tests replace it.
var joy_name_provider: Callable = Input.get_joy_name
## Who gives this machine's real devices their seats, when it is not this layer: while valid, a
## device that would join (the `join` action, `join`) is not seated here; this is called with the
## device, and whoever set it seats it later, on the seat it says (`join_as`). A machine that
## plays another machine's run sets it (net/): the host gives the seats out. Invalid: seats are
## taken here, as ever. This layer knows nothing of why.
var join_asker: Callable = Callable()
## Shakes a gamepad: (device, weak 0..1, strong 0..1, seconds). Tests replace it.
var vibrator: Callable = Input.start_joy_vibration

var _devices: Array[int] = []
## Per player: the glyph family of the gamepad in the slot (GlyphsScript.Kind).
var _pad_kind: Array[int] = []
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
## Per player: the seat's gamepad is unplugged and the seat waits for it (see the top).
var _waiting: Array[bool] = []
## Per player: the raw right stick (x and y axis values, -1 to 1).
var _aim_stick: Array[Vector2] = []
## Per player: the raw left stick, for menu_move().
var _move_stick: Array[Vector2] = []
var _mouse_aiming: bool = false
## This machine's seats: the first slot its real devices may take, and how many (`set_own_seats`).
var _own_first: int = 0
var _own_count: int = MAX_PLAYERS
## True while the keyboard holds P1 provisionally (see the top).
var _keyboard_provisional: bool = false
## How far the mouse moved (pixels) since the cast key last turned mouse aim off.
var _mouse_travel: float = 0.0


func _init() -> void:
	# Menus run while the game is paused (the pause menu), so input does too.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for player in MAX_PLAYERS:
		_devices.append(NO_DEVICE)
		_pad_kind.append(GlyphsScript.Kind.GAMEPAD)
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
		_waiting.append(false)
		_aim_stick.append(Vector2.ZERO)
		_move_stick.append(Vector2.ZERO)


func _ready() -> void:
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if events != null:
		# Heard before Flow (the autoloads' order), so the run starts with the keyboard in.
		events.play_requested.connect(_on_run_requested)
		events.sandbox_requested.connect(_on_run_requested)
		events.hub_requested.connect(_on_run_requested)
		events.seat_leave_requested.connect(_on_seat_leave_requested)
		events.room_entered.connect(_on_room_entered)


## The pause menu's "Leave game" for seat `player`: its device goes (`leave`).
func _on_seat_leave_requested(player: int) -> void:
	leave(player)


## A run was asked for (Play's hub, the sandbox, a run of waves) by seat `requester`. The menu's buttons may
## be pressed with the mouse by nobody who has joined: the keyboard then takes slot 0,
## provisionally (a gamepad that joins before the keyboard is used takes P1 over). Anyone already
## joined (a gamepad, in any slot) plays as they are and the keyboard stays out. The device layer's
## decision, not the game's: the run reads the joined seats from the frames service (core/sim).
func _on_run_requested(requester: int) -> void:
	if requester == 0 and joined_count() == 0:
		join(KEYBOARD, true)


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


## True while `player`'s gamepad is unplugged and the seat waits for it (see the top): the seat is
## still joined, and holds nothing.
func is_waiting(player: int) -> bool:
	return _valid(player) and _waiting[player]


func joined_count() -> int:
	var count: int = 0
	for device in _devices:
		if device != NO_DEVICE:
			count += 1
	return count


## Join a real device (the keyboard or a gamepad). Returns the player index, or
## NO_PLAYER if the device already joined, is not allowed that slot, or the game
## is full. With `provisional`, a keyboard holds P1 only until a gamepad wants it (see the top).
func join(device: int, provisional: bool = false) -> int:
	if device == NO_DEVICE or is_virtual(device) or player_of(device) != NO_PLAYER:
		return NO_PLAYER
	if join_asker.is_valid():
		join_asker.call(device)
		return NO_PLAYER
	var player: int = NO_PLAYER
	if device == KEYBOARD:
		if _own_count > 0 and _devices[_own_first] == NO_DEVICE:
			player = _own_first
	else:
		for own in range(_own_first, _own_first + _own_count):
			if _devices[own] == NO_DEVICE:
				player = own
				break
	if player != NO_PLAYER:
		_keyboard_provisional = provisional and device == KEYBOARD
		_assign(player, device)
	return player


## Seat the real device `device` on `player`, whatever this machine's own seats are: the answer
## to `join_asker`. Returns `player`, or NO_PLAYER (and nothing changes) when the device has
## joined already, is no real device, or the seat is taken.
func join_as(device: int, player: int) -> int:
	if device == NO_DEVICE or is_virtual(device) or player_of(device) != NO_PLAYER or not _valid(player) or _devices[player] != NO_DEVICE:
		return NO_PLAYER
	if device == KEYBOARD:
		_keyboard_provisional = false
	_assign(player, device)
	return player


## True while the keyboard holds its seat (P1, or this machine's first) provisionally.
func is_keyboard_provisional() -> bool:
	return _keyboard_provisional and player_of(KEYBOARD) != NO_PLAYER


## A gamepad takes the provisional keyboard's seat over: the wizard stays, its input is the pad's.
func _hand_over(device: int) -> void:
	var player: int = player_of(KEYBOARD)
	_keyboard_provisional = false
	_clear_state(player)
	_mouse_aiming = false
	_mouse_travel = 0.0
	_devices[player] = device
	_pad_kind[player] = GlyphsScript.kind_of_pad(String(joy_name_provider.call(device)))
	glyph_kind_changed.emit(player)


## This machine's seats are the `count` slots from `first` (see the top). A real device whose
## seat is still one of them keeps it (its wizard is not touched); the others leave and join again
## in their order, each taking the place it would have had it joined now (a provisional keyboard
## stays provisional), and those with no place left stay out. With `reseat` every real device
## leaves and joins again, as if it joined now (a menu's reset: nobody plays). Virtual devices are
## not touched. A seat waiting for its unplugged gamepad that must move leaves instead (there is no
## gamepad to seat). False, and nothing changes, for seats outside the four.
func set_own_seats(first: int = 0, count: int = MAX_PLAYERS, reseat: bool = false) -> bool:
	if first < 0 or count < 0 or first + count > MAX_PLAYERS:
		return false
	if first == _own_first and count == _own_count:
		return true
	var provisional: bool = is_keyboard_provisional()
	var real: Array[int] = []
	for player in MAX_PLAYERS:
		var device: int = _devices[player]
		if device != NO_DEVICE and not is_virtual(device) and (reseat or player < first or player >= first + count):
			if not _waiting[player]:
				real.append(device)
			leave(player)
	_own_first = first
	_own_count = count
	for device in real:
		join(device, provisional and device == KEYBOARD)
	return true


## The first of this machine's seats, and how many it has (`set_own_seats`).
func own_first_seat() -> int:
	return _own_first


func own_seat_count() -> int:
	return _own_count


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
	_waiting[player] = false
	_clear_state(player)
	if device == KEYBOARD:
		_mouse_aiming = false
		_mouse_travel = 0.0
		_keyboard_provisional = false
	if events != null:
		events.device_left.emit(player, device)
	glyph_kind_changed.emit(player)
	return true


## Lets go of everything `player` holds: actions and sticks.
func _clear_state(player: int) -> void:
	_aim_stick[player] = Vector2.ZERO
	_move_stick[player] = Vector2.ZERO
	for action in ACTIONS:
		_strength[player][action] = 0.0
		_sources[player][action].clear()


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
			# A waiting seat comes before any free slot (and before whoever else gives seats out:
			# the seat is this machine's already).
			var waiting: int = _waiting_seat_for(device)
			if waiting != NO_PLAYER:
				_take_back(waiting, device)
			elif device != KEYBOARD and is_keyboard_provisional() and not join_asker.is_valid():
				_hand_over(device)
			else:
				join(device)
		return
	# A gamepad that presses something is plugged in, whether or not its connection was told.
	if _waiting[player]:
		if not _is_sign_of_life(event):
			return
		_take_back(player, device)
	# The keyboard in use for real (a key or a click) keeps P1.
	if device == KEYBOARD and _keyboard_provisional and event.is_pressed() and (event is InputEventKey or event is InputEventMouseButton):
		_keyboard_provisional = false
	if event is InputEventMouseMotion:
		# A brush of the mouse is not a decision to aim with it.
		_mouse_travel += (event as InputEventMouseMotion).relative.length()
		if _mouse_travel >= MOUSE_AIM_TRAVEL:
			_set_mouse_aiming(player, true)
		return
	if event is InputEventMouseButton:
		_set_mouse_aiming(player, true)
	elif event is InputEventKey and event.is_action_pressed(&"staff_2"):
		_set_mouse_aiming(player, false)
		_mouse_travel = 0.0
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


## The right stick of `player` as a unit vector, or zero inside the dead zone
## (or while captured). Gamepads and bots only; see is_mouse_aiming for the mouse.
func get_aim(player: int) -> Vector2:
	if not _valid(player) or _captured[player]:
		return Vector2.ZERO
	var stick: Vector2 = _aim_stick[player]
	if stick.length() <= DEADZONE:
		return Vector2.ZERO
	return stick.normalized()


## The left stick of `player` for their own open menu, length 0 to 1, captured or not: the
## stick alone on a gamepad (zero in its dead zone; the d-pad is left out), the move keys or
## the virtual move actions otherwise.
func menu_move(player: int) -> Vector2:
	if not is_joined(player):
		return Vector2.ZERO
	var device: int = _devices[player]
	if device != KEYBOARD and not is_virtual(device):
		var stick: Vector2 = _move_stick[player]
		var length: float = stick.length()
		if length <= DEADZONE:
			return Vector2.ZERO
		return stick / length * minf((length - DEADZONE) / (1.0 - DEADZONE), 1.0)
	var strength: Dictionary = _strength[player]
	var move := Vector2(
		float(strength[&"move_right"]) - float(strength[&"move_left"]),
		float(strength[&"move_down"]) - float(strength[&"move_up"]))
	return move.limit_length(1.0)


## The right stick of `player` as a unit vector (zero in its dead zone), for their own open
## menu: like get_aim(), but captured or not.
func menu_aim(player: int) -> Vector2:
	if not is_joined(player):
		return Vector2.ZERO
	var stick: Vector2 = _aim_stick[player]
	return stick.normalized() if stick.length() > DEADZONE else Vector2.ZERO


## The right stick of `player` with how far it is pushed: zero in its dead zone, then its
## length rising from 0 to 1 at full tilt, like get_move(). For a menu that reads the tilt too
## (the radial builder's zoom and kind rings).
func menu_tilt(player: int) -> Vector2:
	if not is_joined(player):
		return Vector2.ZERO
	var stick: Vector2 = _aim_stick[player]
	var length: float = stick.length()
	if length <= DEADZONE:
		return Vector2.ZERO
	return stick / length * minf((length - DEADZONE) / (1.0 - DEADZONE), 1.0)


## Shake the gamepad of `player`: `weak` and `strong` (0 to 1) are the two motors, for
## `seconds`. False, and nothing happens, for the keyboard, a free slot or an unplugged gamepad. A virtual device
## shakes nothing real, but `vibrator` hears it, so tests see the rumble.
func rumble(player: int, weak: float, strong: float, seconds: float) -> bool:
	if not is_joined(player) or _devices[player] == KEYBOARD or _waiting[player]:
		return false
	vibrator.call(_devices[player], clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), maxf(seconds, 0.0))
	return true


## Aim the virtual right stick of `player` (a unit vector, or zero to let go),
## through the state a real stick feeds. Does nothing without that virtual device.
func send_virtual_aim(player: int, direction: Vector2) -> void:
	if _valid(player) and _devices[player] == virtual_device_id(player):
		_aim_stick[player] = direction.limit_length(1.0)


## True while `player` is the keyboard player and last aimed with the mouse.
func is_mouse_aiming(player: int) -> bool:
	return _mouse_aiming and _valid(player) and _devices[player] == KEYBOARD and not _captured[player]


## How far `action` is held by `player`, 0 to 1.
func get_strength(player: int, action: StringName) -> float:
	if not _valid(player) or not _strength[player].has(action) or _is_hidden(player, action):
		return 0.0
	return _strength[player][action]


## Whether `action` is down for `player` now, captured or not: for the menu that holds the
## capture, as `get_press_count` counts its presses (the radial builder's LT held clears a staff).
func is_held(player: int, action: StringName) -> bool:
	return _valid(player) and float(_strength[player].get(action, 0.0)) > 0.0


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
	if device == KEYBOARD or is_virtual(device):
		_pad_kind[player] = GlyphsScript.Kind.GAMEPAD
	else:
		_pad_kind[player] = GlyphsScript.kind_of_pad(String(joy_name_provider.call(device)))
	if events != null:
		events.device_joined.emit(player, device)
	glyph_kind_changed.emit(player)


## What `player` holds, for drawing glyphs (a GlyphsScript.Kind). A player with no device
## counts as on the keyboard; a bot's virtual device draws as a plain gamepad.
func glyph_kind(player: int) -> int:
	if not _valid(player):
		return GlyphsScript.Kind.KEYBOARD
	var device: int = _devices[player]
	if device == NO_DEVICE:
		return GlyphsScript.Kind.KEYBOARD
	if device == KEYBOARD:
		return GlyphsScript.Kind.KEYBOARD_MOUSE if _mouse_aiming else GlyphsScript.Kind.KEYBOARD
	return _pad_kind[player]


func _set_mouse_aiming(player: int, aiming: bool) -> void:
	if _mouse_aiming == aiming:
		return
	_mouse_aiming = aiming
	glyph_kind_changed.emit(player)


## Which device an event came from. Keys and mouse are one device; a virtual
## device is an action event with a virtual id; other events have no device.
func _device_of_event(event: InputEvent) -> int:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
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
			_move_stick[player].x = value
			_set_source(player, &"move_left", source, scaled if value < 0.0 else 0.0)
			_set_source(player, &"move_right", source, scaled if value > 0.0 else 0.0)
		AXIS_LEFT_Y:
			_move_stick[player].y = value
			_set_source(player, &"move_up", source, scaled if value < 0.0 else 0.0)
			_set_source(player, &"move_down", source, scaled if value > 0.0 else 0.0)
		AXIS_RIGHT_X:
			_aim_stick[player].x = value
		AXIS_RIGHT_Y:
			_aim_stick[player].y = value
		AXIS_TRIGGER_RIGHT:
			_set_source(player, &"staff_2", source, 1.0 if value > TRIGGER_PRESSED else 0.0)
		AXIS_TRIGGER_LEFT:
			_set_source(player, &"staff_4", source, 1.0 if value > TRIGGER_PRESSED else 0.0)


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


## A gamepad was plugged in or pulled out. One that holds a seat keeps it and the seat waits (see
## the top), until it is back.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	var player: int = player_of(device)
	if player == NO_PLAYER or not _is_gamepad(device):
		return
	if not connected:
		_wait(player)
	elif _waiting[player]:
		_take_back(player, device)


static func _is_gamepad(device: int) -> bool:
	return device >= 0 and not is_virtual(device)


## The waiting seat a device not seated takes with its `join`, or NO_PLAYER: a gamepad the lowest,
## the keyboard only this machine's first seat (the one it may hold).
func _waiting_seat_for(device: int) -> int:
	if _is_gamepad(device):
		return _waiting.find(true)
	if device == KEYBOARD and _own_count > 0 and _waiting[_own_first]:
		return _own_first
	return NO_PLAYER


## Whether an event from a waiting seat's own gamepad says it is in hand: a press, or a stick or
## trigger pushed past the dead zone (never a release or an axis at rest).
static func _is_sign_of_life(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion:
		return absf((event as InputEventJoypadMotion).axis_value) > DEADZONE
	return event.is_pressed()


## Seat `player`'s gamepad is gone: the seat stays, lets go of everything it held, and the game is
## asked to stop until it is back.
func _wait(player: int) -> void:
	if _waiting[player]:
		return
	_waiting[player] = true
	_clear_state(player)
	_ask_wait(player, true)


## The waiting seat `player` plays again, on `device` (its own gamepad back, another that took its
## place, or the keyboard): the game is asked to go on.
func _take_back(player: int, device: int) -> void:
	_waiting[player] = false
	_devices[player] = device
	if device == KEYBOARD:
		_keyboard_provisional = false
		_pad_kind[player] = GlyphsScript.Kind.GAMEPAD
	else:
		_pad_kind[player] = GlyphsScript.kind_of_pad(String(joy_name_provider.call(device)))
	_clear_state(player)
	_ask_wait(player, false)
	glyph_kind_changed.emit(player)


## The command that stops the game for seat `player`'s missing gamepad (`on`), or lets it go.
func _ask_wait(player: int, on: bool) -> void:
	if events != null:
		events.pad_wait_requested.emit(player, 1 if on else 0)


## A room was entered: a run's start lets every stop go, so each seat still waiting asks again.
func _on_room_entered(_room_id: StringName) -> void:
	for player in MAX_PLAYERS:
		if _waiting[player]:
			_ask_wait(player, true)
