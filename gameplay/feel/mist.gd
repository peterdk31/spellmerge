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
## - **At the light's resolution** (`use_passes`; the owner's decision of 2026-11-21, docs/milestones/
##   connected-biomes.md, "The light at a fixed resolution"): while the picture is bigger than
##   PictureGrid.SIZE, a twin of this rect in the spell light's pass under it (`SpellLight.under_holder`)
##   works out how thick the mist is a block at a time (`mist_pass.gdshader`, with this rect's numbers:
##   every uniform is set on both), and this rect takes it whole for each block and lights it by the
##   light at the block's middle. Every room's twin is drawn in one pass, written as it is: the rooms'
##   rects never overlap, so none overwrites another's.
##
## Nothing is made a frame: a frame sets the clock, steps the parting (written where a cell changed)
## and hands the stirs over when they changed.

const SHADER: Shader = preload("res://gameplay/feel/mist.gdshader")
const PASS_SHADER: Shader = preload("res://gameplay/feel/mist_pass.gdshader")
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

## The twin drawing how thick the mist is in the pass at the light's resolution (`use_passes`; null
## with none). Read only.
var twin: ColorRect = null
## Where the twin is to be drawn (`use_passes`; null: none), kept while this rect is out of the tree.
var _holder: Node = null
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
	if mist != null:
		_param(&"colour", Vector3(mist.colour.r, mist.colour.g, mist.colour.b))
		_param(&"thickness", mist.thickness * share)
		_param(&"middle", mist.middle)
		_param(&"edge_reach", mist.edge_reach / MistMaskScript.REACH)
		_param(&"pit_reach", mist.pit_reach / MistMaskScript.REACH)
		_param(&"pit_share", mist.pit_share)
		_param(&"spill", mist.spill / MistMaskScript.SPILL)
		_param(&"patchy", mist.patchy)
		_param(&"scale", mist.scale)
		_param(&"drift", mist.drift)
		_param(&"in_dark", mist.in_dark)
		_param(&"lit", mist.lit)
	parting.clear()
	_refresh()


## How much of it shows (`share`): the mist thins to nothing at 0 (soft, as the mist alone may be).
func set_share(next: float) -> void:
	next = clampf(next, 0.0, 1.0)
	if next == share:
		return
	share = next
	if mist != null:
		_param(&"thickness", mist.thickness * share)


## The spell light's buffer it glows by (SpellLight.buffer).
func use_light(buffer: Texture2D) -> void:
	(material as ShaderMaterial).set_shader_parameter(&"light_buffer", buffer)


## Its twin drawn under `holder` from now on (the spell light's pass under it, `SpellLight.under_holder`:
## the picture bigger than PictureGrid.SIZE), with this rect's place and numbers; none with no holder.
func use_passes(holder: Node) -> void:
	_holder = holder
	if not is_inside_tree():
		_drop_twin()
		return
	if twin != null and not is_instance_valid(twin):
		# Freed with the passes it was drawn in (the light made anew).
		twin = null
	if twin != null and twin.get_parent() == holder:
		return
	_drop_twin()
	if holder == null:
		return
	twin = ColorRect.new()
	twin.name = name
	twin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var drawn := ShaderMaterial.new()
	drawn.shader = PASS_SHADER
	var from := material as ShaderMaterial
	for uniform: Dictionary in PASS_SHADER.get_shader_uniform_list(true):
		var named := StringName(String(uniform.get("name", "")))
		if named != &"" and int(uniform.get("type", TYPE_NIL)) != TYPE_NIL:
			drawn.set_shader_parameter(named, from.get_shader_parameter(named))
	twin.material = drawn
	holder.add_child(twin)
	_refresh()


## The twin goes with this rect out of the tree (the mist freed), and comes back with it.
func _exit_tree() -> void:
	_drop_twin()


func _enter_tree() -> void:
	if _holder != null and is_instance_valid(_holder) and twin == null:
		use_passes(_holder)


func _drop_twin() -> void:
	if twin != null and is_instance_valid(twin):
		if twin.get_parent() != null:
			twin.get_parent().remove_child(twin)
		twin.queue_free()
	twin = null


## `uniform` set to `value`, on the twin too.
func _param(uniform: StringName, value: Variant) -> void:
	(material as ShaderMaterial).set_shader_parameter(uniform, value)
	if twin != null and is_instance_valid(twin):
		(twin.material as ShaderMaterial).set_shader_parameter(uniform, value)


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
	if twin != null and is_instance_valid(twin):
		twin.visible = shown
	if not shown:
		return
	position = room_origin
	size = room_size
	if twin != null and is_instance_valid(twin):
		twin.position = room_origin
		twin.size = room_size
	_param(&"origin", room_origin)
	if _stale or mask == null:
		_stale = false
		var image: Image = MistMaskScript.build(room_size, _walls, _holes, true)
		mask = ImageTexture.create_from_image(image)
		var cell: float = MistMaskScript.cell_of(room_size)
		_param(&"mask", mask)
		_param(&"mask_size", Vector2(float(image.get_width()), float(image.get_height())) * cell)
	_param(&"parted", parting.texture)
	_param(&"parted_size", parting.size())


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
	_param(&"view_time", now)
	parting.step(delta, feet, count)
	if hand_stirs.is_valid() and stirs_version != _stirs_version:
		_stirs_version = stirs_version
		hand_stirs.call(shading)
		if twin != null and is_instance_valid(twin):
			hand_stirs.call(twin.material as ShaderMaterial)
