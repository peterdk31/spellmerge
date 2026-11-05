extends Node
## The spectacle: everything Feel draws that is drawn only (docs/milestones/spell-spectacle.md and
## spell-spectacle-2.md, S1): the motes (`mote.gd`), the floor marks (`marks.gd`), spell light
## (`spell_light.gd`) and the ramp table the motes and marks share (`ramp_table.gd`). A child of
## Feel, made once; it owns their settings ("Particles", "Particle amount", "Floor marks", "Spell
## light", each through its event) and the room they are in (`room_entered`: the walls' colours and
## the mark layer's fit), and plays a cue's `motes` and `mark` parts (`cue_parts`, which Feel adds
## to its table of part players).
##
## Feel says when: its hit and wall handlers call `shed_hit` and `shed_on_wall` with what it
## already worked out (the caster's ramp, the preset's shares, the shot's tag), in the order it
## draws them, a shot's end plays its cue (`expire`, a `motes` part with a `share`; S6), and `step`
## runs once a frame. The
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
const BirthsScript := preload("res://gameplay/feel/births.gd")

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
## A `light` part's reach (px) when it names none and the cue has no size, how bright it is and
## how long it lasts when it does not say (S6, item 4).
const LIGHT_RADIUS: float = 40.0
const LIGHT_STRENGTH: float = 1.0
const LIGHT_SECONDS: float = 0.3
## The look bit of an exact colour (Feel's EXACT: kind 24 of the shot look).
const EXACT: int = 1 << 23
## A status's motes (`status_motes`): how far they drift (pixels), their kind's speed up times
## this, and how flat the oval round the character they leave from is.
const STATUS_DRIFT: float = 6.0
const STATUS_UP: float = 0.3
const STATUS_FLAT: float = 0.8

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
## The motes Feel's own drawings give off this frame (a swing's sparks, a beam's splash, their
## cards' particles; S6 item 10): births in the trails' format, given off after the trails' in
## `step`. Feel adds to it only while `motes_on`.
var births: BirthsScript = BirthsScript.new()

## The motes, and how many they hold (`MoteCap.default_cap()` until the setting changes it). They
## always exist (S3: every particle is a mote; the smallest "Particles" stop is a Minimal ring).
## Read only.
var pool: MotesScript = null
var mote_cap: int = MoteCap.default_cap()
## The "Particle amount" setting (`MoteDensity`): every burst's count is times this.
var mote_density: float = MoteDensity.DEFAULT
## The "Tailless motes" dev setting (`TaillessMotes`): the motes' rows a frame follow its pool.
var tailless_motes: int = TaillessMotes.DEFAULT
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
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


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
	events.tailless_motes_changed.connect(set_tailless_motes)
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
	_drawn_motes()
	if pool != null:
		pool.step(now)
	if marks != null:
		marks.step(now)
	if light != null:
		light.step_cues(now)


## The cue parts the spectacle plays (`CueBase.PART_TYPES`), for Feel's table: part type -> a
## Callable taking the part and the cue's `CueContext`.
func cue_parts() -> Dictionary:
	return {&"motes": [play_motes_part, prepare_motes_part], &"mark": [play_mark_part], &"light": [play_light_part]}


# --- Where motes come from (Feel calls these, in the order it draws) ------------------------

## Whether motes are thrown now: there is a pool and particles are on.
func motes_on() -> bool:
	return pool != null and particles_enabled


## A shot (of the tag `tag`) hit a body at `at`: its cards' motes (`look`, its `core` colour, in
## `ramp`) back along `away`, `share` of their count.
func shed_hit(at: Vector2, away: Vector2, core: Color, ramp: int, look: int, share: float, tag: int = 0) -> void:
	if pool != null and particles_enabled and not pool.shed_closed():
		pool.shed_kinds(cards.motes_of(tag, look), at, away, core, ramp, look, share)


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
	if not on:
		return
	# The tails laid as motes (S5 step 4) take rows of their own: the most the manager lays a frame.
	var rows: int = TaillessMotes.frame_rows_of(tailless_motes) + (projectiles.tail_births_cap if projectiles.tail_births_on else 0)
	if pool.frame_rows != rows:
		pool.frame_rows = rows
	if particles_enabled and projectiles.spark_birth_count > 0:
		pool.give_off(projectiles.spark_births, projectiles.spark_birth_count)


