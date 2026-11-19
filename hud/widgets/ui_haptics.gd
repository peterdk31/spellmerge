class_name UiHaptics
extends RefCounted
## The menus' rumbles (owner, 2026-11-19): a menu says what happened through the pad in the
## player's hands, not through a sound. Moving, pointing, choosing, putting a card in and taking
## one out have no sound; only `ui_choose`, `ui_back` and `ui_deny` are still heard (UiSounds).
## Every menu rumbles with these, so one action feels the same in every menu:
##
## - POINT: the focus or the pointer landed on another entry (a row, a card or bag on a ring, a
##   slot, a tab or a staff paged, a slider's step). A short tick on the light motor.
## - CHOOSE: a press did something that is not a card going in or out (a bag entered, the tree
##   opened). A short knock on the heavy motor.
## - PUT, TAKE and CLEAR: a card went in, a card came out, the staff was cleared.
## - REFUSED: the press was refused (a full or empty staff, nothing pointed at, `build_refused`).
##
## Each is (weak motor, strong motor, seconds). A keyboard player, a seat not joined and a seat
## waiting for its unplugged pad feel nothing (`InputManager.rumble`). Allocates nothing.

const InputManagerScript := preload("res://core/input/input_manager.gd")

const POINT: Vector3 = Vector3(0.25, 0.0, 0.03)
const CHOOSE: Vector3 = Vector3(0.0, 0.35, 0.05)
const PUT: Vector3 = Vector3(0.2, 0.45, 0.06)
const TAKE: Vector3 = Vector3(0.35, 0.0, 0.04)
const CLEAR: Vector3 = Vector3(0.3, 0.7, 0.14)
const REFUSED: Vector3 = Vector3(0.0, 0.6, 0.09)


## Rumble `player`'s pad with `motors` (one of the constants above); false when nothing rumbled
## (no input manager, or `InputManager.rumble` refused).
static func pulse(input: InputManagerScript, player: int, motors: Vector3) -> bool:
	if input == null:
		return false
	return input.rumble(player, motors.x, motors.y, motors.z)
