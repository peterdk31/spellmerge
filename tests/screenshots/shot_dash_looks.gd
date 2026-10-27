extends "res://tests/support/screenshot.gd"
## A wizard's dash as Feel draws it (the glow look, 2026-10-27; `KIND_DASH`): a row per infusion
## (plain, fire, frost, storm, void, lightning; the colours and looks of the real cards), a column
## per moment of an 80 px dash (Medium Dash): 6 frames in (still travelling: streaks behind the
## head, dust where it left), 20 (landed: the ring, lightning's arc) and 30 (lingering cards).
## `dash_looks` at 1x and `dash_looks_4x` (the plain, fire and frost rows).

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const ELEMENTS: Array[Resource] = [
	preload("res://content/spells/elements/fire/fire.tres"),
	preload("res://content/spells/elements/frost/frost.tres"),
	preload("res://content/spells/elements/storm/storm.tres"),
	preload("res://content/spells/elements/void/void.tres"),
	preload("res://content/spells/elements/lightning/lightning.tres"),
]
const MEDIUM_DASH := preload("res://content/spells/forms/medium_dash/medium_dash.tres")
const AGES: Array[int] = [6, 20, 30]
const COLUMN: float = 210.0
const ROW: float = 58.0


func take() -> void:
	if not need(["Feel"]):
		return
	var feel: Node = root.get_node("Feel")
	feel.set("drive_engine", false)
	lay_floor()
	await settle()
	var length: float = float(MEDIUM_DASH.get("ray_length"))
	for left in range(AGES.max(), 0, -1):
		for c in AGES.size():
			if AGES[c] != left:
				continue
			for e in 6:
				var tint: Color = Color.WHITE if e == 0 else ELEMENTS[e - 1].get("tint") as Color
				var look: int = 0 if e == 0 else ManagerScript.pack_look(PackedInt32Array([int(ELEMENTS[e - 1].get("look_layer"))]))
				var at := Vector2(40.0 + c * COLUMN, 32.0 + e * ROW)
				feel.call("show_effect", FeelScript.KIND_DASH, at, Vector2.RIGHT, tint, e % 4, look, 1, FeelScript.DASH_SECONDS, length)
		await process_frame
	var image: Image = await grab()
	if int(feel.call("effects_of", FeelScript.KIND_DASH)) < 18:
		fail("only %d dashes are showing" % int(feel.call("effects_of", FeelScript.KIND_DASH)))
		return
	save(image, "dash_looks")
	save_crop(image, Vector2(40.0 + COLUMN + length * 0.5, 32.0 + ROW), "dash_looks_4x", Vector2i(int(COLUMN * 0.5 + 30.0), int(ROW * 1.5)))
