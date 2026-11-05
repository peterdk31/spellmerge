class_name LocalInput
extends RefCounted
## The local input layer of one seat (online-ready N2, docs/milestones/online-ready.md): its
## device, read through the input manager, into the seat's `InputFrame` for a tick. It sits in
## front of the frame, so the simulation never reads a device: what is quantised into the frame is
## what is simulated, here, in a replay and later online. The frames service (core/sim/frames.gd)
## keeps one per seat; a `PlayerController` a test hands its own input manager keeps its own.
##
## - **The walk:** `get_move` (the stick's dead zone is the input manager's), a byte per axis.
## - **The aim:** the right stick, which holds AIM_HOLD_TIME after it is let go, so a quick flick
##   still shoots where it pointed; else the keyboard player's mouse (once it has moved; the J key
##   switches back), turned into a direction from the hand (`aim_at`); else, with no aim input,
##   the walk's direction; else keep the aim the actor has.
## - **The staff buttons** `staff_1` to `staff_4` (staffs 0-3: RB, RT, LB, LT): held while down,
##   and a press is counted (`get_press_count`), so a tap released again before the tick looked is
##   not lost. Remembering a press until the staff is ready is the simulation's (the press buffer,
##   `PlayerController.INPUT_BUFFER`): it ends when a cast leaves, which only the simulation knows.
## - **Captured:** while an overlay of the seat is open, the frame says so and holds no walk, aim
##   or button; presses made meanwhile are never counted later.
##
## Nothing here allocates per tick.

const InputManagerScript := preload("res://core/input/input_manager.gd")

## The four staff buttons (0 RB, 1 RT, 2 LB, 3 LT; owner, 2026-10-26).
const CAST_ACTIONS: Array[StringName] = [&"staff_1", &"staff_2", &"staff_3", &"staff_4"]
## Seconds the aim holds after the right stick is let go.
const AIM_HOLD_TIME: float = 0.6
## A point closer than this (pixels) to the hand gives no direction (`aim_at`).
const MOUSE_MIN_DISTANCE: float = 4.0

var _aim_hold_left: float = 0.0
## Per staff: the button's press count last seen.
var _seen_presses: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])


## Fill `frame` with what `seat`'s device says for a tick of `delta` seconds. `hand` is where the
## seat's actor holds its staff and `mouse` the mouse in the world (Vector2.INF for either: no
## mouse aim, the seat drives no actor). The frame's seat and commands are left as they are.
func fill(frame: InputFrame, input: InputManagerScript, seat: int, delta: float, hand: Vector2 = Vector2.INF, mouse: Vector2 = Vector2.INF) -> void:
	frame.move = Vector2i.ZERO
	frame.aim = InputFrame.AIM_KEEP
	frame.held_bits = 0
	frame.pressed_bits = 0
	frame.captured = input.is_captured(seat)
	for at in CAST_ACTIONS.size():
		var presses: int = input.get_press_count(seat, CAST_ACTIONS[at])
		var fresh: bool = presses != _seen_presses[at]
		_seen_presses[at] = presses
		if frame.captured:
			continue
		frame.hold(at, input.is_action_pressed(seat, CAST_ACTIONS[at]))
		if fresh:
			frame.press(at)
	if frame.captured:
		_aim_hold_left = 0.0
		return
	var move: Vector2 = input.get_move(seat)
	frame.set_move(move)
	frame.set_aim(_aim(input, seat, move, delta, hand, mouse))


## The aim for this tick: the right stick, else the mouse (keyboard player), else the held stick
## aim, else the move direction; ZERO keeps the aim the actor has.
func _aim(input: InputManagerScript, seat: int, move: Vector2, delta: float, hand: Vector2, mouse: Vector2) -> Vector2:
	var stick: Vector2 = input.get_aim(seat)
	if stick != Vector2.ZERO:
		_aim_hold_left = AIM_HOLD_TIME
		return stick
	if input.is_mouse_aiming(seat) and hand != Vector2.INF and mouse != Vector2.INF:
		_aim_hold_left = 0.0
		return aim_at(hand, mouse)
	_aim_hold_left = maxf(_aim_hold_left - delta, 0.0)
	if _aim_hold_left <= 0.0 and move != Vector2.ZERO:
		return move.normalized()
	return Vector2.ZERO


## The aim (unit length) for a shot from `hand` that flies through `point` (world positions);
## Vector2.ZERO when `point` is within MOUSE_MIN_DISTANCE of the hand.
static func aim_at(hand: Vector2, point: Vector2) -> Vector2:
	var to_point: Vector2 = point - hand
	if to_point.length() < MOUSE_MIN_DISTANCE:
		return Vector2.ZERO
	return to_point.normalized()


## Take `seat`'s press counts as they are now, so no press made before counts later.
func forget_presses(input: InputManagerScript, seat: int) -> void:
	for at in CAST_ACTIONS.size():
		_seen_presses[at] = input.get_press_count(seat, CAST_ACTIONS[at])
