extends "res://tests/support/screenshot.gd"
## The look of shots in flight (the glow look, 2026-10-27): the tails of moving shots, which
## `shot_looks.gd` (a still) cannot show. The looks come from the real cards (`tint` and
## `look_layer`). It fails when fewer than 40 shots are drawn.
##
## `moving_looks` (1x, as a player sees it), a column per infusion (plain, fire, frost, storm,
## void, lightning):
##   top     three orbit shots circling (radius 36, as the orbit form): their tails bend
##           round the circle, behind each shot
##   middle  a nova a quarter of a second after its cast: eight bolts flying out
##   bottom  spiralling bolts (the spiral modifier): their tails bend with every turn
## `moving_orbits_4x`: the first three orbit columns at 4x.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ELEMENTS: Array[Resource] = [
	preload("res://content/spells/elements/fire/fire.tres"),
	preload("res://content/spells/elements/frost/frost.tres"),
	preload("res://content/spells/elements/storm/storm.tres"),
	preload("res://content/spells/elements/void/void.tres"),
	preload("res://content/spells/elements/lightning/lightning.tres"),
]
const ORBIT := preload("res://content/spells/forms/orbit/orbit.tres")
const NOVA := preload("res://content/spells/forms/nova/nova.tres")
const BOLT := preload("res://content/spells/forms/bolt/bolt.tres")

var _shots: Node = null


func take() -> void:
	if not need(["Projectiles"]):
		return
	_shots = root.get_node("Projectiles")
	# A shot's caster is an actor id (actors G3b): open the four wizards in the Actors table, so
	# each player's shots take its hat ramp.
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	var wizards: PackedInt32Array = ActorSeats.seat_wizards(actors)
	lay_floor()
	_shots.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	_shots.call("set_cap", 300)
	var orbit_radius: float = float(ORBIT.get("orbit_radius"))
	var spin: float = float(ORBIT.get("speed")) / orbit_radius
	for e in 6:
		var x: float = 55.0 + e * 106.0
		var tint: Color = Color.WHITE if e == 0 else ELEMENTS[e - 1].get("tint") as Color
		var look: PackedInt32Array = PackedInt32Array() if e == 0 else PackedInt32Array([int(ELEMENTS[e - 1].get("look_layer"))])
		# Each column is its own player's (0-3, then 0 and 1 again), so the orbits have anchors
		# of their own; the plain ones show that player's colour.
		var player: int = wizards[e % 4]
		if e < 4:
			_shots.call("set_anchor", player, Vector2(x, 60.0))
		for n in 3:
			var centre: Vector2 = Vector2(x, 60.0)
			var orb: int = _shots.call("spawn_orbit", player, orbit_radius, n * TAU / 3.0, spin, 600.0, float(ORBIT.get("radius")), 1, 0, 0, centre) as int
			_dress(orb, tint, look)
		var shots: int = int(NOVA.get("shots"))
		for n in shots:
			var dir: Vector2 = Vector2.from_angle(n * TAU / shots)
			var slot: int = _shots.call("spawn", player, Vector2(x, 180.0), dir * float(NOVA.get("speed")), 600.0, float(NOVA.get("radius"))) as int
			_dress(slot, tint, look)
		var bolt: int = _shots.call("spawn", player, Vector2(x - 50.0, 300.0), Vector2(float(BOLT.get("speed")) * 0.5, 0.0), 600.0, float(BOLT.get("radius"))) as int
		_shots.call("set_spiral", bolt, 40.0)
		_dress(bolt, tint, look)
	await settle(15)
	var image: Image = await grab()
	if int(_shots.get("drawn")) < 40:
		fail("only %d shots were drawn" % int(_shots.get("drawn")))
		return
	save(image, "moving_looks")
	save_crop(image, Vector2(160.0, 60.0), "moving_orbits_4x", Vector2i(160, 50))


func _dress(slot: int, tint: Color, look: PackedInt32Array) -> void:
	_shots.call("set_core", slot, tint)
	_shots.call("set_look", slot, ManagerScript.pack_look(look))
