extends "res://tests/support/screenshot.gd"
## The effects Feel draws with the shots' shader (the glow look, 2026-10-27): a row per infusion
## (plain, fire, frost, storm, void, lightning; the colours and looks of the real cards), a
## column per effect at an age, so one still shows how each one plays out:
##   1-3  where a shot lands (KIND_BURST), 2, 6 and 12 frames old
##   4-6  a rune going off (KIND_RUNE_BURST), 3, 10 and 20 frames old
##   7    a nova's cast ring (KIND_RING_OUT), 6 frames old
##   8    a rune's or orbit's cast ring (KIND_RING_IN), 6 frames old
##   9    the cast flash at a staff tip (KIND_CAST), 2 frames old
## `effects_sheet` at 1x and `effects_sheet_4x` (the plain, fire and frost rows, columns 1-6).
## `effects_enemy_sheet`: the same grid cast by an enemy (staffs F7), in the enemy ramp
## where a player's colour would show.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ELEMENTS: Array[Resource] = [
	preload("res://content/spells/elements/fire/fire.tres"),
	preload("res://content/spells/elements/frost/frost.tres"),
	preload("res://content/spells/elements/storm/storm.tres"),
	preload("res://content/spells/elements/void/void.tres"),
	preload("res://content/spells/elements/lightning/lightning.tres"),
]
const COLUMN: float = 68.0
const ROW: float = 58.0
## Each column: [kind, zoom, frames old].
const COLUMNS: Array = [
	[FeelScript.KIND_BURST, 1, 2], [FeelScript.KIND_BURST, 1, 6], [FeelScript.KIND_BURST, 1, 12],
	[FeelScript.KIND_RUNE_BURST, 3, 3], [FeelScript.KIND_RUNE_BURST, 3, 10], [FeelScript.KIND_RUNE_BURST, 3, 20],
	[FeelScript.KIND_RING_OUT, 1, 6], [FeelScript.KIND_RING_IN, 1, 6], [FeelScript.KIND_CAST, 1, 2],
]


func take() -> void:
	if not need(["Feel"]):
		return
	var feel: Node = root.get_node("Feel")
	# On game time each frame is 1/60 s, so the ages are exact however slow the display is.
	feel.set("drive_engine", false)
	lay_floor()
	await settle()
	if not await _sheet(feel, false):
		return
	save(_image, "effects_sheet")
	save_crop(_image, Vector2(40.0 + 2.5 * COLUMN, 35.0 + ROW), "effects_sheet_4x", Vector2i(int(3.0 * COLUMN), int(1.5 * ROW)))
	# Let every effect end before the enemy's grid.
	for i in 90:
		feel.call("step", 1.0 / 60.0)
	if not await _sheet(feel, true):
		return
	save(_image, "effects_enemy_sheet")


var _image: Image = null


## Show the grid (by players, or by an enemy) and grab it into `_image`; false when it failed.
## An effect takes a ramp (actors G3b): a player's hat ramp 0-3, or the enemy ramp.
func _sheet(feel: Node, enemy: bool) -> bool:
	var oldest: int = 0
	for column: Array in COLUMNS:
		oldest = maxi(oldest, column[2] as int)
	# Start the oldest first, so every effect is its age in the same frame.
	for left in range(oldest, 0, -1):
		for c in COLUMNS.size():
			var column: Array = COLUMNS[c]
			if column[2] as int != left:
				continue
			for e in 6:
				var tint: Color = Color.WHITE if e == 0 else ELEMENTS[e - 1].get("tint") as Color
				var look: int = 0 if e == 0 else ManagerScript.pack_look(PackedInt32Array([int(ELEMENTS[e - 1].get("look_layer"))]))
				var at := Vector2(40.0 + c * COLUMN, 35.0 + e * ROW)
				var seconds: float = _seconds_of(column[0] as int)
				feel.call("show_effect", column[0] as int, at, Vector2.RIGHT, tint, ActorsScript.RAMP_ENEMY if enemy else e % 4, look, column[1] as int, seconds)
		await process_frame
	_image = await grab()
	if int(feel.call("live_effects")) < 50:
		fail("only %d effects are showing" % int(feel.call("live_effects")))
		return false
	return true


func _seconds_of(kind: int) -> float:
	match kind:
		FeelScript.KIND_BURST:
			return FeelScript.BURST_SECONDS
		FeelScript.KIND_RUNE_BURST:
			return FeelScript.RUNE_BURST_SECONDS
		FeelScript.KIND_CAST:
			return FeelScript.CAST_SECONDS
	return FeelScript.RING_SECONDS
