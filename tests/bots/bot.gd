extends RefCounted
## A bot: plays one player slot through a virtual device and the real input path
## (`PlayerInput.send_virtual`), the same path a gamepad uses. It holds `move_*`
## and `cast` and taps `overlay`; it never touches a spell field or the projectile
## manager, so it plays the way a person does. The wizard fires the equipped spell
## through its one cast method when `cast` is held, so a bot calls nothing on the
## spell itself.
##
## Fighter: walks toward the nearest enemy of the current world (a wizard faces
## where it walks, so the shots fly at the enemy) and holds `cast` within
## FIRE_RANGE. When it hardly moved for STUCK_STEPS steps (a pillar) it side-steps
## for SIDESTEP_STEPS steps. Idler: stands still; it only opens its overlay.
##
## Everything is driven by step(delta), so a run with the same frames repeats. A
## bot sends an input only when it changes.

enum Mode { FIGHTER, IDLER }

## Closer than this (pixels) the bot holds `cast`.
const FIRE_RANGE: float = 170.0
## A step that moves less than this (pixels) counts as stuck.
const STUCK_DISTANCE: float = 0.5
const STUCK_STEPS: int = 20
const SIDESTEP_STEPS: int = 25

var player: int = 0
var mode: Mode = Mode.FIGHTER

var _input: Node = null
var _flow: Node = null
var _held_move: Vector2i = Vector2i.ZERO
var _casting: bool = false
var _last_position: Vector2 = Vector2.INF
var _stuck: int = 0
var _sidestep_left: int = 0
var _sidestep_sign: float = 1.0


## `input` is the `PlayerInput` autoload and `flow` the `Flow` autoload. Takes the
## virtual device of `index`; returns false if that slot is not free.
func join(index: int, bot_mode: Mode, input: Node, flow: Node) -> bool:
	player = index
	mode = bot_mode
	_input = input
	_flow = flow
	_sidestep_sign = 1.0 if index % 2 == 0 else -1.0
	return int(_input.call("add_virtual_device", player)) != int(_input.get("NO_DEVICE"))


## Press and release `overlay` once.
func tap_overlay() -> void:
	_input.call("send_virtual", player, &"overlay", 1.0)
	_input.call("send_virtual", player, &"overlay", 0.0)


## Let go of everything the bot holds and free the slot.
func leave() -> void:
	_release()
	_input.call("leave", player)


## One decision. An idler does nothing.
func step(_delta: float) -> void:
	if mode == Mode.IDLER:
		return
	var wizard := _flow.call("get_wizard", player) as Node2D
	var world := _flow.get("world") as Node2D
	if wizard == null or world == null or bool(wizard.call("is_downed")):
		_release()
		return
	var target: Node2D = _nearest_enemy(world, wizard.global_position)
	if target == null:
		_release()
		return
	var offset: Vector2 = target.global_position - wizard.global_position
	_track_stuck(wizard.global_position)
	var direction: Vector2 = offset.normalized()
	if _sidestep_left > 0:
		_sidestep_left -= 1
		direction = direction.orthogonal() * _sidestep_sign
	_hold_move(direction)
	_hold_cast(offset.length() <= FIRE_RANGE)


func _nearest_enemy(world: Node2D, from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_distance: float = INF
	for child in world.get_children():
		# Enemies are the bodies with the AI script on their root.
		var enemy := child as CharacterBody2D
		if enemy == null or not enemy.has_method("telegraph_progress") or enemy.is_queued_for_deletion():
			continue
		var distance: float = from.distance_squared_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


func _track_stuck(at: Vector2) -> void:
	if _sidestep_left > 0:
		_last_position = at
		return
	if at.distance_to(_last_position) < STUCK_DISTANCE:
		_stuck += 1
		if _stuck >= STUCK_STEPS:
			_stuck = 0
			_sidestep_left = SIDESTEP_STEPS
			_sidestep_sign = -_sidestep_sign
	else:
		_stuck = 0
	_last_position = at


## Hold the four move actions for `direction` (each axis on or off).
func _hold_move(direction: Vector2) -> void:
	var wanted := Vector2i(signi(roundi(direction.x * 1.5)), signi(roundi(direction.y * 1.5)))
	if wanted == _held_move:
		return
	_input.call("send_virtual", player, &"move_left", 1.0 if wanted.x < 0 else 0.0)
	_input.call("send_virtual", player, &"move_right", 1.0 if wanted.x > 0 else 0.0)
	_input.call("send_virtual", player, &"move_up", 1.0 if wanted.y < 0 else 0.0)
	_input.call("send_virtual", player, &"move_down", 1.0 if wanted.y > 0 else 0.0)
	_held_move = wanted


func _hold_cast(on: bool) -> void:
	if on == _casting:
		return
	_input.call("send_virtual", player, &"cast", 1.0 if on else 0.0)
	_casting = on


func _release() -> void:
	_hold_move(Vector2.ZERO)
	_hold_cast(false)
