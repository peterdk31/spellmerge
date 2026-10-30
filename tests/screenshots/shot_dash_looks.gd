extends "res://tests/support/screenshot.gd"
## A wizard's dash (the owner, 2026-10-28: the dash look went the aim's way, not the wizard's): a
## row per infusion (plain, fire, frost, storm, void, lightning; the real cards' colours and
## looks), each caster dashing 80 px (Dash) to the right and bending down on the way, as
## a wizard does that walks while it dashes. The way is the caster's trail (`follow_caster`, the
## projectile manager): speed streaks in the player's colours and the cards where it went; Feel
## draws the dust where it left and the ring where it landed (`caster_move_finished`).
## `dash_looks` half way through, `dash_looks_landed` just after the landing, and
## `dash_looks_4x` (the plain, fire and frost rows half way).

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ELEMENTS: Array[Resource] = [
	preload("res://content/spells/elements/fire/fire.tres"),
	preload("res://content/spells/elements/frost/frost.tres"),
	preload("res://content/spells/elements/storm/storm.tres"),
	preload("res://content/spells/elements/void/void.tres"),
	preload("res://content/spells/elements/lightning/lightning.tres"),
]
const DASH := preload("res://content/spells/forms/dash/dash.tres")
const ROW: float = 58.0
## Physics steps the dash takes (0.27 s, as the mockup's).
const STEPS: int = 16


func take() -> void:
	if not need(["Feel", "Projectiles", "Events"]):
		return
	var feel: Node = root.get_node("Feel")
	var shots: Node = root.get_node("Projectiles")
	var events: Node = root.get_node("Events")
	feel.set("drive_engine", false)
	lay_floor()
	shots.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	await settle()
	var length: float = float(DASH.get("ray_length"))
	var casters: Array[int] = []
	# Casters are actor ids (actors G8): the four wizards seated 0-3 (ids 0-3) and two enemies.
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	ActorSeats.seat_wizards(actors)
	var enemies: Array[int] = [ActorSeats.enemy(actors), ActorSeats.enemy(actors)]
	for e in 6:
		var tint: Color = Color.WHITE if e == 0 else ELEMENTS[e - 1].get("tint") as Color
		var look: int = 0 if e == 0 else ManagerScript.pack_look(PackedInt32Array([int(ELEMENTS[e - 1].get("look_layer"))]))
		# Players 0-3, then two enemy casters (their streaks are the enemy ramp).
		var caster: int = e if e < 4 else enemies[e - 4]
		casters.append(caster)
		shots.call("set_anchor", caster, _at(e, 0.0, length))
		shots.call("follow_caster", caster, tint, look, float(STEPS) / 60.0)
		events.emit_signal("form_shown", caster, &"dash", _at(e, 0.0, length), Vector2.UP, length, tint, look)
	for n in STEPS + 4:
		await physics_frame
		for e in 6:
			shots.call("set_anchor", casters[e], _at(e, float(n + 1) / float(STEPS), length))
		feel.call("step", 1.0 / 60.0)
		if n == STEPS / 2:
			var image: Image = await grab()
			save(image, "dash_looks")
			save_crop(image, Vector2(220.0, 32.0 + ROW), "dash_looks_4x", Vector2i(110, int(ROW * 1.5)))
		if n == STEPS - 1:
			for e in 6:
				events.emit_signal("caster_move_finished", casters[e], &"dash", _at(e, 1.0, length), 0)
	if int(shots.get("drawn_trails")) < 6:
		fail("only %d dash trails are showing" % int(shots.get("drawn_trails")))
		return
	save(await grab(), "dash_looks_landed")


## Where dasher `e` is `t` of the way through: right along its row, bending down at the end.
func _at(e: int, t: float, length: float) -> Vector2:
	var p: float = minf(t, 1.0)
	var eased: float = 1.0 - (1.0 - p) * (1.0 - p)
	return Vector2(180.0 + length * eased, 32.0 + e * ROW + 14.0 * eased * eased)
