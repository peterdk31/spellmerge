extends "res://tests/support/screenshot.gd"
## The shots' cores at the art's detail (ART2, docs/STYLE.md, "The picture and the art's detail"): a
## contact sheet of shot heads held still, one row an infusion (plain, fire, frost, storm, void,
## lightning, water, mend), one column a hit radius (a speck, then zoom 1, 2 and 3) for the plain head
## (`shot_head.gdshader`, a round bead and a `+`) and then the bolt's own (`carriers/bolt`, a cut gem
## and an `x`), player 1's. The world is drawn ZOOM times bigger than the cameras' zoom 1 (every art
## pixel a 2 x 2 block of the picture at 4, where the camera shows it as one): `spell_art_heads`.
## Then the motes a spell, a hit or a cue throws (content/motes, each at its `shape_2x`), a burst of
## each kind in a grid (rows of ten, in the order of MOTE_KINDS), seen MOTE_TIMES after they were
## thrown: `spell_art_motes_<n>`, at the same scale, taken first so no shot's own motes are among them.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ELEMENTS: Array[Resource] = [
	preload("res://content/spells/elements/fire/fire.tres"),
	preload("res://content/spells/elements/frost/frost.tres"),
	preload("res://content/spells/elements/storm/storm.tres"),
	preload("res://content/spells/elements/void/void.tres"),
	preload("res://content/spells/elements/lightning/lightning.tres"),
	preload("res://content/spells/elements/water/water.tres"),
	preload("res://content/spells/elements/mend/mend.tres"),
]
const BOLT := preload("res://content/spells/carriers/bolt/bolt.tres")
const MotesScript := preload("res://gameplay/feel/mote.gd")
## The kinds shown, each with the tint of the element it is thrown for (white: a plain shot's).
const MOTE_KINDS: Array[Array] = [
	[&"spark", Color.WHITE], [&"ember", Color(1.0, 0.45, 0.2)], [&"fleck", Color(0.6, 0.9, 1.0)], [&"glimmer", Color(1.0, 0.95, 0.6)],
	[&"murk", Color(0.65, 0.2, 0.6)], [&"droplet", Color(0.2, 0.6, 0.55)], [&"wisp", Color(0.85, 0.85, 0.9)], [&"tail", Color.WHITE],
	[&"tail_long", Color.WHITE], [&"tail_streak", Color.WHITE], [&"streak", Color.WHITE], [&"glob", Color(0.9, 1.0, 0.5)],
	[&"drain", Color(0.2, 0.25, 0.7)], [&"bit", Color(0.8, 0.8, 0.85)], [&"ash", Color(0.8, 0.8, 0.85)], [&"dust", Color(0.8, 0.8, 0.85)],
	[&"smoke", Color(0.8, 0.8, 0.85)], [&"ward", Color(0.6, 0.9, 1.0)], [&"rising", Color(1.0, 0.45, 0.2)], [&"seam", Color(1.0, 0.45, 0.2)],
	[&"grit", Color(0.8, 0.8, 0.85)], [&"drip", Color(0.65, 0.2, 0.6)], [&"chip", Color(0.8, 0.8, 0.85)],
]
const MOTE_TIMES: Array[float] = [0.04, 0.12, 0.3]
const MOTE_BORN: float = 10.0
## The hit radii shown: a speck (below SPECK_RADIUS), then look zooms 1, 2 and 3.
const RADII: Array[float] = [1.5, 5.0, 8.0, 12.0]
const ORIGIN := Vector2(36.0, 22.0)
const COLUMN: float = 24.0
const ROW: float = 20.0
## The world's scale in the picture: 2 is the cameras' zoom 1 (an art pixel a picture pixel).
const ZOOM: float = 4.0


func take() -> void:
	if not need(["Projectiles"]):
		return
	var shots: Node = root.get_node("Projectiles")
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	var wizard: int = ActorSeats.seat_wizards(actors, 1)[0]
	root.canvas_transform = Transform2D(0.0, Vector2(ZOOM, ZOOM), 0.0, Vector2.ZERO)
	var floor_sprite := Sprite2D.new()
	floor_sprite.texture = FLOOR
	floor_sprite.centered = false
	floor_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor_sprite.region_enabled = true
	floor_sprite.region_rect = Rect2(Vector2.ZERO, SCREEN)
	floor_sprite.z_index = -10
	root.add_child(floor_sprite)
	await _motes()
	shots.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	shots.call("set_cap", 300)
	var bolt_body: int = shots.call("register_body", BOLT.get("look_shader"), ManagerScript.MESH_HEAD) as int
	var rows: int = ELEMENTS.size() + 1
	for e in rows:
		var tint: Color = Color.WHITE if e == 0 else ELEMENTS[e - 1].get("tint") as Color
		var look: PackedInt32Array = PackedInt32Array() if e == 0 else PackedInt32Array([int(ELEMENTS[e - 1].get("look_layer"))])
		for c in RADII.size() * 2:
			var at: Vector2 = ORIGIN + Vector2(c * COLUMN + (12.0 if c >= RADII.size() else 0.0), e * ROW)
			# Held still, flying right (its way read from its velocity), lasting the shot.
			var slot: int = shots.call("spawn", wizard, at, Vector2(0.001, 0.0), 600.0, RADII[c % RADII.size()]) as int
			if c >= RADII.size():
				shots.call("set_carrier_card", slot, &"bolt", bolt_body)
			shots.call("set_core", slot, tint)
			shots.call("set_look", slot, ManagerScript.pack_look(look))
	await settle(10)
	var image: Image = await grab()
	if int(shots.get("drawn")) < rows * RADII.size() * 2:
		fail("only %d shots were drawn" % int(shots.get("drawn")))
		return
	save(image, "spell_art_heads")


## Each of MOTE_KINDS thrown once, up, at MOTE_TIMES.
func _motes() -> void:
	var registry: Node = root.get_node_or_null("Registry")
	if registry == null:
		fail("there is no Registry for the mote kinds")
		return
	var kinds: Array[MoteKind] = []
	for found: Resource in registry.call("get_all", &"motes"):
		kinds.append(found as MoteKind)
	var motes: MotesScript = MotesScript.new(4096, 0, kinds)
	root.add_child(motes)
	motes.step(MOTE_BORN)
	for i in MOTE_KINDS.size():
		var k: int = motes.kind_index(MOTE_KINDS[i][0] as StringName)
		if k < 0:
			fail("there is no mote kind %s" % MOTE_KINDS[i][0])
			return
		var at := Vector2(24.0 + float(i % 10) * 30.0, 50.0 + float(i / 10) * 60.0)
		motes.throw(k, at, Vector2.RIGHT, 0, MOTE_KINDS[i][1] as Color)
	for n in MOTE_TIMES.size():
		motes.step(MOTE_BORN + MOTE_TIMES[n])
		await settle(3)
		save(await grab(), "spell_art_motes_%d" % n)
	motes.queue_free()
	await settle(2)
