class_name BeamUnion
extends RefCounted
## Every beam drawn with one look shader as ONE merged shape, in one draw (the owner, 2026-11-27:
## "Beams should merge into each other (like the pool)", "Everything merges. Ideally beams should
## inherit colors from every source after a junction"; core/projectiles/shot_beam_union.gdshaderinc
## draws it). Feel's beams job hands it each frame's beams (`begin`, `add` a beam, `publish`): live
## beams and beams shown whole alike, every player's and the enemies'.
##
## **What the shader is told.** One float texture (`beam_data`, through its own TextureUpload): a row
## of ROW texels a beam (B_*: its ends, length, fade, swell, width, core colour, player, look, its
## ramp and first infusion's kind as `ramp_of` and `first_kind_of` work them out, and its infusions),
## then from row `beam_rows` its path's pieces, SEGS_A_ROW to a row (S_*: the piece's two ends, how far
## along the beam it starts, the beam's length, swell and fade, which beam, whether it is the beam's
## first or last piece, the beam's ramp and kind, its width). A texture, not uniform arrays: the
## pieces of every beam on screen (46 beams of a bounce or two, a homing beam of 79) are far past
## what a uniform array may hold on the web (a vec4 array of a few hundred is the most a GLSL ES
## shader is sure of), and one texture is one upload a frame however many there are.
##
## **How it is drawn.** One mesh (`MeshInstance2D`) of a quad a piece, as many as the pieces it
## holds room for: a quad past `seg_count` folds away. A path is cut into pieces of at most
## PIECE_MOST pixels, so a piece's quad is small and finds few pieces near it (once, in vertex():
## NEAR_MOST at most, its own beam's neighbours first), and a pixel takes the soft union of their
## distances: one distance, so one rim round the merged shape and no rim inside it, and only the
## piece nearest the pixel draws it (its beam's pixels, or its light where it has none), so nothing
## is drawn twice (no doubled light or alpha where beams overlap).
##
## Grows (doubling) to the most beams and pieces a frame has had, and is kept: a frame allocates
## nothing once it has. View only.

