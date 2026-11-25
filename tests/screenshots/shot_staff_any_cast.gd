extends "res://tests/support/screenshot.gd"
## On Any Cast in play (docs/milestones/staff-language.md, L3, build 9): a rune laid with `on any
## cast · rune · frost · nova · atom` answers each cast of the wizard's other staff (atoms fired
## down) with a frost nova. `staff_any_cast_play` is the moment of the third answer.

const ActorSeats := preload("res://tests/support/actor_seats.gd")
const DUMMY := preload("res://content/enemies/training_dummy/idle.svg")
const RUNE: Array[StringName] = [&"on_any_cast", &"rune", &"frost", &"nova", &"atom"]
const OTHER: Array[StringName] = [&"atom"]
const FROM := Vector2(200.0, 180.0)
## Frames the other staff casts on, and the frame of the shot.
const CASTS_AT: Array[int] = [20, 40, 60]
const SHOT_AT: int = 62


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
	var wizard: int = ActorSeats.seat_wizards(actors, 1)[0]
	var staff_base := StaffBase.new()
	staff_base.id = &"staff_any_cast"
	staff_base.slots = 8
	staff_base.cooldown = 0.0
	staff_base.spread = 0.0
	lay_floor()
	for at: Vector2 in [Vector2(330.0, 120.0), Vector2(330.0, 240.0), Vector2(420.0, 180.0)]:
		var dummy := Node2D.new()
		dummy.position = at * k
		root.add_child(dummy)
		place(DUMMY, 1.0, at)
		projectiles.call("add_target", dummy, 10.0, 1)
	label("staff 1: " + " ".join(PackedStringArray(RUNE)), Vector2(20.0, 20.0))
	label("staff 2: atom, cast three times (down): each cast sets the rune off", Vector2(20.0, 34.0))
	spells.call("install_staff", wizard, 0, spells.call("compile_staff", RUNE, staff_base))
	spells.call("install_staff", wizard, 1, spells.call("compile_staff", OTHER, staff_base))
	projectiles.call("set_anchor", wizard, FROM * k)
	spells.call("press_staff", wizard, 0, FROM * k, Vector2.RIGHT, 100.0)
	for frame in SHOT_AT:
		if CASTS_AT.has(frame):
			spells.call("press_staff", wizard, 1, FROM * k, Vector2.DOWN, 100.0)
		await physics_frame
	await shot("staff_any_cast_play")
