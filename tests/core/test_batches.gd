extends "res://tests/support/suite.gd"
## The batches' maker (core/projectiles/batches.gd): every 2D MultiMesh in the game is made by it,
## so its box is the world and no batch is ever culled. Godot culls a MultiMeshInstance2D by the
## box it read at the node's last redraw; the horde's swarmers and gems, made without it, vanished
## a whole kind at once when the camera moved off where they first were (2026-11-02).

const BatchesScript := preload("res://core/projectiles/batches.gd")
const MAKER: String = "res://core/projectiles/batches.gd"
## Folders that hold nothing the game draws.
const SKIP: Array[String] = ["res://.godot", "res://addons", "res://build"]


## Every file under `path` whose name ends with one of `endings`.
func _find(path: String, endings: Array[String], found: PackedStringArray) -> void:
	if SKIP.has(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		for ending in endings:
			if file.ends_with(ending):
				found.append(path.path_join(file))
	for sub in dir.get_directories():
		_find(path.path_join(sub), endings, found)


func test_its_multimesh_is_never_culled() -> void:
	var made: MultiMesh = BatchesScript.multimesh()
	check_equal(made.transform_format, MultiMesh.TRANSFORM_2D, "a 2D batch")
	check(made.custom_aabb.size.x >= 100000.0 and made.custom_aabb.size.y >= 100000.0, "its box is the whole world")
	check(made.custom_aabb.has_point(Vector3.ZERO), "round the world's origin")


func test_no_script_makes_a_multimesh_another_way() -> void:
	var found := PackedStringArray()
	_find("res://", [".gd"], found)
	check(found.size() > 100, "the scripts are found: %d" % found.size())
	# Split, so this file does not name what it looks for.
	var made_by_hand: String = "MultiMesh" + ".new("
	for path in found:
		if path == MAKER:
			continue
		var text: String = FileAccess.get_file_as_string(path)
		check(not text.contains(made_by_hand), "%s makes a MultiMesh by hand: make it with Batches.multimesh() (core/projectiles/batches.gd), or the renderer may cull the whole batch" % path)


func test_every_multimesh_in_a_scene_or_resource_has_a_box() -> void:
	var found := PackedStringArray()
	_find("res://", [".tscn", ".tres"], found)
	for path in found:
		var text: String = FileAccess.get_file_as_string(path)
		var message: String = "%s has a MultiMesh with no custom_aabb: give it a box round the whole world (Batches.WORLD), or the renderer may cull the whole batch" % path
		# A MultiMesh resource file: its [resource] block sets the box.
		if text.begins_with("[gd_resource type=\"MultiMesh\""):
			check(text.contains("\ncustom_aabb ="), message)
		# Each MultiMesh sub-resource block sets its own.
		for block in text.split("\n[sub_resource type=\"MultiMesh\"").slice(1):
			check(block.get_slice("\n[", 0).contains("\ncustom_aabb ="), message)
