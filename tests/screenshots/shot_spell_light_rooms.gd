extends "res://tests/support/screenshot.gd"
## Screenshots of spell light in a room (gameplay/feel/spell_light.gd; docs/milestones/
## spell-spectacle.md, P3b), for the owner's two picks: the sandbox's ambient and the light's steps.
## The same still fight in the crypt sandbox, its torches lit: the four players' bolts, a fire, a
## frost and a lightning bolt, an enemy's bolt, a burst and a blast going off. Taken at the
## ambients `spell_light_room_ambient_100`, `_085` (the sandbox's, the owner's pick of
## 2026-11-04) and `_070`, all in three steps (bands 3), and `spell_light_room_smooth_085` at
## 0.85 with no steps (bands 0), beside `_085`; each also at 3x round the middle (`..._3x`).

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ROOM := preload("res://content/rooms/crypt/sandbox.tscn")
const FIRE := preload("res://content/spells/elements/fire/fire.tres")
const FROST := preload("res://content/spells/elements/frost/frost.tres")
const LIGHTNING := preload("res://content/spells/elements/lightning/lightning.tres")
const BOLT_RADIUS: float = 5.0
const MIDDLE := Vector2(320.0, 150.0)
## How long the burst and the blast last: long, so they hardly change between the takes.
const FLASH_SECONDS: float = 600.0

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
		_bolt(p, Vector2(150.0 + 110.0 * p, 250.0), BOLT_RADIUS, Color.WHITE, PackedInt32Array())
	_bolt(0, Vector2(130.0, 120.0), BOLT_RADIUS, FIRE.get("tint") as Color, PackedInt32Array([int(FIRE.get("look_layer"))]))
	_bolt(1, Vector2(260.0, 160.0), BOLT_RADIUS, FROST.get("tint") as Color, PackedInt32Array([int(FROST.get("look_layer"))]))
	_bolt(3, Vector2(520.0, 120.0), BOLT_RADIUS, LIGHTNING.get("tint") as Color, PackedInt32Array([int(LIGHTNING.get("look_layer"))]))
	_bolt(enemy, Vector2(420.0, 70.0), BOLT_RADIUS, Color.WHITE, PackedInt32Array())
	feel.call("show_flash", &"burst", Vector2(360.0, 190.0), Vector2.RIGHT, Color.WHITE, 2, 0, 2, FLASH_SECONDS)
	feel.call("show_flash", &"shell", Vector2(200.0, 300.0), Vector2.RIGHT, FIRE.get("tint") as Color, 0, ManagerScript.pack_look(PackedInt32Array([int(FIRE.get("look_layer"))])), 6, FLASH_SECONDS)
	feel.call("set_spell_light", true)
	var light: Node = feel.call("light")
	if light == null:
		fail("no spell light with the setting on")
		return
	await settle(30)
	if int(_shots.get("drawn")) < 8:
		fail("the shots are not drawn, got %d" % int(_shots.get("drawn")))
		return
	if int(light.call("spot_count")) < 4:
		fail("the sandbox's torches do not light, got %d" % int(light.call("spot_count")))
		return
	light.call("set_bands", 3)
	for ambient: float in [1.0, 0.85, 0.7]:
		light.call("set_ambient", ambient)
		await _take("spell_light_room_ambient_%03d" % roundi(ambient * 100.0))
	light.call("set_ambient", 0.85)
	light.call("set_bands", 0)
	await _take("spell_light_room_smooth_085")
	light.call("set_bands", 3)
	light.call("set_ambient", 1.0)


func _take(shot_name: String) -> void:
	await settle(6)
	var image: Image = await grab()
	save(image, shot_name)
	save_crop(image, MIDDLE, shot_name + "_3x", Vector2i(200, 110), 3)


## A bolt of `caster` that barely moves (the sheet is a still), with a core and layers.
func _bolt(caster: int, at: Vector2, radius: float, tint: Color, look: PackedInt32Array) -> void:
	var slot: int = _shots.call("spawn", caster, at, Vector2(0.01, 0.0), 600.0, radius) as int
	_shots.call("set_core", slot, tint)
	_shots.call("set_look", slot, ManagerScript.pack_look(look))
