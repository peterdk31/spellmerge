extends "res://tests/support/screenshot.gd"
## Penta (docs/milestones/portal.md, "Penta") on four carriers, each ringing its caster: five held
## fire beams burning in at it, five walls caging it, five runes round it, and five homing frost
## bolts leaving the ring aimed in before they bend for a dummy. `penta_looks` is the whole screen.

const ActorSeats := preload("res://tests/support/actor_seats.gd")
const DUMMY := preload("res://content/enemies/training_dummy/idle.svg")
## Each: the cards, where they are cast from (aiming right) and the dummy (INF for none). The
## caster has no body here, so the wall row shows the ring round the point it is cast from.
const CASTS: Array = [
	[[&"hold", &"penta", &"fire", &"beam"], Vector2(130.0, 90.0), Vector2.INF],
	[[&"penta", &"wall"], Vector2(400.0, 90.0), Vector2.INF],
	[[&"penta", &"rune"], Vector2(130.0, 270.0), Vector2.INF],
	[[&"homing", &"penta", &"frost", &"bolt"], Vector2(330.0, 270.0), Vector2(470.0, 270.0)],
]


func take() -> void:
	if not need(["Spells", "Projectiles", "Feel"]):
		return
	settle_frames = 6
	var spells: Node = root.get_node("Spells")
	var projectiles: Node = root.get_node("Projectiles")
	projectiles.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	var wizards: PackedInt32Array = ActorSeats.seat_wizards(actors, 1)
	var staff_base := StaffBase.new()
	staff_base.id = &"penta_looks"
	staff_base.slots = 8
	staff_base.cooldown = 0.0
	staff_base.spread = 0.0
	lay_floor()
	for row: Array in CASTS:
		if not (row[2] as Vector2).is_finite():
			continue
		var dummy := Node2D.new()
		dummy.position = row[2]
		root.add_child(dummy)
		place(DUMMY, 1.0, row[2])
		# Many hits: it stands through them all.
		projectiles.call("add_target", dummy, 10.0, 1)
	for i in CASTS.size():
		var row: Array = CASTS[i]
		var cards: Array[StringName] = []
		cards.assign(row[0])
		spells.call("install_staff", wizards[0], i, spells.call("compile_staff", cards, staff_base))
		spells.call("cast_staff", wizards[0], i, row[1], Vector2.RIGHT, 100.0)
		label(" ".join(PackedStringArray(cards)), row[1] + Vector2(0.0, -70.0))
	await settle()
	await shot("penta_looks")
