extends Node
## Spell light (docs/milestones/spell-spectacle.md, P3a, P3b): shots, flashes, beams and the
## room's own lights light the floor, the walls and the bodies round them. A child of the
## spectacle (gameplay/feel/spectacle.gd, under Feel), made only while the "Dynamic lighting" setting
## is on (`SpellLightSetting`, `spell_light_changed`); with it off none of these nodes exist.
##
## - **Grid lighting** (the owner's decision of 2026-11-21, docs/milestones/connected-biomes.md, "Grid
##   lighting"): the light is worked out on the CPU on a grid of world cells (`grid`,
##   gameplay/feel/light_grid.gd: a grid a view, `grid_cell` px each way, in one small texture), in the
##   native module where it is loaded, every frame just before the draw (`follow`). Its readers take the
##   cell their world point lies in (`light_grid.gdshaderinc`). There is no light buffer drawn by the
##   GPU any more, and no SubViewport a view for it.
## - **Rows are never written twice:** the grid reads the rows their owners already write, as the GPU's
##   light did (its row formats, LightGrid.ROWS_*):
##   - Shots, every one (the enemies' too): each projectile batch's rows drawn this frame
##     (`ProjectileManager.light_rows`, kept while `light_rows_wanted`), read as shots, or as runes
##     for a quad body's batch.
##   - Feel's flashes (flares, rings, casts, arcs, blasts): `light_flashes` hands over the buffers Feel
##     just uploaded. How much each lights is its kind's `room_light` (`FlashKind`; Feel writes it into
##     the row's transform, 0 for an unlit flash), fading out over its life.
##   - Live beams: `light_beam` hands over the path Feel just gave the beam's own shader; each is a band
##     of light along it, in its glow (the grid's `look_glow`, its own infusions alone).
##   The rows handed over are let go once the grid has read them (`follow`), so their owners write
##   them in place again.
## - **The cues' lights** (docs/milestones/spell-spectacle-2.md, S6 item 4): a cue's `light` part
##   (`flash`) lights round the cue's point for its seconds, fading; up to CUE_LIGHTS at once (a new one
##   takes the oldest's place). Their rows are this node's own, written each frame while one lasts
##   (`step_cues`). A cue with a light part lights by it alone: Feel codes its flashes' rows as unlit.
## - **The room's lights:** every node in the group `LightSpot.GROUP` (a torch's flame;
##   core/base/light_spot.gd) is a spot row, written only when a spot comes or goes. The light painted
##   into the art (the group `LightSpot.PAINTED`) is hidden while this node is in the tree, and shown
##   again when it leaves, so a torch lights once (S6, item 12).
## - **The room's lights take notice** (docs/milestones/atmosphere.md, E): their rows as drawn may be
##   moved each frame (`show_spots`, gameplay/feel/spot_stirs.gd); the rows as placed stay `spot_rows`
##   (what the bodies' shadows fall away from), and `spots_written` counts each new set.
## - **Carried lights** (docs/milestones/atmosphere.md, A): spot rows their owner writes each frame
##   (gameplay/feel/carried_lights.gd) and hands over (`light_carried`).
## - **Light blocked** (docs/milestones/atmosphere.md, C): every light but the shots' and runes'
##   (SHOTS_BLOCKED) is stopped by up to MAX_BLOCKERS boxes handed over by `set_blockers`.
## - **What draws by the light** (docs/milestones/atmosphere.md, B): every reader is handed the grid
##   (`read_by`: the lit-only motes, the mist; `buffer` is its texture).
## - **Applying it:** one rect over the whole world at `z` (Feel's LIGHT_Z), drawn by
##   `light_apply.gdshader`: what is under it, times the room's `ambient` (`set_ambient`, times its
##   `shade`) plus the light, cut into the steps `bands` sets (`set_bands`). Each room's own light may
##   lean toward its kind's light (`set_room_tints`).
## - **A grid a view** (connected biomes CB6): while the screen is split each view has a grid of its own
##   part of the world (`use_views`), side by side in the one texture. What reads the light by the screen
##   reads its own view's (`readers`, `view_readers.gd`: the first two views share an item told apart in
##   its shader, the third and fourth each draw a copy naming its view; `light_views.gdshaderinc`).
## - **At a fixed resolution** (#902): while the picture is `grid_scale` times PictureGrid.SIZE the apply
##   rect's factor and the mist's billows are worked out in a pass a view at PictureGrid.SIZE
##   (`factor_passes`, `under_passes`, gameplay/feel/light_passes.gd) and taken whole for each block.

