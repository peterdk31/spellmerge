extends "res://tests/support/screenshot.gd"
## Cues past the old size caps (the owner, 2026-11-09: no cue is capped in size; an explosion was
## 126 px round at most, an arc 252 px long): `big_blasts` is the shell (`blast`) and the rising
## fireball (`fireball`) of radius 150 a few frames after they go off, each with a thin white
## ring at exactly that radius (the blast's damage zone), so the drawing can be checked against
## it; `big_arc` is a 560 px discharge arc.

const ActorsScript := preload("res://core/actors/actors.gd")
const FIRE := preload("res://content/spells/elements/fire/fire.tres")
const RADIUS: float = 150.0
## Frames from going off to the shot (60 a second): the shell at its fullest, the fireball's
## lobes swollen.
const FRAMES: int = 6
const ARC_LENGTH: float = 560.0


func take() -> void:
	if not need(["Feel", "Actors", "Events"]):
		return
	var feel: Node = root.get_node("Feel")
	var actors: ActorsScript = root.get_node("Actors") as ActorsScript
	var events: Node = root.get_node("Events")
	feel.set("drive_engine", false)
	_enter_room()
	actors.clear()
	lay_floor()
	var actor: int = actors.open(ActorsScript.TEAM_WIZARDS, 0)
	var spots: Array[Vector2] = [Vector2(165.0, 200.0), Vector2(480.0, 200.0)]
	var cues: Array[StringName] = [&"blast", &"fireball"]
	for i in cues.size():
		label("%s, radius %d" % [cues[i], RADIUS], spots[i] + Vector2(-50.0, -RADIUS - 28.0))
		_ring(spots[i], RADIUS)
		events.emit_signal(&"cue_shown", actor, cues[i], spots[i], Vector2.ZERO, RADIUS, FIRE.tint, 0)
	for frame in FRAMES:
		await physics_frame
	save(await grab(), "big_blasts")
	for frame in 90:
		await physics_frame
	label("arc, %d px" % ARC_LENGTH, Vector2(40.0, 150.0))
	feel.call("show_flash", &"arc", Vector2(40.0, 190.0), Vector2.RIGHT, Color.WHITE, 0, 0, 1, 0.6, ARC_LENGTH)
	for frame in 4:
		await physics_frame
	save(await grab(), "big_arc")


## A thin white ring of `radius` round `at`, over the cues.
func _ring(at: Vector2, radius: float) -> void:
	var line := Line2D.new()
	line.width = 1.0
	line.default_color = Color(1.0, 1.0, 1.0, 0.7)
	line.z_index = 100
	for n in 97:
		line.add_point(at + Vector2.RIGHT.rotated(TAU * n / 96.0) * radius)
	root.add_child(line)


## The room as Flow gives it (shot_blast.gd's way), so Feel's floor marks and walls are fitted.
func _enter_room() -> void:
	var projectiles: Node = root.get_node_or_null("Projectiles")
	if projectiles != null:
		projectiles.call("set_bounds", Rect2(Vector2.ZERO, Vector2(640.0, 384.0)))
	root.get_node("Events").emit_signal(&"room_entered", &"arena_01")
