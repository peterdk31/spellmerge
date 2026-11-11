extends "res://tests/support/suite.gd"
## Every mote source in the game is sound (props W7; core/base/mote_source.gd): every node of every
## scene under content/ in the group `mote_source` (a room's art, a decal) has a `MoteSource` with no
## problems, a mote kind that content/motes has, and art to read when it names `mote_art`. A
## prop's sources are its looks' (tests/content/props/test_prop_data.gd checks them with its looks,
## by the same `kind_problems`). Found by folder, so a new scene is checked with no edit here.

const CONTENT: String = "res://content"
const MOTES: String = "res://content/motes/%s.tres"


## What is wrong with the kind `kind`, in words after `owner` (empty when content/motes has it).
static func kind_problems(kind: StringName, owner: String) -> PackedStringArray:
	if kind != &"" and not ResourceLoader.exists(MOTES % kind):
		return PackedStringArray(["%s: '%s' is no mote kind (content/motes/%s.tres)" % [owner, kind, kind]])
	return PackedStringArray()


func _scenes(path: String, found: PackedStringArray) -> PackedStringArray:
	for file in DirAccess.get_files_at(path):
		if file.ends_with(".tscn"):
			found.append(path.path_join(file))
	for folder in DirAccess.get_directories_at(path):
		_scenes(path.path_join(folder), found)
	return found


func test_every_mote_source_in_a_scene_is_sound() -> void:
	var sources: int = 0
	for path in _scenes(CONTENT, PackedStringArray()):
		var scene: PackedScene = load(path) as PackedScene
		var root_node: Node = scene.instantiate() if scene != null else null
		if root_node == null:
			continue
		for node: Node in [root_node] + root_node.find_children("*", "", true, false):
			if not node.is_in_group(MoteSource.GROUP):
				continue
			sources += 1
			var owner: String = "%s: %s" % [path, root_node.get_path_to(node)]
			var look: MoteSource = MoteSource.of(node)
			check(look != null, "%s is in the group and names a MoteSource" % owner)
			if look == null:
				continue
			check(node is Node2D, "%s is a Node2D (it says where)" % owner)
			var art_path: NodePath = node.get_meta(MoteSource.ART, NodePath())
			var art: Sprite2D = node.get_node_or_null(art_path) as Sprite2D if not art_path.is_empty() else null
			check(art_path.is_empty() or (art != null and art.texture != null), "%s: its mote_art %s is a sprite with a picture" % [owner, art_path])
			var found := PackedStringArray()
			found.append_array(look.problems(art != null and art.texture != null))
			found.append_array(kind_problems(look.kind, owner))
			check_equal(found, PackedStringArray(), "%s is sound" % owner)
		root_node.free()
	check(sources >= 1, "the scan finds the hub's rim at least (%d)" % sources)