const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ViewReadersScript := preload("res://gameplay/feel/view_readers.gd")
const UnseenMaskScript := preload("res://gameplay/feel/unseen_mask.gd")
const LightGridScript := preload("res://gameplay/feel/light_grid.gd")
const InfusionTableScript := preload("res://core/spells/infusion_table.gd")
const APPLY_SHADER: Shader = preload("res://gameplay/feel/light_apply.gdshader")
const FACTOR_SHADER: Shader = preload("res://gameplay/feel/light_factor.gdshader")
const PictureGridScript := preload("res://gameplay/feel/picture_grid.gd")
const LightPassesScript := preload("res://gameplay/feel/light_passes.gd")
## The grid's cell by default (world px each way; LightGrid.CELLS the choices).
const GRID_CELL: float = LightGridScript.CELL
## How much smaller than its view the split's cheaper light made a buffer once (SplitBudget's rungs
## still name it); the grid's cost is the CPU's, a view's share of it small, so it changes nothing now.
const DOWNSCALE: int = 4
## The apply rect reaches this far from the origin each way: past any room, so it always covers
## the view (the GPU only shades what is on screen).
const REACH: float = 65536.0
## How the rows read (LightGrid.ROWS_*).
const ROWS_SHOT: int = LightGridScript.ROWS_SHOT
const ROWS_RUNE: int = LightGridScript.ROWS_RUNE
const ROWS_FLASH: int = LightGridScript.ROWS_FLASH
const ROWS_SPOT: int = LightGridScript.ROWS_SPOT
const ROWS_CUE: int = LightGridScript.ROWS_CUE
## The most cue lights at once (`flash`).
const CUE_LIGHTS: int = 64
## The steps the light comes in by default (`light_apply.gdshader`'s `bands`): 3 (dim, lit,
## bright); 0 is smooth. The owner's choice between them is open (2026-11-04).
const DEFAULT_BANDS: int = 3
## From how bright a light (its brightest channel) the floor is lit, and bright: the apply rect's
## steps (`light_apply.gdshader`'s `lit_from`, `bright_from`), set from here. What else draws by the
## light takes its steps from the same numbers (`lit_steps`), so they stay in step when these are tuned.
const LIT_FROM: float = 0.16
const BRIGHT_FROM: float = 0.45
## A lit-only mote's faint first step, a share of LIT_FROM (`lit_steps`): just inside a pool's edge.
const FAINT_SHARE: float = 0.75
## A flash's light reaches this many times its square's half size, plus FLASH_PAD (px); an
## explosion's square is already BLAST_SPAN radii, so it reaches about that far.
const FLASH_REACH: float = 1.6
const BLAST_REACH: float = 1.0
const ARC_REACH: float = 1.0
const FLASH_PAD: float = 10.0
## The flash batches (`light_flashes`).
const FLASHES_FLARE: int = 0
const FLASHES_BLAST: int = 1
const FLASHES_ARC: int = 2
const FLASH_REACHES: PackedFloat32Array = [FLASH_REACH, BLAST_REACH, ARC_REACH]
## The most points a beam's path has (Feel's LIVE_BEAM_POINTS).
const BEAM_POINTS: int = 80
## How far a beam's light reaches each side of it (px), and how bright it is.
const BEAM_REACH: float = 24.0
const BEAM_STRENGTH: float = 0.8
## The most beams lit at once (Feel's live beams).
const BEAMS_MOST: int = 32
## The most views a grid each (`use_views`; ScreenViews.VIEWS_MOST).
const VIEWS_MOST: int = ViewReadersScript.VIEWS_MOST
## The uniforms of `light_grid.gdshaderinc`: the grid's texture, its cell, whether it is smoothed, and
## each view's grid (its first cell's corner and where it starts in the texture; its columns and rows).
const GRID_TEXTURE: StringName = &"light_grid"
const GRID_CELL_UNIFORM: StringName = &"light_grid_cell"
const GRID_SMOOTH: StringName = &"light_grid_smooth"
const GRID_VIEWS: Array[StringName] = [&"light_grid_view_0", &"light_grid_view_1", &"light_grid_view_2", &"light_grid_view_3"]
const GRID_SIZES: Array[StringName] = [&"light_grid_size_0", &"light_grid_size_1", &"light_grid_size_2", &"light_grid_size_3"]
## The uniforms of `light_passes.gdshaderinc` that hold a view's pass (the first view's and every copy's
## own, `ViewReaders.set_view_uniform`; the second view's), say which views have one and how much smaller
## they are.
const PASS_UNIFORMS: Array[StringName] = [&"light_pass_0", &"light_pass_1"]
const PASS_VIEWS: StringName = &"light_pass_views"
const PASS_SCALE: StringName = &"light_pass_scale"
## The apply rect's uniforms its factor passes' rects share (`light_apply.gdshaderinc`'s).
const APPLY_UNIFORMS: Array[StringName] = [&"ambient", &"shade", &"bands", &"lit_from", &"bright_from", &"tint_rects", &"tint_hues", &"tint_count"]
## Floats a light row holds (a 2D transform, a colour, custom data).
const STRIDE: int = LightGridScript.STRIDE
## Where a spot row (`write_spot_row`) holds its light's reach, its middle's x and y, and its strength.
const ROW_REACH: int = 0
const ROW_X: int = 3
const ROW_Y: int = 7
const SPOT_ROW_STRENGTH: int = 11
## Where a spot row holds where its light stands on the floor, from its middle (x, y).
const SPOT_ROW_GROUND: int = 14
## The most boxes that block light (LightBlockers.MAX).
const MAX_BLOCKERS: int = 32
## The most rooms whose own light the apply rect tints at once (`set_room_tints`; light_apply.gdshaderinc's
## MAX_TINTS): a biome's rooms at most (`MapRules.rooms_max` 32, and its start room).
const MAX_TINTS: int = 40
## Whether the shots' and runes' lights are blocked too. Not: there are thousands of them; a shot's
## light is small and moves on, its glow passes over a pillar as the shot itself is drawn over it.
## Flashes, cues, spots and carried lights are blocked.
const SHOTS_BLOCKED: bool = false

## The passes came or went (the picture's size crossed a whole multiple of PictureGrid.SIZE): what
## draws under the light at its resolution (`under_holder`) draws its pass again.
signal passes_changed

