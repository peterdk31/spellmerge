extends "res://tests/support/screenshot.gd"
## Where motes come from (gameplay/feel/feel.gd; docs/milestones/spell-spectacle.md, P1b), as the
## game makes them, each with the flashes it comes with. `mote_sources`: a frost bolt hitting a
## body (its flecks back the way it came), a fire bolt whose life runs out (a puff of embers), a
## shatter reaction (a ring in its colour) and an enemy dying to a fire bolt (embers, and chips in
## the colours of its own art). `mote_cues`: the cues' `motes` parts, a fire blast, a fireball, a
## slam, a quake and a lightning nova, each 40 px big, in the crypt arena (its walls' colours for
## the ground's chips). Columns are moments after it happened, each cell its own; `_4x` sheets are
## the second column at 4x.

const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const HUSK := preload("res://content/enemies/bone_husk/idle.svg")
const DUMMY := preload("res://content/enemies/training_dummy/idle.svg")
const FIRE := preload("res://content/spells/elements/fire/fire.tres")
const FROST := preload("res://content/spells/elements/frost/frost.tres")
const LIGHTNING := preload("res://content/spells/elements/lightning/lightning.tres")
## Frames from each cell's moment to the shot (60 a second).
const PHASES: Array[int] = [3, 12, 30, 72]
const ROW_HEIGHT: float = 70.0
const SIZE: float = 40.0
const SOURCES: Array[StringName] = [&"hit", &"expired", &"reaction", &"death"]
const CUES: Array[StringName] = [&"blast", &"fireball", &"slam", &"quake", &"nova"]


func take() -> void:
	if not need(["Feel", "Actors", "Events", "Projectiles"]):
		return
	var feel: Node = root.get_node("Feel")
	feel.set("drive_engine", false)
	feel.call("_on_room_entered", &"arena_01")
	await _sheet(SOURCES, "mote_sources")
	await _sheet(CUES, "mote_cues")


## One sheet: a row for each of `rows`, a column for each phase.
func _sheet(rows: Array[StringName], shot_name: String) -> void:
	var actors: ActorsScript = root.get_node("Actors") as ActorsScript
	actors.clear()
	# The last sheet's floor, labels and bodies go, and its motes cool out.
	for child in root.get_children():
		if child.has_meta(&"mote_sheet") or child is Label or child is Sprite2D:
			child.queue_free()
	await settle(260)
	lay_floor()
	var cells: Array = []
	for r in rows.size():
		label(String(rows[r]), Vector2(4.0, 44.0 + ROW_HEIGHT * r))
		for c in PHASES.size():
			var actor: int = actors.open(ActorsScript.TEAM_WIZARDS, 0)
			var at := Vector2(150.0 + 130.0 * c, 50.0 + ROW_HEIGHT * r)
			cells.append([actor, at, PHASES[c], rows[r]])
	for c in PHASES.size():
		label("%.2f s" % (PHASES[c] / 60.0), Vector2(130.0 + 130.0 * c, 2.0))
	var longest: int = PHASES.max()
	for frame in longest:
		for cell: Array in cells:
			if longest - frame == cell[2]:
				_make(cell[3] as StringName, int(cell[0]), cell[1] as Vector2)
		await physics_frame
	var image: Image = await grab()
	save(image, shot_name)
	save_crop(image, on_screen(Vector2(280.0, 50.0 + ROW_HEIGHT * (rows.size() - 1) * 0.5)), shot_name + "_4x", Vector2i(60, 80), 4)


## Set off `what` by `actor` at `at`.
func _make(what: StringName, actor: int, at: Vector2) -> void:
	var events: Node = root.get_node("Events")
	var shots: ProjectilesScript = root.get_node("Projectiles") as ProjectilesScript
	match what:
		&"hit":
			var target: Sprite2D = _body(DUMMY, at)
			shots.impact_look = 1 << (FROST.look_layer - 1)
			shots.impact_core = FROST.tint
			shots.impact_form = &"bolt"
			events.emit_signal(&"projectile_impact", actor, target, at, Vector2.RIGHT)
			shots.impact_look = 0
			shots.impact_core = Color.WHITE
			shots.impact_form = &""
		&"expired":
			shots.impact_body = ProjectilesScript.KIND_BOLT
			shots.impact_look = 1 << (FIRE.look_layer - 1)
			shots.impact_core = FIRE.tint
			shots.impact_heading = Vector2.RIGHT
			shots.expired_on_wall = false
			events.emit_signal(&"projectile_expired", actor, at, 0, -1)
			shots.impact_body = 0
			shots.impact_look = 0
			shots.impact_core = Color.WHITE
		&"reaction":
			events.emit_signal(&"reaction_triggered", actor, &"shatter", at, -1)
		&"death":
			var shot: int = shots.spawn(actor, at + Vector2(0.0, 4000.0), Vector2.RIGHT, 0.5, 4.0, 0)
			shots.set_look(shot, 1 << (FIRE.look_layer - 1))
			shots.set_core(shot, FIRE.tint)
			var body: Sprite2D = _body(HUSK, at)
			events.emit_signal(&"enemy_died", actor, body.get_parent(), at, shot)
			body.get_parent().queue_free()
		&"nova":
			events.emit_signal(&"cue_shown", actor, what, at, Vector2.ZERO, SIZE, LIGHTNING.tint, 1 << (LIGHTNING.look_layer - 1))
		_:
			events.emit_signal(&"cue_shown", actor, what, at, Vector2.RIGHT, SIZE, FIRE.tint, 1 << (FIRE.look_layer - 1))


## A body showing `texture` at `at` (its `Sprite`), left on the sheet.
func _body(texture: Texture2D, at: Vector2) -> Sprite2D:
	var body := Node2D.new()
	body.set_meta(&"mote_sheet", true)
	body.global_position = at
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	body.add_child(sprite)
	root.add_child(body)
	return sprite
