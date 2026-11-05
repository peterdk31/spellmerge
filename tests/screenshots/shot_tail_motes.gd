extends "res://tests/support/screenshot.gd"
## Tails as motes (docs/milestones/spell-spectacle-2.md, S5 step 4; the owner, 2026-11-05: "if
## only the motes could look more like a tail"; the pick, 2026-11-05: all three, each shot its own):
## the shots' tails as motes, drawn by the real projectile manager and Feel's motes, every shot's
## tail in one of the tail kinds (A `tail`, B `tail_streak`, C `tail_long`, content/motes) picked
## by its sequence (`ProjectileManager.tail_code`). Two rows of the same streams, the second a
## stream later, so other shots pick other kinds.
## Each row is a held stream of atoms (the atom's speed and life, one shot every ATOM_EVERY
## frames, player 1's plain shot) above a slower stream of fire bolts, seen at FRAMES (a
## filmstrip: the stream held, then let go and cooling). `tail_motes` is the strip at 1x;
## `tail_motes_4x` the same moments near the streams' start, four times bigger.

const ATOM := preload("res://content/spells/forms/atom/atom.tres")
const BOLT := preload("res://content/spells/forms/bolt/bolt.tres")
const FIRE := preload("res://content/spells/elements/fire/fire.tres")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
## The rows' names.
const ROWS: Array[Array] = [["each shot A, B or C"], ["the next streams"]]
## Frames the streams are held for, an atom every ATOM_EVERY of them and a bolt every BOLT_EVERY.
const HELD: int = 30
const ATOM_EVERY: int = 1
const BOLT_EVERY: int = 10
## The frames each row is seen at (from its first shot): held, held, just let go, cooling.
const FRAMES: Array[int] = [10, 22, 32, 40]
## Where the streams start, a row's band (its top and height) and the strip's crop of it.
const START_X: float = 70.0
const BAND_TOP: float = 14.0
const BAND: float = 68.0
const STRIP: Vector2i = Vector2i(480, 60)
## The 4x crop: from this far along the atoms' path, this big.
const ZOOM_AT: float = 20.0
const ZOOM: Vector2i = Vector2i(120, 44)

var _shots: Node = null
var _events: Node = null


func take() -> void:
	if not need(["Projectiles", "Events", "Feel"]):
		return
	_shots = root.get_node("Projectiles")
	_events = root.get_node("Events")
	lay_floor()
	_shots.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	ActorSeats.seat_wizards(actors)
	var strips := Image.create_empty(STRIP.x * FRAMES.size(), STRIP.y * ROWS.size(), false, Image.FORMAT_RGBA8)
	var zooms := Image.create_empty(ZOOM.x * 4 * FRAMES.size(), ZOOM.y * 4 * ROWS.size(), false, Image.FORMAT_RGBA8)
	for r in ROWS.size():
		var row: Array = ROWS[r]
		var top: float = BAND_TOP + r * BAND
		label(row[0] as String, Vector2(4.0, top + 4.0), 8)
		var seen: int = 0
		for f in FRAMES[-1] + 1:
			if f < HELD and f % ATOM_EVERY == 0:
				_shoot(ATOM, Vector2(START_X, top + 16.0), Color.WHITE, 0)
			if f < HELD and f % BOLT_EVERY == 0:
				_shoot(BOLT, Vector2(START_X, top + 42.0), FIRE.get("tint") as Color, ManagerScript.pack_look(PackedInt32Array([int(FIRE.get("look_layer"))])))
			if seen < FRAMES.size() and f == FRAMES[seen]:
				var image: Image = await grab()
				var scale: Vector2 = Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
				var strip: Image = image.get_region(Rect2i(Vector2i(Vector2(0.0, top) * scale), Vector2i(Vector2(STRIP) * scale)))
				strip.resize(STRIP.x, STRIP.y, Image.INTERPOLATE_NEAREST)
				strips.blit_rect(strip, Rect2i(Vector2i.ZERO, STRIP), Vector2i(seen * STRIP.x, r * STRIP.y))
				var zoom: Image = image.get_region(Rect2i(Vector2i(Vector2(START_X + ZOOM_AT, top + 4.0) * scale), Vector2i(Vector2(ZOOM) * scale)))
				zoom.resize(ZOOM.x * 4, ZOOM.y * 4, Image.INTERPOLATE_NEAREST)
				zooms.blit_rect(zoom, Rect2i(Vector2i.ZERO, ZOOM * 4), Vector2i(seen * ZOOM.x * 4, r * ZOOM.y * 4))
				seen += 1
			await physics_frame
		# Let this row's shots end and its motes cool before the next row.
		for f in 45:
			await physics_frame
	if int(_shots.get("tail_births")) < 0:
		fail("the manager has no tail births")
		return
	save(strips, "tail_motes")
	save(zooms, "tail_motes_4x")


func _shoot(form: Resource, at: Vector2, tint: Color, look: int) -> void:
	var speed: float = float(form.get("speed"))
	var slot: int = _shots.call("spawn", 0, at, Vector2(speed, 0.0), float(form.get("lifetime")), float(form.get("radius"))) as int
	if slot < 0:
		return
	_shots.call("set_core", slot, tint)
	_shots.call("set_look", slot, look)