## The grid the light is worked out on, and the rect that applies it. Read only.
var grid: LightGridScript = LightGridScript.new()
var apply: ColorRect = null
## The room's light and the colour of its dark (`set_ambient`) and the steps (`set_bands`). Read only.
var ambient: float = 1.0
var shade: Color = Color.WHITE
var bands: int = DEFAULT_BANDS
## How many rooms' tints the apply rect reads (`set_room_tints`). Read only.
var tint_count: int = 0
## How many times bigger than PictureGrid.SIZE the picture is each way (PictureGrid.scale_of, at
## every draw). Read only.
var grid_scale: int = 1
## Whether the light keeps its resolution (PictureGrid.SIZE a view) in a bigger picture; false draws it
## at the picture's own (the benchmarks' A/B: `--light-at-picture`).
var fixed_resolution: bool = true
## The passes at the light's resolution while `grid_scale` is more than 1 (the picture at least twice
## PictureGrid.SIZE each way; null at 1): the apply rect's factor a view, with its rects (one a view,
## each on its view's layer), and what readers drawn under the light draw there (`under_holder`). Read only.
var factor_passes: LightPassesScript = null
var under_passes: LightPassesScript = null
var factor_rects: Array[ColorRect] = []
## Whether the grid is read smoothed between the cells' middles (`set_grid_smooth`), and how many times
## it was worked out (for tests). Read only.
var grid_smooth: bool = false
var grids_baked: int = 0
## How many times the spots' rows were written anew (`draw_spots`), for what moves them.
var spots_written: int = 0
## Where the spots are left out (`hide_unseen`; null: none).
var unseen: UnseenMaskScript = null
## What reads the light by the screen, drawn once a view (the apply rect and every item drawn with a
## reader's material; `view_readers.gd`). Read only.
var readers: ViewReadersScript = ViewReadersScript.new()
var _unseen_changes: int = -1
var _projectiles: ProjectileManagerScript = null
## The spots need writing again (one came or went), their rows as placed and how many, and the rows
## as moved this frame (`show_spots`; empty: as placed).
var _spots_dirty: bool = true
var _spot_buffer: PackedFloat32Array = PackedFloat32Array()
var _spot_count: int = 0
var _spot_shown: PackedFloat32Array = PackedFloat32Array()
## The rows handed over this frame, let go once read: the flashes' (by FLASHES_*) and the carried
## lights', and how many of each.
var _flash_rows: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
var _flash_count: PackedInt32Array = PackedInt32Array([0, 0, 0])
var _carried_rows: PackedFloat32Array = PackedFloat32Array()
var _carried_count: int = 0
## The live beams lit this frame (`light_beam`): each one's path, points, reach and colour, and how
## many; let go once read.
var _beam_paths: Array[PackedVector3Array] = []
var _beam_points: PackedInt32Array = PackedInt32Array()
var _beam_reach: PackedFloat32Array = PackedFloat32Array()
var _beam_colour: PackedColorArray = PackedColorArray()
var _beams_lit: int = 0
var _no_rows: PackedFloat32Array = PackedFloat32Array()
var _no_path: PackedVector3Array = PackedVector3Array()
## The views the grid covers while the screen is split (`use_views`; empty: the one picture), the
## materials that read the light by the screen besides the apply rect (`read_by`, by name), and each
## view's part of the world this frame (x0, y0, x1, y1).
var _views: Array[Viewport] = []
var _readers: Dictionary = {}
var _view_boxes: PackedVector4Array = PackedVector4Array()
## The grid's uniforms as last handed to the materials (set again only when they change).
var _grid_view_keys: PackedVector4Array = PackedVector4Array()
var _grid_size_keys: PackedVector4Array = PackedVector4Array()
var _tints_version: int = -1
## The grid's texture as last handed to the readers (made again when its atlas grows).
var _bound_texture: Texture2D = null
## Whether the equal split's void quarter is drawn as one view more (`use_views`).
var _void_view: bool = false
## A spot's colour by the texture it is read from (read once per texture).
var _art_colours: Dictionary = {}
## The cue lights, by slot (CUE_LIGHTS of them, the next one `_next_cue`): where, how far they reach,
## how bright, when they began and how long they last (0: none), and their row colour and core; and
## their rows, written while one lasts (`_cue_live` of them).
var _cue_at: PackedVector2Array = PackedVector2Array()
var _cue_reach: PackedFloat32Array = PackedFloat32Array()
var _cue_strength: PackedFloat32Array = PackedFloat32Array()
var _cue_from: PackedFloat32Array = PackedFloat32Array()
var _cue_seconds: PackedFloat32Array = PackedFloat32Array()
var _cue_data: PackedColorArray = PackedColorArray()
var _cue_core: PackedColorArray = PackedColorArray()
var _next_cue: int = 0
var _cue_live: int = 0
var _cue_buffer: PackedFloat32Array = PackedFloat32Array()
## Feel's clock as last told (`step_cues`): what the spots' flicker steps by.
var _now: float = 0.0


## Light for `projectiles`' shots (null: the flashes', cues', spots' and beams' only), applied at `z`.
func _init(projectiles: ProjectileManagerScript, z: int) -> void:
	_projectiles = projectiles
	if _projectiles != null:
		_projectiles.light_rows_wanted = true
	grid.set_cell(GRID_CELL)
	grid.use_native(true)
	_view_boxes.resize(VIEWS_MOST)
	_grid_view_keys.resize(VIEWS_MOST)
	_grid_size_keys.resize(VIEWS_MOST)
	_grid_size_keys.fill(Vector4(-1.0, -1.0, -1.0, -1.0))
	_beam_paths.resize(BEAMS_MOST)
	_beam_paths.fill(_no_path)
	_beam_points.resize(BEAMS_MOST)
	_beam_reach.resize(BEAMS_MOST)
	_beam_colour.resize(BEAMS_MOST)
	_cue_at.resize(CUE_LIGHTS)
	_cue_reach.resize(CUE_LIGHTS)
	_cue_strength.resize(CUE_LIGHTS)
	_cue_from.resize(CUE_LIGHTS)
	_cue_seconds.resize(CUE_LIGHTS)
	_cue_data.resize(CUE_LIGHTS)
	_cue_core.resize(CUE_LIGHTS)
	_cue_buffer.resize(CUE_LIGHTS * STRIDE)
	apply = ColorRect.new()
	apply.name = "LightApply"
	apply.top_level = true
	apply.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apply.position = Vector2(-REACH, -REACH)
	apply.size = Vector2(REACH, REACH) * 2.0
	apply.z_index = z
	var material := ShaderMaterial.new()
	material.shader = APPLY_SHADER
	material.set_shader_parameter(&"bands", bands)
	material.set_shader_parameter(&"lit_from", LIT_FROM)
	material.set_shader_parameter(&"bright_from", BRIGHT_FROM)
	apply.material = material
	add_child(apply)
	_bind(material)
	readers.watch(material, null)
	readers.take(apply)


