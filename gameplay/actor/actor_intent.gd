class_name ActorIntent
extends RefCounted
## What a controller wants its actor to do this step (actors G4, docs/milestones/M2-actors.md,
## "The actor"): the only thing that crosses from a controller to the body. The controller
## writes it in `think`; the Caster and the Mover read it in the same step.
##
## - `move`: the walk direction, length 0 to 1 (a stick's tilt walks slower).
## - `aim`: where to aim (any length; ZERO keeps the aim the actor has).
## - per staff 0-3, `pressed` (a new press this step) and `held` (the button is down).
##
## Made once per actor and never replaced: nothing here allocates after `_init`. `pressed` lasts
## one step (the actor clears it before `think`); `held`, `move` and `aim` stay until the
## controller changes them or `clear` empties everything (no controller: the body stands).

## The most staffs an actor has (one per button).
const STAFFS: int = 4

var move: Vector2 = Vector2.ZERO
var aim: Vector2 = Vector2.ZERO
var _pressed: PackedByteArray = PackedByteArray()
var _held: PackedByteArray = PackedByteArray()


func _init() -> void:
	_pressed.resize(STAFFS)
	_held.resize(STAFFS)


## Staff `staff` (0-3) was pressed this step. A staff outside 0-3 is ignored.
func press(staff: int) -> void:
	if staff >= 0 and staff < STAFFS:
		_pressed[staff] = 1


## Staff `staff`'s button is down (`on`) or up.
func hold(staff: int, on: bool) -> void:
	if staff >= 0 and staff < STAFFS:
		_held[staff] = 1 if on else 0


func is_pressed(staff: int) -> bool:
	return staff >= 0 and staff < STAFFS and _pressed[staff] != 0


func is_held(staff: int) -> bool:
	return staff >= 0 and staff < STAFFS and _held[staff] != 0


## The start of a step: last step's presses are spent.
func begin_step() -> void:
	_pressed.fill(0)


## Nothing wanted: stand, keep the aim, cast nothing.
func clear() -> void:
	move = Vector2.ZERO
	aim = Vector2.ZERO
	_pressed.fill(0)
	_held.fill(0)
