extends "res://tests/support/screenshot.gd"
## The atom beside the bolt in flight: a speck (hit radius below `SPECK_RADIUS`) drawn as a
## one-pixel core (`shot_head.gdshader`), and a fast shot's tail of motes, laid along all the
## way it went. It fails when fewer than 18 shots
## are drawn.
##
## `atom_looks` (1x): three lanes per infusion (plain, fire, frost, storm, void, lightning), all
## flying right: a bolt drawn by its card's own shader (`carriers/bolt/bolt.gdshader`, its core a `x`;
## docs/milestones/card-looks.md), an atom, and a bolt drawn by the plain head (`+`) for the owner
## to judge them side by side. `atom_looks_4x`: the plain infusion's three heads at 4x.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ELEMENTS: Array[Resource] = [
	preload("res://content/spells/elements/fire/fire.tres"),
	preload("res://content/spells/elements/frost/frost.tres"),
	preload("res://content/spells/elements/storm/storm.tres"),
	preload("res://content/spells/elements/void/void.tres"),
	preload("res://content/spells/elements/lightning/lightning.tres"),
]
const BOLT := preload("res://content/spells/carriers/bolt/bolt.tres")
const ATOM := preload("res://content/spells/carriers/atom/atom.tres")
## Frames the shots fly before the picture (a quarter of a second).
const FLIGHT: int = 15

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
	var atom_at: Vector2 = Vector2.ZERO
	for e in 6:
		var tint: Color = Color.WHITE if e == 0 else ELEMENTS[e - 1].get("tint") as Color
		var look: PackedInt32Array = PackedInt32Array() if e == 0 else PackedInt32Array([int(ELEMENTS[e - 1].get("look_layer"))])
		var player: int = wizards[e % 4]
		var y: float = 30.0 + e * 56.0
		for lane in 3:
			var carrier_card: Resource = ATOM if lane == 1 else BOLT
			var speed: float = float(carrier_card.get("speed"))
			# Both end their flight at the same x, so the tails line up behind them.
			var start: Vector2 = Vector2(420.0 - speed * float(FLIGHT) / 60.0, y + lane * 17.0)
			var slot: int = _shots.call("spawn", player, start, Vector2(speed, 0.0), 600.0, float(carrier_card.get("radius"))) as int
			if lane == 0:
				# The bolt's own look: its card's shader, a pair of head batches of its own.
				_shots.call("set_carrier_card", slot, &"bolt", _shots.call("register_body", carrier_card.get("look_shader"), ManagerScript.MESH_HEAD))
			_shots.call("set_core", slot, tint)
			_shots.call("set_look", slot, ManagerScript.pack_look(look))
		if e == 0:
			atom_at = Vector2(420.0, y + 17.0)
	await settle(FLIGHT)
	var image: Image = await grab()
	if int(_shots.get("drawn")) < 18:
		fail("only %d shots were drawn" % int(_shots.get("drawn")))
		return
	save(image, "atom_looks")
	save_crop(image, atom_at, "atom_looks_4x", Vector2i(80, 44))
