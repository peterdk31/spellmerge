class_name ProjectileBatches
extends Object
## The projectile manager's batches and card bodies (core/projectiles/projectile_manager.gd, "Drawing"):
## the MultiMesh batches every shot is drawn in, the card bodies' pairs of batches and their nodes,
## and the heads' mesh. Static functions of the manager (`pm`), whose members hold all of it.

const Manager := preload("res://core/projectiles/projectile_manager.gd")

## Not state (core/sim/README.md): the manager, the other jobs this one calls and the manager's
## arrays it works on, each the manager's own array (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"pm", &"_nodes", &"_rooms", &"_buffers", &"_mirrors", &"_still_views", &"_batch_counts", &"_body_shaders", &"_body_meshes", &"_body_shapes", &"_body_ground", &"_merges", &"_draw_out"]

var pm: Manager = null
var _nodes: Array[MultiMeshInstance2D]
var _rooms: PackedInt32Array
var _buffers: Array[PackedFloat32Array]
var _mirrors: Array[MultiMesh]
var _still_views: Array[StillShotView]
var _batch_counts: PackedInt32Array
var _body_shaders: Array[Shader]
var _body_meshes: PackedInt32Array
var _body_shapes: Dictionary
var _body_ground: Dictionary
var _merges: Dictionary
var _draw_out: PackedInt32Array


## Takes the manager's arrays and jobs, by the names in DERIVED: again whenever the manager's arrays
## may have been replaced (`ProjectileManager._link_jobs`).
func link(manager: Manager) -> void:
	pm = manager
	for name: StringName in DERIVED:
		if name != &"pm":
			set(name, manager.get(name))


## The body number (from 1) of a card's own shader drawing `mesh` (MESH_QUAD for still shots,
## MESH_HEAD for flying or orbiting ones), numbered the first time the pair is asked for: a pair of
## batches is made with them (`batches_grown`), and the shader is handed to the shader warm-up
## (`ShaderWarmup.want`, drawn as a batch), so it is compiled before the first room when it is
## asked for before then (Spells numbers every carrier card's when it starts). The same shader under
## the other mesh is another body. 0 for none, and for one past MOST_BODIES (an error names it; its
## shots are drawn by their motion's plain batch).
func register_body(shader: Shader, mesh: int = Manager.MESH_QUAD) -> int:
	if shader == null:
		return 0
	for at in _body_shaders.size():
		if _body_shaders[at] == shader and _body_meshes[at] == mesh:
			return at + 1
	if _body_shaders.size() >= Manager.MOST_BODIES:
		push_error("Projectiles: no batch left for the shot shader %s (MOST_BODIES is %d); its shots are drawn plain" % [shader.resource_path, Manager.MOST_BODIES])
		return 0
	if not _body_shaders.has(shader):
		Manager.ShaderWarmupScript.want(shader, Manager.ShaderWarmupScript.BATCH)
	_body_shaders.append(shader)
	_body_meshes.append(Manager.MESH_HEAD if mesh == Manager.MESH_HEAD else Manager.MESH_QUAD)
	var body: int = _body_shaders.size()
	pm._batch_total = Manager.BATCH_BODY_FIRST + 2 * body
	_rooms.resize(pm._batch_total)
	_batch_counts.resize(pm._batch_total)
	_draw_out.resize(Manager.DRAW_OUT_FIRST + pm._batch_total)
	while _buffers.size() < pm._batch_total:
		_buffers.append(PackedFloat32Array())
	if _mirrors.size() < pm._batch_total:
		_mirrors.resize(pm._batch_total)
	if _nodes.size() >= Manager.BATCH_BODY_FIRST:
		_make_body_batches(body)
	pm.batches_grown.emit(pm._batch_total)
	return body


