extends "res://tests/support/screenshot.gd"
## Arc shots as the game draws them (owner, 2026-10-30: arcs crackle at random and look like
## lightning): a stream of arc atoms (plain, lightning and frost) and of arc fire bolts, cast every
## frame they are ready for half a second, past a row of dummies beside their line. Their zaps
## leave from different places at different dummies, some miss, and with nothing near they spark
## into the air. `live_arcs`, `live_arcs_2` and `live_arcs_3` are the whole screen a sixth of a
## second apart, `live_arcs_4x` a crop of the lightning stream.

const ActorSeats := preload("res://tests/support/actor_seats.gd")
const DUMMY := preload("res://content/enemies/training_dummy/idle.svg")
const STARTER := preload("res://content/wizard/staffs/curl/curl.tres")
## Each row: the cards and where its stream starts; its dummies stand beside its line.
const ROWS: Array = [
	[[&"arc", &"atom"], Vector2(30.0, 50.0)],
	[[&"arc", &"lightning", &"atom"], Vector2(30.0, 140.0)],
	[[&"arc", &"frost", &"atom"], Vector2(30.0, 230.0)],
	[[&"arc", &"fire", &"bolt"], Vector2(30.0, 320.0)],
]
## How far beside the line the dummies stand, and how far apart.
const BESIDE: float = 34.0
const APART: float = 70.0


func take() -> void:
	if not need(["Spells", "Projectiles", "Feel"]):
		return
	var spells: Node = root.get_node("Spells")
	var projectiles: Node = root.get_node("Projectiles")
	# Feel on game time, a 60th of a second a frame, so a zap lives as long as it does in the game
	# however slowly the virtual display draws.
	root.get_node("Feel").set("drive_engine", false)
	projectiles.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	var wizards: PackedInt32Array = ActorSeats.seat_wizards(actors, 1)
	lay_floor()
	for row: Array in ROWS:
		var start: Vector2 = row[1]
		for n in 5:
			var at: Vector2 = start + Vector2(90.0 + APART * n, BESIDE * (1.0 if n % 2 == 0 else -1.0))
			var dummy := Node2D.new()
			dummy.position = at
			root.add_child(dummy)
			place(DUMMY, 1.0, at)
			projectiles.call("add_target", dummy, 10.0, 1)
	for i in ROWS.size():
		var cards: Array[StringName] = []
		cards.assign(ROWS[i][0])
		spells.call("install_staff", wizards[0], i, spells.call("compile_staff", cards, STARTER))
		label(" ".join(PackedStringArray(cards)), (ROWS[i][1] as Vector2) + Vector2(0.0, -40.0))
	# Cast every staff whenever it is ready, for two thirds of a second of physics steps, then three
	# moments a sixth of a second apart: the crackle is random, so one moment shows only some of it.
	for moment in 3:
		for frame in 40 if moment == 0 else 10:
			for i in ROWS.size():
				spells.call("cast_staff", wizards[0], i, ROWS[i][1], Vector2.RIGHT, 100.0)
			await physics_frame
		await shot("live_arcs" if moment == 0 else "live_arcs_%d" % (moment + 1))
	await snap(Vector2(200.0, 140.0), "live_arcs_4x", Vector2i(160, 60), 4)