## The boxes that stop light from now on (docs/milestones/atmosphere.md, C): `count` of `boxes`
## (each base: x0, y0, x1, y1, world px) and `bodies` (the column over each: x0, top, x1, and how much
## it blocks, 0 to 1), at most MAX_BLOCKERS; every light but the shots' is stopped by them.
func set_blockers(boxes: PackedVector4Array, bodies: PackedVector4Array, count: int) -> void:
	grid.set_blockers(boxes, bodies, count)


## How many boxes block light (for tests).
func blocker_count() -> int:
	return grid.blocker_count


func _enter_tree() -> void:
	if not RenderingServer.frame_pre_draw.is_connected(follow):
		RenderingServer.frame_pre_draw.connect(follow)
	var tree: SceneTree = get_tree()
	if not tree.node_added.is_connected(_on_node_changed):
		tree.node_added.connect(_on_node_changed)
		tree.node_removed.connect(_on_node_changed)
		tree.node_added.connect(readers.take)
		tree.node_removed.connect(readers.release)
	_spots_dirty = true
	_show_painted(tree, false)
	readers.watch(apply.material, tree)
	for key: StringName in _readers:
		readers.watch(_readers[key] as ShaderMaterial, tree)
	_use_readers()


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(follow):
		RenderingServer.frame_pre_draw.disconnect(follow)
	var tree: SceneTree = get_tree()
	if tree.node_added.is_connected(_on_node_changed):
		tree.node_added.disconnect(_on_node_changed)
		tree.node_removed.disconnect(_on_node_changed)
		tree.node_added.disconnect(readers.take)
		tree.node_removed.disconnect(readers.release)
	_show_painted(tree, true)
	# The copies a view go with the light (made again, as they are needed, when it comes back).
	readers.clear()


func _on_node_changed(node: Node) -> void:
	if node.is_in_group(LightSpot.GROUP):
		_spots_dirty = true
	elif node.is_in_group(LightSpot.PAINTED) and node.is_inside_tree():
		# A torch come into the room while the light is on: its painted glow is the spot's now.
		_show_painted_node(node, false)


## Show or hide the light painted into the room's art (every node in `LightSpot.PAINTED`).
func _show_painted(tree: SceneTree, shown: bool) -> void:
	for node: Node in tree.get_nodes_in_group(LightSpot.PAINTED):
		_show_painted_node(node, shown)


func _show_painted_node(node: Node, shown: bool) -> void:
	var item := node as CanvasItem
	if item != null:
		item.visible = shown


## Stop reading the projectile manager's rows (before this node is freed: the setting turned off).
func release() -> void:
	if _projectiles == null:
		return
	_projectiles.light_rows_wanted = false
	_projectiles = null


## Just before every draw, after the camera has moved: the spots written again if one came or went,
## each reader's copies a view following it (`readers`), the passes at the light's resolution fitted
## to the views, and the grid worked out over each view's part of the world from every light handed
## over this frame (`_light_grid`), then handed to every reader.
func follow() -> void:
	if _spots_dirty and is_inside_tree():
		draw_spots()
	var root: Viewport = get_viewport()
	if root != null:
		var by: int = PictureGridScript.scale_of(root.get_visible_rect().size) if fixed_resolution else 1
		if by != grid_scale:
			_use_scale(by)
	var count: int = 0
	if _views.is_empty():
		if root != null:
			_view_boxes[0] = _world_box(root)
			_fit_passes(0, root)
			count = 1
	else:
		for k in _views.size():
			var shown: Viewport = _views[k]
			if shown == null or not is_instance_valid(shown):
				break
			_view_boxes[k] = _world_box(shown)
			_fit_passes(k, shown)
			count += 1
	_light_grid(count)
	# After the grid is handed over: the copies a view take this frame's grid, not last frame's.
	readers.follow(_views)


## The part of the world `view` shows (x0, y0, x1, y1).
static func _world_box(view: Viewport) -> Vector4:
	var to_world: Transform2D = (view.global_canvas_transform * view.canvas_transform).affine_inverse()
	var shown: Rect2 = to_world * view.get_visible_rect()
	return Vector4(shown.position.x, shown.position.y, shown.end.x, shown.end.y)


## The grid over the first `count` views' boxes, worked out from every light handed over this frame,
## baked into its texture and handed to the readers; the rows handed over let go.
func _light_grid(count: int) -> void:
	if InfusionTableScript.published_version != _tints_version:
		_tints_version = InfusionTableScript.published_version
		grid.use_tints(InfusionTableScript.published)
	grid.fit(_view_boxes, count)
	if grid.texture != _bound_texture:
		# The atlas grew: a texture of its new size.
		_bound_texture = grid.texture
		_each_reader(GRID_TEXTURE, grid.texture)
	grid.clear()
	if _projectiles != null:
		for batch in _projectiles.batch_count():
			var rows: PackedFloat32Array = _projectiles.light_rows(batch)
			var drawn: int = _projectiles.light_count(batch)
			if drawn > 0:
				var kind: int = ROWS_RUNE if _projectiles.batch_mesh(batch) == ProjectileManagerScript.MESH_QUAD else ROWS_SHOT
				grid.add_rows(rows, drawn, kind, 1.0, 0.0, _now, SHOTS_BLOCKED)
	for kind in FLASH_REACHES.size():
		if _flash_count[kind] > 0:
			grid.add_rows(_flash_rows[kind], _flash_count[kind], ROWS_FLASH, FLASH_REACHES[kind], FLASH_PAD, _now, true)
		_flash_rows[kind] = _no_rows
		_flash_count[kind] = 0
	if _cue_live > 0:
		grid.add_rows(_cue_buffer, _cue_live, ROWS_CUE, 1.0, 0.0, _now, true)
	if _spot_count > 0:
		var spots: PackedFloat32Array = _spot_shown if _spot_shown.size() == _spot_count * STRIDE else _spot_buffer
		grid.add_rows(spots, _spot_count, ROWS_SPOT, 1.0, 0.0, _now, true)
	_spot_shown = _no_rows
	if _carried_count > 0:
		grid.add_rows(_carried_rows, _carried_count, ROWS_SPOT, 1.0, 0.0, _now, true)
	_carried_rows = _no_rows
	_carried_count = 0
	for i in _beams_lit:
		grid.add_beam(_beam_paths[i], _beam_points[i], _beam_reach[i], _beam_colour[i])
		_beam_paths[i] = _no_path
	_beams_lit = 0
	grid.bake()
	grids_baked += 1
	_hand_grid_views()


