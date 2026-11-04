extends "res://tests/support/screenshot.gd"
## The cues whose flashes threw their sparks and card particles inside the flash shader until S6
## item 3 (docs/milestones/spell-spectacle-2.md), played by name, so one sheet shows the sparks
## and card particles as they are now (motes parts of the cues since item 3), a row per infusion
## (plain, fire, frost, lightning: the real cards' colours and looks), a column per cue at an age
## (its frames since it played, on game time):
##   `flash_motes_strikes`  a shot striking (`impact`) 2, 6 and 12 frames old, a rune going off
##                          (`rune_burst`) 3, 10 and 20, a cast (`cast`) 2 and 5, a deflection 4
##   `flash_motes_columns`  a teleport leaving (`vanish`) 6 and 15 frames old, landing (`appear`)
##                          4 and 12, a swap's trade 8, a dismissal 6, a quake 3 and 15, a slam 4
## and each enlarged four times round its first three rows (`_4x`). Played with `weight` off: the
## looks only, no shake, kick or hold. Mote throws are random, so two runs differ in their motes.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ELEMENTS: Array[Resource] = [
	preload("res://content/spells/elements/fire/fire.tres"),
	preload("res://content/spells/elements/frost/frost.tres"),
	preload("res://content/spells/elements/lightning/lightning.tres"),
]
const COLUMN: float = 68.0
## Each sheet: its name, the pixels between its rows, how far down its first row is, and its
## columns as [cue, size in pixels, frames old].
const SHEETS: Array = [
	["flash_motes_strikes", 64.0, 40.0, [
		[&"impact", 0.0, 2], [&"impact", 0.0, 6], [&"impact", 0.0, 12],
		[&"rune_burst", 14.0, 3], [&"rune_burst", 14.0, 10], [&"rune_burst", 14.0, 20],
		[&"cast", 0.0, 2], [&"cast", 0.0, 5], [&"deflect", 0.0, 4],
	]],
	["flash_motes_columns", 84.0, 56.0, [
		[&"vanish", 0.0, 6], [&"vanish", 0.0, 15], [&"appear", 0.0, 4], [&"appear", 0.0, 12],
		[&"trade", 0.0, 8], [&"dismiss", 0.0, 6], [&"quake", 16.0, 3], [&"quake", 16.0, 15],
		[&"slam", 16.0, 4],
	]],
]


func take() -> void:
	if not need(["Feel"]):
		return
	var feel: Node = root.get_node("Feel")
	# On game time each frame is 1/60 s, so the ages are exact however slow the display is.
	feel.set("drive_engine", false)
	feel.set("shake_enabled", false)
	lay_floor()
	await settle()
	for sheet: Array in SHEETS:
		var image: Image = await _sheet(feel, sheet[1] as float, sheet[2] as float, sheet[3] as Array)
		save(image, sheet[0] as String)
		var columns: int = (sheet[3] as Array).size()
		save_crop(image, Vector2(40.0 + (columns - 1) * 0.5 * COLUMN, sheet[2] as float + (sheet[1] as float)), String(sheet[0]) + "_4x", Vector2i(int(columns * 0.5 * COLUMN), int(1.5 * (sheet[1] as float))))
		# Let everything end before the next sheet.
		for i in 120:
			feel.call("step", 1.0 / 60.0)
		await process_frame


## Play the sheet's cues, the oldest first, so every one is its age in the same frame; grab it.
func _sheet(feel: Node, row: float, top: float, columns: Array) -> Image:
	var oldest: int = 0
	for column: Array in columns:
		oldest = maxi(oldest, column[2] as int)
	for left in range(oldest, -1, -1):
		for c in columns.size():
			var column: Array = columns[c]
			if column[2] as int != left:
				continue
			for e in 4:
				var tint: Color = Color.WHITE if e == 0 else ELEMENTS[e - 1].get("tint") as Color
				var look: int = 0 if e == 0 else ManagerScript.pack_look(PackedInt32Array([int(ELEMENTS[e - 1].get("look_layer"))]))
				var at := Vector2(40.0 + c * COLUMN, top + e * row)
				feel.call("play_cue", column[0] as StringName, e, at, Vector2.RIGHT, column[1] as float, tint, look, -1, -1, -1, 0, false)
		feel.call("step", 1.0 / 60.0)
		await process_frame
	return await grab()
