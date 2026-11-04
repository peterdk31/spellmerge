extends Node
## Spell light (docs/milestones/spell-spectacle.md, P3a, P3b): shots, effects, beams and the
## room's own lights light the floor, the walls and the bodies round them. A child of the
## spectacle (gameplay/feel/spectacle.gd, under Feel), made only while the "Spell light" setting is on (`SpellLightSetting`, `spell_light_changed`); with
## it off none of these nodes exist.
##
## - **The light buffer:** a SubViewport a DOWNSCALE-th of the view each way, cleared to black
##   every frame, its canvas transform the main view's scaled down (`follow`, before every draw),
##   so it sees the same part of the world. Everything below draws one soft light per row into it
##   with `light.gdshader` (ROWS_* say how its rows read) or `light_beam.gdshader`.
## - **Rows are never written twice:** the lights draw the rows their owners already upload.
##   - Shots, every one (the enemies' too): one batch per projectile batch, its MultiMesh
##     mirroring the batch (`ProjectileManager.mirror_batch`): each frame it is handed the buffer
##     the batch uploads, with a quad of its own (the batch's MultiMesh is not shared: it holds
##     the trails' mesh, hundreds of quads a shot, drawn or folded; DECISIONS, 2026-11-02).
##   - Feel's effects (flares, rings, casts, arcs, blasts): `light_effects` hands over the buffers
##     Feel just uploaded (Feel calls the spectacle's, which calls this). How much each effect kind lights is EFFECT_LIGHT and BLAST_LIGHT (data
##     here, by Feel's KIND_* codes; a test names each one), fading out over its life.
##   - Live beams: `light_beam` hands over the path Feel just gave the beam's own shader; each is
##     a band of light along it.
## - **The room's lights:** every node in the group `LightSpot.GROUP` (a torch's flame;
##   core/base/light_spot.gd: its reach, strength, flicker and the art its colour is read from, as
##   metadata) is a row of one batch, written only when a spot comes or goes.
## - **Applying it:** one rect over the whole world at `z` (Feel's LIGHT_Z: above the room and the
##   bodies, under the motes, beams, flashes, telegraphs and shots), drawn by
##   `light_apply.gdshader`: what is under it, times the room's `ambient` (`RoomBase.ambient`,
##   `set_ambient`) plus the light, cut into the steps `bands` sets (`set_bands`: 3 steps by
##   default, 0 smooth).

const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const BatchesScript := preload("res://core/projectiles/batches.gd")
const LIGHT_SHADER: Shader = preload("res://gameplay/feel/light.gdshader")
const APPLY_SHADER: Shader = preload("res://gameplay/feel/light_apply.gdshader")
const BEAM_SHADER: Shader = preload("res://gameplay/feel/light_beam.gdshader")
## The light buffer is this many times smaller than the view each way (a quarter: 160 x 90 for
## the game's 640 x 360).
const DOWNSCALE: int = 4
## The apply rect reaches this far from the origin each way: past any room, so it always covers
## the view (the GPU only shades what is on screen).
const REACH: float = 65536.0
## How `light.gdshader` reads a batch's rows (its ROWS_*).
const ROWS_TRAIL: int = 0
const ROWS_RUNE: int = 1
const ROWS_EFFECT: int = 2
const ROWS_SPOT: int = 3
## The steps the light comes in by default (`light_apply.gdshader`'s `bands`): 3 (dim, lit,
## bright); 0 is smooth. The owner's choice between them is open (2026-11-04).
const DEFAULT_BANDS: int = 3
## How much each effect kind lights at its start (0: none), by Feel's KIND_* (its code in the
## effect rows); `test_light.gd` names each. Flashes and bursts light; a dash, chips and a
## status mark do not.
const EFFECT_LIGHT: Dictionary = {
	4: 1.0,   # KIND_BURST: a shot's end
	5: 0.8,   # KIND_RING_OUT
	6: 0.6,   # KIND_RING_IN
	7: 0.9,   # KIND_RUNE_BURST
	8: 0.6,   # KIND_CAST: the flash at the staff
	11: 0.35, # KIND_SPRAY: a hit
	12: 0.45, # KIND_PUFF: a hit with no way, a kill, a reaction
	14: 0.9,  # KIND_ARC: lightning between two bodies
}
## The same for the explosions' parts, by their code (Feel's KIND_* less KIND_SHELL).
const BLAST_LIGHT: Dictionary = {
	0: 1.0, # KIND_SHELL: a blast's flash
	1: 1.0, # KIND_FIREBALL
}
## An effect's light reaches this many times its square's half size, plus EFFECT_PAD (px); an
## explosion's square is already BLAST_SPAN radii, so it reaches about that far.
const EFFECT_REACH: float = 1.6
const BLAST_REACH: float = 1.0
const ARC_REACH: float = 1.0
const EFFECT_PAD: float = 10.0
## The effect light batches (`effects`, `light_effects`).
const EFFECTS_FLARE: int = 0
const EFFECTS_BLAST: int = 1
const EFFECTS_ARC: int = 2
## The most points a beam's path has (Feel's LIVE_BEAM_POINTS, `light_beam.gdshader`'s BEAM_POINTS).
const BEAM_POINTS: int = 80
## How far a beam's light reaches each side of it (px), and how bright it is.
const BEAM_REACH: float = 24.0
const BEAM_STRENGTH: float = 0.8
## Floats a 2D MultiMesh row holds with colours and custom data.
const STRIDE: int = 16

