extends "res://tests/support/screenshot.gd"
## Explosions as the game draws them (`explosion_shown`, Feel's `explode`): rows are blast in
## player 1's ramp, blast with fire, an enemy's blast, and the rising fireball (a barrel's);
## columns are moments after it goes off, each cell its own explosion of radius 40 by an actor of
## that row's ramp. `blast` is the whole screen and `blast_4x` a crop of the first row's first
## two cells.

const ActorsScript := preload("res://core/actors/actors.gd")
const DUMMY := preload("res://content/enemies/training_dummy/idle.svg")
const FIRE := preload("res://content/spells/elements/fire/fire.tres")
## Each row: the style, the ramp of its actor and the tint (white: plain).
const ROWS: Array = [
	[&"blast", 0, false],
	[&"blast", 0, true],
	[&"blast", ActorsScript.RAMP_ENEMY, false],
	[&"fireball", ActorsScript.RAMP_ENEMY, true],
]
## Frames from each cell's explosion to the shot (60 a second).
const PHASES: Array[int] = [2, 8, 20, 54]
const RADIUS: float = 40.0


func take() -> void:
	if not need(["Feel", "Actors", "Events"]):
		return
	var feel: Node = root.get_node("Feel")
	var actors: ActorsScript = root.get_node("Actors") as ActorsScript
	var events: Node = root.get_node("Events")
	# Feel on the frames' own time (--fixed-fps), so each column is the moment it names.
	feel.set("drive_engine", false)
	actors.clear()
	lay_floor()
	var cells: Array = []
	for r in ROWS.size():
		var row: Array = ROWS[r]
		var team: int = ActorsScript.TEAM_ENEMIES if row[1] == ActorsScript.RAMP_ENEMY else ActorsScript.TEAM_WIZARDS
		label("%s%s" % [row[0], " fire" if row[2] else ""], Vector2(4.0, 40.0 + 84.0 * r))
		for c in PHASES.size():
			var actor: int = actors.open(team, row[1])
			var at := Vector2(130.0 + 140.0 * c, 50.0 + 84.0 * r)
			place(DUMMY, 1.0, at + Vector2(24.0, -6.0))
			cells.append([actor, at, PHASES[c], row])
	for c in PHASES.size():
		label("%.2f s" % (PHASES[c] / 60.0), Vector2(110.0 + 140.0 * c, 2.0))
	var longest: int = PHASES.max()
	for frame in longest:
		for cell: Array in cells:
			if longest - frame == cell[2]:
				var row: Array = cell[3]
				var tint: Color = FIRE.tint if row[2] else Color.WHITE
				events.emit_signal(&"explosion_shown", cell[0], cell[1], RADIUS, row[0], tint, 0)
		await physics_frame
	var image: Image = await grab()
	save(image, "blast")
	save_crop(image, on_screen(Vector2(200.0, 50.0)), "blast_4x", Vector2i(140, 45), 4)
