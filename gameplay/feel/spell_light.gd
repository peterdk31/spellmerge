extends Node
## Spell light (docs/milestones/spell-spectacle.md, P3a): shots light the floor, the walls and the
## bodies round them. A child of Feel, made only while the "Spell light" setting is on
## (`SpellLightSetting`, `spell_light_changed`); with it off none of these nodes exist.
##
## - **The light buffer:** a SubViewport a DOWNSCALE-th of the view each way, cleared to black
##   every frame, its canvas transform the main view's scaled down (`follow`, before every draw),
##   so it sees the same part of the world.
## - **Shot light, with no rows written twice:** one MultiMeshInstance2D in it per projectile
##   batch, drawn by `light.gdshader` (a soft light round each live shot, in its glow colour; a
##   rune a dimmer one). Its MultiMesh mirrors the batch (`ProjectileManager.mirror_batch`): each
##   frame it is handed the buffer the batch uploads, with a quad of its own. The batch's
##   MultiMesh itself is not shared, because a MultiMesh holds its mesh, and the trails' mesh is
##   hundreds of quads that every one runs the vertex stage, drawn or folded (DECISIONS,
##   2026-11-02): the light would have cost as many vertices as the trails themselves.
## - **Applying it:** one rect over the whole world at `z` (Feel's LIGHT_Z: above the room and the
##   bodies, under the motes, beams, flashes, telegraphs and shots), drawn by
##   `light_apply.gdshader`: what is under it, times the ambient plus the light, cut into three
##   steps. The ambient is 1.0 here (no room is darker yet: P3b), so a room looks as it does
##   without spell light until something glows.

const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const BatchesScript := preload("res://core/projectiles/batches.gd")
const LIGHT_SHADER: Shader = preload("res://gameplay/feel/light.gdshader")
const APPLY_SHADER: Shader = preload("res://gameplay/feel/light_apply.gdshader")
## The light buffer is this many times smaller than the view each way (a quarter: 160 x 90 for
## the game's 640 x 360).
const DOWNSCALE: int = 4
## The apply rect reaches this far from the origin each way: past any room, so it always covers
## the view (the GPU only shades what is on screen).
const REACH: float = 65536.0

## The light buffer, its batches (by BATCH_*) and the rect that applies it. Read only.
var viewport: SubViewport = null
var batches: Array[MultiMeshInstance2D] = []
var apply: ColorRect = null
var _projectiles: ProjectileManagerScript = null


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
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for batch in ProjectileManagerScript.BATCHES:
		var node := MultiMeshInstance2D.new()
		var multimesh: MultiMesh = BatchesScript.multimesh()
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = quad
		multimesh.instance_count = 0
		multimesh.visible_instance_count = 0
		node.multimesh = multimesh
		var material := ShaderMaterial.new()
		material.shader = LIGHT_SHADER
		material.set_shader_parameter(&"rune_rows", ProjectileManagerScript.BATCH_MESH[batch] < 0)
		node.material = material
		viewport.add_child(node)
		batches.append(node)
		if _projectiles != null:
			_projectiles.mirror_batch(batch, multimesh)
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
	apply.material = shade
	add_child(apply)


func _enter_tree() -> void:
	if not RenderingServer.frame_pre_draw.is_connected(follow):
		RenderingServer.frame_pre_draw.connect(follow)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(follow):
		RenderingServer.frame_pre_draw.disconnect(follow)


## Stop mirroring the batches (before this node is freed: the setting turned off).
func release() -> void:
	if _projectiles == null:
		return
	for batch in batches.size():
		if _projectiles.batch_mirror(batch) == batches[batch].multimesh:
			_projectiles.mirror_batch(batch, null)
	_projectiles = null


## Fit the light buffer to the view: its size a DOWNSCALE-th of the view's, its canvas transform
## the view's scaled down, so a light lands under its shot. Run just before every draw, after the
## camera has moved.
func follow() -> void:
	var view: Viewport = get_viewport()
	if view == null:
		return
	var size: Vector2 = view.get_visible_rect().size
	var wanted := Vector2i(maxi(ceili(size.x / DOWNSCALE), 1), maxi(ceili(size.y / DOWNSCALE), 1))
	if viewport.size != wanted:
		viewport.size = wanted
	var scale := Vector2(float(wanted.x) / maxf(size.x, 1.0), float(wanted.y) / maxf(size.y, 1.0))
	viewport.canvas_transform = Transform2D(0.0, scale, 0.0, Vector2.ZERO) * view.global_canvas_transform * view.canvas_transform


## The ambient light: 1.0 is the room as it is (P3a keeps it there; a room's own ambient is P3b).
func set_ambient(ambient: float) -> void:
	(apply.material as ShaderMaterial).set_shader_parameter(&"ambient", ambient)
