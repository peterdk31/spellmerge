extends "res://tests/support/suite.gd"
## The shader warm-up (core/projectiles/shader_warmup.gd, a LoadTask): every shader in the game is
## drawn once, one a unit, by the kind of node the game draws it with, and nothing is left behind.

const WarmupScript := preload("res://core/projectiles/shader_warmup.gd")
## Folders that hold no game shaders.
const SKIP: Array[String] = ["res://.godot", "res://addons", "res://build", "res://tests"]

var warmup: WarmupScript
var host: Node


func before_each() -> void:
	host = own(Node.new()) as Node
	root.add_child(host)
	warmup = WarmupScript.new()


func after_each() -> void:
	warmup.end()
	WarmupScript.warmed = false


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


## The draws `begin` made (under its holder).
func _draws() -> Array[Node]:
	return host.get_child(0).get_children()


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
	warmup.begin(host)
	check_equal(warmup.units(), WarmupScript.shaders().size() + 2, "a unit for every shader, and Godot's own canvas shader by a batch and a mesh")
	for child in _draws():
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


func test_one_a_unit_then_warmed_and_gone() -> void:
	WarmupScript.warmed = false
	warmup.begin(host)
	for child in _draws():
		check(not (child as CanvasItem).visible, "nothing drawn before the first unit")
	warmup.step()
	var shown: int = 0
	for child in _draws():
		shown += 1 if (child as CanvasItem).visible else 0
	check_equal(shown, 1, "one at a time")
	var steps: int = 1
	while not warmup.is_done() and steps < 100:
		warmup.step()
		steps += 1
	check_equal(steps, warmup.units() + 1, "each shown for one frame, the last taken off after it")
	check_equal(warmup.units_done(), warmup.units(), "all done")
	check(WarmupScript.warmed, "the shaders stay compiled for the session")
	var holder: Node = host.get_child(0)
	warmup.end()
	check(holder.is_queued_for_deletion(), "it leaves nothing behind")


func test_wanting_a_shader_twice_warms_it_once() -> void:
	var shader: Shader = WarmupScript.BATCH_SHADERS[0]
	var before: int = WarmupScript.shaders().size()
	WarmupScript.want(shader, WarmupScript.RECT)
	WarmupScript.want(shader, WarmupScript.RECT)
	check_equal(WarmupScript.shaders().size(), before, "a listed shader is not drawn again")
