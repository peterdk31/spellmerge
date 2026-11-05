extends "res://tests/support/screenshot.gd"
## A shot's head grows with its hit radius (`look_zoom`, `shot_trail.gdshader`): a bare bolt
## (radius 5, zoom 1), one with Bigger (8, zoom 2) and one with Bigger twice (12.8, zoom 3), in
## flight. Lanes: plain, fire, frost, void. It fails when fewer than 12 shots are drawn.
##
## `bigger_looks` (1x), `bigger_looks_4x`: the plain lane's three heads at 4x.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const BOLT := preload("res://content/spells/forms/bolt/bolt.tres")
const BIGGER := preload("res://content/spells/modifiers/bigger/bigger.tres")
const ELEMENTS: Array[Resource] = [
	preload("res://content/spells/elements/fire/fire.tres"),
	preload("res://content/spells/elements/frost/frost.tres"),
	preload("res://content/spells/elements/void/void.tres"),
]
## Frames the shots fly before the picture (a quarter of a second).
const FLIGHT: int = 15
## The columns: no Bigger, one, two.
const COLUMNS: int = 3

var _shots: Node = null


func take() -> void:
	if not need(["Projectiles"]):
		return
	_shots = root.get_node("Projectiles")
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	var wizards: PackedInt32Array = ActorSeats.seat_wizards(actors)
	lay_floor()
	_shots.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	_shots.call("set_cap", 300)
	var plain_at: Vector2 = Vector2.ZERO
	for lane in 4:
		var tint: Color = Color.WHITE if lane == 0 else ELEMENTS[lane - 1].get("tint") as Color
		var look: PackedInt32Array = PackedInt32Array() if lane == 0 else PackedInt32Array([int(ELEMENTS[lane - 1].get("look_layer"))])
		var player: int = wizards[lane % 4]
		var y: float = 50.0 + lane * 80.0
		for column in COLUMNS:
			var radius: float = float(BOLT.get("radius")) * pow(float(BIGGER.get("radius_mult")), column)
			var speed: float = float(BOLT.get("speed")) * pow(float(BIGGER.get("speed_mult")), column)
			var kinds: PackedInt32Array = look.duplicate()
			if column > 0:
				kinds.append(int(BIGGER.get("look_layer")))
			var end_x: float = 200.0 + column * 160.0
			var slot: int = _shots.call("spawn", player, Vector2(end_x - speed * float(FLIGHT) / 60.0, y), Vector2(speed, 0.0), 600.0, radius) as int
			_shots.call("set_core", slot, tint)
			_shots.call("set_look", slot, ManagerScript.pack_look(kinds))
			if lane == 0 and column == 1:
				plain_at = Vector2(end_x, y)
	await settle(FLIGHT)
	var image: Image = await grab()
	if int(_shots.get("drawn")) < 12:
		fail("only %d shots were drawn" % int(_shots.get("drawn")))
		return
	save(image, "bigger_looks")
	save_crop(image, plain_at, "bigger_looks_4x", Vector2i(200, 30))