## The body number (from 1) of a card's own shader drawing `mesh`, if it was numbered
## (`register_body`), or 0. Only a look up: it numbers nothing, so asking makes no batches.
func body_of(shader: Shader, mesh: int = Manager.MESH_QUAD) -> int:
	if shader == null:
		return 0
	for at in _body_shaders.size():
		if _body_shaders[at] == shader and _body_meshes[at] == (Manager.MESH_HEAD if mesh == Manager.MESH_HEAD else Manager.MESH_QUAD):
			return at + 1
	return 0


## Card body `body`'s look shape (`CarrierCard.look_shape`, in its drawn hit size's units, STILL_HIT)
## and its clock (`Vector2(look_open, look_fade)`, seconds), handed to its batches' shader as the
## uniforms `look_shape` and `look_clock`, so the shader draws its look by the card's numbers and
## whoever gives off its motes (`still_motes.gd`, from the card's `CardLook`) reads the same ones.
## Spells sets them as it numbers the card's body. A body is its shader, so the cards sharing one
## must share these (test_card_looks checks the cards do).
func set_body_shape(body: int, shape: Vector2, clock: Vector2) -> void:
	if body < 1 or body > _body_shaders.size():
		return
	_body_shapes[body] = [shape, clock]
	for enemy: bool in [false, true]:
		var batch: int = Manager.body_batch(body, enemy)
		if batch < _nodes.size() and _nodes[batch] != null:
			_apply_body_shape(_nodes[batch], body)


## How card body `body` lies (`CarrierCard.look_on_floor`, `look_merges`): `on_floor` draws its
## batches at FLOOR_DRAW_Z, under every body, instead of over everyone as a shot; with `merges` its
## shader is told every shot of the body drawn each frame (`StillMerge`), so it draws the ones that
## overlap as one. Spells sets it as it numbers the card's body; a body is its shader, so the cards
## sharing one must agree (test_card_looks checks the cards do).
func set_body_ground(body: int, on_floor: bool, merges: bool) -> void:
	if body < 1 or body > _body_shaders.size():
		return
	var ground: int = (Manager.GROUND_FLOOR if on_floor else 0) | (Manager.GROUND_MERGES if merges else 0)
	if ground == 0:
		_body_ground.erase(body)
	else:
		_body_ground[body] = ground
	if merges and not _merges.has(body):
		_merges[body] = StillMerge.new()
	elif not merges:
		_merges.erase(body)
	for enemy: bool in [false, true]:
		var batch: int = Manager.body_batch(body, enemy)
		if batch < _nodes.size() and _nodes[batch] != null:
			_nodes[batch].z_index = pm._body_z(body, enemy)
			if not merges:
				StillMerge.hand_none(_nodes[batch].material as ShaderMaterial)


## Tells both batches of each merging body of the body's shots drawn this frame, in one list
## (`StillMerge`: the hat ramps' batch's rows, then the enemy ramp's), when it drew any; the rows
## are the ones uploaded (the kernel's when it drew). Both are told, so neither material keeps the
## list that is written next.
func _hand_merges(kernel_draw: bool) -> void:
	for body: int in _merges:
		var hat_batch: int = Manager.body_batch(body, false)
		var foe_batch: int = Manager.body_batch(body, true)
		if foe_batch >= pm._batch_total:
			continue
		var hats: int = _draw_out[Manager.DRAW_OUT_FIRST + hat_batch]
		var foes: int = _draw_out[Manager.DRAW_OUT_FIRST + foe_batch]
		if hats + foes == 0:
			continue
		var merge: StillMerge = _merges[body]
		merge.fill(_drawn_rows(hat_batch, hats, kernel_draw), hats, _drawn_rows(foe_batch, foes, kernel_draw), foes)
		merge.hand_to(_nodes[hat_batch].material as ShaderMaterial, false)
		merge.hand_to(_nodes[foe_batch].material as ShaderMaterial, true)


## The rows batch `batch` uploads this frame (the kernel's when it drew), or none for `out` 0.
func _drawn_rows(batch: int, out: int, kernel_draw: bool) -> PackedFloat32Array:
	var _kernel: Object = pm._kernel
	if out == 0:
		return PackedFloat32Array()
	return _kernel.call(&"buffer", batch) if kernel_draw else _buffers[batch]


