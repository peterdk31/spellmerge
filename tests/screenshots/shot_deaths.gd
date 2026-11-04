extends "res://tests/support/screenshot.gd"
## Deaths as the game draws them (gameplay/feel/feel.gd, `enemy_died`; docs/milestones/
## spell-spectacle-2.md, S3): a row per body size, the crypt mite, the ember imp, the bone husk and
## a boss-sized body (the bone scepter's art drawn twice as big), each killed by a plain bolt flying
## right; columns are moments after the kill, each cell its own death. `deaths` at 1x, `deaths_3x`
## a crop of the bone husk's and the boss's first four moments at 3x.

const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
## The bodies, and how much bigger than its art each is drawn.
const BODIES: Array[Texture2D] = [
	preload("res://content/enemies/crypt_mite/idle.svg"),
	preload("res://content/enemies/ember_imp/idle.svg"),
	preload("res://content/enemies/bone_husk/idle.svg"),
	preload("res://content/enemies/bone_scepter/idle.svg"),
]
const SCALES: Array[float] = [1.0, 1.0, 1.0, 2.0]
const NAMES: Array[String] = ["mite", "imp", "husk", "boss size"]
## Frames from each cell's kill to the shot (60 a second).
const PHASES: Array[int] = [2, 6, 10, 16, 30, 60]
const ROW_HEIGHT: float = 80.0
const COLUMN: float = 90.0


func take() -> void:
	if not need(["Feel", "Actors", "Events", "Projectiles"]):
		return
	var feel: Node = root.get_node("Feel")
	feel.set("drive_engine", false)
	_enter_room()
	var actors: ActorsScript = root.get_node("Actors") as ActorsScript
	actors.clear()
	await settle(30)
	lay_floor()
	var cells: Array = []
	for r in BODIES.size():
		label(NAMES[r], Vector2(4.0, 40.0 + ROW_HEIGHT * r))
		for c in PHASES.size():
			var actor: int = actors.open(ActorsScript.TEAM_WIZARDS, 0)
			# A row a frame apart, so no two deaths share a frame's motes.
			cells.append([actor, Vector2(110.0 + COLUMN * c, 56.0 + ROW_HEIGHT * r), PHASES[c] + r, r])
	for c in PHASES.size():
		label("%.2f s" % (PHASES[c] / 60.0), Vector2(92.0 + COLUMN * c, 2.0))
	var longest: int = PHASES.max() + BODIES.size()
	for frame in longest:
		for cell: Array in cells:
			if longest - frame == cell[2]:
				_kill(int(cell[0]), cell[1] as Vector2, int(cell[3]))
		await physics_frame
	var image: Image = await grab()
	save(image, "deaths")
	save_crop(image, on_screen(Vector2(110.0 + COLUMN * 1.5, 56.0 + ROW_HEIGHT * 2.5)), "deaths_3x", Vector2i(180, 80), 3)


## Kill a body of row `r` at `at` with a plain bolt of `actor`'s.
func _kill(actor: int, at: Vector2, r: int) -> void:
	var events: Node = root.get_node("Events")
	var shots: ProjectilesScript = root.get_node("Projectiles") as ProjectilesScript
	var shot: int = shots.spawn(actor, at + Vector2(0.0, 4000.0), Vector2.RIGHT, 0.5, 4.0, 0)
	var body := Node2D.new()
	body.global_position = at
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = BODIES[r]
	sprite.scale = Vector2.ONE * SCALES[r]
	body.add_child(sprite)
	root.add_child(body)
	events.emit_signal(&"enemy_died", actor, body, at, shot)
	body.queue_free()


## The room as Flow gives it (shot_marks.gd's way): the projectile manager's bounds, then
## `room_entered`, so Feel's floor marks (a blast's scorch, S3) and the walls' colours are fitted.
func _enter_room() -> void:
	var projectiles: Node = root.get_node_or_null("Projectiles")
	if projectiles != null:
		projectiles.call("set_bounds", Rect2(Vector2.ZERO, Vector2(640.0, 384.0)))
	root.get_node("Events").emit_signal(&"room_entered", &"arena_01")
