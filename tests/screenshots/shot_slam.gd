extends "res://tests/support/screenshot.gd"
## Slams as the game draws them (melee I8): rows are cards (plain in player 1's ramp, fire, an
## enemy's); columns are moments of one slam (mid wind-up with its mark, the impact, 0.1 s and
## 0.3 s on), each cell its own caster. `slam` is the whole screen and `slam_4x` a crop of the
## first row.

const ActorsScript := preload("res://core/actors/actors.gd")
const STARTER := preload("res://content/wizard/staffs/curl/curl.tres")
const DUMMY := preload("res://content/enemies/training_dummy/idle.svg")
## Each row: the cards and the ramp of its casters.
const ROWS: Array = [
	[[&"slam"], 0],
	[[&"fire", &"slam"], 0],
	[[&"slam"], ActorsScript.RAMP_ENEMY],
]
## Frames from each column's cast to the shot (60 a second; a 0.25 s wind-up).
const PHASES: Array[int] = [8, 16, 22, 34]


func take() -> void:
	if not need(["Spells", "Projectiles", "Feel", "Actors"]):
		return
	var spells: Node = root.get_node("Spells")
	var projectiles: Node = root.get_node("Projectiles")
	var feel: Node = root.get_node("Feel")
	var actors: ActorsScript = root.get_node("Actors") as ActorsScript
	projectiles.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	# Feel on the frames' own time (--fixed-fps), so each column is the moment it names.
	feel.set("drive_engine", false)
	actors.clear()
	lay_floor()
	var cells: Array = []
	for r in ROWS.size():
		var row: Array = ROWS[r]
		var cards: Array[StringName] = []
		cards.assign(row[0])
		var compiled: Variant = spells.call("compile_staff", cards, STARTER)
		var team: int = ActorsScript.TEAM_ENEMIES if row[1] == ActorsScript.RAMP_ENEMY else ActorsScript.TEAM_WIZARDS
		label(" ".join(PackedStringArray(cards)), Vector2(8.0, 50.0 + 100.0 * r))
		for c in PHASES.size():
			var actor: int = actors.open(team, row[1])
			spells.call("install_staff", actor, 0, compiled)
			var at := Vector2(110.0 + 130.0 * c, 60.0 + 100.0 * r)
			place(DUMMY, 1.0, at + Vector2(34.0, 0.0))
			cells.append([actor, at, PHASES[c]])
	for c in PHASES.size():
		label("%.2f s" % (PHASES[c] / 60.0), Vector2(110.0 + 130.0 * c, 8.0))
	var longest: int = PHASES.max()
	for frame in longest:
		for cell: Array in cells:
			if longest - frame == cell[2]:
				spells.call("cast_staff", cell[0], 0, cell[1], Vector2.RIGHT, 0.0)
		await physics_frame
	var image: Image = await grab()
	save(image, "slam")
	save_crop(image, on_screen(Vector2(330.0, 60.0)), "slam_4x", Vector2i(160, 40), 4)