## The light buffer, its shot batches (by BATCH_*), effect batches (EFFECTS_*), beams, the spots'
## batch and the rect that applies it. Read only.
var viewport: SubViewport = null
var batches: Array[MultiMeshInstance2D] = []
var effects: Array[MultiMeshInstance2D] = []
var beams: Array[MeshInstance2D] = []
var spots: MultiMeshInstance2D = null
var apply: ColorRect = null
## The room's light (`set_ambient`) and the steps (`set_bands`). Read only.
var ambient: float = 1.0
var bands: int = DEFAULT_BANDS
var _projectiles: ProjectileManagerScript = null
var _quad: QuadMesh = null
static var _beam_mesh: ArrayMesh = null
## The spots need redrawing (one came or went), and their rows.
var _spots_dirty: bool = true
var _spot_buffer: PackedFloat32Array = PackedFloat32Array()
## A spot's colour by the texture it is read from (read once per texture).
var _art_colours: Dictionary = {}


## Light for `projectiles`' shots (null: the buffer and the rect only), applied at `z`.
func _init(projectiles: ProjectileManagerScript, z: int) -> void:
	_projectiles = projectiles
	viewport = SubViewport.new()
	viewport.name = "LightBuffer"
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.size = Vector2i(1, 1)
	add_child(viewport)
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	for batch in ProjectileManagerScript.BATCHES:
		var rows: int = ROWS_RUNE if ProjectileManagerScript.BATCH_MESH[batch] < 0 else ROWS_TRAIL
		var node: MultiMeshInstance2D = _light_batch(rows)
		batches.append(node)
		if _projectiles != null:
			_projectiles.mirror_batch(batch, node.multimesh)
	for kind in [EFFECTS_FLARE, EFFECTS_BLAST, EFFECTS_ARC]:
		var node: MultiMeshInstance2D = _light_batch(ROWS_EFFECT)
		var material: ShaderMaterial = node.material as ShaderMaterial
		material.set_shader_parameter(&"kind_light", kind_lights(BLAST_LIGHT if kind == EFFECTS_BLAST else EFFECT_LIGHT))
		material.set_shader_parameter(&"effect_reach", [EFFECT_REACH, BLAST_REACH, ARC_REACH][kind])
		material.set_shader_parameter(&"effect_pad", EFFECT_PAD)
		effects.append(node)
	spots = _light_batch(ROWS_SPOT)
	spots.name = "Spots"
	apply = ColorRect.new()
	apply.name = "LightApply"
	apply.top_level = true
	apply.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apply.position = Vector2(-REACH, -REACH)
	apply.size = Vector2(REACH, REACH) * 2.0
	apply.z_index = z
	var shade := ShaderMaterial.new()
	shade.shader = APPLY_SHADER
	shade.set_shader_parameter(&"light_buffer", viewport.get_texture())
	shade.set_shader_parameter(&"bands", bands)
	apply.material = shade
	add_child(apply)


## A batch in the light buffer drawing `rows` (ROWS_*) with `light.gdshader`, empty.
func _light_batch(rows: int) -> MultiMeshInstance2D:
	var node := MultiMeshInstance2D.new()
	var multimesh: MultiMesh = BatchesScript.multimesh()
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _quad
	multimesh.instance_count = 0
	multimesh.visible_instance_count = 0
	node.multimesh = multimesh
	var material := ShaderMaterial.new()
	material.shader = LIGHT_SHADER
	material.set_shader_parameter(&"rows", rows)
	node.material = material
	viewport.add_child(node)
	return node


