extends "res://tests/support/screenshot.gd"
## The marks Feel draws for the five combo classes (`combo_marks`): what `combo_cast` shows when
## a cast is more than a plain shot. One column per class (boosted, on_hit, on_expire, timer,
## stacked). Row 1: the mark as it appears, at its own size, in fire. Rows 2 to 4: the same mark
## swelled, in frost, void and lightning, so the class reads from its shape and the element from
## its colour. A mark lasts a third of a second, so the two takes of each column are put
## together into one sheet.

const ActorSeats := preload("res://tests/support/actor_seats.gd")

const COLUMN := 128
const LOWER := 95
const CLASSES: Array[StringName] = [&"boosted", &"on_hit", &"on_expire", &"timer", &"stacked"]
const ROWS_Y: Array[float] = [50.0, 140.0, 220.0, 300.0]
const TINTS: Array[Color] = [Color("e0592f"), Color("4fd6dc"), Color("a0309a"), Color("b4e82a")]


func take() -> void:
	if not need(["Feel", "Events"]):
		return
	settle_frames = 30
	var events: Node = root.get_node("Events")
	var height: int = int(SCREEN.y)
	# A combo cast names its caster's actor id and Feel marks the seat that drives it (actors
	# G3b): open the four wizards in the Actors table, one per row.
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	var wizards: PackedInt32Array = ActorSeats.seat_wizards(actors)
	lay_floor()
	await settle()
	var sheet: Image = null
	for i in CLASSES.size():
		var x: float = COLUMN * i + COLUMN * 0.5
		for row in ROWS_Y.size():
			events.call("emit_signal", "combo_cast", wizards[row], CLASSES[i], Vector2(x, ROWS_Y[row]), Vector2.RIGHT, TINTS[row])
		await process_frame
		var early: Image = await grab()
		if sheet == null:
			sheet = early
		else:
			sheet.blit_rect(early, Rect2i(COLUMN * i, 0, COLUMN, height), Vector2i(COLUMN * i, 0))
		await create_timer(0.2).timeout
		var late: Image = await grab()
		sheet.blit_rect(late, Rect2i(COLUMN * i, LOWER, COLUMN, height - LOWER), Vector2i(COLUMN * i, LOWER))
		await settle()
	save(sheet, "combo_marks")
