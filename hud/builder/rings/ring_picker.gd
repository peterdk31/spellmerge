extends RefCounted
## A ring style for the radial builder (`../radial_builder.gd`, its `ring_picker`; owner,
## 2026-10-30): how the right stick picks a card and how the ring is drawn, for trying ways to
## pick among many cards with a pad. Each style is one file in this folder, chosen on the pause
## menu's Sandbox page ("Ring:", `hud/panels` sets it). They are experiments: deleting a style is
## its file, its test, and its entry in `PauseMenu.Ring` and `panels.gd`.
##
## A style reads the radial's ring (its places, entries and kinds) and draws with the radial's own
## helpers; the radial keeps everything else (the slots, RT, LT, the hub, the numbers).

const NONE: int = -1


## Forget any state (the builder opened, the ring was laid out again, the style was chosen).
func reset() -> void:
	pass


## The ring entry the stick (or P1's mouse) picks now, or NONE. Called every step while the
## builder is open; `radial` is the radial builder.
func pick(_radial: Control, _delta: float) -> int:
	return NONE


## Draw the ring in this style's way, inside the radial's `_draw`; false draws the plain ring.
func draw(_radial: Control) -> bool:
	return false


## True while the style animates on its own, so the radial redraws every step.
func is_animating() -> bool:
	return false
