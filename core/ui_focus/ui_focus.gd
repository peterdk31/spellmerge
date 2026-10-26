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
## move_right to the next (wrapping round); `cast_a` activates the focused
## control, `cast_b` cancels, `cast_x` sends `alternate` for the focused control
## and `page_prev` / `page_next` (LB, RB) send `paged`. A panel laid out in two
## dimensions gives a navigator (`set_navigator`): each move asks it for the control
## in that direction first, and only when it has none does the move go to the
## previous or next control. `focus(player, control)` jumps straight to a control. Presses come from PlayerInput's press counter,
## so even a tap released within one frame is not lost, and a button already
## held when the panel opens (the one that opened it) does nothing until it is
## let go and pressed again.
##
## While a panel is open its owner's gameplay input is captured
## (PlayerInput.set_captured): the wizard does not walk or cast a staff, and
## gameplay needs no check of its own. The other players are not affected.
##
## A control can take focus when it is valid, visible in the tree (a hidden
## parent counts; a control not in the tree uses its own `visible`) and does not
## have `disabled` set. Its `focus_mode` is ignored, since Godot's focus is
## never used. The focused control is checked again every frame and before
## each activation: if it was disabled, hidden or freed, focus moves on to the
## next usable control (or to none) and nothing is activated for it. Nothing
## here allocates per frame.

