extends "res://tests/support/screenshot.gd"
## Swing trails as the game draws them (melee I4; the owner's pick A3 from the melee mockup): a
## brief line at the reach that sheds pixel sparks outward, cooling through the ramp, with the
## swing's card particles. Rows are cards (plain in player 1's ramp, fire, frost, lightning, plain
## in player 2's, an enemy's); columns are moments of one swing (mid-sweep, its end, 0.1 s and
## 0.25 s on), each cell its own caster so none chains on another. `swing_trails` is the whole
## screen and `swing_trails_4x` a crop of the fire row.

const ActorsScript := preload("res://core/actors/actors.gd")
const STARTER := preload("res://content/wizard/staffs/curl/curl.tres")
## Each row: the cards and the ramp of its casters.
const ROWS: Array = [
	[[&"swing"], 0],
	[[&"fire", &"swing"], 0],
	[[&"frost", &"swing"], 0],
	[[&"lightning", &"swing"], 0],
	[[&"swing"], 1],
	[[&"swing"], ActorsScript.RAMP_ENEMY],
]
## Frames from each column's cast to the shot (60 a second; a 0.12 s wind-up, a 0.06 s sweep).
const PHASES: Array[int] = [9, 11, 17, 26]


func take() -> void:
	if not need(["Spells", "Projectiles", "Feel", "Actors"]):
		return
	var spells: Node = root.get_node("Spells")
	var projectiles: Node = root.get_node("Projectiles")
	var feel: Node = root.get_node("Feel")
	var actors: ActorsScript = root.get_node("Actors") as ActorsScript
	projectiles.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	# Feel on the frames' own time (--fixed-fps), not the wall clock, so each column is the moment
	# it names however slowly the frames draw.
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
		label(" ".join(PackedStringArray(cards)), Vector2(8.0, 30.0 + 55.0 * r))
		for c in PHASES.size():
			var actor: int = actors.open(team, row[1])
			spells.call("install_staff", actor, 0, compiled)
			cells.append([actor, Vector2(120.0 + 80.0 * c, 40.0 + 55.0 * r), PHASES[c]])
	for c in PHASES.size():
		label("%.2f s" % (PHASES[c] / 60.0), Vector2(110.0 + 80.0 * c, 8.0))
	var longest: int = PHASES.max()
	for frame in longest:
		for cell: Array in cells:
			if longest - frame == cell[2]:
				spells.call("cast_staff", cell[0], 0, cell[1], Vector2.RIGHT.rotated(-0.4), 0.0)
		await physics_frame
	var image: Image = await grab()
	save(image, "swing_trails")
	save_crop(image, on_screen(Vector2(240.0, 95.0)), "swing_trails_4x", Vector2i(140, 30), 4)