## `lights` (code -> light) as the shader's 16 kinds.
static func kind_lights(lights: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(16)
	for code: int in lights:
		out[code] = float(lights[code])
	return out


func _enter_tree() -> void:
	if not RenderingServer.frame_pre_draw.is_connected(follow):
		RenderingServer.frame_pre_draw.connect(follow)
	var tree: SceneTree = get_tree()
	if not tree.node_added.is_connected(_on_node_changed):
		tree.node_added.connect(_on_node_changed)
		tree.node_removed.connect(_on_node_changed)
	_spots_dirty = true


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(follow):
		RenderingServer.frame_pre_draw.disconnect(follow)
	var tree: SceneTree = get_tree()
	if tree.node_added.is_connected(_on_node_changed):
		tree.node_added.disconnect(_on_node_changed)
		tree.node_removed.disconnect(_on_node_changed)


func _on_node_changed(node: Node) -> void:
	if node.is_in_group(LightSpot.GROUP):
		_spots_dirty = true


## Stop mirroring the batches (before this node is freed: the setting turned off).
func release() -> void:
	if _projectiles == null:
		return
	for batch in batches.size():
		if _projectiles.batch_mirror(batch) == batches[batch].multimesh:
			_projectiles.mirror_batch(batch, null)
	_projectiles = null


## Fit the light buffer to the view: its size a DOWNSCALE-th of the view's, its canvas transform
## the view's scaled down, so a light lands under its shot; and redraw the spots if one came or
## went. Run just before every draw, after the camera has moved.
func follow() -> void:
	if _spots_dirty and is_inside_tree():
		draw_spots()
	var view: Viewport = get_viewport()
	if view == null:
		return
	var size: Vector2 = view.get_visible_rect().size
	var wanted := Vector2i(maxi(ceili(size.x / DOWNSCALE), 1), maxi(ceili(size.y / DOWNSCALE), 1))
	if viewport.size != wanted:
		viewport.size = wanted
	var scale := Vector2(float(wanted.x) / maxf(size.x, 1.0), float(wanted.y) / maxf(size.y, 1.0))
	viewport.canvas_transform = Transform2D(0.0, scale, 0.0, Vector2.ZERO) * view.global_canvas_transform * view.canvas_transform


## The room's light where nothing lights it (`RoomBase.ambient`; 1.0 the room as it is).
func set_ambient(to: float) -> void:
	ambient = clampf(to, 0.0, 1.0)
	(apply.material as ShaderMaterial).set_shader_parameter(&"ambient", ambient)


## The steps the light comes in: 0 smooth, 2 or more that many (dim counted); DEFAULT_BANDS 3.
func set_bands(to: int) -> void:
	bands = 0 if to <= 0 else maxi(to, 2)
	(apply.material as ShaderMaterial).set_shader_parameter(&"bands", bands)


## Feel's effect rows, just uploaded: the flares' (`flares` rows of `flare_rows`), the explosions'
## and the arcs', each buffer `slots` rows long. Their lights draw those rows.
func light_effects(flare_rows: PackedFloat32Array, flares: int, blast_rows: PackedFloat32Array, blasts: int, arc_rows: PackedFloat32Array, arcs: int, slots: int) -> void:
	_hand(effects[EFFECTS_FLARE].multimesh, flare_rows, flares, slots)
	_hand(effects[EFFECTS_BLAST].multimesh, blast_rows, blasts, slots)
	_hand(effects[EFFECTS_ARC].multimesh, arc_rows, arcs, slots)


func _hand(multimesh: MultiMesh, buffer: PackedFloat32Array, count: int, slots: int) -> void:
	if multimesh.instance_count != slots:
		multimesh.instance_count = slots
	if count > 0 and buffer.size() == slots * STRIDE:
		multimesh.buffer = buffer
		multimesh.visible_instance_count = count
	elif multimesh.visible_instance_count != 0:
		multimesh.visible_instance_count = 0


## Before Feel draws its live beams: none lit until `light_beam` lights one this frame.
func light_beams_begin() -> void:
	for node in beams:
		if node.visible:
			node.visible = false


## Live beam `i`'s light along the path Feel just gave its shader: `points` of `path` (x, y, how
## far along), in the ramp `player` (shot_beam's `beam_player`), its look and core colour, faded
## by `fade`.
func light_beam(i: int, path: PackedVector3Array, points: int, player: int, look: int, core: Color, fade: float) -> void:
	while beams.size() <= i:
		var node := MeshInstance2D.new()
		node.mesh = beam_light_mesh()
		var material := ShaderMaterial.new()
		material.shader = BEAM_SHADER
		material.set_shader_parameter(&"beam_reach", BEAM_REACH)
		material.set_shader_parameter(&"beam_strength", BEAM_STRENGTH)
		node.material = material
		node.visible = false
		viewport.add_child(node)
		beams.append(node)
	var beam: MeshInstance2D = beams[i]
	var shade: ShaderMaterial = beam.material as ShaderMaterial
	shade.set_shader_parameter(&"beam_path", path)
	shade.set_shader_parameter(&"beam_points", mini(points, BEAM_POINTS))
	shade.set_shader_parameter(&"beam_player", player)
	shade.set_shader_parameter(&"beam_look", look)
	shade.set_shader_parameter(&"core_override", Color(core.r, core.g, core.b, 1.0))
	shade.set_shader_parameter(&"beam_fade", fade)
	beam.visible = true


## The mesh a beam's light is drawn as (`light_beam.gdshader`): BEAM_POINTS - 1 quads, quad k on
## the path's piece k (UV.x k + 0.25 or 0.75, UV.y 0.25 or 0.75). Made once; its box is the
## world, so it is never culled by a stale one.
static func beam_light_mesh() -> ArrayMesh:
	if _beam_mesh != null:
		return _beam_mesh
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for k in BEAM_POINTS - 1:
		var base: int = verts.size()
		for corner: Vector2 in [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]:
			verts.append(corner)
			uvs.append(Vector2(float(k) + 0.25 + 0.5 * corner.x, 0.25 + 0.5 * corner.y))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_beam_mesh = ArrayMesh.new()
	_beam_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_beam_mesh.custom_aabb = BatchesScript.WORLD
	return _beam_mesh


## Write the room's light spots (every node in `LightSpot.GROUP` in the tree) into the spots'
## batch: done when one comes or goes (`follow`), not every frame.
func draw_spots() -> void:
	_spots_dirty = false
	var found: Array[Node] = get_tree().get_nodes_in_group(LightSpot.GROUP)
	var at: int = 0
	_spot_buffer.resize(found.size() * STRIDE)
	for node in found:
		var spot := node as Node2D
		if spot == null or not spot.is_inside_tree() or spot.is_queued_for_deletion():
			continue
		var reach: float = LightSpot.reach_of(spot)
		var colour: Color = _colour_of(spot)
		var where: Vector2 = spot.global_position
		var i: int = at * STRIDE
		_spot_buffer[i] = reach
		_spot_buffer[i + 1] = 0.0
		_spot_buffer[i + 2] = 0.0
		_spot_buffer[i + 3] = where.x
		_spot_buffer[i + 4] = 0.0
		_spot_buffer[i + 5] = reach
		_spot_buffer[i + 6] = 0.0
		_spot_buffer[i + 7] = where.y
		_spot_buffer[i + 8] = colour.r
		_spot_buffer[i + 9] = colour.g
		_spot_buffer[i + 10] = colour.b
		_spot_buffer[i + 11] = clampf(LightSpot.strength_of(spot), 0.0, 1.0)
		_spot_buffer[i + 12] = clampf(LightSpot.flicker_of(spot), 0.0, 1.0)
		# A seed from where it is, so two torches flicker out of step and a run is the same.
		_spot_buffer[i + 13] = fposmod(where.x * 0.137 + where.y * 0.311, 1.0)
		_spot_buffer[i + 14] = 0.0
		_spot_buffer[i + 15] = 0.0
		at += 1
	_spot_buffer.resize(at * STRIDE)
	var multimesh: MultiMesh = spots.multimesh
	multimesh.instance_count = at
	multimesh.visible_instance_count = at
	if at > 0:
		multimesh.buffer = _spot_buffer


## How many spots are lit (for tests).
func spot_count() -> int:
	return spots.multimesh.visible_instance_count


func _colour_of(spot: Node) -> Color:
	if spot.has_meta(LightSpot.TINT):
		return LightSpot.colour_of(spot)
	var art: Texture2D = LightSpot.art_of(spot)
	if art == null:
		return Color.WHITE
	if not _art_colours.has(art):
		_art_colours[art] = LightSpot.colour_of(spot)
	return _art_colours[art]
