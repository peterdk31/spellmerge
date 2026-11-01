extends "res://core/loading/load_task.gd"
## Compiles every shader in the game before anyone plays (core/README.md, "The shot shaders";
## docs/DECISIONS.md, 2026-10-29, "Shader warm-up"). A browser on Windows compiles WebGL through
## Direct3D, and a shot shader takes it up to a few seconds there; Godot compiles a shader the
## first time something draws with it, so without this the first room stood still for 12-14 s
## while every one of them compiled.
##
## A LoadTask (`core/loading/`): Flow puts one in the work before the first room (`play_tasks`)
## while `warmed` is false, so it runs behind the loading screen (owner, 2026-10-29: not on the
## main menu, not in the room). Each unit draws one shader for a frame the way the game draws it;
## `warmed` stays true for the session, as Godot keeps them. A draw puts nothing on the screen (a
## quad of no size that is never culled, or a sprite too small to cover a pixel), but the shader
## is compiled and kept for the game. Godot's own canvas shader is drawn too, by a batch and a
## mesh with no material.
##
## **Every shader is warmed:** the shot shaders are listed here (BATCH_SHADERS, MESH_SHADERS,
## RECT_SHADERS); an area's own shader is handed over with `want(shader, how)` by the area that
## uses it, before the first Play (an autoload's `_ready`, a node's `_init`). How it is drawn
## picks the variant Godot compiles: BATCH a MultiMeshInstance2D, MESH a MeshInstance2D, RECT a
## Sprite2D or Control. `tests/core/test_shader_warmup.gd` fails for any `.gdshader` in the project
## that is neither listed nor wanted, so a new shader cannot be forgotten.

## How a shader is drawn.
const BATCH: int = 0
const MESH: int = 1
const RECT: int = 2
## The shot shaders by how they are drawn: batches of instances (TRANSFORM_2D, a colour and
## custom data each), one mesh each (`Feel`'s beams and swing trails), sprites (deaths, ghosts, staffs).
const BATCH_SHADERS: Array[Shader] = [
	preload("res://core/projectiles/shot_trail.gdshader"),
	preload("res://core/projectiles/shot_effect.gdshader"),
	preload("res://core/projectiles/shot_rune.gdshader"),
	preload("res://core/projectiles/shot_orbit.gdshader"),
	preload("res://core/projectiles/shot_status.gdshader"),
	preload("res://core/projectiles/shot_arc.gdshader"),
	preload("res://core/projectiles/shot_blast.gdshader"),
]
const MESH_SHADERS: Array[Shader] = [
	preload("res://core/projectiles/shot_beam.gdshader"),
	preload("res://core/projectiles/shot_swing.gdshader"),
]
const RECT_SHADERS: Array[Shader] = [
	preload("res://core/projectiles/shot_sprite.gdshader"),
]
const BatchesScript := preload("res://core/projectiles/batches.gd")
## The world, as far as a draw needs to reach to never be culled.
const WORLD: AABB = BatchesScript.WORLD

## True once a warm-up has finished in this session: the shaders stay compiled.
static var warmed: bool = false
## The areas' shaders (`want`), and how each is drawn.
static var _wanted: Array[Shader] = []
static var _wanted_how: PackedInt32Array = PackedInt32Array()

## Every draw, shown one a unit in this order (made by `begin`), what holds them, and the one
## on show (-1 before the first).
var _draws: Array[CanvasItem] = []
var _holder: Node2D = null
var _shown: int = -1

## Warm `shader` too, drawn `how` (BATCH, MESH or RECT). Called by the area that uses it, before
## the first draw; asking twice is the same as once.
static func want(shader: Shader, how: int) -> void:
	if shader != null and not _wanted.has(shader):
		_wanted.append(shader)
		_wanted_how.append(how)


## Every shader that is warmed: the shot shaders and the ones wanted.
static func shaders() -> Array[Shader]:
	var all: Array[Shader] = []
	all.append_array(BATCH_SHADERS)
	all.append_array(MESH_SHADERS)
	all.append_array(RECT_SHADERS)
	for shader in _wanted:
		if not all.has(shader):
			all.append(shader)
	return all


func units() -> int:
	return maxi(_draws.size(), 1) if _holder != null else shaders().size() + 2


func units_done() -> int:
	return clampi(_shown, 0, _draws.size())


func begin(host: Node) -> void:
	_holder = Node2D.new()
	_holder.name = "ShaderWarmup"
	_holder.top_level = true
	host.add_child(_holder)
	_make_draws()


## Take the last one off and show the next (each shows for one frame, when it is compiled).
func step() -> void:
	if _shown >= 0 and _shown < _draws.size():
		_draws[_shown].visible = false
	_shown += 1
	if _shown < _draws.size():
		_draws[_shown].visible = true
	else:
		warmed = true


func is_done() -> bool:
	return _holder != null and _shown >= _draws.size()


func end() -> void:
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	_draws.clear()


func _make_draws() -> void:
	var empty := _empty_mesh()
	var pixel := ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
	for shader in shaders():
		var how: int = RECT
		if BATCH_SHADERS.has(shader):
			how = BATCH
		elif MESH_SHADERS.has(shader):
			how = MESH
		elif not RECT_SHADERS.has(shader):
			how = _wanted_how[_wanted.find(shader)]
		if how == BATCH:
			_draws.append(_batch(shader, empty))
		elif how == MESH:
			_draws.append(_mesh(shader, empty))
		else:
			_draws.append(_rect(shader, pixel))
	_draws.append(_batch(null, empty))
	_draws.append(_mesh(null, empty))


## A mesh of one quad of no size, its box the whole world: drawn, never culled, never seen.
func _empty_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = WORLD
	return mesh


func _material(shader: Shader) -> ShaderMaterial:
	if shader == null:
		return null
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


## A batch of one instance, as the projectile manager's and Feel's are made.
func _batch(shader: Shader, mesh: Mesh) -> MultiMeshInstance2D:
	var node := MultiMeshInstance2D.new()
	var multimesh: MultiMesh = BatchesScript.multimesh()
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = 1
	# Data that draws nothing: a trail of row -1 (no samples, not alive), an effect of no kind.
	multimesh.set_instance_transform_2d(0, Transform2D(Vector2(-1.0, 0.0), Vector2.ZERO, Vector2.ZERO))
	multimesh.set_instance_custom_data(0, Color(0.0, 0.0, 0.0, 0.0))
	node.multimesh = multimesh
	node.material = _material(shader)
	node.visible = false
	_holder.add_child(node)
	return node


func _mesh(shader: Shader, mesh: Mesh) -> MeshInstance2D:
	var node := MeshInstance2D.new()
	node.mesh = mesh
	node.material = _material(shader)
	node.visible = false
	_holder.add_child(node)
	return node


## A sprite of one clear pixel, scaled far below a pixel.
func _rect(shader: Shader, pixel: Texture2D) -> Sprite2D:
	var node := Sprite2D.new()
	node.texture = pixel
	node.scale = Vector2(0.001, 0.001)
	node.material = _material(shader)
	node.visible = false
	_holder.add_child(node)
	return node