## Each view's grid handed to every reader where it changed.
func _hand_grid_views() -> void:
	for k in VIEWS_MOST:
		var at := Vector4.ZERO
		var size := Vector4.ZERO
		if k < grid.view_count:
			at = Vector4(grid.view_origin[k * 2], grid.view_origin[k * 2 + 1], grid.view_at[k * 2], grid.view_at[k * 2 + 1])
			size = Vector4(grid.view_size[k * 2], grid.view_size[k * 2 + 1], 0.0, 0.0)
		if at == _grid_view_keys[k] and size == _grid_size_keys[k]:
			continue
		_grid_view_keys[k] = at
		_grid_size_keys[k] = size
		_each_reader(GRID_VIEWS[k], at)
		_each_reader(GRID_SIZES[k], size)


## `uniform` set to `value` on every material that reads the light (the apply rect's, its factor rects',
## the readers').
func _each_reader(uniform: StringName, value: Variant) -> void:
	_set_apply(uniform, value)
	for key: StringName in _readers:
		(_readers[key] as ShaderMaterial).set_shader_parameter(uniform, value)


## The grid's cell from now on (world px each way; LightGrid.CELLS the choices: a coarser grid is
## cheaper and blockier).
func set_grid_cell(size: float) -> void:
	grid.set_cell(size)
	_each_reader(GRID_CELL_UNIFORM, grid.cell)


## Whether the readers smooth the grid between its cells' middles (the bands then follow the world's
## pixels, still in hard steps) or take each cell whole (blockier).
func set_grid_smooth(on: bool) -> void:
	grid_smooth = on
	_each_reader(GRID_SMOOTH, on)


## View `k`'s passes fitted to `view` (while there are passes).
func _fit_passes(k: int, view: Viewport) -> void:
	if factor_passes == null or k >= factor_passes.count:
		return
	factor_passes.fit(k, view)
	under_passes.fit(k, view)
	# The pass under the light is drawn only while something is drawn in it (a mist's twin).
	var wanted: int = SubViewport.UPDATE_ALWAYS if under_passes.holder().get_child_count() > 0 else SubViewport.UPDATE_DISABLED
	if under_passes.viewports[k].render_target_update_mode != wanted:
		under_passes.viewports[k].render_target_update_mode = wanted


## The views the light follows from now on, a grid each (`views`, in the order the split screen lays
## them out, at most VIEWS_MOST; empty: the one picture, this node's viewport). The split's cheaper
## light once (its downscale) changes nothing now (DOWNSCALE). `void_view`: the equal split's void
## quarter is drawn too, one view more than `views` (no grid: no light), with its own copy of each
## reader (`readers`, `ViewReaders.use`).
func use_views(views: Array[Viewport], _extra_downscale: int = DOWNSCALE, void_view: bool = false) -> void:
	_void_view = void_view
	if views.size() == _views.size():
		var same: bool = true
		for k in views.size():
			same = same and views[k] == _views[k]
		if same:
			# A reader come since (a motes chunk made in a fight) gets its copies.
			_use_readers()
			return
	_views = views.slice(0, VIEWS_MOST)
	_use_passes()
	_use_readers()
	follow()


## The passes at the light's resolution for a picture `by` times PictureGrid.SIZE: made past 1, freed
## at 1; every reader handed them.
func _use_scale(by: int) -> void:
	grid_scale = maxi(by, 1)
	if grid_scale > 1 and factor_passes == null:
		factor_passes = LightPassesScript.new("LightFactor")
		add_child(factor_passes)
		under_passes = LightPassesScript.new("LightUnder")
		add_child(under_passes)
	elif grid_scale == 1 and factor_passes != null:
		for passes: LightPassesScript in [factor_passes, under_passes]:
			remove_child(passes)
			passes.queue_free()
		factor_passes = null
		under_passes = null
		factor_rects.clear()
	_use_passes()
	passes_changed.emit()


## A pass a view (while there are passes; the equal split's void quarter has none), each view's factor
## rect reading its own view's grid; the passes drawn before their view, and every reader handed them.
func _use_passes() -> void:
	var count: int = maxi(_views.size(), 1)
	if factor_passes != null:
		factor_passes.use(count, grid_scale)
		under_passes.use(count, grid_scale)
		while factor_rects.size() < count:
			factor_rects.append(_factor_rect(factor_rects.size()))
		for k in factor_rects.size():
			factor_rects[k].visible = k < count
		# Each pass is drawn before the view that reads it (Godot draws a viewport's children first):
		# made after the views, it would be read a frame late.
		for k in count:
			var reader: Viewport = _views[k] if k < _views.size() and is_instance_valid(_views[k]) else get_viewport()
			if reader != null:
				factor_passes.draw_before(k, reader)
				under_passes.draw_before(k, reader)
	_bind(apply.material as ShaderMaterial)
	for key: StringName in _readers:
		_bind(_readers[key] as ShaderMaterial)