const InputManagerScript := preload("res://core/input/input_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const MAX_PLAYERS: int = InputManagerScript.MAX_PLAYERS
## Returned by focus_index() where nothing is focused.
const NO_FOCUS: int = -1

const PREVIOUS_ACTIONS: Array[StringName] = [&"move_up", &"move_left"]
## A (Space) activates and B (Q) goes back, as on most gamepads (staffs A6a); X (J) is the
## panel's second action on the focused control, LB and RB (Z, C) page (staffs B8).
const ACTIVATE: StringName = &"cast_a"
const CANCEL: StringName = &"cast_b"
const ALTERNATE: StringName = &"cast_x"
const PAGE_PREV: StringName = &"page_prev"
const PAGE_NEXT: StringName = &"page_next"
## The direction of each move action, for a navigator.
const DIRECTIONS: Dictionary = {
	&"move_up": Vector2i.UP, &"move_down": Vector2i.DOWN, &"move_left": Vector2i.LEFT, &"move_right": Vector2i.RIGHT,
}
## Every action read while a panel is open.
const WATCHED: Array[StringName] = [
	&"move_up", &"move_left", &"move_down", &"move_right", &"cast_a", &"cast_b", &"cast_x", &"page_prev", &"page_next",
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
## `player` pressed the second action (`cast_x`) on `control`. The panel decides what it does.
signal alternate(player: int, control: Control)
## `player` paged: -1 for `page_prev`, +1 for `page_next`. The panel decides what it does.
signal paged(player: int, step: int)

## The input manager and the event bus. Only tests set these, before adding the
## node, to use their own; otherwise the "PlayerInput" and "Events" autoloads.
var input: InputManagerScript = null
var events: EventsScript = null

## Per player: the controls of the open panel (empty when closed).
var _controls: Array[Array] = []
var _open: Array[bool] = []
var _focus: Array[int] = []
## Per player: action -> PlayerInput's press count at the last poll.
var _seen: Array[Dictionary] = []
## Per player: the open panel's navigator (see `set_navigator`), or an empty Callable.
var _navigators: Array[Callable] = []


func _init() -> void:
	for player in MAX_PLAYERS:
		var controls: Array = []
		_controls.append(controls)
		_open.append(false)
		_focus.append(NO_FOCUS)
		var seen: Dictionary = {}
		for action in WATCHED:
			seen[action] = 0
		_seen.append(seen)
		_navigators.append(Callable())


func _ready() -> void:
	if input == null:
		input = get_node_or_null("/root/PlayerInput") as InputManagerScript
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if events != null:
		events.device_left.connect(_on_device_left)


func _process(_delta: float) -> void:
	poll()


## Read the input of every player with an open panel and act on new presses
## since the last poll. Called every frame by _process; tests call it directly.
func poll() -> void:
	if input == null:
		return
	for player in MAX_PLAYERS:
		if _open[player]:
			_poll_player(player)


## Open `player`'s panel with these controls, in order, and focus the first one
## that can take focus, and capture the player's gameplay input. Returns false
## for a bad index, no controls, or a player with no joined device (such a panel
## could never be driven or closed). Opening a panel that is already open
## replaces it: `closed` is sent for the old one, then `opened` for the new one.
func open(player: int, controls: Array[Control]) -> bool:
	if not _valid(player) or controls.is_empty():
		return false
	if input == null or not input.is_joined(player):
		return false
	if _open[player]:
		# Replacing the panel keeps its navigator: a panel that opens again with new controls
		# (a list that grew) is still the same panel.
		var navigator: Callable = _navigators[player]
		close(player)
		_navigators[player] = navigator
	_controls[player].clear()
	_controls[player].append_array(controls)
	_open[player] = true
	_focus[player] = NO_FOCUS
	_prime(player)
	input.set_captured(player, true)
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
	_navigators[player] = Callable()
	if input != null:
		input.set_captured(player, false)
	closed.emit(player)
	return true


func is_open(player: int) -> bool:
	return _valid(player) and _open[player]


## The focused control of `player`, or null.
func focused(player: int) -> Control:
	var index: int = focus_index(player)
	if index == NO_FOCUS or not is_instance_valid(_controls[player][index]):
		return null
	return _controls[player][index] as Control


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


## Give `player`'s open panel a navigator: `navigator.call(control, direction)` (the focused
## control, or null, and a Vector2i step) returns the control to move to, or null to let the
## move go to the previous or next control as usual. A control it returns that is not in the
## panel or cannot take focus counts as null. Cleared when the panel closes; kept when it is
## opened again with new controls. An empty Callable removes it.
func set_navigator(player: int, navigator: Callable) -> void:
	if is_open(player):
		_navigators[player] = navigator


## Move `player`'s focus straight to `control`. False when the panel is closed or `control`
## is not one of its controls or cannot take focus.
func focus(player: int, control: Control) -> bool:
	if not is_open(player) or control == null:
		return false
	var at: int = _controls[player].find(control)
	if at < 0 or not _can_focus(control):
		return false
	_set_focus(player, at)
	return true


## Activate the focused control of `player`, as if the activate button was
## pressed. Does nothing if the panel is closed or nothing is focused. If the
## focused control can no longer take focus, nothing is activated and focus
## moves on to the next usable control instead (the player sees it, then
## presses again).
func activate(player: int) -> void:
	if not is_open(player):
		return
	var control: Control = focused(player)
	if control == null or not _can_focus(control):
		_revalidate(player)
		return
	activated.emit(player, control)


## Ask to go back, as if the cancel button was pressed.
func cancel(player: int) -> void:
	if is_open(player):
		cancelled.emit(player)


func _valid(player: int) -> bool:
	return player >= 0 and player < MAX_PLAYERS


func _poll_player(player: int) -> void:
	var seen: Dictionary = _seen[player]
	for action in WATCHED:
		var count: int = input.get_press_count(player, action)
		var presses: int = count - int(seen[action])
		seen[action] = count
		# An earlier press in this poll may have closed or replaced the panel.
		for _press in presses:
			if not _open[player]:
				break
			if action == ACTIVATE:
				activate(player)
			elif action == CANCEL:
				cancel(player)
			elif action == ALTERNATE:
				_alternate(player)
			elif action == PAGE_PREV or action == PAGE_NEXT:
				paged.emit(player, -1 if action == PAGE_PREV else 1)
			elif not _navigate(player, DIRECTIONS[action]):
				move_focus(player, -1 if PREVIOUS_ACTIONS.has(action) else 1)
	# After the presses, so a press never lands on a control the player has not
	# seen focused.
	_revalidate(player)


## The second action on the focused control, checked like `activate`.
func _alternate(player: int) -> void:
	var control: Control = focused(player)
	if control == null or not _can_focus(control):
		_revalidate(player)
		return
	alternate.emit(player, control)


## Ask the panel's navigator where `direction` goes; true when it moved the focus.
func _navigate(player: int, direction: Vector2i) -> bool:
	var navigator: Callable = _navigators[player]
	if not navigator.is_valid():
		return false
	var target: Variant = navigator.call(focused(player), direction)
	return target is Control and focus(player, target as Control)


## Remember the press counts now, so presses from before the panel opened (and a
## button still held from then) are not acted on.
func _prime(player: int) -> void:
	var seen: Dictionary = _seen[player]
	for action in WATCHED:
		seen[action] = input.get_press_count(player, action)


## If the focused control can no longer take focus (disabled, hidden, freed),
## move focus to the next usable control, or to none.
func _revalidate(player: int) -> void:
	if not is_open(player):
		return
	var index: int = _focus[player]
	if index == NO_FOCUS or _can_focus(_controls[player][index]):
		return
	var count: int = _controls[player].size()
	for step in range(1, count):
		var next: int = (index + step) % count
		if _can_focus(_controls[player][next]):
			_set_focus(player, next)
			return
	_focus[player] = NO_FOCUS


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


## Takes a Variant because a stored control may have been freed since.
func _can_focus(candidate: Variant) -> bool:
	if not is_instance_valid(candidate):
		return false
	var control: Control = candidate
	var shown: bool = control.is_visible_in_tree() if control.is_inside_tree() else control.visible
	if not shown:
		return false
	var disabled: Variant = control.get(&"disabled")
	return disabled != true


func _on_device_left(player: int, _device: int) -> void:
	close(player)
