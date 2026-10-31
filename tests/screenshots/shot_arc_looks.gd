extends "res://tests/support/screenshot.gd"
## Arc lightning (Feel's KIND_ARC, `shot_arc.gdshader`; owner, 2026-10-30: "arcs should look waaaay
## cooler"): a row per infusion (plain, fire, frost, storm, void, lightning; the colours of the real
## cards), a column per zap at an age, so one still shows how a zap plays out:
##   1-4  a zap 60 px long, 1, 3, 6 and 10 frames old
##   5    a zap 30 px long, up and to the right, 2 frames old
##   6    a spark into the air (16 px), 2 frames old
## `arc_looks` at 1x and `arc_looks_4x` (the plain and fire rows, columns 1-3).

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const ELEMENTS: Array[Resource] = [
	preload("res://content/spells/elements/fire/fire.tres"),
	preload("res://content/spells/elements/frost/frost.tres"),
	preload("res://content/spells/elements/storm/storm.tres"),
	preload("res://content/spells/elements/void/void.tres"),
	preload("res://content/spells/elements/lightning/lightning.tres"),
]
const ROW: float = 58.0
## Each column: [x, length, direction, frames old].
const COLUMNS: Array = [
	[30.0, 60.0, Vector2.RIGHT, 1], [130.0, 60.0, Vector2.RIGHT, 3], [230.0, 60.0, Vector2.RIGHT, 6],
	[330.0, 60.0, Vector2.RIGHT, 10], [440.0, 30.0, Vector2(1.0, -1.0), 2], [540.0, 16.0, Vector2(1.0, 0.3), 2],
]


func take() -> void:
	if not need(["Feel"]):
		return
	var feel: Node = root.get_node("Feel")
	feel.set("drive_engine", false)
	lay_floor()
	await settle()
	var oldest: int = 0
	for column: Array in COLUMNS:
		oldest = maxi(oldest, column[3] as int)
	# Start the oldest first, so every zap is its age in the same frame.
	for left in range(oldest, 0, -1):
		for column: Array in COLUMNS:
			if column[3] as int != left:
				continue
			for e in 6:
				var tint: Color = Color.WHITE if e == 0 else ELEMENTS[e - 1].get("tint") as Color
				var look: int = 0 if e == 0 else ManagerScript.pack_look(PackedInt32Array([int(ELEMENTS[e - 1].get("look_layer"))]))
				var at := Vector2(column[0] as float, 35.0 + e * ROW)
				var length: float = column[1] as float
				var seconds: float = 0.25 * (1.0 if length > FeelScript.SPARK_LONGEST else 0.6)
				feel.call("show_effect", FeelScript.KIND_ARC, at, column[2] as Vector2, tint, e % 4, look, 1, seconds, length)
		await process_frame
	var image: Image = await grab()
	if int(feel.call("live_arcs")) < 30:
		fail("only %d arcs are showing" % int(feel.call("live_arcs")))
		return
	save(image, "arc_looks")
	save_crop(image, Vector2(130.0, 35.0 + ROW * 0.5), "arc_looks_4x", Vector2i(160, 60))
