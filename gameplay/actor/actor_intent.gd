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
## Made once per actor and never replaced: nothing here allocates. `pressed` lasts one step (the
## actor clears it before `think`); `held`, `move` and `aim` stay until the controller changes
## them or `clear` empties everything (no controller: the body stands). The buttons are two bit
## masks (bit `staff`), so starting a step and asking "any button?" cost one int each (the Caster
## skips its staffs while `pressed_bits | held_bits` is 0; performance pass, 2026-10-28).

## The most staffs an actor has (one per button).
const STAFFS: int = 4

var move: Vector2 = Vector2.ZERO
var aim: Vector2 = Vector2.ZERO
## Read only: bit `staff` is set while that staff is pressed this step / held (`press`, `hold`).
var pressed_bits: int = 0
var held_bits: int = 0


## Staff `staff` (0-3) was pressed this step. A staff outside 0-3 is ignored.
func press(staff: int) -> void:
	if staff >= 0 and staff < STAFFS:
		pressed_bits |= 1 << staff


## Staff `staff`'s button is down (`on`) or up.
func hold(staff: int, on: bool) -> void:
	if staff >= 0 and staff < STAFFS:
		if on:
			held_bits |= 1 << staff
		else:
			held_bits &= ~(1 << staff)


func is_pressed(staff: int) -> bool:
	return staff >= 0 and staff < STAFFS and (pressed_bits & (1 << staff)) != 0


func is_held(staff: int) -> bool:
	return staff >= 0 and staff < STAFFS and (held_bits & (1 << staff)) != 0


## The start of a step: last step's presses are spent.
func begin_step() -> void:
	pressed_bits = 0


## Want what `other` wants: its walk, aim, presses and held buttons (a puppet, possess).
func copy_from(other: ActorIntent) -> void:
	move = other.move
	aim = other.aim
	pressed_bits = other.pressed_bits
	held_bits = other.held_bits


## Nothing wanted: stand, keep the aim, cast nothing.
func clear() -> void:
	move = Vector2.ZERO
	aim = Vector2.ZERO
	pressed_bits = 0
	held_bits = 0