## Hands card body `body`'s look shape and clock to its batch `node`'s shader, once it has them.
func _apply_body_shape(node: MultiMeshInstance2D, body: int) -> void:
	var shaped: Variant = _body_shapes.get(body)
	if shaped == null:
		return
	var material := node.material as ShaderMaterial
	material.set_shader_parameter(&"look_shape", shaped[0])
	material.set_shader_parameter(&"look_clock", shaped[1])


## Batch `batch`'s mesh: MESH_HEAD the shots' (`head_mesh`), MESH_QUAD one quad a shot (runes, a
## still card's body); a card body's batch draws its body's mesh.
func batch_mesh(batch: int) -> int:
	if batch >= Manager.BATCH_BODY_FIRST:
		var body: int = (batch - Manager.BATCH_BODY_FIRST) / 2 + 1
		return _body_meshes[body - 1] if body <= _body_meshes.size() else Manager.MESH_QUAD
	return Manager.first_batch_mesh(batch)


## Makes card body `body`'s pair of batches with its shader and mesh (the nodes before it are made),
## fitted to the room as the others are, each placed in the draw order (`_place_body_node`).
func _make_body_batches(body: int) -> void:
	var mesh: int = _body_meshes[body - 1]
	for enemy: bool in [false, true]:
		var batch: int = Manager.body_batch(body, enemy)
		if _nodes.size() <= batch:
			_nodes.resize(batch + 1)
		if _nodes[batch] == null:
			_nodes[batch] = _make_batch(pm._body_z(body, enemy), _body_shaders[body - 1], head_mesh() if mesh == Manager.MESH_HEAD else null)
			_nodes[batch].multimesh.custom_aabb = _nodes[Manager.BATCH_BOLT].multimesh.custom_aabb
			_apply_body_shape(_nodes[batch], body)
			_place_body_node(body, enemy)


## Moves card body `body`'s node (the hat ramps' or, with `enemy`, the enemy ramp's) into the first
## batches' draw order at its z (BATCH_ORDER: bolts, runes, orbits; a node later among its siblings
## draws above the ones before it): right after the batch of plain shots its mesh draws
## (BATCH_BOLT or BATCH_ENEMY for a head body, BATCH_STILL or BATCH_ENEMY_STILL for a quad one) and
## the bodies of its mesh and layer numbered before it. So a bolt with a look of its own still draws
## under the runes and the orbit shots, as a plain bolt does.
func _place_body_node(body: int, enemy: bool) -> void:
	var mesh: int = _body_meshes[body - 1]
	var plain: int
	if mesh == Manager.MESH_HEAD:
		plain = Manager.BATCH_ENEMY if enemy else Manager.BATCH_BOLT
	else:
		plain = Manager.BATCH_ENEMY_STILL if enemy else Manager.BATCH_STILL
	var after: Node = _nodes[plain]
	for earlier in range(1, body):
		if _body_meshes[earlier - 1] == mesh:
			var node: Node = _nodes[Manager.body_batch(earlier, enemy)]
			if node != null and node.get_index() > after.get_index():
				after = node
	var mine: Node = _nodes[Manager.body_batch(body, enemy)]
	pm.move_child(mine, after.get_index() + 1 if mine.get_index() > after.get_index() else after.get_index())


## Draw batch `batch`'s rows (BATCH_*) again in `multimesh` too, or stop with null (Feel's spell
## light, docs/milestones/spell-spectacle.md, P3a). `multimesh` takes the batch's instance count and
## each frame the same buffer the batch uploads (`update_draw`), so it must have the batch's format
## (TRANSFORM_2D, colours and custom data); its mesh and its node's shader are its own.
func mirror_batch(batch: int, multimesh: MultiMesh) -> void:
	if _mirrors.size() < pm._batch_total:
		_mirrors.resize(pm._batch_total)
	_mirrors[batch] = multimesh
	if multimesh != null and batch < _nodes.size() and _nodes[batch] != null:
		var source: MultiMesh = _nodes[batch].multimesh
		multimesh.instance_count = source.instance_count
		multimesh.visible_instance_count = 0


