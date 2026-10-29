extends "res://tests/support/suite.gd"
## The shader warm-up (core/projectiles/shader_warmup.gd): every shader in the game is drawn
## once, one a frame after the screen under it is up, by the kind of node the game draws it with,
## and nothing is left behind.

const WarmupScript := preload("res://core/projectiles/shader_warmup.gd")
## Folders that hold no game shaders.
const SKIP: Array[String] = ["res://.godot", "res://addons", "res://build", "res://tests"]

var warmup: WarmupScript


func before_each() -> void:
	warmup = WarmupScript.new()
	root.add_child(warmup)


func after_each() -> void:
	if is_instance_valid(warmup):
		warmup.free()


## Every `.gdshader` under `path`.
func _find_shaders(path: String, found: PackedStringArray) -> void:
	if SKIP.has(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".gdshader"):
			found.append(path.path_join(file))
	for sub in dir.get_directories():
		_find_shaders(path.path_join(sub), found)


func _run_to_the_end() -> void:
	for i in WarmupScript.WAIT_FRAMES + 1:
		warmup._process(0.016)
	var left: int = warmup.draws()
	for i in left:
		warmup._process(0.016)


func test_every_shader_in_the_game_is_warmed() -> void:
	# The areas hand theirs over when they start: the autoloads are up, the HUD's vignette made.
	check(root.has_node("Feel") and root.has_node("Entities"), "the autoloads that want shaders are up")
	load("res://hud/panels/vignette/vignette.gd").new().free()
	var found := PackedStringArray()
	_find_shaders("res://", found)
	check(found.size() >= 11, "the shaders are found: %d" % found.size())
	var warmed: Array[Shader] = WarmupScript.shaders()
	for path in found:
		check(warmed.has(load(path) as Shader), "%s is warmed before the first room: list a shot shader in shader_warmup.gd, or call ShaderWarmup.want(shader, how) where an area's shader is first used" % path)


func test_each_is_drawn_the_way_the_game_draws_it() -> void:
	_run_to_the_end()
	check_equal(warmup.draws(), WarmupScript.shaders().size() + 2, "every shader, and Godot's own canvas shader by a batch and a mesh")
	for child in warmup.get_children():
		var material := (child as CanvasItem).material as ShaderMaterial
		if material == null:
			continue
		var shader: Shader = material.shader
		if WarmupScript.BATCH_SHADERS.has(shader):
			check(child is MultiMeshInstance2D, "%s by a batch" % shader.resource_path)
		elif WarmupScript.MESH_SHADERS.has(shader):
			check(child is MeshInstance2D, "%s by a mesh, as Feel draws a beam" % shader.resource_path)
		else:
			check(child is Sprite2D, "%s by a sprite" % shader.resource_path)


func test_one_a_frame_after_the_wait_then_it_is_gone() -> void:
	for i in WarmupScript.WAIT_FRAMES - 1:
		warmup._process(0.016)
	check_equal(warmup.get_child_count(), 0, "nothing made while the screen comes up")
	warmup._process(0.016)
	var shown: int = 0
	for child in warmup.get_children():
		shown += 1 if (child as CanvasItem).visible else 0
	check_equal(shown, 1, "then one at a time")
	for i in warmup.draws():
		warmup._process(0.016)
	check_equal(warmup.drawn, warmup.draws(), "each drew once")
	check(warmup.is_queued_for_deletion(), "then it frees itself")


func test_wanting_a_shader_twice_warms_it_once() -> void:
	var shader: Shader = WarmupScript.BATCH_SHADERS[0]
	var before: int = WarmupScript.shaders().size()
	WarmupScript.want(shader, WarmupScript.RECT)
	WarmupScript.want(shader, WarmupScript.RECT)
	check_equal(WarmupScript.shaders().size(), before, "a listed shader is not drawn again")