## View `k`'s factor rect: over the world in its factor pass, on that view's layer alone, drawn with the
## apply rect's numbers (`APPLY_UNIFORMS` and the grid's, kept the same by `_set_apply`) and reading
## view `k`'s grid.
func _factor_rect(k: int) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = "Factor%d" % k
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.position = Vector2(-REACH, -REACH)
	rect.size = Vector2(REACH, REACH) * 2.0
	rect.visibility_layer = LightPassesScript.view_layer(k)
	var material := ShaderMaterial.new()
	material.shader = FACTOR_SHADER
	var from := apply.material as ShaderMaterial
	for uniform: StringName in APPLY_UNIFORMS:
		material.set_shader_parameter(uniform, from.get_shader_parameter(uniform))
	for uniform: StringName in [GRID_TEXTURE, GRID_CELL_UNIFORM, GRID_SMOOTH] + GRID_VIEWS + GRID_SIZES:
		material.set_shader_parameter(uniform, from.get_shader_parameter(uniform))
	material.set_shader_parameter(&"light_grid_view_id", k)
	rect.material = material
	factor_passes.holder().add_child(rect)
	return rect


## Where what reads the light under it draws its pass at the light's resolution (the mist's billows: an
## item under it is drawn in every view's pass, and read back by the reader through `read_by`); null
## while there are no passes (the picture at PictureGrid.SIZE).
func under_holder() -> Node:
	return under_passes.holder() if under_passes != null else null


## The apply rect's uniform `uniform` set to `value`, on its factor rects too.
func _set_apply(uniform: StringName, value: Variant) -> void:
	(apply.material as ShaderMaterial).set_shader_parameter(uniform, value)
	for rect in factor_rects:
		(rect.material as ShaderMaterial).set_shader_parameter(uniform, value)


## The readers drawn in each view for the views now (and the void quarter's).
func _use_readers() -> void:
	readers.use(_views.size() + (1 if _void_view and _views.size() > 1 else 0))


## How many views the light follows (0: the one picture).
func view_count() -> int:
	return _views.size()


## `material` reads the light by the screen as the apply rect does (`light_views.gdshaderinc`,
## `light_grid.gdshaderinc`): it is given the grid and each view's transform from now on, under `key`
## (one a reader: the motes', the mist's; a new one under a key takes the old one's place; null: none).
func read_by(key: StringName, material: ShaderMaterial) -> void:
	var before: ShaderMaterial = _readers.get(key) as ShaderMaterial
	if before != null and before != material:
		readers.forget(before)
	if material == null:
		_readers.erase(key)
		return
	_readers[key] = material
	_bind(material)
	readers.watch(material, get_tree() if is_inside_tree() else null)
	_use_readers()


## The grid on `material` (its texture, cell, smoothing and every view's grid), and its passes at the
## light's resolution (the apply rect's factor passes, the others' `under_passes`; none at PictureGrid.SIZE).
func _bind(material: ShaderMaterial) -> void:
	material.set_shader_parameter(GRID_TEXTURE, grid.texture)
	material.set_shader_parameter(GRID_CELL_UNIFORM, grid.cell)
	material.set_shader_parameter(GRID_SMOOTH, grid_smooth)
	for k in VIEWS_MOST:
		material.set_shader_parameter(GRID_VIEWS[k], _grid_view_keys[k])
		material.set_shader_parameter(GRID_SIZES[k], _grid_size_keys[k] if _grid_size_keys[k].x >= 0.0 else Vector4.ZERO)
	var passes: LightPassesScript = factor_passes if material == apply.material else under_passes
	var count: int = passes.count if passes != null else 0
	for k in VIEWS_MOST:
		var drawn: Texture2D = passes.texture(k) if k < count else null
		if k < PASS_UNIFORMS.size():
			material.set_shader_parameter(PASS_UNIFORMS[k], drawn)
		else:
			# The third and fourth views' copies hold their own pass where the first view's is.
			readers.set_view_uniform(material, k, PASS_UNIFORMS[0], drawn)
	material.set_shader_parameter(PASS_VIEWS, (1 << count) - 1)
	material.set_shader_parameter(PASS_SCALE, grid_scale)


## The grid's texture (the light round everything this frame, by view), for what draws by the light:
## handed over, nothing asked of them.
func buffer() -> Texture2D:
	return grid.texture


## The light's brightest channel from which a lit-only mote (`MoteKind.lit_only`) shows in its
## shadow, base, light and white-hot shade: faint just inside where the floor is lit (FAINT_SHARE of
## LIT_FROM), then at LIT_FROM, halfway to BRIGHT_FROM and at BRIGHT_FROM, the apply rect's steps.
static func lit_steps() -> Vector4:
	return Vector4(LIT_FROM * FAINT_SHARE, LIT_FROM, (LIT_FROM + BRIGHT_FROM) * 0.5, BRIGHT_FROM)


## The room's light where nothing lights it (`RoomBase.ambient`; 1.0 the room as it is), and the
## colour of its dark (`RoomBase.shade`; white an even dark).
func set_ambient(to: float, dark: Color = Color.WHITE) -> void:
	ambient = clampf(to, 0.0, 1.0)
	shade = Color(clampf(dark.r, 0.0, 1.0), clampf(dark.g, 0.0, 1.0), clampf(dark.b, 0.0, 1.0))
	_set_apply(&"ambient", ambient)
	_set_apply(&"shade", Vector3(shade.r, shade.g, shade.b))


## Each room's own light tinted by its kind (connected biomes CB12b, gameplay/feel/room_tints.gd):
## `count` rooms of `rects` (each a world rectangle: x0, y0, x1, y1) and `tints` (each the hue its
## light leans toward, and how far), MAX_TINTS long each; a world pixel in a room's rectangle has its
## dark and the light on it lean toward its hue (`light_apply.gdshader`). This node knows nothing of
## rooms. Set only when a tint changes.
func set_room_tints(rects: PackedVector4Array, tints: PackedVector4Array, count: int) -> void:
	tint_count = clampi(count, 0, mini(MAX_TINTS, mini(rects.size(), tints.size())))
	_set_apply(&"tint_rects", rects)
	_set_apply(&"tint_hues", tints)
	_set_apply(&"tint_count", tint_count)


