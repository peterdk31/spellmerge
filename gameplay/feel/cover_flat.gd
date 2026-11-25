extends Sprite2D
## A flat cover kind's look in one room (the floor's first slice, docs/milestones/floor.md): one
## sprite over the room's cover grid, drawn by `cover_flat.gdshader` from a texture of a texel a
## cell (red: the state the cell shows; green: when it began to show it, Feel's clock). Feel's
## `cover.gd` makes one for each kind of `CoverKind.Look.FLAT` a room has (`lay`), tells it each
## cell's change (`show`) and hands its picture over once a frame when one changed (`hand`). Its
## states' looks (`CoverState.flat_*`, the palette's shades) are the shader's uniforms, set once.
##
## Pure view: nothing here is the game's, and nothing here is read by the simulation. Allocates
## nothing once laid.

const SHADER: Shader = preload("res://gameplay/feel/cover_flat.gdshader")
## The most states a flat kind's look holds (the shader's STATES).
const STATES: int = 16
## Art pixels a world pixel of the look (ArtDetail, core/display/art_detail.gd): the shader works its
## shapes out at this detail. 1 while the floor states are 32-unit art (drawn as 2x2 blocks of the
## 1280 x 720 picture at zoom 1); `ArtDetail.DETAIL` once they are redrawn at 64 px a cell.
const DETAIL: int = 1

## The kind drawn and its index + 1 in the layout's cells.
var kind: CoverKind = null
var mark: int = 0
var _cells: Image = null
var _upload: TextureUpload = TextureUpload.new()
var _dirty: bool = false


## Lays kind `kind_index` of `laid` at rest, its cells shown since `now`.
func lay(laid: CoverLayout, kind_index: int, now: float) -> void:
	kind = laid.kinds[kind_index]
	mark = kind_index + 1
	centered = false
	position = laid.origin
	scale = Vector2(CoverLayout.CELL, CoverLayout.CELL)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cells = Image.create_empty(maxi(laid.columns, 1), maxi(laid.rows, 1), false, Image.FORMAT_RGF)
	_cells.fill(Color(0.0, now, 0.0, 1.0))
	texture = _upload.hand(_cells)
	_dirty = false
	var made := ShaderMaterial.new()
	made.shader = SHADER
	_set_looks(made)
	made.set_shader_parameter(&"cells", texture)
	made.set_shader_parameter(&"art_detail", DETAIL)
	material = made


## The uniforms of the kind's states' looks (the shader's arrays, STATES long).
func _set_looks(made: ShaderMaterial) -> void:
	var fills := PackedColorArray()
	var edges := PackedColorArray()
	var glints := PackedColorArray()
	var unders := PackedColorArray()
	var under_edges := PackedColorArray()
	var sparks := PackedColorArray()
	var motions := PackedColorArray()
	for list: PackedColorArray in [fills, edges, glints, unders, under_edges, sparks, motions]:
		list.resize(STATES)
		list.fill(Color(0.0, 0.0, 0.0, 0.0))
	for at in mini(kind.states.size(), STATES):
		var state: CoverState = kind.states[at]
		if state == null or state.flat_material == &"" or not Palette.has(state.flat_material):
			continue
		var shades: PackedColorArray = Palette.shades_of(state.flat_material)
		edges[at] = shades[0]
		fills[at] = shades[1]
		glints[at] = shades[2]
		if state.flat_under != &"" and Palette.has(state.flat_under):
			var under: PackedColorArray = Palette.shades_of(state.flat_under)
			under_edges[at] = under[0]
			unders[at] = under[1]
		if state.flat_spark != &"" and Palette.has(state.flat_spark):
			sparks[at] = Palette.shades_of(state.flat_spark)[2]
		motions[at] = Color(float(state.flat_motion), float(state.animation_frames), float(state.animation_fps), 1.0 if state.animation_loops else 0.0)
	made.set_shader_parameter(&"fills", fills)
	made.set_shader_parameter(&"edges", edges)
	made.set_shader_parameter(&"glints", glints)
	made.set_shader_parameter(&"unders", unders)
	made.set_shader_parameter(&"under_edges", under_edges)
	made.set_shader_parameter(&"sparks", sparks)
	made.set_shader_parameter(&"motions", motions)


## Cell `cell` (of `columns` a row) shows `state` from `now` on.
func show_cell(cell: int, columns: int, state: int, now: float) -> void:
	if _cells == null or columns <= 0:
		return
	_cells.set_pixel(cell % columns, cell / columns, Color(float(state), now, 0.0, 1.0))
	_dirty = true


## The state cell `cell` shows (0 at rest).
func shown_cell(cell: int, columns: int) -> int:
	if _cells == null or columns <= 0:
		return 0
	return roundi(_cells.get_pixel(cell % columns, cell / columns).r)


## The frame's picture: the clock set, the grid handed over when a cell changed.
func hand(now: float) -> void:
	(material as ShaderMaterial).set_shader_parameter(&"view_time", now)
	if _dirty:
		_dirty = false
		var handed: ImageTexture = _upload.hand(_cells)
		if handed != texture:
			texture = handed
			(material as ShaderMaterial).set_shader_parameter(&"cells", handed)
