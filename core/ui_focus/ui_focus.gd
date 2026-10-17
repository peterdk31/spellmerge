extends Node
## Per-player UI focus: one autoload ("UIFocus") that lets every player move
## through their own panel with their own device, because Godot has only one
## global focus.
##
## A panel belongs to one player. The owner opens it with the controls it
## offers, in order; from then on only that player's input moves its focus:
##
##     UIFocus.open(player, [resume_button, options_button])
##     UIFocus.activated.connect(_on_activated)  # (player, control)
##
## The panel (or a widget) listens to the signals and checks that the player is
## its owner. This service never calls `grab_focus` and never reads `Input`: it
## asks `PlayerInput` by player index, so a panel open for player 2 ignores
## players 1, 3 and 4 completely, and a closed panel costs nothing. Opening
## never pauses the game, and no player ever waits for another.
##
## Controls: move_up and move_left go to the previous control, move_down and
## move_right to the next (wrapping round); `cast` activates the focused
## control and `dodge` cancels. A button already held when the panel opens (the
## one that opened it) does nothing until it is let go. Controls that are hidden
## or have `disabled` set are skipped. Nothing here allocates per frame.

const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const MAX_PLAYERS: int = InputManagerScript.MAX_PLAYERS
## Returned by focus_index() where nothing is focused.
const NO_FOCUS: int = -1

const PREVIOUS_ACTIONS: Array[StringName] = [&"move_up", &"move_left"]
const ACTIVATE: StringName = &"cast"
const CANCEL: StringName = &"dodge"
## Every action read while a panel is open.
const WATCHED: Array[StringName] = [
	&"move_up", &"move_left", &"move_down", &"move_right", &"cast", &"dodge",
]

## A panel opened for `player`.
signal opened(player: int)
## A panel closed (by close(), or because the player's device left).
signal closed(player: int)
## `control` is now the focused control of `player`'s panel.
signal focus_changed(player: int, control: Control)
## `player` activated `control`.
signal activated(player: int, control: Control)
## `player` asked to go back. The panel decides what that means (usually close()).
signal cancelled(player: int)

## The input manager and the event bus. Only tests set these, before adding the
## node, to use their own; otherwise the "PlayerInput" and "Events" autoloads.
var input: InputManagerScript = null
var events: EventsScript = null

## Per player: the controls of the open panel (empty when closed).
var _controls: Array[Array] = []
var _open: Array[bool] = []
var _focus: Array[int] = []
## Per player: action -> was it held at the last poll (for press edges).
var _held: Array[Dictionary] = []


func _init() -> void:
	for player in MAX_PLAYERS:
		var controls: Array = []
		_controls.append(controls)
		_open.append(false)
		_focus.append(NO_FOCUS)
		var held: Dictionary = {}
		for action in WATCHED:
			held[action] = false
		_held.append(held)


func _ready() -> void:
	if input == null:
		input = get_node_or_null("/root/PlayerInput") as InputManagerScript
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if events != null:
		events.device_left.connect(_on_device_left)


func _process(_delta: float) -> void:
	poll()


## Read the input of every player with an open panel and act on new presses.
## Called every frame by _process; tests call it directly.
func poll() -> void:
	if input == null:
		return
	for player in MAX_PLAYERS:
		if _open[player]:
			_poll_player(player)


## Open `player`'s panel with these controls, in order, and focus the first one
## that can take focus. Returns false for a bad index or no controls. Opening
## again replaces the controls.
func open(player: int, controls: Array[Control]) -> bool:
	if not _valid(player) or controls.is_empty():
		return false
	_controls[player].clear()
	_controls[player].append_array(controls)
	_open[player] = true
	_focus[player] = NO_FOCUS
	_prime(player)
	opened.emit(player)
	_focus_first(player)
	return true


## Close `player`'s panel. Returns false if it was not open.
func close(player: int) -> bool:
	if not is_open(player):
		return false
	_open[player] = false
	_focus[player] = NO_FOCUS
	_controls[player].clear()
	closed.emit(player)
	return true


func is_open(player: int) -> bool:
	return _valid(player) and _open[player]


## The focused control of `player`, or null.
func focused(player: int) -> Control:
	var index: int = focus_index(player)
	return null if index == NO_FOCUS else _controls[player][index] as Control


func focus_index(player: int) -> int:
	return _focus[player] if _valid(player) else NO_FOCUS


## Move `player`'s focus one step: +1 to the next control, -1 to the previous.
## Does nothing if the panel is closed or no control can take focus.
func move_focus(player: int, step: int) -> void:
	if not is_open(player) or step == 0:
		return
	var count: int = _controls[player].size()
	var index: int = _focus[player]
	if index == NO_FOCUS and step < 0:
		index = 0
	for _attempt in count:
		index = posmod(index + signi(step), count)
		if _can_focus(_controls[player][index]):
			_set_focus(player, index)
			return


## Activate the focused control of `player`, as if the activate button was
## pressed. Does nothing if the panel is closed or nothing is focused.
func activate(player: int) -> void:
	var control: Control = focused(player)
	if control != null:
		activated.emit(player, control)


## Ask to go back, as if the cancel button was pressed.
func cancel(player: int) -> void:
	if is_open(player):
		cancelled.emit(player)


func _valid(player: int) -> bool:
	return player >= 0 and player < MAX_PLAYERS


func _poll_player(player: int) -> void:
	var held: Dictionary = _held[player]
	for action in WATCHED:
		var down: bool = input.is_action_pressed(player, action)
		var pressed: bool = down and not held[action]
		held[action] = down
		# An earlier press in this poll may have closed the panel.
		if not pressed or not _open[player]:
			continue
		if action == ACTIVATE:
			activate(player)
		elif action == CANCEL:
			cancel(player)
		elif PREVIOUS_ACTIONS.has(action):
			move_focus(player, -1)
		else:
			move_focus(player, 1)


## Remember what is held now, so a button that was already down is not a press.
func _prime(player: int) -> void:
	var held: Dictionary = _held[player]
	for action in WATCHED:
		held[action] = input != null and input.is_action_pressed(player, action)


func _focus_first(player: int) -> void:
	for index in _controls[player].size():
		if _can_focus(_controls[player][index]):
			_set_focus(player, index)
			return


func _set_focus(player: int, index: int) -> void:
	if _focus[player] == index:
		return
	_focus[player] = index
	focus_changed.emit(player, _controls[player][index])


func _can_focus(control: Control) -> bool:
	if not is_instance_valid(control) or not control.visible:
		return false
	var disabled: Variant = control.get(&"disabled")
	return disabled != true


func _on_device_left(player: int, _device: int) -> void:
	close(player)
