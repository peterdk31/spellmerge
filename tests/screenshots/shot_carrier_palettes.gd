extends "res://tests/support/screenshot.gd"
## The carrier looks of 2026-11-09 with one, two and four infusions (the owner: "all of these should
## work with the new code that adds the infusion palette in cool ways"), each shot spawned with its
## card's body, the first infusion's tint and every infusion's look layer: one row per palette (fire;
## fire and frost; frost, void, fire and lightning), one column per look: a rune arming, a rune
## armed, a pool standing (its rising motes real motes, `still_motes.gd`), a wall across (its stream
## real motes too) and a swap's charm in flight (a spark an infusion). `carrier_palettes` is the
## whole sheet at 2x; `carrier_palettes_rune`, `_pool`, `_wall` at 3x and `_swap` at 4x each column.
## The portal's are `shot_portal_rifts.gd` (a portal needs its carrier, so it is cast).

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const RUNE := preload("res://content/spells/carriers/rune/rune.tres")
const POOL := preload("res://content/spells/carriers/pool/pool.tres")
const WALL := preload("res://content/spells/carriers/wall/wall.tres")
const SWAP := preload("res://content/spells/carriers/swap/swap.tres")
const FIRE := preload("res://content/spells/elements/fire/fire.tres")
const FROST := preload("res://content/spells/elements/frost/frost.tres")
const VOID := preload("res://content/spells/elements/void/void.tres")
const LIGHTNING := preload("res://content/spells/elements/lightning/lightning.tres")
## Each row's infusions, in slot order.
const PALETTES: Array = [[FIRE], [FIRE, FROST], [FROST, VOID, FIRE, LIGHTNING]]
const ROWS: Array[float] = [64.0, 176.0, 288.0]
## The columns' middles: rune arming, rune armed, pool, wall, swap (where its flight ends).
const COLUMNS: Array[float] = [60.0, 170.0, 290.0, 410.0, 560.0]
## Frames the swap flies before the picture.
const FLIGHT: int = 8

var _shots: Node = null
var _wizard: int = 0


func take() -> void:
	if not need(["Feel", "Events", "Projectiles", "Spells"]):
		return
	settle_frames = 40
	root.get_node("Feel").set("drive_engine", false)
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	_wizard = ActorSeats.seat_wizards(actors, 1)[0]
	_shots = root.get_node("Projectiles")
	_shots.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	lay_floor()
	await settle()
	for r in PALETTES.size():
		_spawn(RUNE, Vector2(COLUMNS[1], ROWS[r]), PALETTES[r])
		_spawn(POOL, Vector2(COLUMNS[2], ROWS[r]), PALETTES[r])
		var wall: int = _spawn(WALL, Vector2(COLUMNS[3], ROWS[r]), PALETTES[r])
		_shots.call("set_solid", wall, Vector2.RIGHT, int(WALL.get("shots")), float(WALL.get("spread")))
	await settle(70)
	for r in PALETTES.size():
		_spawn(RUNE, Vector2(COLUMNS[0], ROWS[r]), PALETTES[r])
	await settle(40 - FLIGHT)
	for r in PALETTES.size():
		var from := Vector2(COLUMNS[4] - float(SWAP.get("speed")) * float(FLIGHT) / 60.0, ROWS[r])
		_spawn(SWAP, from, PALETTES[r], Vector2(float(SWAP.get("speed")), 0.0))
	await settle(FLIGHT)
	var image: Image = await grab()
	var sheet: Image = image.duplicate() as Image
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	save(sheet, "carrier_palettes")
	save_crop(image, on_screen(Vector2((COLUMNS[0] + COLUMNS[1]) * 0.5, 176.0)), "carrier_palettes_rune", Vector2i(80, 150), 3)
	save_crop(image, on_screen(Vector2(COLUMNS[2], 166.0)), "carrier_palettes_pool", Vector2i(40, 140), 3)
	save_crop(image, on_screen(Vector2(COLUMNS[3], 166.0)), "carrier_palettes_wall", Vector2i(40, 140), 3)
	save_crop(image, on_screen(Vector2(COLUMNS[4] - 6.0, 176.0)), "carrier_palettes_swap", Vector2i(24, 130), 4)


## A still or flying shot of `form`'s body at `at` (moving at `velocity`), in the palette `infusions`
## (the first's tint, every one's look layer).
func _spawn(form: Resource, at: Vector2, infusions: Array, velocity: Vector2 = Vector2.ZERO) -> int:
	var motion: int = ManagerScript.MOTION_STILL if velocity == Vector2.ZERO else ManagerScript.MOTION_STRAIGHT
	var slot: int = _shots.call("spawn", _wizard, at, velocity, 600.0, float(form.get("radius")), ManagerScript.LAYER_ENEMY, 0, 0, motion)
	var mesh: int = ManagerScript.MESH_QUAD if velocity == Vector2.ZERO else ManagerScript.MESH_HEAD
	_shots.call("set_form", slot, StringName(form.get("id")), _shots.call("register_body", form.get("look_shader"), mesh))
	var layers := PackedInt32Array()
	for element: Resource in infusions:
		layers.append(int(element.get("look_layer")))
	_shots.call("set_core", slot, infusions[0].get("tint") as Color)
	_shots.call("set_look", slot, ManagerScript.pack_look(layers))
	return slot