## What Feel's own drawings gave off this frame (`births`), thrown like the trails' and forgotten.
func _drawn_motes() -> void:
	if births.count > 0 and motes_on():
		pool.give_off(births.rows, births.count)
	births.clear()


## A status's motes (spell spectacle 2, S6 item 11): `count` motes of the element card `card`'s
## kinds (those that name it, else those of its look layer `layer`), each from a random point of
## an oval `reach` pixels round `at` (a character), drifting out STATUS_DRIFT pixels and a little
## up (STATUS_UP of its kind's own), cooling from the exact colour `core`. One of many a frame: it
## leaves the moments' rows alone, as a shed does.
func status_motes(card: StringName, layer: int, at: Vector2, reach: float, core: Color, count: int) -> void:
	if count <= 0 or not motes_on() or not at.is_finite():
		return
	var found: PackedInt32Array = pool.kinds_of_card(card)
	if found.is_empty():
		found = pool.kinds_of_layer(layer)
	if found.is_empty():
		return
	var source: int = MotesScript.spell_source(0, MotesScript.LOOK_EXACT)
	for n in count:
		var k: int = found[0] if found.size() == 1 else found[_rng.randi_range(0, found.size() - 1)]
		var angle: float = _rng.randf() * TAU
		var out: Vector2 = Vector2(cos(angle), sin(angle))
		var from: Vector2 = at + Vector2(out.x, out.y * STATUS_FLAT) * reach * (0.5 + 0.5 * _rng.randf())
		pool.throw_part(k, from, out, source, core, 1, STATUS_DRIFT, -1.0, STATUS_UP, false, true)


# --- Cue parts -------------------------------------------------------------------------------

