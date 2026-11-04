extends Node
## The spectacle: everything Feel draws that is drawn only (docs/milestones/spell-spectacle.md and
## spell-spectacle-2.md, S1): the motes (`mote.gd`), the floor marks (`marks.gd`), spell light
## (`spell_light.gd`) and the ramp table the motes and marks share (`ramp_table.gd`). A child of
## Feel, made once; it owns their settings ("Particles", "Particle amount", "Floor marks", "Spell
## light", each through its event) and the room they are in (`room_entered`: the walls' colours and
## the mark layer's fit), and plays a cue's `motes` and `mark` parts (`cue_parts`, which Feel adds
## to its table of part players).
##
## Feel says when: its hit, end, wall and reaction handlers call `shed_hit`, `shed_end`,
## `shed_on_wall` and `reaction_motes` with what it already worked out (the caster's ramp, the
## preset's shares, the shot's tag), in the order it draws them, and `step` once a frame. The
## spectacle says what: which kinds (a spell's, from its cards: `card_kinds.gd`; S2), in which
## colours, where they settle. Nothing here changes a fight.
##
## A new drawn-only system goes here the same way: made in `_ready`, its setting through its own
## event, its cue parts in `cue_parts`.

const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const MarksScript := preload("res://gameplay/feel/marks.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const CueContextScript := preload("res://gameplay/feel/cue_context.gd")
const CardKindsScript := preload("res://gameplay/feel/card_kinds.gd")

## Motes draw under the floor marks, the beams and every flash and telegraph (Feel's FORM_Z 18
## less 2; docs/milestones/spell-spectacle.md, "Budget and degradation": never over a telegraph).
const MOTE_Z: int = 16
## The floor marks lie on the room's floor (RoomBase.FLOOR_Z) and under every body (0).
const MARK_Z: int = RoomBase.FLOOR_Z + 1
## Spell light is applied just under the motes: above the room and every body (a body layer is
## at most a few), under every spell, flash and telegraph (`spell_light.gd`; P3a).
const LIGHT_Z: int = MOTE_Z - 1
## The folders of the mote kinds, the mark kinds and the rooms in the registry, and a mark part's
## radius with no size to go by.
const MOTE_FOLDER: StringName = &"motes"
const MARK_FOLDER: StringName = &"marks"
const ROOM_FOLDER: StringName = &"rooms"
const MARK_RADIUS: float = 8.0

## What a shot's spell sheds, from its cards (`card_kinds.gd`; spell-spectacle-2.md, S2).
var cards: CardKindsScript = CardKindsScript.new()
## The services: Feel hands down its own (and again whenever it is given new ones).
var events: EventsScript = null
var registry: RegistryScript = null:
	set(value):
		registry = value
		cards.registry = value
		cards.clear()
## The spell runtime, which a shot's tag gives its spell from (`profile`; null for none: every
## shot's motes by its look). Feel hands it down with the projectile manager (`attach`).
var spells: Object = null:
	set(value):
		spells = value
		cards.spells = value
		cards.clear()
## The projectile manager: the trails' births, the walls the marks keep off, the batches the light
## mirrors (null in some tests: then no light and no trail motes).
var projectiles: ProjectileManagerScript = null
## Feel's switch for the stress benchmark (`Feel.particles_enabled`): off, no motes are thrown.
var particles_enabled: bool = true

## The motes, and how many they hold (`MoteCap.default_cap()` until the setting changes it). They
## always exist (S3: every particle is a mote; the smallest "Particles" stop is a Minimal ring).
## Read only.
var pool: MotesScript = null
var mote_cap: int = MoteCap.default_cap()
## The "Particle amount" setting (`MoteDensity`): every burst's count is times this.
var mote_density: float = MoteDensity.DEFAULT
## The floor marks (null with the "Floor marks" setting off), and the setting. Read only.
var marks: MarksScript = null
var floor_marks: bool = FloorMarks.default_on()
## Spell light (null with the setting off, or with no projectile manager), and the setting.
var light: SpellLightScript = null
var spell_light: bool = SpellLightSetting.default_on()
## The room's light where nothing lights it (`RoomBase.ambient`, from `room_entered`; P3b), kept
## for a light made later. Read only.
var ambient: float = 1.0

## The ramp table the motes and the floor marks share: a surface's colours and a body's art, one
## row each, so a mote and the mark it leaves read the same colours.
var _ramp_table: RampTableScript = RampTableScript.new()
## The room's surface colours (`RoomBase.surface_colors`, from `room_entered`; empty for none),
## and their source in the ramp table (-1 for none).
var _surface_colors: PackedColorArray = PackedColorArray()
var _surface_source: int = -1
## The mote kinds the room's walls shed (`RoomBase.surface_kinds`, empty: every surface kind), and
## their indices in the pool (`_take_surface_kinds`).
var _surface_ids: Array[StringName] = []
var _surface_kinds: PackedInt32Array = PackedInt32Array()
## The colours of each body art read so far (texture -> colours), and the pixels of each frame of
## one ([texture, frame rect] -> PackedVector2Array; `break_body`).
var _art_colors: Dictionary = {}
var _art_pixels: Dictionary = {}
## The art and the place of the last body broken (`broken_from`, `broken_at`; for tests).
var _broken_from: Texture2D = null
var _broken_at: Vector2 = Vector2.INF
## The room the marks were last fitted to (`room_entered`), to fit a layer made later.
var _mark_room: StringName = &""
## Feel's clock at the last step.
var _clock: float = 0.0


func _ready() -> void:
	ShaderWarmupScript.want(MotesScript.SHADER, ShaderWarmupScript.BATCH)
	ShaderWarmupScript.want(SpellLightScript.LIGHT_SHADER, ShaderWarmupScript.BATCH)
	ShaderWarmupScript.want(SpellLightScript.APPLY_SHADER, ShaderWarmupScript.RECT)
	ShaderWarmupScript.want(SpellLightScript.BEAM_SHADER, ShaderWarmupScript.MESH)
	_make_motes(mote_cap)
	ShaderWarmupScript.want(MarksScript.SHADER, ShaderWarmupScript.BATCH)
	set_floor_marks(floor_marks)
	if events == null:
		return
	events.mote_cap_changed.connect(set_mote_cap)
	events.mote_density_changed.connect(set_mote_density)
	events.spell_light_changed.connect(set_spell_light)
	events.room_entered.connect(_on_room_entered)
	events.room_entered.connect(_fit_marks)
	events.floor_marks_changed.connect(set_floor_marks)


## The projectile manager and the spell runtime are known (Feel finds them after its children are
## made): spell light can be made now.
func attach(manager: ProjectileManagerScript, runtime: Object = null) -> void:
	projectiles = manager
	spells = runtime
	_make_light(spell_light)


## Once a frame, at Feel's clock `now`: the trails' particles thrown, then the motes and the marks
## stepped.
func step(now: float) -> void:
	_clock = now
	cards.new_frame()
	_trail_motes()
	if pool != null:
		pool.step(now)
	if marks != null:
		marks.step(now)


## The cue parts the spectacle plays (`CueBase.PART_TYPES`), for Feel's table: part type -> a
## Callable taking the part and the cue's `CueContext`.
func cue_parts() -> Dictionary:
	return {&"motes": play_motes_part, &"mark": play_mark_part}


# --- Where motes come from (Feel calls these, in the order it draws) ------------------------

## Whether motes are thrown now: there is a pool and particles are on.
func motes_on() -> bool:
	return pool != null and particles_enabled


## A shot (of the tag `tag`) hit a body at `at`: its cards' motes (`look`, its `core` colour, in
## `ramp`) back along `away`, `share` of their count.
func shed_hit(at: Vector2, away: Vector2, core: Color, ramp: int, look: int, share: float, tag: int = 0) -> void:
	if pool != null and particles_enabled and not pool.shed_closed():
		pool.shed_kinds(cards.motes_of(tag, look), at, away, core, ramp, look, share)


## A shot's (of the tag `tag`) life ran out at `at`: a puff of its cards' motes on along
## `heading`, `share` of their count.
func shed_end(at: Vector2, heading: Vector2, core: Color, ramp: int, look: int, share: float, tag: int = 0) -> void:
	if pool != null and particles_enabled and not pool.shed_closed():
		pool.shed_kinds(cards.motes_of(tag, look), at, heading, core, ramp, look, share)


## A shot of an actor of `ramp` ended on a wall at `at`: its cards' motes in its own ramp (the
## projectile manager's `impact_look`, `impact_core` and `impact_tag` while the impact is sent) and
## the wall's surface motes (the room's, `surface_kinds`) in the room's colours, thrown along
## `away` (back off the wall).
func shed_on_wall(ramp: int, at: Vector2, away: Vector2) -> void:
	if pool == null or not particles_enabled:
		return
	var look: int = projectiles.impact_look if projectiles != null else 0
	var core: Color = projectiles.impact_core if projectiles != null else Color.WHITE
	var tag: int = projectiles.impact_tag if projectiles != null else 0
	if not pool.shed_closed():
		pool.shed_kinds(cards.motes_of(tag, look), at, away, core, ramp, look)
	if _surface_source >= 0:
		for k in _surface_kinds:
			pool.throw(k, at, away, _surface_source, Color.WHITE)


## The mote kinds the room's walls shed: its `surface_kinds`, or every surface kind (read it,
## never change it).
func surface_kinds() -> PackedInt32Array:
	return _surface_kinds


## A reaction's motes: a ring of the reacting shot's kinds (its `look` and `tag`, read while the
## event is sent; layer 0's for none) in the reaction's colour `tint`, from a caster of `ramp`:
## `count` in all and `reach` pixels out.
func reaction_motes(ramp: int, at: Vector2, look: int, tint: Color, count: float, reach: float, tag: int = 0) -> void:
	if pool == null or not particles_enabled:
		return
	var kinds: PackedInt32Array = cards.motes_of(tag, look)
	var source: int = MotesScript.spell_source(ramp, MotesScript.LOOK_EXACT)
	var each: int = maxi(roundi(count / float(kinds.size())), 1)
	for k in kinds:
		pool.throw_part(k, at, Vector2.RIGHT, source, tint, each, reach, 360.0, 1.0, true)


## The sparks of a flash that sprays them (a hit's spray, a puff; S3): `count` motes of the kind
## `kind` at `at` along `way` within `spread` degrees (all round as a ring with `ring`), out to
## `reach` pixels, in the colours the flash is in (the `core` of a caster of `ramp`, the cards of
## `look`, exact with its LOOK_EXACT bit). One of many a frame: it leaves the moments' rows alone.
func flash_motes(kind: StringName, at: Vector2, way: Vector2, core: Color, ramp: int, look: int, count: int, reach: float, spread: float, ring: bool) -> void:
	if pool == null or not particles_enabled or count <= 0:
		return
	pool.throw_part(pool.kind_index(kind), at, way, MotesScript.spell_source(ramp, look), core, count, reach, spread, 1.0, ring, true)


## A body breaking into motes (S3: a death, in place of the white-hot copy that fell apart pixel by
## pixel): about `share` of the pixels of the art `sprite` shows (times the area of `to_world`'s
## scale, at most `most`), each a mote of the surface kind `kind` (a body is a surface that broke)
## in its art's colours, from where that pixel was (`to_world`: the sprite's world transform, at its
## rest scale), falling to the body's feet, flung out from its middle at `speed` (px/s, slowest and
## fastest) and `up`.
func break_body(sprite: Sprite2D, to_world: Transform2D, kind: StringName, share: float, most: int, speed: Vector2, up: Vector2) -> void:
	if sprite == null or sprite.texture == null:
		return
	_broken_from = sprite.texture
	_broken_at = to_world.origin
	if pool == null or not particles_enabled or share <= 0.0:
		return
	var source: int = body_source(sprite)
	var k: int = pool.kind_index(kind)
	if source < 0 or k < 0:
		return
	var rect: Rect2i = _frame_rect(sprite)
	var key: Array = [sprite.texture, rect]
	var pixels: Variant = _art_pixels.get(key)
	if pixels == null:
		pixels = RoomBase.pixels_of_art(sprite.texture, rect)
		_art_pixels[key] = pixels
	var art: PackedVector2Array = pixels as PackedVector2Array
	if art.is_empty():
		return
	var scale: Vector2 = to_world.get_scale().abs()
	var want: int = clampi(roundi(float(art.size()) * share * scale.x * scale.y), 1, most)
	var step: float = float(art.size()) / float(want)
	var size: Vector2 = Vector2(rect.size)
	var corner: Vector2 = sprite.offset - (size * 0.5 if sprite.centered else Vector2.ZERO)
	var points := PackedVector2Array()
	points.resize(want)
	var feet: float = -INF
	for i in want:
		var p: Vector2 = art[mini(floori((float(i) + 0.5) * step), art.size() - 1)]
		if sprite.flip_h:
			p.x = size.x - 1.0 - p.x
		var world: Vector2 = to_world * (corner + p + Vector2(0.5, 0.5))
		points[i] = world
		feet = maxf(feet, world.y)
	pool.crumble(k, points, feet, to_world * (corner + size * 0.5), speed, 360.0, up, source, Color.WHITE)


## The art the last body broken was drawn with, and where its sprite was (for tests).
func broken_from() -> Texture2D:
	return _broken_from


func broken_at() -> Vector2:
	return _broken_at


## The ramp table's source for the colours of a body's art (the `sprite` it shows, read once per
## texture; `RoomBase.colours_of_art`), -1 when it has none (the room's walls' then), or with
## neither motes nor floor marks to show it.
func body_source(sprite: Sprite2D) -> int:
	if pool == null and marks == null:
		return -1
	if sprite == null or sprite.texture == null:
		return -1
	var colours: Variant = _art_colors.get(sprite.texture)
	if colours == null:
		colours = RoomBase.colours_of_art(sprite.texture, _frame_rect(sprite))
		_art_colors[sprite.texture] = colours
	return _ramp_table.source(colours as PackedColorArray)


## The part of its texture `sprite` shows: its region, or its frame of a sheet.
static func _frame_rect(sprite: Sprite2D) -> Rect2i:
	if sprite.region_enabled:
		return Rect2i(sprite.region_rect)
	var size: Vector2i = Vector2i(sprite.texture.get_size()) / Vector2i(maxi(sprite.hframes, 1), maxi(sprite.vframes, 1))
	return Rect2i(Vector2i(sprite.frame % maxi(sprite.hframes, 1), sprite.frame / maxi(sprite.hframes, 1)) * size, size)


## The shots' trail particles as motes (spell spectacle P1d): the projectile manager hands them out
## while there are motes (`spark_motes`), and they are thrown before the motes step. With
## `particles_enabled` off (the stress benchmark's "no particles") the trails stay without their
## particle slots and none are thrown: no trail particles at all, not the shader's instead.
func _trail_motes() -> void:
	if projectiles == null:
		return
	var on: bool = pool != null
	if projectiles.spark_motes != on:
		projectiles.spark_motes = on
	if on and particles_enabled and projectiles.spark_birth_count > 0:
		pool.give_off(projectiles.spark_births, projectiles.spark_birth_count)


# --- Cue parts -------------------------------------------------------------------------------

## A cue's `motes` part (`CueBase`) played with `cue`: the kinds it names thrown as it says, the
## cue's size times its `reach` out, in the cue's ramp with its tint and the cards of its look.
func play_motes_part(part: Dictionary, cue: CueContextScript) -> void:
	if pool == null or not particles_enabled:
		return
	var way: Vector2 = cue.way_of(part)
	var reach: float = cue.size * float(part["reach"]) if part.has("reach") and cue.size > 0.0 else 0.0
	var spread: float = float(part.get("spread", -1.0))
	var up: float = float(part.get("up", 1.0))
	var ring: bool = bool(part.get("ring", false))
	var named: StringName = StringName(part.get("kind", "spell"))
	var kinds: PackedInt32Array
	match named:
		&"spell":
			kinds = cards.motes_of(cue.tag, cue.look)
		&"surface":
			kinds = _surface_kinds
		_:
			var k: int = pool.kind_index(named)
			if k < 0:
				return
			kinds = PackedInt32Array([k])
	var spell: int = MotesScript.spell_source(cue.ramp, cue.look)
	var surface: int = cue.surface if cue.surface >= 0 else _surface_source
	var count: int = int(part.get("count", -1))
	# What a surface sheds (the walls', or a room's own kinds) cools through the surface's colours,
	# as does a part whose `colours` say so; one whose `colours` are the spell's, through its ramp.
	var colours: StringName = StringName(part.get("colours", ""))
	var of_surface: bool = named == &"surface" or colours == &"surface"
	var at: Vector2 = cue.at + Vector2(0.0, float(part.get("below", 0.0)))
	for k in kinds:
		var walls: bool = of_surface or (pool.kinds()[k].surface and colours != &"spell")
		var source: int = surface if walls else spell
		var each: int = -1 if count < 0 else maxi(roundi(float(count) / float(kinds.size())), 1)
		pool.throw_part(k, at, way, source, Color.WHITE if walls else cue.tint, each, reach, spread, up, ring)


## Stamp a cue's mark part (`CueBase`, "part": "mark") played with `cue`: its mark, or with
## `cards` the marks of the cards of the cue's look when they have any; the cue's size x its
## `reach` pixels round (or its `radius`), turned at random or along the cue's way, in the colours
## of a spell of its ramp with its tint and of what broke (a dying body's art, else the walls).
func play_mark_part(part: Dictionary, cue: CueContextScript) -> void:
	if marks == null:
		return
	var radius: float = float(part.get("radius", MARK_RADIUS))
	if part.has("reach") and cue.size > 0.0:
		radius = cue.size * float(part["reach"])
	var source: int = MotesScript.spell_source(cue.ramp, cue.look)
	var turn: float = cue.aim.angle() if StringName(part.get("rot", "random")) == &"aim" else marks.random_turn()
	var found: PackedInt32Array = cards.marks_of(cue.tag, cue.look) if bool(part.get("cards", false)) else PackedInt32Array()
	if found.is_empty():
		var named: StringName = StringName(part.get("mark", ""))
		if named == &"":
			# Only its cards' marks, and they have none.
			return
		found = PackedInt32Array([marks.kind_index(named)])
	var surface: int = cue.surface if cue.surface >= 0 else _surface_source
	for k in found:
		marks.stamp(k, cue.at, radius, turn, source, cue.tint, surface)


# --- Settings ----------------------------------------------------------------------------------

## The "Particles" setting: how many motes the ring holds (from `MoteCap`'s Minimal stop to its
## top one; a 0, Off before S3, is Minimal). A new size remakes the ring, ending the motes in the
## air. Returns the number taken.
func set_mote_cap(cap: int) -> int:
	var taken: int = clampi(cap, MoteCap.STOPS[0], MoteCap.STOPS[-1])
	if taken != mote_cap or pool == null:
		_make_motes(taken)
	return mote_cap


## Use `motes` as the pool from now on, in place of the one made for the setting (its cap is the
## setting's now). For the benchmarks, which hand one that times its own calls
## (tests/benchmark/timed_motes.gd); null (the stress benchmark's "no particles") leaves none.
func use_motes(motes: MotesScript) -> void:
	if pool != null:
		pool.queue_free()
		remove_child(pool)
		pool = null
	pool = motes
	mote_cap = motes.cap() if motes != null else 0
	if motes != null:
		pool.name = "Motes"
		pool.density = mote_density
		add_child(pool)
		pool.step(_clock)
		pool.settle_into(marks)
	cards.use_motes(pool)
	if pool != null:
		pool.use_cards(cards if pool.has_card_kinds() else null)
	_take_surface_kinds()
	_surface_source = _ramp_table.source(_surface_colors)


## The colour table the motes and the floor marks share (a pool handed to `use_motes` is made
## with it, so its table sources are the marks').
func ramp_table() -> RampTableScript:
	return _ramp_table


func _make_motes(cap: int) -> void:
	use_motes(MotesScript.new(cap, MOTE_Z, _mote_kinds(), _ramp_table))


## The mote kinds of the registry (content/motes), in id order.
func _mote_kinds() -> Array[MoteKind]:
	var kinds: Array[MoteKind] = []
	if registry != null:
		for found: Resource in registry.get_all(MOTE_FOLDER):
			if found is MoteKind:
				kinds.append(found as MoteKind)
	return kinds


## The "Particle amount" setting: the share of its count every burst of motes throws (snapped by
## `MoteDensity.snap`). Returns the share taken.
func set_mote_density(density: float) -> float:
	mote_density = MoteDensity.snap(density)
	if pool != null:
		pool.density = mote_density
	return mote_density


## The "Floor marks" setting: on makes the mark layer (fitted to the room it was last told of),
## off frees it and every mark with it.
func set_floor_marks(on: bool) -> void:
	floor_marks = on
	if on and marks == null:
		var kinds: Array[MarkKind] = []
		if registry != null:
			for found: Resource in registry.get_all(MARK_FOLDER):
				if found is MarkKind:
					kinds.append(found as MarkKind)
		marks = MarksScript.new(MARK_Z, kinds)
		marks.name = "Marks"
		marks.set_ramp_table(_ramp_table.texture())
		add_child(marks)
		if _mark_room != &"":
			_fit_marks(_mark_room)
	elif not on and marks != null:
		marks.queue_free()
		remove_child(marks)
		marks = null
	cards.use_marks(marks)
	if pool != null:
		pool.settle_into(marks)


## The "Spell light" setting: on makes the light buffer and its rect, off frees them (no nodes).
## Returns the setting.
func set_spell_light(on: bool) -> bool:
	if on != spell_light or (light == null) == on:
		_make_light(on)
	return spell_light


func _make_light(on: bool) -> void:
	spell_light = on
	if light != null:
		light.release()
		remove_child(light)
		light.queue_free()
		light = null
	if on and projectiles != null:
		light = SpellLightScript.new(projectiles, LIGHT_Z)
		light.name = "SpellLight"
		light.set_ambient(ambient)
		add_child(light)


## Feel's effect rows, just uploaded (the flares', the explosions' and the arcs'; `slots` rows
## each), lit by the spell light while it is on (P3b; `SpellLight.light_effects`).
func light_effects(flare_rows: PackedFloat32Array, flares: int, blast_rows: PackedFloat32Array, blasts: int, arc_rows: PackedFloat32Array, arcs: int, slots: int) -> void:
	if light != null:
		light.light_effects(flare_rows, flares, blast_rows, blasts, arc_rows, arcs, slots)


## Before Feel draws its live beams: none lit until `light_beam` lights one (P3b).
func light_beams_begin() -> void:
	if light != null:
		light.light_beams_begin()


## Live beam `i`'s light along the path Feel just gave its shader (`SpellLight.light_beam`).
func light_beam(i: int, path: PackedVector3Array, points: int, player: int, look: int, core: Color, fade: float) -> void:
	if light != null:
		light.light_beam(i, path, points, player, look, core, fade)


# --- The room ------------------------------------------------------------------------------------

## A new room: its colours for its walls' motes (`RoomBase.surface_colors`) and its ambient light
## (`RoomBase.ambient`, P3b).
func _on_room_entered(room_id: StringName) -> void:
	use_room(registry.get_resource(ROOM_FOLDER, room_id) as RoomBase if registry != null else null)


## The room `room` (null for none) is the one played in now: its walls' colours and motes, and its
## ambient light (`room_entered` calls this; tests too).
func use_room(room: RoomBase) -> void:
	_surface_colors = room.surface_colors() if room != null else PackedColorArray()
	_surface_ids = room.surface_kinds if room != null else ([] as Array[StringName])
	_take_surface_kinds()
	ambient = room.ambient if room != null else 1.0
	if light != null:
		light.set_ambient(ambient)
	_surface_source = _ramp_table.source(_surface_colors)


## The pool's indices of the room's surface kinds (`RoomBase.surface_kinds`; a kind the pool does not
## have is left out), or every surface kind of the pool when the room names none.
func _take_surface_kinds() -> void:
	_surface_kinds = PackedInt32Array()
	if pool == null:
		return
	if _surface_ids.is_empty():
		_surface_kinds = pool.surface_kinds()
		return
	for id in _surface_ids:
		var k: int = pool.kind_index(id)
		if k >= 0 and not _surface_kinds.has(k):
			_surface_kinds.append(k)


## A new room: the mark layer wiped and fitted to its bounds and walls (the projectile manager's,
## set before `room_entered`) in its floor's colours.
func _fit_marks(room_id: StringName) -> void:
	_mark_room = room_id
	if marks == null:
		return
	var room: RoomBase = registry.get_resource(ROOM_FOLDER, room_id) as RoomBase if registry != null else null
	var bounds: Rect2 = projectiles.bounds() if projectiles != null else Rect2()
	marks.enter(bounds, projectiles.wall_image() if projectiles != null else null, ProjectileManagerScript.WALL_CELL)
	marks.set_floor_colors(room.floor_colors() if room != null else PackedColorArray())
