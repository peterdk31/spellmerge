extends "res://tests/support/screenshot.gd"
## The portal's mote rift (the owner's pick, 2026-11-09; gameplay/feel/portal_look.gd: the lens the
## card's shader, the lips real motes) with one, two and four infusions, staged in an empty room (a
## laid floor, no run: no waves, no telegraphs, no banner; docs/milestones/carrier-looks-fixes.md,
## phase 4), as `shot_carrier_palettes` stages the still carriers: three seated wizards' staffs of
## fire; fire and frost; frost, void, fire and lightning (the dev staff, for five cards), each casting
## a portal to the right from a row of its own. `portal_rifts` open (a lip an infusion, the motes in
## turn) at 2x, `portal_rifts_close` the four infusions' mouth at 5x, and `portal_rifts_opening` a
## tenth of a second after they open (tall, not yet wide) at 2x.

const ActorSeats := preload("res://tests/support/actor_seats.gd")
const STAFF := preload("res://content/wizard/staffs/dev/dev.tres")
const INFUSIONS: Array = [[&"fire"], [&"fire", &"frost"], [&"frost", &"void", &"fire", &"lightning"]]
## Where each row's portal is cast from, and its staff's slot.
const FROM: Array[Vector2] = [Vector2(200.0, 96.0), Vector2(200.0, 180.0), Vector2(200.0, 264.0)]
const STAFF_SLOT: int = 0
## Mana enough for any cast.
const MANA: float = 1000.0

var _spells: Node = null
var _shots: Node = null
var _wizards: PackedInt32Array = PackedInt32Array()


func take() -> void:
	if not need(["Feel", "Events", "Projectiles", "Spells"]):
		return
	settle_frames = 40
	root.get_node("Feel").set("drive_engine", false)
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	_wizards = ActorSeats.seat_wizards(actors, 3)
	_spells = root.get_node("Spells")
	_shots = root.get_node("Projectiles")
	_shots.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	lay_floor()
	await settle()
	for p in 3:
		var cards: Array[StringName] = []
		cards.assign(INFUSIONS[p])
		cards.append(&"portal")
		_spells.call("install_staff", _wizards[p], STAFF_SLOT, _spells.call("compile_staff", cards, STAFF))
	await _cast(50)
	var image: Image = await grab()
	save_crop(image, on_screen(Vector2(290.0, 180.0)), "portal_rifts", Vector2i(130, 110), 2)
	save_crop(image, on_screen(FROM[2] + Vector2(22.0, 0.0)), "portal_rifts_close", Vector2i(30, 24), 5)
	await _cast(6)
	await snap(Vector2(290.0, 180.0), "portal_rifts_opening", Vector2i(130, 110), 2)


## Clear the shots and the portals, cast each row's portal to the right and wait `frames` frames.
func _cast(frames: int) -> void:
	_shots.call("clear")
	var portals: CarrierPortal = CarrierPortal.of(_spells as SpellRuntime)
	if portals != null:
		portals.clear()
	await settle(2)
	for p in 3:
		var spent: float = float(_spells.call("cast_staff", _wizards[p], STAFF_SLOT, FROM[p], Vector2.RIGHT, MANA))
		if spent < 0.0:
			fail("wizard %d's portal was refused" % p)
	for frame in frames:
		await physics_frame