## The carried lights this frame: `count` spot rows (ROWS_SPOT, STRIDE floats each) of `rows`, read at
## the next draw and let go then.
func light_carried(rows: PackedFloat32Array, count: int) -> void:
	_carried_rows = rows
	_carried_count = clampi(count, 0, rows.size() / STRIDE)


## How many carried lights are lit this frame (for tests).
func carried_count() -> int:
	return _carried_count


## The steps the light comes in: 0 smooth, 2 or more that many (dim counted); DEFAULT_BANDS 3.
func set_bands(to: int) -> void:
	bands = 0 if to <= 0 else maxi(to, 2)
	_set_apply(&"bands", bands)


## Feel's flash rows, just uploaded: the flares' (`flares` rows of `flare_rows`), the explosions'
## and the arcs', each buffer `slots` rows long. Read at the next draw and let go then.
func light_flashes(flare_rows: PackedFloat32Array, flares: int, blast_rows: PackedFloat32Array, blasts: int, arc_rows: PackedFloat32Array, arcs: int, slots: int) -> void:
	_take_flashes(FLASHES_FLARE, flare_rows, flares, slots)
	_take_flashes(FLASHES_BLAST, blast_rows, blasts, slots)
	_take_flashes(FLASHES_ARC, arc_rows, arcs, slots)


func _take_flashes(kind: int, rows: PackedFloat32Array, count: int, slots: int) -> void:
	var lit: bool = count > 0 and rows.size() >= slots * STRIDE
	_flash_rows[kind] = rows if lit else _no_rows
	_flash_count[kind] = mini(count, rows.size() / STRIDE) if lit else 0


## How many of flash batch `kind`'s rows (FLASHES_*) light this frame, and those rows, until the next
## draw reads them (for tests).
func flash_count(kind: int) -> int:
	return _flash_count[kind]


func flash_rows(kind: int) -> PackedFloat32Array:
	return _flash_rows[kind]


## The cue lights' rows (`cue_light_count` of them) and the carried lights' this frame (for tests).
func cue_rows() -> PackedFloat32Array:
	return _cue_buffer


func carried_rows() -> PackedFloat32Array:
	return _carried_rows


## Lit beam `i`'s path, reach and colour this frame, until the next draw reads them (for tests).
func beam_path(i: int) -> PackedVector3Array:
	return _beam_paths[i]


func beam_reach(i: int) -> float:
	return _beam_reach[i]


func beam_colour(i: int) -> Color:
	return _beam_colour[i]


## A cue's light (its `light` part): round `at`, reaching `reach` pixels, `strength` bright at
## first and fading to nothing over `seconds`, from the clock time `now` (the spectacle's), in the
## colour of a flash row in the ramp `ramp` with the cards `look` and the core `core` (`look`
## with Feel's EXACT: `core` exactly). Takes the oldest light's place when all are lit.
func flash(at: Vector2, reach: float, strength: float, seconds: float, core: Color, ramp: int, look: int, now: float) -> void:
	if reach <= 0.0 or strength <= 0.0 or seconds <= 0.0 or not at.is_finite():
		return
	var slot: int = _next_cue
	_next_cue = (_next_cue + 1) % CUE_LIGHTS
	_cue_at[slot] = at
	_cue_reach[slot] = reach
	_cue_strength[slot] = strength
	_cue_from[slot] = now
	_cue_seconds[slot] = seconds
	_cue_data[slot] = ProjectileManagerScript.look_color(ramp, 1, look)
	_cue_core[slot] = core
	_cue_live = CUE_LIGHTS


## The cue lights' rows at the clock time `now`, each fading over its seconds; one past its seconds
## goes out. Also the clock the spots' flicker steps by.
func step_cues(now: float) -> void:
	_now = now
	if _cue_live == 0:
		return
	var out: int = 0
	for slot in CUE_LIGHTS:
		if _cue_seconds[slot] <= 0.0:
			continue
		var through: float = (now - _cue_from[slot]) / _cue_seconds[slot]
		if through >= 1.0:
			_cue_seconds[slot] = 0.0
			continue
		var i: int = out * STRIDE
		var reach: float = _cue_reach[slot]
		var at: Vector2 = _cue_at[slot]
		_cue_buffer[i] = reach
		_cue_buffer[i + 1] = 0.0
		_cue_buffer[i + 2] = 0.0
		_cue_buffer[i + 3] = at.x
		_cue_buffer[i + 4] = 0.0
		_cue_buffer[i + 5] = reach
		_cue_buffer[i + 6] = 0.0
		_cue_buffer[i + 7] = at.y
		var data: Color = _cue_data[slot]
		_cue_buffer[i + 8] = data.r
		_cue_buffer[i + 9] = data.g
		_cue_buffer[i + 10] = data.b
		_cue_buffer[i + 11] = data.a
		var core: Color = _cue_core[slot]
		_cue_buffer[i + 12] = core.r
		_cue_buffer[i + 13] = core.g
		_cue_buffer[i + 14] = core.b
		_cue_buffer[i + 15] = _cue_strength[slot] * (1.0 - maxf(through, 0.0))
		out += 1
	_cue_live = out


## How many cue lights are lit (for tests).
func cue_light_count() -> int:
	return _cue_live


## Before Feel draws its live beams: none lit until `light_beam` lights one this frame.
func light_beams_begin() -> void:
	for i in _beams_lit:
		_beam_paths[i] = _no_path
	_beams_lit = 0


