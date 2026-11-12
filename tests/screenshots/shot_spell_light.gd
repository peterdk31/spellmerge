extends "res://tests/support/screenshot.gd"
## Screenshots of spell light (gameplay/feel/spell_light.gd; docs/milestones/spell-spectacle.md,
## P3a): shots lighting the crypt arena's floor, walls and pillars round them, in three steps.
## The same still frame three times: `spell_light_off` (the setting off: the room as it was),
## `spell_light_on` (ambient 1.0, as the game draws it now: light only brightens) and
## `spell_light_ambient_07` (a dev look at a darker room, ambient 0.7); and each at 3x round the
## middle (`..._3x`). The shots: the four players' plain bolts, a fire, a frost, a storm and a
## lightning bolt, a bigger fire bolt, an enemy's bolt and a rune, some beside the walls and the
## pillars; the arena's torches light too (P3b). In the middle, a plain bolt beside an atom, which
## lights less and less far by its card's light (`look_light_intensity`, `look_light_reach`;
## docs/milestones/card-looks.md, phase 1b). The owner's picks of a room's ambient and of the
## light's steps are drawn by shot_spell_light_rooms.gd.

## The rune card's own shot shader, which draws its still shots.
const RUNE: Shader = preload("res://content/spells/carriers/rune/rune.gdshader")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ROOM := preload("res://content/rooms/crypt/arena_01.tscn")
const FIRE := preload("res://content/spells/elements/fire/fire.tres")
const FROST := preload("res://content/spells/elements/frost/frost.tres")
const STORM := preload("res://content/spells/elements/storm/storm.tres")
const LIGHTNING := preload("res://content/spells/elements/lightning/lightning.tres")
const BIGGER := preload("res://content/spells/modifiers/bigger/bigger.tres")
const BOLT := preload("res://content/spells/carriers/bolt/bolt.tres")
const ATOM := preload("res://content/spells/carriers/atom/atom.tres")
const BOLT_RADIUS: float = 5.0
const MIDDLE := Vector2(320.0, 180.0)

var _shots: Node = null


func take() -> void:
	if not need(["Projectiles", "Feel"]):
		return
	_shots = root.get_node("Projectiles")
	var feel: Node = root.get_node("Feel")
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	ActorSeats.seat_wizards(actors)
	var enemy: int = ActorSeats.enemy(actors)
	var room: Node = ROOM.instantiate()
	root.add_child(room)
	_shots.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	_shots.call("set_cap", 200)
	for p in 4:
		_bolt(p, Vector2(110.0 + 140.0 * p, 70.0), BOLT_RADIUS, Color.WHITE, PackedInt32Array())
	_bolt(0, Vector2(150.0, 180.0), BOLT_RADIUS, FIRE.get("tint") as Color, PackedInt32Array([int(FIRE.get("look_layer"))]))
	_bolt(1, Vector2(250.0, 230.0), BOLT_RADIUS, FROST.get("tint") as Color, PackedInt32Array([int(FROST.get("look_layer"))]))
	_bolt(2, Vector2(390.0, 230.0), BOLT_RADIUS, STORM.get("tint") as Color, PackedInt32Array([int(STORM.get("look_layer"))]))
	_bolt(3, Vector2(490.0, 180.0), BOLT_RADIUS, LIGHTNING.get("tint") as Color, PackedInt32Array([int(LIGHTNING.get("look_layer"))]))
	_bolt(0, Vector2(320.0, 300.0), BOLT_RADIUS * 2.0, FIRE.get("tint") as Color, PackedInt32Array([int(FIRE.get("look_layer")), int(BIGGER.get("look_layer"))]))
	_bolt(enemy, Vector2(560.0, 300.0), BOLT_RADIUS, Color.WHITE, PackedInt32Array())
	# A bolt and an atom side by side, each with its card's light.
	for card: Resource in [BOLT, ATOM]:
		var slot: int = _shots.call("spawn", 1, Vector2(285.0 if card == BOLT else 355.0, 150.0), Vector2(0.01, 0.0), 600.0, float(card.get("radius"))) as int
		_shots.call("set_light", slot, float(card.get("look_light_intensity")), float(card.get("look_light_reach")))
	var rune: int = _shots.call("spawn", 0, Vector2(80.0, 300.0), Vector2.ZERO, 600.0, 14.0, 1, 0, 0, ManagerScript.MOTION_STILL) as int
	_shots.call("set_carrier_card", rune, &"rune", _shots.call("register_body", RUNE))
	_dress(rune, FIRE.get("tint") as Color, PackedInt32Array([int(FIRE.get("look_layer"))]))
	if int(_shots.get("drawn")) < 0:
		fail("no shots")
		return
	feel.call("set_spell_light", false)
	await settle(30)
	if int(_shots.get("drawn")) < 10:
		fail("the shots are not drawn, got %d" % int(_shots.get("drawn")))
		return
	await _take("spell_light_off")
	feel.call("set_spell_light", true)
	if feel.call("light") == null:
		fail("no spell light with the setting on")
		return
	await _take("spell_light_on")
	feel.call("light").call("set_ambient", 0.7)
	await _take("spell_light_ambient_07")
	feel.call("light").call("set_ambient", 1.0)


func _take(shot_name: String) -> void:
	await settle(6)
	var image: Image = await grab()
	save(image, shot_name)
	save_crop(image, MIDDLE, shot_name + "_3x", Vector2i(200, 110), 3)


## A bolt of `caster` that barely moves (the sheet is a still), with a core and layers.
func _bolt(caster: int, at: Vector2, radius: float, tint: Color, look: PackedInt32Array) -> void:
	var slot: int = _shots.call("spawn", caster, at, Vector2(0.01, 0.0), 600.0, radius) as int
	_dress(slot, tint, look)


func _dress(slot: int, tint: Color, look: PackedInt32Array) -> void:
	_shots.call("set_core", slot, tint)
	_shots.call("set_look", slot, ManagerScript.pack_look(look))
