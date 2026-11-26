extends "res://tests/support/screenshot.gd"
## Conditions in play (docs/milestones/staff-language.md, L2): the same staff, `when hurt · frost ·
## nova · bolt` then a plain bolt, pressed once by a whole wizard (the nova is skipped, the bolt
## leaves) and by one below half health (the nova leaves); and `when close · fire · nova · bolt` then
## a bolt, pressed with the dummy far (the bolt) and close (the ring). `staff_conditions_play`.

const ActorSeats := preload("res://tests/support/actor_seats.gd")
const DUMMY := preload("res://content/enemies/training_dummy/idle@2x.svg")
const HURT: Array[StringName] = [&"when_hurt", &"frost", &"nova", &"bolt", &"bolt"]
const CLOSE: Array[StringName] = [&"when_close", &"fire", &"nova", &"bolt", &"bolt"]
## Each: the cards, the wizard's seat, its health share, where it casts from (aiming right), the dummy
## and the label.
const ROWS: Array = [
	[HURT, 0, 1.0, Vector2(80.0, 90.0), Vector2(250.0, 90.0), "whole: when hurt is skipped"],
	[HURT, 1, 0.3, Vector2(80.0, 260.0), Vector2(250.0, 260.0), "below half: it leaves"],
	[CLOSE, 2, 1.0, Vector2(380.0, 90.0), Vector2(590.0, 90.0), "foe far: when close is skipped"],
	[CLOSE, 3, 1.0, Vector2(380.0, 260.0), Vector2(440.0, 260.0), "foe close: it leaves"],
]
const SHOT_AT: int = 6


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
	var wizards: PackedInt32Array = ActorSeats.seat_wizards(actors, 4)
	var staff_base := StaffBase.new()
	staff_base.id = &"staff_conditions"
	staff_base.slots = 8
	staff_base.cooldown = 0.0
	staff_base.spread = 0.0
	lay_floor()
	for row: Array in ROWS:
		var dummy := Node2D.new()
		dummy.position = (row[4] as Vector2) * k
		root.add_child(dummy)
		place(DUMMY, 1.0, row[4])
		projectiles.call("add_target", dummy, 10.0, 1)
		label(" ".join(PackedStringArray(row[0] as Array[StringName])), (row[3] as Vector2) + Vector2(-60.0, -70.0))
		label(row[5], (row[3] as Vector2) + Vector2(-60.0, -56.0))
	await physics_frame
	for row: Array in ROWS:
		var wizard: int = wizards[int(row[1])]
		spells.call("sense_health", wizard, float(row[2]))
		spells.call("install_staff", wizard, 0, spells.call("compile_staff", row[0], staff_base))
		projectiles.call("set_anchor", wizard, (row[3] as Vector2) * k)
		spells.call("press_staff", wizard, 0, (row[3] as Vector2) * k, Vector2.RIGHT, 100.0)
	for frame in SHOT_AT:
		await physics_frame
	await shot("staff_conditions_play")
