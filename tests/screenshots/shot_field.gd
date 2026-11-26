extends "res://tests/support/screenshot.gd"
## The field (docs/milestones/field.md; content/spells/carriers/field/: its card's own
## `field.gdshader`), staged in an empty room (a laid floor, no run), on the real runtime:
## - `field_changing`: a wizard's fire field, and a teammate's plain bolts fired through it: white
##   before it, burning past it (2x).
## - `field_enemy`: a wizard's frost field, and an enemy's bolts fired at the wizard through it: they
##   come out of it frost (2x).
## - `field_dam`: a linger field holding a volley where it came in (2x).
## - `field_close`: the fire field's look close up (5x), and `field_opening` its second frame.

const ActorSeats := preload("res://tests/support/actor_seats.gd")
const STAFF := preload("res://content/wizard/staffs/dev/dev.tres")
## Mana enough for any cast.
const MANA: float = 1000.0
const FIELD_STAFF: int = 0
const BOLT_STAFF: int = 1

var _spells: Node = null
var _shots: Node = null
var _wizards: PackedInt32Array = PackedInt32Array()
var _enemy: int = -1


func take() -> void:
	if not need(["Feel", "Events", "Projectiles", "Spells"]):
		return
	settle_frames = 40
	root.get_node("Feel").set("drive_engine", false)
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	_wizards = ActorSeats.seat_wizards(actors, 2)
	_enemy = ActorSeats.enemy(actors)
	_spells = root.get_node("Spells")
	_shots = root.get_node("Projectiles")
	_shots.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	lay_floor()
	await settle()
	# A fire field, and a teammate's plain bolts through it.
	_install(_wizards[0], FIELD_STAFF, [&"fire", &"field"])
	_install(_wizards[1], BOLT_STAFF, [&"split", &"split", &"bolt"])
	await _clear()
	var from := Vector2(120.0, 180.0)
	_cast(_wizards[0], FIELD_STAFF, from, Vector2.RIGHT)
	await _frames(2)
	var opening: Image = await grab()
	save_crop(opening, on_screen(from + Vector2(72.0, 0.0)), "field_opening", Vector2i(40, 30), 5)
	await _frames(20)
	_cast(_wizards[1], BOLT_STAFF, Vector2(40.0, 180.0), Vector2.RIGHT)
	await _frames(30)
	var image: Image = await grab()
	save_crop(image, on_screen(Vector2(220.0, 180.0)), "field_changing", Vector2i(170, 80), 2)
	save_crop(image, on_screen(from + Vector2(72.0, 0.0)), "field_close", Vector2i(40, 30), 5)
	# A frost field, and an enemy's bolts at the wizard through it.
	_install(_wizards[0], FIELD_STAFF, [&"frost", &"field"])
	_install(_enemy, BOLT_STAFF, [&"split", &"split", &"bolt"])
	await _clear()
	_cast(_wizards[0], FIELD_STAFF, from, Vector2.RIGHT)
	await _frames(20)
	var foe := Vector2(400.0, 180.0)
	_shots.call("set_anchor", _enemy, foe)
	_cast(_enemy, BOLT_STAFF, foe, (from - foe).normalized())
	await _frames(40)
	await snap(Vector2(250.0, 180.0), "field_enemy", Vector2i(170, 80), 2)
	# The dam: a linger field holding a volley.
	_install(_wizards[0], FIELD_STAFF, [&"linger", &"field"])
	await _clear()
	_cast(_wizards[0], FIELD_STAFF, from, Vector2.RIGHT)
	await _frames(20)
	_cast(_wizards[1], BOLT_STAFF, Vector2(40.0, 180.0), Vector2.RIGHT)
	await _frames(40)
	await snap(Vector2(190.0, 180.0), "field_dam", Vector2i(130, 70), 2)


func _install(actor: int, slot: int, cards: Array[StringName]) -> void:
	_spells.call("install_staff", actor, slot, _spells.call("compile_staff", cards, STAFF))


func _cast(actor: int, slot: int, at: Vector2, way: Vector2) -> void:
	var spent: float = float(_spells.call("cast_staff", actor, slot, at, way.normalized(), MANA))
	if spent < 0.0:
		fail("actor %d's cast was refused" % actor)


## Clear the shots and the fields.
func _clear() -> void:
	_shots.call("clear")
	var fields: CarrierField = CarrierField.of(_spells as SpellRuntime)
	if fields != null:
		fields.clear()
	await settle(2)


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame
