extends "res://tests/support/screenshot.gd"
## The staff as a language (docs/milestones/staff-language.md) in play: Point Blank's blast and its
## `on expire` frost ring going off at the staff's tip (build 11), and a stream of bolts that two
## Quick Hands make with no wind-down beside a plain bolt staff pressed as often (build 12).
## `staff_language_play` is the whole screen.

const ActorSeats := preload("res://tests/support/actor_seats.gd")
const DUMMY := preload("res://content/enemies/training_dummy/idle.svg")
## Each: the cards, where they are cast from (aiming right), the dummies, and every how many frames
## the staff is pressed (0: once, `ONCE_AT` frames in, so its burst is still on screen).
const CASTS: Array = [
	[[&"point_blank", &"blast", &"fire", &"bolt"], Vector2(70.0, 120.0), [Vector2(96.0, 146.0), Vector2(200.0, 120.0)], 0],
	[[&"on_expire", &"point_blank", &"bolt", &"frost", &"nova", &"atom"], Vector2(400.0, 120.0), [Vector2(340.0, 120.0), Vector2(460.0, 150.0)], 0],
	[[&"quick_hand", &"quick_hand", &"bolt"], Vector2(70.0, 230.0), [Vector2(560.0, 230.0)], 6],
	[[&"bolt"], Vector2(70.0, 310.0), [Vector2(560.0, 310.0)], 6],
]
## Frames the presses go on, and frames from the first press to the shot.
const PRESSING: int = 30
const SHOT_AT: int = 34
const ONCE_AT: int = 31


func take() -> void:
	if not need(["Spells", "Projectiles", "Feel"]):
		return
	var spells: Node = root.get_node("Spells")
	var projectiles: Node = root.get_node("Projectiles")
	# The world is drawn 1:1 in the picture (ART0), the sheet in layout pixels at `sheet_scale`:
	# every world point below is a layout point times `k`.
	var k: float = float(sheet_scale())
	projectiles.call("set_bounds", Rect2(Vector2.ZERO, SCREEN * k))
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	var wizards: PackedInt32Array = ActorSeats.seat_wizards(actors, 1)
	var staff_base := StaffBase.new()
	staff_base.id = &"staff_language"
	staff_base.slots = 8
	staff_base.cooldown = 0.0
	staff_base.spread = 0.0
	lay_floor()
	for row: Array in CASTS:
		for at: Vector2 in row[2]:
			var dummy := Node2D.new()
			dummy.position = at * k
			root.add_child(dummy)
			place(DUMMY, 1.0, at)
			projectiles.call("add_target", dummy, 10.0, 1)
	for i in CASTS.size():
		var row: Array = CASTS[i]
		var cards: Array[StringName] = []
		cards.assign(row[0])
		spells.call("install_staff", wizards[0], i, spells.call("compile_staff", cards, staff_base))
		label(" ".join(PackedStringArray(cards)), row[1] + Vector2(-60.0, -100.0) if i < 2 else row[1] + Vector2(-60.0, -22.0))
	for frame in SHOT_AT:
		for i in CASTS.size():
			var row: Array = CASTS[i]
			var every: int = int(row[3])
			var pressed: bool = frame == ONCE_AT if every == 0 else (frame < PRESSING and frame % every == 0)
			if pressed:
				spells.call("press_staff", wizards[0], i, (row[1] as Vector2) * k, Vector2.RIGHT, 100.0)
		await physics_frame
	await shot("staff_language_play")
