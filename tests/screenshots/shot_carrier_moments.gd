extends "res://tests/support/screenshot.gd"
## The carriers' moments that are cues their cards name, over their lives (`carrier_moments_1` and
## `_2`, drawn twice as big): one row per moment, one column per age. Sheet 1: where a teleport
## leaves (`vanish`) and lands (`appear`), one end of a swap's trade (`trade`).
## Sheet 2: a decoy or familiar appearing (`conjure`) and going (`dismiss`), and a
## wall's row of stones rising and standing (the wall's own `stone.gdshader`; `carrier_moments_stones` close up). Each column is its own take, put
## together into one sheet.

const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## The ages shown, in frames of 1/60 s.
const AGES: Array[int] = [1, 4, 8, 14, 22]
const COLUMN := 128
const FIRE := Color("e0592f")
const STONE: Shader = preload("res://content/spells/forms/wall/stone.gdshader")


func take() -> void:
	if not need(["Feel", "Events", "Projectiles"]):
		return
	settle_frames = 50
	root.get_node("Feel").set("drive_engine", false)
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	var wizard: int = ActorSeats.seat_wizards(actors, 1)[0]
	lay_floor()
	await settle()
	var first: Array[Array] = [
		["form_shown", &"teleport", 0.0],
		["carrier_ended", &"teleport", 6.0],
		["form_shown", &"swap", 80.0],
	]
	await _sheet(wizard, first, false, "carrier_moments_1")
	var second: Array[Array] = [
		["form_shown", &"decoy", 0.0],
		["carrier_ended", &"decoy", 8.0],
		["wall", &"wall", 0.0],
	]
	await _sheet(wizard, second, true, "carrier_moments_2")


## One sheet: `rows` of [event, card, size] down the screen, each played in every column at once
## and grabbed at the column's age.
func _sheet(wizard: int, rows: Array[Array], walls: bool, shot_name: String) -> void:
	var events: Node = root.get_node("Events")
	var projectiles: Node = root.get_node("Projectiles")
	var row_h: float = SCREEN.y / rows.size()
	var sheet: Image = null
	for column in AGES.size():
		var x: float = COLUMN * column + COLUMN * 0.5
		# The stones of this take, under a tag of their own.
		var tag: int = 7000 + column
		for r in rows.size():
			var row: Array = rows[r]
			var at := Vector2(x, row_h * r + row_h * 0.62)
			if row[0] == "wall":
				var slot: int = projectiles.call("spawn", wizard, at, Vector2.ZERO, 5.0, 5.0, ProjectilesScript.LAYER_ENEMY, 0, tag, ProjectilesScript.MOTION_STILL)
				projectiles.call("set_core", slot, FIRE)
				projectiles.call("set_form", slot, &"wall", projectiles.call("register_body", STONE))
				projectiles.call("set_solid", slot, Vector2.RIGHT, 5, 9.0)
			else:
				events.call("emit_signal", row[0], wizard, row[1], at, Vector2.RIGHT, row[2], FIRE, 0)
		for i in AGES[column]:
			await process_frame
		var image: Image = await grab()
		if sheet == null:
			sheet = image
		else:
			sheet.blit_rect(image, Rect2i(COLUMN * column, 0, COLUMN, int(SCREEN.y)), Vector2i(COLUMN * column, 0))
		if walls and column == AGES.size() - 1:
			# The stones standing, close up.
			save_crop(image, on_screen(Vector2(x, row_h * (rows.size() - 1) + row_h * 0.62 - 6.0)), "carrier_moments_stones", Vector2i(40, 20), 6)
		projectiles.call("remove_by_tag", tag)
		await settle()
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	save(sheet, shot_name)
