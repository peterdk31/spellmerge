extends "res://tests/support/screenshot.gd"
## What Feel draws when five of the forms are cast and when their shots end (`form_looks`). One
## column per form (bolt, beam, nova, rune, orbit). Row 1: the cast flash on the wizard's staff
## (the body of a beam and a nova is drawn with it). Row 2: where a player's shot ends. Row 3:
## where an enemy's shot ends, which is the same ember mark in every column. Each column is its
## own take (a flash lasts a tenth of a second), put together into one sheet.

const COLUMN := 128
const FORMS: Array[StringName] = [&"bolt", &"beam", &"nova", &"rune", &"orbit"]
const ROWS_Y: Array[float] = [70.0, 170.0, 270.0]


func take() -> void:
	if not need(["Feel", "Events", "Projectiles"]):
		return
	settle_frames = 12
	# Feel ages its effects on the real clock, which a slow virtual display stretches past
	# their tenth of a second; on game time each frame is 1/60 s, as in play.
	root.get_node("Feel").set("drive_engine", false)
	var events: Node = root.get_node("Events")
	var projectiles: Node = root.get_node("Projectiles")
	lay_floor()
	await settle()
	var sheet: Image = null
	for i in FORMS.size():
		var form: StringName = FORMS[i]
		var x: float = COLUMN * i + COLUMN * 0.5
		events.call("emit_signal", "spell_cast", 0, form, Vector2(x - 20.0, ROWS_Y[0]), Vector2.RIGHT)
		if form == &"beam":
			events.call("emit_signal", "form_shown", 0, &"beam", Vector2(x - 20.0, ROWS_Y[0]), Vector2.RIGHT, 56.0, Color("e0592f"))
		elif form == &"nova":
			events.call("emit_signal", "form_shown", 0, &"nova", Vector2(x, ROWS_Y[0]), Vector2.RIGHT, 0.0, Color("e0592f"))
		# The manager names the form of the shot while it sends the impact.
		projectiles.set("impact_form", form)
		events.call("emit_signal", "projectile_impact", 0, null, Vector2(x, ROWS_Y[1]), Vector2.RIGHT)
		projectiles.set("impact_form", &"")
		events.call("emit_signal", "projectile_impact", -1, null, Vector2(x, ROWS_Y[2]), Vector2.RIGHT)
		await process_frame
		var image: Image = await grab()
		if sheet == null:
			sheet = image
		else:
			sheet.blit_rect(image, Rect2i(COLUMN * i, 0, COLUMN, int(SCREEN.y)), Vector2i(COLUMN * i, 0))
		await settle()
	save(sheet, "form_looks")
