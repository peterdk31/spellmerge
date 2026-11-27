extends "res://tests/support/screenshot.gd"
## A field catches every shot inside its circle, not only what crosses its edge (the owner,
## 2026-11-26; docs/milestones/field.md, "Caught"), staged in an empty room (a laid floor, no run):
## - `field_inside_strip`: a wizard standing in its own field casts a split bolt; the frames after
##   the cast, left to right (1, 4, 10 and 30 steps): the bolts caught where they are and drawn in
##   to its middle step by step (2x).
## - `field_inside_burst`: the field's end, the bolts leaving the way they were cast (2x).

const ActorSeats := preload("res://tests/support/actor_seats.gd")
const STAFF := preload("res://content/wizard/staffs/dev/dev.tres")
const WIZARD: Texture2D = preload("res://content/wizard/base/wizard_idle@2x.svg")
## Mana enough for any cast.
const MANA: float = 1000.0
const FIELD_STAFF: int = 0
const BOLT_STAFF: int = 1
## The frames after the bolts' cast the strip shows.
const STRIP: Array[int] = [1, 4, 10, 30]
const HALF := Vector2i(50, 36)

var _spells: Node = null
var _shots: Node = null


func take() -> void:
	if not need(["Feel", "Events", "Projectiles", "Spells"]):
		return
	settle_frames = 40
	root.get_node("Feel").set("drive_engine", false)
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	var wizard: int = ActorSeats.seat_wizards(actors, 1)[0]
	_spells = root.get_node("Spells")
	_shots = root.get_node("Projectiles")
	_shots.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	lay_floor()
	await settle()
	_install(wizard, FIELD_STAFF, [&"fire", &"field"])
	_install(wizard, BOLT_STAFF, [&"plus_two", &"plus_two", &"bolt"])
	var from := Vector2(120.0, 180.0)
	var middle: Vector2 = from + Vector2(72.0, 0.0)
	_cast(wizard, FIELD_STAFF, from, Vector2.RIGHT)
	await _frames(20)
	# The wizard steps into the field and casts from inside it.
	var hand: Vector2 = middle + Vector2(-22.0, 6.0)
	_stand(hand)
	_shots.call("set_anchor", wizard, hand)
	_cast(wizard, BOLT_STAFF, hand, Vector2.RIGHT)
	var crops: Array[Image] = []
	var done: int = 0
	for frame: int in STRIP:
		await _frames(frame - done)
		done = frame
		crops.append(crop_round(await grab(), on_screen(middle), HALF))
	var fields: CarrierField = CarrierField.of(_spells as SpellRuntime)
	if fields == null or fields.held_count() < 3:
		fail("the field did not catch the bolts cast inside it (%d)" % (fields.held_count() if fields != null else -1))
		return
	var strip := Image.create(crops[0].get_width() * crops.size(), crops[0].get_height(), false, crops[0].get_format())
	for n in crops.size():
		strip.blit_rect(crops[n], Rect2i(Vector2i.ZERO, crops[n].get_size()), Vector2i(crops[0].get_width() * n, 0))
	strip.resize(strip.get_width() * 2, strip.get_height() * 2, Image.INTERPOLATE_NEAREST)
	save(strip, "field_inside_strip")
	# Its end: the burst, the way they were cast, burning.
	await _frames(180 - 20 - done + 8)
	await snap(middle + Vector2(70.0, 0.0), "field_inside_burst", Vector2i(150, 70), 2)


## The wizard's look (its first idle frame), its 32-unit cell centred on the world point `hand`,
## over the field.
func _stand(hand: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = WIZARD
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * ArtDetail.draw_scale(WIZARD)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2.ZERO, ArtDetail.to_art(WIZARD, Vector2(32.0, 32.0)))
	sprite.position = hand
	sprite.z_index = 5
	root.add_child(sprite)


func _install(actor: int, slot: int, cards: Array[StringName]) -> void:
	_spells.call("install_staff", actor, slot, _spells.call("compile_staff", cards, STAFF))


func _cast(actor: int, slot: int, at: Vector2, way: Vector2) -> void:
	var spent: float = float(_spells.call("cast_staff", actor, slot, at, way.normalized(), MANA))
	if spent < 0.0:
		fail("actor %d's cast was refused" % actor)


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame
