extends ColorRect
## A room's low floor mist (docs/milestones/atmosphere.md, F; the room's `RoomBase.mist`, a
## `RoomMist`): one rect over the room drawn by `mist.gdshader`, soft and see-through (the owner's
## exception to the pixel rules, 2026-11-18, docs/STYLE.md), drifting slowly on Feel's clock. The
## spectacle's, made and freed with the spell light (only while the "Dynamic lighting" and "Fog"
## settings are on, easing in and out with "Fog": `share`; the mist reads the light buffer to glow in
## the light, and without the light's dark round it, it would be a flat veil over the room).
##
## - **Where:** at the floor marks' z (the spectacle's MARK_Z), the last of the spectacle's children
##   there, so it lies over the floor, the cover, the marks and the bodies' shadows (a shadow is on the
##   floor and the mist over it; the bodies part the mist round their feet, so their own shadows show
##   clear) and under every body (z 0), and under the spell light's apply rect, which darkens it with
##   the room's dark and lights it by the floor's bands. A room's own art at that z (a pit's `Glow`
##   in its ground, a light shaft's `Pool`) is in the world's tree, after Feel's, so it draws over the
##   mist: a pit's rim keeps its cold glow crisp, the mist pooled in the hole inside it.
## - **Thin over the middle** (crypt rework rule 6): thicker toward the walls and the pits, by the
##   room's mask (`mist_mask.gd`, built once a room from the walls and holes as laid: `lay`).
## - **Pushed and parted:** the world's stirs (the shots' wake, the blasts' push: `stirs.gd`, handed
##   by `step`'s `hand_stirs` whenever their version changes; this knows nothing else of them), and
##   the bodies' feet (a short list, the ground cover's, handed to `step`) through `mist_parting.gd`.
## - **Lit** by the spell light's buffer (`use_light`).
##
## Nothing is made a frame: a frame sets the clock, steps the parting (written where a cell changed)
## and hands the stirs over when they changed.

const SHADER: Shader = preload("res://gameplay/feel/mist.gdshader")
const MistMaskScript := preload("res://gameplay/feel/mist_mask.gd")
const MistPartingScript := preload("res://gameplay/feel/mist_parting.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")

## How far the shots' wake and a blast's push move the mist at their fullest (px), how much they
## thin it, and how far a body pushes it aside round its feet and how much it thins where parted
## (mist.gdshader's STIR_SHOT_PIXELS, STIR_BLAST_PIXELS, STIR_THIN, PART_PIXELS, PART_THIN), and
## the most it may hide (THICKEST_DRAWN, RoomMist.THICKEST).
const STIR_SHOT_PIXELS: float = 10.0
const STIR_BLAST_PIXELS: float = 26.0
const STIR_THIN: float = 0.9
const PART_PIXELS: float = 6.0
const PART_THIN: float = 0.92
const THICKEST_DRAWN: float = RoomMist.THICKEST

## The mist drawn (null: none) and the room it lies in (its size, px, and its place, world px: where
## the room stands, connected biomes; the origin for a room of its own). Read only.
var mist: RoomMist = null
var room_size: Vector2 = Vector2.ZERO
var room_origin: Vector2 = Vector2.ZERO
## Where bodies part it. Read only.
var parting: MistPartingScript = MistPartingScript.new()
## The mask of the room laid (null before one). Read only.
var mask: ImageTexture = null
## How much of it shows (0 to 1; the "Fog" setting easing it in or out, the spectacle sets it each
## frame through `set_share`): its thickness times this. Read only.
var share: float = 1.0

## The room's walls and holes in its own px (from `room_origin`), as the mask is built from them.
var _walls: Array[Rect2] = []
var _holes: Array[Rect2] = []
## The mask is to be built again before the next draw (a room laid, or a mist given to one).
var _stale: bool = false
## The stirs' version last handed over (-1: hand them at the next step), and Feel's clock then.
var _stirs_version: int = -1
var _now: float = -1.0
## Whether its room is one nobody has seen yet (`set_unseen`): not drawn, the void shows there.
var _unseen: bool = false


## Mist drawn at `z` (the spectacle's MARK_Z).
func _init(z: int) -> void:
	name = "Mist"
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = z
	visible = false
	var shading := ShaderMaterial.new()
	shading.shader = SHADER
	shading.set_shader_parameter(&"bright_from", SpellLightScript.BRIGHT_FROM)
	material = shading


## The room laid (`room_built`): its size (px), its walls and its holes (world px, as mirrored where it
## stands: `PieceShape.laid_walls`), and its place `at` (world px; the origin for a room of its own).
func lay(size: Vector2, walls: Array[Rect2], holes: Array[Rect2], at: Vector2 = Vector2.ZERO) -> void:
	room_size = size
	room_origin = at
	_walls = _moved(walls, -at)
	_holes = _moved(holes, -at)
	_stale = true
	parting.lay(size, at)
	_refresh()


## The room's mist (`RoomBase.mist`; null: none).
func use(given: RoomMist) -> void:
	mist = given
	var shading := material as ShaderMaterial
	if mist != null:
		shading.set_shader_parameter(&"colour", Vector3(mist.colour.r, mist.colour.g, mist.colour.b))
		shading.set_shader_parameter(&"thickness", mist.thickness * share)
		shading.set_shader_parameter(&"middle", mist.middle)
		shading.set_shader_parameter(&"edge_reach", mist.edge_reach / MistMaskScript.REACH)
		shading.set_shader_parameter(&"pit_reach", mist.pit_reach / MistMaskScript.REACH)
		shading.set_shader_parameter(&"pit_share", mist.pit_share)
		shading.set_shader_parameter(&"spill", mist.spill / MistMaskScript.SPILL)
		shading.set_shader_parameter(&"patchy", mist.patchy)
		shading.set_shader_parameter(&"scale", mist.scale)
		shading.set_shader_parameter(&"drift", mist.drift)
		shading.set_shader_parameter(&"in_dark", mist.in_dark)
		shading.set_shader_parameter(&"lit", mist.lit)
	parting.clear()
	_refresh()


## How much of it shows (`share`): the mist thins to nothing at 0 (soft, as the mist alone may be).
func set_share(next: float) -> void:
	next = clampf(next, 0.0, 1.0)
	if next == share:
		return
	share = next
	if mist != null:
		(material as ShaderMaterial).set_shader_parameter(&"thickness", mist.thickness * share)


## The spell light's buffer it glows by (SpellLight.buffer).
func use_light(buffer: Texture2D) -> void:
	(material as ShaderMaterial).set_shader_parameter(&"light_buffer", buffer)


## Not drawn while its room is one nobody has seen yet (`unseen_standing.gd`), drawn as it stands
## again from the room's reveal.
func set_unseen(unseen: bool) -> void:
	if unseen == _unseen:
		return
	_unseen = unseen
	_refresh()


## Shown when there is a mist and a room to lay it in, not unseen; the mask built again when it is
## stale.
func _refresh() -> void:
	var shown: bool = mist != null and room_size.x > 0.0 and room_size.y > 0.0 and not _unseen
	visible = shown
	if not shown:
		return
	position = room_origin
	size = room_size
	var shading := material as ShaderMaterial
	shading.set_shader_parameter(&"origin", room_origin)
	if _stale or mask == null:
		_stale = false
		var image: Image = MistMaskScript.build(room_size, _walls, _holes, true)
		mask = ImageTexture.create_from_image(image)
		var cell: float = MistMaskScript.cell_of(room_size)
		shading.set_shader_parameter(&"mask", mask)
		shading.set_shader_parameter(&"mask_size", Vector2(float(image.get_width()), float(image.get_height())) * cell)
	shading.set_shader_parameter(&"parted", parting.texture)
	shading.set_shader_parameter(&"parted_size", parting.size())


## `rects` moved by `by` (a copy: the caller's are kept).
static func _moved(rects: Array[Rect2], by: Vector2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for rect in rects:
		out.append(Rect2(rect.position + by, rect.size))
	return out


## Once a frame, at Feel's clock `now`: the clock handed over, the mist parted round the first `count`
## of `feet` (the bodies' positions, world px), and the world's stirs handed over by `hand_stirs`
## (taking a ShaderMaterial: `Stirs.hand_to`) whenever `stirs_version` is not the one handed last.
func step(now: float, feet: PackedVector2Array, count: int, stirs_version: int = -1, hand_stirs: Callable = Callable()) -> void:
	var delta: float = now - _now if _now >= 0.0 else 0.0
	_now = now
	if not visible:
		return
	var shading := material as ShaderMaterial
	shading.set_shader_parameter(&"view_time", now)
	parting.step(delta, feet, count)
	if hand_stirs.is_valid() and stirs_version != _stirs_version:
		_stirs_version = stirs_version
		hand_stirs.call(shading)