## Hand out card body `body`'s still shots each frame its batches draw any (`still_shots_drawn`,
## a `StillShotView` per batch of its pair), or stop with `on` false. Only a still body's (MESH_QUAD)
## shots are read; a frame costs nothing more for a body nobody watches.
func watch_body(body: int, on: bool) -> void:
	if body < 1 or body > _body_shaders.size() or _body_meshes[body - 1] != Manager.MESH_QUAD:
		return
	for enemy: bool in [false, true]:
		var batch: int = Manager.body_batch(body, enemy)
		if _still_views.size() <= batch:
			_still_views.resize(batch + 1)
		var view: StillShotView = null
		if on:
			view = _still_views[batch] if _still_views[batch] != null else StillShotView.new()
			view.body = body
			view.enemy = enemy
		_still_views[batch] = view


## One batched draw of up to `_cap` instances (TRANSFORM_2D plus a colour and custom data each)
## by `shader`, added as a child: each a quad, or each a `mesh` (the shots' `head_mesh`).
func _make_batch(z: int, shader: Shader, mesh: Mesh) -> MultiMeshInstance2D:
	var node := MultiMeshInstance2D.new()
	if mesh == null:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		mesh = quad
	# Never culled until `_fit_draw_bounds` fits its box to the room.
	var multimesh: MultiMesh = Manager.BatchesScript.multimesh()
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var material := ShaderMaterial.new()
	material.shader = shader
	node.material = material
	multimesh.mesh = mesh
	multimesh.instance_count = 0
	multimesh.visible_instance_count = 0
	node.multimesh = multimesh
	node.z_index = z
	pm.add_child(node)
	return node


## The mesh a shot is drawn as (`shot_head.gdshader`, PARTICLES ARE GEOMETRY there): small
## quads, each told in its UV which quad kind (HEAD_Q_*) it is, in HEAD_QUAD_KINDS' order (the
## light first, then the core). The shader places each quad round the head, or folds it away; a
## vertex says which quad and corner it is in its UV: x 0.25 or 0.75, y the kind + 0.25 or 0.75. A
## quad is one triangle of HEAD_QUAD_VERTICES vertices, twice its box each way, which the fragment
## stage cuts to the box: each vertex runs the whole vertex stage, so three cost a quarter less than
## a square's four (performance, 2026-11-02; the pixels are the same). It is made once and shared
## by the shot batches.
static func head_mesh() -> ArrayMesh:
	if Manager._head_mesh != null:
		return Manager._head_mesh
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var corners: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0)]
	for kind: int in Manager.HEAD_QUAD_KINDS:
		var base: int = verts.size()
		for corner: Vector2 in corners:
			verts.append(corner)
			uvs.append(Vector2(0.25 + 0.5 * corner.x, float(kind) + 0.25 + 0.5 * corner.y))
			colors.append(Color.WHITE)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	Manager._head_mesh = mesh
	return mesh


func _apply_textures() -> void:
	for batch in _nodes.size():
		if Manager.batch_textured(batch):
			_nodes[batch].texture = pm.texture


## The batch's culling box must cover the whole area. Without it the renderer
## culls the batch by a box that does not follow the shots, and shots away from
## the origin were never drawn.
func _fit_draw_bounds() -> void:
	if pm._draw_node == null:
		return
	var box: Rect2 = pm._bounds.grow(Manager.BOUNDS_MARGIN)
	var aabb := AABB(Vector3(box.position.x, box.position.y, -1.0), Vector3(box.size.x, box.size.y, 2.0))
	for node in _nodes:
		node.multimesh.custom_aabb = aabb