## Live beam `i`'s light along the path Feel just gave its shader: `points` of `path` (x, y, how
## far along), in the ramp `player` (shot_beam's `beam_player`), its look and core colour, faded
## by `fade`; BEAM_STRENGTH times `intensity` bright and BEAM_REACH times `reach` wide (its card's
## `look_light_intensity` and `look_light_reach`; docs/milestones/card-looks.md, phase 1b). Read at the
## next draw and let go then.
func light_beam(_i: int, path: PackedVector3Array, points: int, player: int, look: int, core: Color, fade: float, intensity: float = 1.0, reach: float = 1.0) -> void:
	if _beams_lit >= BEAMS_MOST:
		return
	var who: int = LightGridScript.ENEMY_PLAYER if player < 0 else mini(player, 3)
	var glow: Vector3 = grid.look_glow(core.r, core.g, core.b, who, look & 255, (look >> 8) & 255, (look >> 16) & 255, true)
	var strength: float = BEAM_STRENGTH * intensity * fade
	_beam_paths[_beams_lit] = path
	_beam_points[_beams_lit] = mini(points, BEAM_POINTS)
	_beam_reach[_beams_lit] = BEAM_REACH * reach
	_beam_colour[_beams_lit] = Color(glow.x * strength, glow.y * strength, glow.z * strength)
	_beams_lit += 1


## How many beams light this frame (for tests).
func beams_lit() -> int:
	return _beams_lit


## The spots left out where `mask` hides (null: none), written again when it changes.
func hide_unseen(mask: UnseenMaskScript) -> void:
	var changes: int = mask.changes if mask != null else -1
	if mask == unseen and changes == _unseen_changes:
		return
	unseen = mask
	_unseen_changes = changes
	_spots_dirty = true


## Write the room's light spots (every node in `LightSpot.GROUP` in the tree, but where `unseen`
## hides) as spot rows: done when one comes or goes or the mask changes (`follow`), not every frame.
func draw_spots() -> void:
	_spots_dirty = false
	var found: Array[Node] = get_tree().get_nodes_in_group(LightSpot.GROUP)
	var at: int = 0
	_spot_buffer.resize(found.size() * STRIDE)
	for node in found:
		var spot := node as Node2D
		if spot == null or not spot.is_inside_tree() or spot.is_queued_for_deletion():
			continue
		var where: Vector2 = spot.global_position
		if unseen != null and unseen.hides(where):
			continue
		var reach: float = LightSpot.reach_of(spot)
		var colour: Color = _colour_of(spot)
		# A seed from where it is, so two torches flicker out of step and a run is the same.
		var seed: float = fposmod(where.x * 0.137 + where.y * 0.311, 1.0)
		write_spot_row(_spot_buffer, at, where, reach, colour, LightSpot.strength_of(spot), LightSpot.flicker_of(spot), seed)
		at += 1
	_spot_buffer.resize(at * STRIDE)
	_spot_count = at
	spots_written += 1


## Write row `at` of `buffer` (STRIDE floats a row) as a spot row (ROWS_SPOT): a light at `where`
## reaching `reach` px, in `colour`, `strength` bright at its middle, its strength dropping by up to
## `flicker` a step a few times a second from `seed` (0 to 1), standing on the floor `ground` from
## `where` (zero: right there; a carried light over its body's feet), which is what blocking goes by
## (docs/milestones/atmosphere.md, C). The rows' one writer: the room's spots and the carried lights.
static func write_spot_row(buffer: PackedFloat32Array, at: int, where: Vector2, reach: float, colour: Color, strength: float, flicker: float, seed: float, ground: Vector2 = Vector2.ZERO) -> void:
	var i: int = at * STRIDE
	buffer[i] = reach
	buffer[i + 1] = 0.0
	buffer[i + 2] = 0.0
	buffer[i + 3] = where.x
	buffer[i + 4] = 0.0
	buffer[i + 5] = reach
	buffer[i + 6] = 0.0
	buffer[i + 7] = where.y
	buffer[i + 8] = colour.r
	buffer[i + 9] = colour.g
	buffer[i + 10] = colour.b
	buffer[i + 11] = clampf(strength, 0.0, 1.0)
	buffer[i + 12] = clampf(flicker, 0.0, 1.0)
	buffer[i + 13] = seed
	buffer[i + 14] = ground.x
	buffer[i + 15] = ground.y


## Spot row `at` of `buffer` (as `write_spot_row` wrote it) moved by the world's stirs: its middle
## leaned `lean` px (where it stands on the floor kept, so what blocks it stays), and its strength
## `duck` (0 to 1) less, a share of `strength`, the row's as written.
static func move_spot_row(buffer: PackedFloat32Array, at: int, lean: Vector2, duck: float, strength: float) -> void:
	var i: int = at * STRIDE
	buffer[i + ROW_X] += lean.x
	buffer[i + ROW_Y] += lean.y
	buffer[i + SPOT_ROW_STRENGTH] = clampf(strength * (1.0 - clampf(duck, 0.0, 1.0)), 0.0, 1.0)
	buffer[i + SPOT_ROW_GROUND] -= lean.x
	buffer[i + SPOT_ROW_GROUND + 1] -= lean.y


## Light the room's spots by `rows` this frame (`spot_count` rows in `spot_rows`' layout: those rows
## moved, `spot_stirs.gd`), or by the rows as placed with `rows` empty. Read at the next draw.
func show_spots(rows: PackedFloat32Array) -> void:
	_spot_shown = rows if rows.size() == _spot_count * STRIDE else _no_rows


## The rows the room's spots light by this frame (the moved rows `show_spots` was handed, else the rows
## as placed), until the next draw reads them (for tests).
func spot_rows_shown() -> PackedFloat32Array:
	return _spot_shown if _spot_shown.size() == _spot_count * STRIDE and _spot_count > 0 else _spot_buffer


## The room's spots' rows (`spot_count` of them; ROWS_SPOT, `write_spot_row`) as placed, read only:
## what the bodies' shadows fall away from.
func spot_rows() -> PackedFloat32Array:
	return _spot_buffer


## How many spots are lit (also how many rows of `spot_rows` are).
func spot_count() -> int:
	return _spot_count


func _colour_of(spot: Node) -> Color:
	if spot.has_meta(LightSpot.TINT):
		return LightSpot.colour_of(spot)
	var art: Texture2D = LightSpot.art_of(spot)
	if art == null:
		return Color.WHITE
	if not _art_colours.has(art):
		_art_colours[art] = LightSpot.colour_of(spot)
	return _art_colours[art]