## A cue's `motes` part (`CueBase`) played with `cue`: the kinds it names thrown as it says, the
## cue's size times its `reach` out (or its `radius`), in its exact `color` or the cue's own, else in
## the cue's ramp with its tint and the cards of its look (in the caster's ramp alone when `bare`);
## its count and reach times the cue's power. One of many a frame (`often`, a hit's sparks, S6 2; and any with a `share`, a shot's end) is
## skipped, before its kinds are looked up, once the frame has only the moments' rows left; one with
## a `share` throws each kind its own count times the share (and the power), split between the
## kinds, as they shed.
func play_motes_part(part: MotesPart, cue: CueContextScript) -> void:
	if pool == null or not particles_enabled:
		return
	if part.often and pool.shed_closed():
		return
	var way: Vector2 = cue.aim
	var turn: StringName = part.way
	if turn != &"aim":
		if turn == &"back":
			way = -way
		elif turn == &"right":
			way = Vector2.RIGHT
		elif turn == &"up":
			way = Vector2.UP
	var reach: float = part.radius
	if part.reach >= 0.0 and cue.size > 0.0:
		reach = cue.size * part.reach
	reach *= cue.power
	# In an exact colour (the part's, else the cue's own), or in the cue's ramp, tint and cards.
	# A bare part keeps to the caster's ramp even in a cue with a colour of its own, as a bare flash.
	var colour: Color = part.color if part.color.a > 0.0 else (Color(0.0, 0.0, 0.0, 0.0) if part.bare else cue.color)
	var exact: bool = colour.a > 0.0
	var spell: int = MotesScript.spell_source(cue.ramp, MotesScript.LOOK_EXACT if exact else cue.look)
	var core: Color = colour if exact else cue.tint
	if part.body and not exact:
		# The body's own colour (a death puff's sparks), in no one's ramp and without the cards.
		spell = MotesScript.spell_source(0, 0)
		core = cue.body if cue.body.a > 0.0 else Color.WHITE
	elif part.bare and not exact:
		# The caster's ramp without the cards (a cast's sparks, in the seat's colours).
		spell = MotesScript.spell_source(cue.ramp, 0)
		core = Color.WHITE
	var surface: int = cue.surface if cue.surface >= 0 else _surface_source
	var at: Vector2 = cue.at
	if part.place >= 0.0:
		# Where on the cue's line (`along`, S6 item 9).
		at += cue.aim * cue.size * part.place
	if part.below != 0.0:
		at.y += part.below
	# Thrown from all along the cue's line (`line`: a staff coming apart), else from its point.
	var line: Vector2 = cue.aim * cue.size if part.line else Vector2.ZERO
	var life: float = part.life
	var named: StringName = part.named
	if named != &"spell" and named != &"surface":
		# One kind by its id: looked up once a pool (the pool is made again when its cap changes),
		# with whether it is a surface kind and its own count.
		if part.pool_seen != pool:
			part.pool_seen = pool
			part.kind_at = pool.kind_index(named)
			if part.kind_at >= 0:
				part.kind_surface = pool.kinds()[part.kind_at].surface
				part.kind_count = pool.kinds()[part.kind_at].count
		if part.kind_at < 0:
			return
		var alone: bool = part.colours == &"surface" or (part.kind_surface and part.colours != &"spell" and not exact)
		var each: int
		if part.share >= 0.0:
			each = maxi(roundi(float(part.kind_count) * part.share * cue.power), 1)
			pool.throw_part(part.kind_at, at, way, surface if alone else spell, Color.WHITE if alone else core, each, 0.0, part.spread, part.up, false, true, line, life)
			return
		each = -1 if part.count < 0 and cue.power == 1.0 else maxi(roundi(float(part.kind_count if part.count < 0 else part.count) * cue.power), 1)
		pool.throw_part(part.kind_at, at, way, surface if alone else spell, Color.WHITE if alone else core, each, reach, part.spread, part.up, part.ring, part.often, line, life)
		return
	var kinds: PackedInt32Array = cards.motes_of(cue.tag, cue.look) if named == &"spell" else _surface_kinds
	var count: int = part.count
	var shed: bool = part.share >= 0.0
	var share: float = part.share * cue.power / float(maxi(kinds.size(), 1))
	# What a surface sheds (the walls', or a room's own kinds) cools through the surface's colours,
	# as does a part whose `colours` say so; one whose `colours` are the spell's, through its ramp.
	var of_surface: bool = named == &"surface" or part.colours == &"surface"
	for k in kinds:
		# A card's own surface kind (grit) cools through the walls' colours, unless in an exact one.
		var walls: bool = of_surface or (pool.kinds()[k].surface and part.colours != &"spell" and not exact)
		var source: int = surface if walls else spell
		if shed:
			pool.throw_part(k, at, way, source, Color.WHITE if walls else core, maxi(roundi(float(pool.kinds()[k].count) * share), 1), 0.0, part.spread, part.up, false, true, line, life)
			continue
		# How many of this kind: its share of the part's count (else its own count), times the power.
		var each_share: float = float(pool.kinds()[k].count) if count < 0 else float(count) / float(kinds.size())
		var each: int = -1 if count < 0 and cue.power == 1.0 else maxi(roundi(each_share * cue.power), 1)
		pool.throw_part(k, at, way, source, Color.WHITE if walls else core, each, reach, part.spread, part.up, part.ring, part.often, line, life)


## A cue's `motes` part read into its typed fields once (`Feel.add_cue_part`'s `prepare`, S6 2: a
## hit's sparks are played hundreds of times a second).
func prepare_motes_part(part: Dictionary) -> MotesPart:
	var made := MotesPart.new()
	made.named = StringName(part.get("kind", "spell"))
	made.colours = StringName(part.get("colours", ""))
	made.count = int(part.get("count", -1))
	made.reach = float(part["reach"]) if part.has("reach") else -1.0
	made.radius = float(part.get("radius", 0.0))
	made.spread = float(part.get("spread", -1.0))
	made.up = float(part.get("up", 1.0))
	made.ring = bool(part.get("ring", false))
	made.share = float(part.get("share", -1.0))
	made.often = bool(part.get("often", false)) or made.share >= 0.0
	made.body = bool(part.get("body", false))
	made.bare = bool(part.get("bare", false))
	made.way = StringName(part.get("way", "aim"))
	made.below = float(part.get("below", 0.0))
	made.color = part["color"] as Color if part.has("color") else Color(0.0, 0.0, 0.0, 0.0)
	made.place = clampf(float(part["along"]), 0.0, 1.0) if part.has("along") else -1.0
	made.line = bool(part.get("line", false))
	made.life = float(part.get("life", 1.0))
	return made


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
	radius *= cue.power
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


