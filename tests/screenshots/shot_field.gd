extends "res://tests/support/screenshot.gd"
## The field (docs/milestones/field.md, the owner's design of 2026-11-26; content/spells/carriers/field/:
## its card's own `field.gdshader`), staged in an empty room (a laid floor, no run), on the real runtime:
## - `field_catching`: a wizard's fire field catching a teammate's bolts, drawn in to its middle, the
##   field grown (2x); `field_close` its look close up (5x); `field_opening` its second frame (5x).
## - `field_burst`: the same field at its end, its bolts leaving the way they came in, burning (2x).
## - `field_enemy`: a wizard's frost field holding an enemy's bolts, then `field_enemy_burst` sending
##   them on at the wizard, frost (2x).

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
	# A fire field, and a teammate's plain bolts into it.
	_install(_wizards[0], FIELD_STAFF, [&"fire", &"field"])
	_install(_wizards[1], BOLT_STAFF, [&"plus_two", &"plus_two", &"bolt"])
	await _clear()
	var from := Vector2(120.0, 180.0)
	var middle: Vector2 = from + Vector2(72.0, 0.0)
	_cast(_wizards[0], FIELD_STAFF, from, Vector2.RIGHT)
	await _frames(2)
	var opening: Image = await grab()
	save_crop(opening, on_screen(middle), "field_opening", Vector2i(40, 30), 5)
	await _frames(20)
	_cast(_wizards[1], BOLT_STAFF, Vector2(40.0, 180.0), Vector2.RIGHT)
	await _frames(40)
	var image: Image = await grab()
	save_crop(image, on_screen(middle + Vector2(40.0, 0.0)), "field_catching", Vector2i(150, 70), 2)
	save_crop(image, on_screen(middle), "field_close", Vector2i(50, 36), 5)
	# Its end: the burst, the way they came in, burning.
	await _frames(180 - 62 + 8)
	await snap(middle + Vector2(70.0, 0.0), "field_burst", Vector2i(150, 70), 2)
	# A frost field, and an enemy's bolts at the wizard into it.
	_install(_wizards[0], FIELD_STAFF, [&"frost", &"field"])
	_install(_enemy, BOLT_STAFF, [&"plus_two", &"plus_two", &"bolt"])
	await _clear()
	_cast(_wizards[0], FIELD_STAFF, from, Vector2.RIGHT)
	await _frames(20)
	var foe := Vector2(420.0, 180.0)
	_shots.call("set_anchor", _enemy, foe)
	_cast(_enemy, BOLT_STAFF, foe, (from - foe).normalized())
	await _frames(50)
	await snap(middle + Vector2(60.0, 0.0), "field_enemy", Vector2i(150, 70), 2)
	await _frames(180 - 70 + 8)
	await snap(middle - Vector2(20.0, 0.0), "field_enemy_burst", Vector2i(150, 70), 2)


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
