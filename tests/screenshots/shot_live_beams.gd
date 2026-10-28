extends "res://tests/support/screenshot.gd"
## Live beams as the game draws them (owner, 2026-10-27): a plain beam, a fire beam, a homing
## frost beam bending along its curve onto a dummy off its line, and storm, lightning and void
## beams (the glow look), each kept on with `hold` so the shot catches it. `live_beams` is the whole screen and `live_beams_bend` a crop of the
## bent one.

const ActorSeats := preload("res://tests/support/actor_seats.gd")
const DUMMY := preload("res://content/enemies/training_dummy/idle.svg")
const STARTER := preload("res://content/wizard/staffs/starter/starter.tres")
## Each row: the cards, the beam's start and the dummy it may hit (the homing one is off its line).
const ROWS: Array = [
	[[&"hold", &"beam"], Vector2(60.0, 40.0), Vector2(240.0, 40.0)],
	[[&"hold", &"fire", &"beam"], Vector2(60.0, 95.0), Vector2(240.0, 95.0)],
	[[&"hold", &"homing", &"frost", &"beam"], Vector2(60.0, 150.0), Vector2(170.0, 185.0)],
	[[&"hold", &"storm", &"beam"], Vector2(60.0, 225.0), Vector2(240.0, 225.0)],
	[[&"hold", &"lightning", &"beam"], Vector2(60.0, 280.0), Vector2(240.0, 280.0)],
	[[&"hold", &"void", &"beam"], Vector2(60.0, 335.0), Vector2(240.0, 335.0)],
]


func take() -> void:
	if not need(["Spells", "Projectiles", "Feel"]):
		return
	settle_frames = 6
	var spells: Node = root.get_node("Spells")
	var projectiles: Node = root.get_node("Projectiles")
	projectiles.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	# Spells keeps staffs by actor id and a beam takes its caster's ramp (actors G3b): open the
	# wizards of players 1 and 2 in the Actors table and cast as them.
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	var wizards: PackedInt32Array = ActorSeats.seat_wizards(actors, 2)
	lay_floor()
	for row: Array in ROWS:
		var dummy := Node2D.new()
		dummy.position = row[2]
		root.add_child(dummy)
		place(DUMMY, 1.0, row[2])
		projectiles.call("add_target", dummy, 10.0, 1)
	for i in ROWS.size():
		var row: Array = ROWS[i]
		var cards: Array[StringName] = []
		cards.assign(row[0])
		# A wizard has four staffs; the last rows are player 2's.
		spells.call("install_staff", wizards[i / 4], i % 4, spells.call("compile_staff", cards, STARTER))
		spells.call("cast_staff", wizards[i / 4], i % 4, row[1], Vector2.RIGHT, 100.0)
		label(" ".join(PackedStringArray(cards)), row[1] + Vector2(0.0, -24.0))
	await settle()
	await shot("live_beams")
	await snap(Vector2(140.0, 170.0), "live_beams_bend", Vector2i(100, 50), 3)
	await snap(Vector2(150.0, 280.0), "live_beams_4x", Vector2i(100, 60), 4)