const BatchesScript := preload("res://core/projectiles/batches.gd")
const LightGridScript := preload("res://gameplay/feel/light_grid.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## Texels a row of the data texture.
const ROW: int = 16
## A beam's row: start x, y and end x, y; length, fade, swell, width; core r, g, b and player (-1 an
## enemy's); look channels and glow; infusions, ramp and first kind; then its infusions.
const B_ENDS: int = 0
const B_SHAPE: int = 1
const B_CORE: int = 2
const B_LOOK: int = 3
const B_KIND: int = 4
const B_INFUSIONS: int = 5
## The most infusions a beam hands its look (the shader's INFUSIONS; Feel's BEAM_INFUSIONS_MOST).
const INFUSIONS_MOST: int = 8
## A piece's texels, SEGS_A_ROW pieces a row: its ends (A x, y, B x, y); how far along the beam A is,
## the beam's length, swell and how far it gives way as it fades; its beam, flags (F_*), the beam's
## ramp and kind; the beam's width, glow and fade.
const SEG_TEXELS: int = 4
const SEGS_A_ROW: int = ROW / SEG_TEXELS
const S_ENDS: int = 0
const S_SHAPE: int = 1
const S_WHO: int = 2
const S_WIDTH: int = 3
## How soft the union is (the shader's SOFT, pixels).
const SOFT: float = 3.0
## How whole a fading beam is when it starts giving way in the union (its swell's floor, Feel's 0.35).
const FADE_GIVES: float = 0.35
## The longest piece a path is cut into (pixels): a piece's quad is this long and a beam's width wide.
const PIECE_MOST: float = 64.0
## A piece's flags: its beam's first piece (its start's flare), its last (its end's), and a cut of a
## straight piece of the path before it and after it (a pixel past a cut is the next piece's own, so
## the pieces of a straight piece never look at each other).
const F_FIRST: int = 1
const F_LAST: int = 2
const F_CUT_BEFORE: int = 4
const F_CUT_AFTER: int = 8
## A beam's ramp as the shader draws its colours at a junction (`ramp_of`): a palette material (0 to
## 7), a player's ramp (RAMP_PLAYER + 0-3, + 4 the enemies'), or its own tint (RAMP_OWN: a tint no
## palette material holds, mend's green, or an exact colour).
const RAMP_PLAYER: int = 8
const RAMP_OWN: int = 16
## How far a tint may be from every palette shade and still be drawn in its material (the shader's).
const PALETTE_NEAR: float = 0.08
## The look kinds a beam's look sways, jags or rifts by (L_* in shot_palette.gdshaderinc).
const L_EMBERS: int = 1
const L_GUSTS: int = 3
const L_PULL: int = 4
const L_SPARKS: int = 5
## The kinds a shown beam's look is searched for, in order (`first_kind_of`).
const SWAYING_KINDS: PackedInt32Array = [L_PULL, L_SPARKS, L_GUSTS, L_EMBERS]
## The look's flags (shot_palette.gdshaderinc's ENEMY_RAMP and EXACT, kinds 29 and 30).
const LOOK_ENEMY_RAMP: int = ManagerScript.LOOK_ENEMY_RAMP
const LOOK_EXACT: int = ManagerScript.LOOK_ENEMY_RAMP << 1
## The colour rules at a junction (the shader's `beam_mix`): an ordered dither between the sources'
## colours by how near each is, each blend snapped to the nearest palette shade, or the nearest
## source's alone.
const MIX_DITHER: int = 0
const MIX_SNAP: int = 1
const MIX_NEAREST: int = 2
const MIX_NAMES: Array[String] = ["dither", "snap", "nearest"]
## Room made at first (a texture of 16 x 32 texels).
const START_BEAMS: int = 16
const START_SEGMENTS: int = 64

## The node that draws it all (Feel's child), and its material.
var node: MeshInstance2D = null
var material: ShaderMaterial = null
## This frame's beams and pieces.
var beams: int = 0
var segments: int = 0
## Each beam's (by index, `add`'s), for the tests to read: its start, end, length, fade, swell,
## width, core, player, look, glow, infusions, first piece and how many pieces.
var starts: PackedVector2Array = PackedVector2Array()
var ends: PackedVector2Array = PackedVector2Array()
var lengths: PackedFloat32Array = PackedFloat32Array()
var fades: PackedFloat32Array = PackedFloat32Array()
var swells: PackedFloat32Array = PackedFloat32Array()
var widths: PackedFloat32Array = PackedFloat32Array()
var cores: PackedColorArray = PackedColorArray()
var players: PackedInt32Array = PackedInt32Array()
var looks: PackedInt32Array = PackedInt32Array()
var glows: PackedFloat32Array = PackedFloat32Array()
var infusions: Array[PackedColorArray] = []
var first_segments: PackedInt32Array = PackedInt32Array()
var segment_counts: PackedInt32Array = PackedInt32Array()
## Each beam's path as it was added (x, y and how far along), its points from `first_points`.
var path_points: PackedVector3Array = PackedVector3Array()
var first_points: PackedInt32Array = PackedInt32Array()
var point_counts: PackedInt32Array = PackedInt32Array()
var _points_used: int = 0
## The colour rule at a junction (MIX_*).
var mix: int = MIX_DITHER

var _beam_room: int = 0
var _segment_room: int = 0
var _image: Image = null
var _upload: TextureUpload = TextureUpload.new()
var _texture: Texture2D = null
var _mix_told: int = -1
var _lead: float = 0.0


## A union drawn by `shader` at `z`, its beams' quads reaching `lead` past each end (so the flares
## there are whole). Its node is the caller's to add to the tree.
func _init(shader: Shader, z: int, lead: float) -> void:
	_lead = lead
	node = MeshInstance2D.new()
	material = ShaderMaterial.new()
	material.shader = shader
	node.material = material
	node.top_level = true
	node.visible = false
	node.z_index = z
	_grow(START_BEAMS, START_SEGMENTS)


## The mesh for `pieces` pieces: a quad each, told in its UV its slot. The shader places them in
## the world, so the mesh says nothing of where: its box is the whole world.
static func mesh_for(pieces: int) -> ArrayMesh:
	var mesh: ArrayMesh = FeelFlashes._quads_mesh([Vector3i(0, pieces, 0)] as Array[Vector3i])
	mesh.custom_aabb = BatchesScript.WORLD
	return mesh


## How many pieces the mesh and the texture hold room for.
func segment_room() -> int:
	return _segment_room


## A new frame: no beams.
func begin() -> void:
	beams = 0
	segments = 0
	_points_used = 0


## Adds a beam: the first `points` of `path` (x, y and how far along, the last as far as it got,
## `length`), from `start` to `end_at`, its core colour `core`, its caster's ramp `player` (0-3, -1
## the enemies'), its look bits `look`, its infusions (`CompiledSpell.infusion_looks`; empty for a
## beam shown with its tint and look only), `fade` whole (1 to 0), swollen `swell` (1 at rest),
## `width` wide, glowing `glow`. Its index, or -1 for a path of fewer than two points.
func add(path: PackedVector3Array, points: int, start: Vector2, end_at: Vector2, length: float, core: Color, player: int, look: int, beam_infusions: PackedColorArray, fade: float, swell: float, width: float, glow: float) -> int:
	if points < 2:
		return -1
	var pieces: int = 0
	for n in points - 1:
		pieces += pieces_of(path[n], path[n + 1])
	if beams >= _beam_room or segments + pieces > _segment_room:
		_grow(maxi(_beam_room, (beams + 1) * 2), maxi(_segment_room, (segments + pieces) * 2))
	if _points_used + points > path_points.size():
		path_points.resize((_points_used + points) * 2)
	var b: int = beams
	beams += 1
	var ramp: int = ramp_of(core, player, look)
	var kind: int = first_kind_of(core, look, beam_infusions)
	var count: int = mini(beam_infusions.size(), INFUSIONS_MOST)
	starts[b] = start
	ends[b] = end_at
	lengths[b] = length
	fades[b] = fade
	swells[b] = swell
	widths[b] = width
	cores[b] = core
	players[b] = player
	looks[b] = look
	glows[b] = glow
	infusions[b] = beam_infusions
	first_segments[b] = segments
	segment_counts[b] = pieces
	first_points[b] = _points_used
	point_counts[b] = points
	for n in points:
		path_points[_points_used + n] = path[n]
	_points_used += points
	_image.set_pixel(B_ENDS, b, Color(start.x, start.y, end_at.x, end_at.y))
	_image.set_pixel(B_SHAPE, b, Color(length, fade, swell, width))
	_image.set_pixel(B_CORE, b, Color(core.r, core.g, core.b, float(player)))
	var channels: Vector3 = look_channels(look)
	_image.set_pixel(B_LOOK, b, Color(channels.x, channels.y, channels.z, glow))
	_image.set_pixel(B_KIND, b, Color(float(count), float(ramp), float(kind), 0.0))
	for n in count:
		_image.set_pixel(B_INFUSIONS + n, b, beam_infusions[n])
	var first: int = segments
	var last: int = segments + pieces - 1
	var give: float = give_of(fade)
	for n in points - 1:
		var from: Vector3 = path[n]
		var to: Vector3 = path[n + 1]
		var cuts: int = pieces_of(from, to)
		for c in cuts:
			var a: Vector3 = from.lerp(to, float(c) / cuts)
			var z: Vector3 = from.lerp(to, float(c + 1) / cuts)
			var s: int = segments
			segments += 1
			var flags: int = (F_FIRST if s == first else 0) | (F_LAST if s == last else 0) | (F_CUT_BEFORE if c > 0 else 0) | (F_CUT_AFTER if c < cuts - 1 else 0)
			var x: int = (s % SEGS_A_ROW) * SEG_TEXELS
			var y: int = _beam_room + s / SEGS_A_ROW
			_image.set_pixel(x + S_ENDS, y, Color(a.x, a.y, z.x, z.y))
			_image.set_pixel(x + S_SHAPE, y, Color(a.z, length, swell, give))
			_image.set_pixel(x + S_WHO, y, Color(float(b), float(flags), float(ramp), float(kind)))
			_image.set_pixel(x + S_WIDTH, y, Color(width, glow, fade, 0.0))
	return b


## How far a beam `fade` whole gives way in the union (pixels; the shader's `shape.w`): nothing while
## it is more than FADE_GIVES whole (a lone beam keeps its own shape as it dissolves into pixels),
## then SOFT x -log of what is left of it, so it lets go of the beams it meets smoothly to nothing.
static func give_of(fade: float) -> float:
	return -SOFT * log(clampf(fade / FADE_GIVES, 0.001, 1.0))


## How many pieces the path's piece from `from` to `to` is cut into: none longer than PIECE_MOST.
static func pieces_of(from: Vector3, to: Vector3) -> int:
	return maxi(ceili(Vector2(from.x, from.y).distance_to(Vector2(to.x, to.y)) / PIECE_MOST), 1)


## Hands this frame's beams to the shader at `sim_time` (Feel's clock); hidden with none.
func publish(sim_time: float) -> void:
	node.visible = segments > 0
	if segments == 0:
		return
	var texture: Texture2D = _upload.hand(_image)
	if texture != _texture:
		_texture = texture
		material.set_shader_parameter(&"beam_data", texture)
		material.set_shader_parameter(&"beam_rows", _beam_room)
		material.set_shader_parameter(&"beam_lead", _lead)
	if mix != _mix_told:
		_mix_told = mix
		material.set_shader_parameter(&"beam_mix", mix)
	material.set_shader_parameter(&"seg_count", segments)
	material.set_shader_parameter(&"sim_time", sim_time)


## The points of beam `b`'s path as it was added (x, y and how far along). Allocates: for tests.
func path_of(b: int) -> PackedVector3Array:
	return path_points.slice(first_points[b], first_points[b] + point_counts[b])


## A look's three channels (ProjectileManager's LOOK_CHANNEL_BITS each) as whole numbers, as the
## shaders' `look_channels` splits a look int: a float texel holds a whole number to 2^24 only.
static func look_channels(look: int) -> Vector3:
	var bits: int = ManagerScript.LOOK_CHANNEL_BITS
	var mask: int = (1 << bits) - 1
	return Vector3(float(look & mask), float((look >> bits) & mask), float((look >> (2 * bits)) & mask))


## The ramp a beam's colours are drawn in at a junction (RAMP_*), from its core colour, its caster's
## ramp and its look bits, as `look_of` (shot_look.gdshaderinc) picks the ramp the beam itself is
## drawn in: a white core is its player's ramp, an exact colour or a tint no palette material holds
## its own, any other its palette material.
static func ramp_of(core: Color, player: int, look: int) -> int:
	if look & LOOK_EXACT != 0:
		return RAMP_OWN
	if core.r > 0.99 and core.g > 0.99 and core.b > 0.99:
		var who: int = 4 if player < 0 or look & LOOK_ENEMY_RAMP != 0 else mini(player, 3)
		return RAMP_PLAYER + who
	var nearest: float = 9.0
	for i in LightGridScript.MATERIALS * 3:
		var dr: float = core.r - LightGridScript.SHADES[i * 3]
		var dg: float = core.g - LightGridScript.SHADES[i * 3 + 1]
		var db: float = core.b - LightGridScript.SHADES[i * 3 + 2]
		nearest = minf(nearest, sqrt(dr * dr + dg * dg + db * db))
	if nearest > PALETTE_NEAR:
		return RAMP_OWN
	return LightGridScript.material_of(core.r, core.g, core.b)


## The look kind a beam sways, jags or rifts by: its first infusion's (its alpha, the kind / 255),
## or for a beam shown with its tint and look only the first of void's, lightning's, storm's and
## fire's its look has (a plain beam: none, 0).
static func first_kind_of(core: Color, look: int, beam_infusions: PackedColorArray) -> int:
	if not beam_infusions.is_empty():
		return roundi(beam_infusions[0].a * 255.0)
	if core.r > 0.99 and core.g > 0.99 and core.b > 0.99:
		return 0
	for kind: int in SWAYING_KINDS:
		if look & (1 << (kind - 1)) != 0:
			return kind
	return 0


## Room for `beam_room` beams and `segment_room` pieces: a new texture image, mesh and arrays.
func _grow(beam_room: int, segment_room: int) -> void:
	# Whole rows of pieces.
	segment_room = ceili(float(segment_room) / SEGS_A_ROW) * SEGS_A_ROW
	var old: Image = _image
	var old_beams: int = _beam_room
	_image = Image.create_empty(ROW, beam_room + segment_room / SEGS_A_ROW, false, Image.FORMAT_RGBAF)
	if old != null:
		# What this frame already added keeps its place: its beams' rows, its pieces' rows below them.
		_image.blit_rect(old, Rect2i(0, 0, ROW, old_beams), Vector2i.ZERO)
		_image.blit_rect(old, Rect2i(0, old_beams, ROW, old.get_height() - old_beams), Vector2i(0, beam_room))
	if segment_room != _segment_room:
		node.mesh = mesh_for(segment_room)
	_beam_room = beam_room
	_segment_room = segment_room
	_texture = null
	# Each member resized in place (a packed array held in another array is a copy once written).
	starts.resize(beam_room)
	ends.resize(beam_room)
	lengths.resize(beam_room)
	fades.resize(beam_room)
	swells.resize(beam_room)
	widths.resize(beam_room)
	cores.resize(beam_room)
	players.resize(beam_room)
	looks.resize(beam_room)
	glows.resize(beam_room)
	first_segments.resize(beam_room)
	segment_counts.resize(beam_room)
	first_points.resize(beam_room)
	point_counts.resize(beam_room)
	infusions.resize(beam_room)