## A cue's `light` part (CueBase; S6, item 4), played with `cue`: the room lit round the cue's point
## while Spell light is on, out to its `radius` pixels (or the cue's size times its `reach`; either
## times the cue's power), `strength` bright, fading over its `seconds`, in its exact `color`,
## plain, in the caster's ramp alone (`bare`), in the cue's own colour, or in the cue's ramp, tint
## and cards: as a flash would be.
func play_light_part(part: Dictionary, cue: CueContextScript) -> void:
	if light == null:
		return
	var reach: float = float(part.get("radius", LIGHT_RADIUS))
	if part.has("reach") and cue.size > 0.0:
		reach = cue.size * float(part["reach"])
	reach *= cue.power
	var strength: float = float(part.get("strength", LIGHT_STRENGTH))
	var seconds: float = float(part.get("seconds", LIGHT_SECONDS))
	var at: Vector2 = cue.point_of(part)
	if part.has("color"):
		light.flash(at, reach, strength, seconds, part["color"] as Color, 0, EXACT, _clock)
	elif bool(part.get("plain", false)):
		light.flash(at, reach, strength, seconds, Color.WHITE, 0, 0, _clock)
	elif bool(part.get("bare", false)):
		light.flash(at, reach, strength, seconds, Color.WHITE, cue.ramp, 0, _clock)
	elif cue.color.a > 0.0:
		light.flash(at, reach, strength, seconds, cue.color, 0, EXACT, _clock)
	else:
		light.flash(at, reach, strength, seconds, cue.tint, cue.ramp, cue.look, _clock)


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
		pool.frame_rows = TaillessMotes.frame_rows_of(tailless_motes)
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


## The "Tailless motes" dev setting: the motes may write `TaillessMotes.frame_rows_of(births)`
## rows a frame, so the bigger births' pool the projectile manager takes with the tails off is
## drawn. Returns the rows a frame.
func set_tailless_motes(births: int) -> int:
	tailless_motes = TaillessMotes.snap(births)
	var rows: int = TaillessMotes.frame_rows_of(tailless_motes)
	if pool != null:
		pool.frame_rows = rows
	return rows


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


## A cue's `motes` part as typed fields (`prepare_motes_part`; `CueBase` names each key): its kind
## (`spell`, `surface` or a kind's id), `colours`, `count` (-1: the kinds' own), `reach` (-1: none),
## `radius`, `spread` (-1: the kind's own), `up`, `ring`, `often`, `way`, `below`, and its exact
## `color` (alpha 0: none).
class MotesPart:
	extends RefCounted
	var named: StringName = &"spell"
	var colours: StringName = &""
	var count: int = -1
	var reach: float = -1.0
	var radius: float = 0.0
	var spread: float = -1.0
	var up: float = 1.0
	var ring: bool = false
	var often: bool = false
	## Its `share` (-1: none; a shed's, which is `often` too).
	var share: float = -1.0
	## In the body's own colour (`CueContext.body`), as a flash's `body`.
	var body: bool = false
	## In the caster's ramp without the cards, as a flash's `bare`.
	var bare: bool = false
	var way: StringName = &"aim"
	var below: float = 0.0
	var color: Color = Color(0.0, 0.0, 0.0, 0.0)
	## Where on the cue's line it is thrown from (`along`, 0 to 1; -1: the cue's point), whether
	## from all along the line (`line`), and its `life` (times its kinds' own lives) (S6 item 9).
	var place: float = -1.0
	var line: bool = false
	var life: float = 1.0
	## A named kind's index in the pool `pool_seen` (-1: none), whether it is a surface kind, and
	## its own count, kept for that pool.
	var pool_seen: Object = null
	var kind_at: int = -1
	var kind_surface: bool = false
	var kind_count: int = 1
