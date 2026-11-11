extends SceneTree
## Tests for core/registry: lookup by folder and id, every resource seen, duplicate
## ids, and sounds by id (`null` for an unknown one), on a fixture folder.
##
## godot --headless --path . --script res://tests/core/test_registry.gd

const RegistryScript := preload("res://core/registry/registry.gd")
const FIXTURE: String = "res://tests/core/fixtures/registry"

var _failures: Array[String] = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	_test_lookup()
	_test_nested_folders_and_skipped_files()
	_test_duplicate_id_keeps_the_first()
	_test_every_resource_is_seen()
	_test_unknown_folder_and_id()
	_test_sounds()
	_test_rescan_and_missing_roots()
	_test_export_suffixes_and_default_sounds()
	_test_add_a_fixture()
	if _failures.is_empty():
		print("TEST OK: core/registry")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## A typed copy: the registry returns Array[StringName], which never equals an untyped array.
func _names(values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(values)
	return result


func _registry() -> Node:
	var registry: Node = RegistryScript.new()
	registry.scan(FIXTURE + "/content", FIXTURE + "/audio", PackedStringArray(["tres"]))
	return registry


func _test_lookup() -> void:
	var registry: Node = _registry()
	var spark: Resource = registry.get_resource(&"spells", &"spark")
	_check(spark is FormBase, "spark is a FormBase")
	_check(registry.get_resource(&"enemies", &"blob") is EnemyBase, "blob is an EnemyBase")
	_check(registry.get_resource(&"rooms", &"hall") is RoomBase, "hall is a RoomBase")
	_check(registry.get_folders() == _names([&"enemies", &"rooms", &"spells"]), "folders are found, sorted: %s" % [registry.get_folders()])
	_check(registry.get_resource(&"enemies", &"spark") == null, "ids are per folder")
	registry.free()


## `add` registers a resource as a scan would (tests: a fixture beside the content): found by id,
## its id in order, a new folder made; never one with no id or an id the folder holds.
func _test_add_a_fixture() -> void:
	var registry: Node = _registry()
	var blob: EnemyBase = registry.get_resource(&"enemies", &"blob") as EnemyBase
	var other: EnemyBase = blob.duplicate() as EnemyBase
	other.id = &"aardvark"
	_check(registry.add(&"enemies", other), "a new id is added")
	_check(registry.get_resource(&"enemies", &"aardvark") == other, "and found")
	_check(registry.get_ids(&"enemies") == _names([&"aardvark", &"blob"]), "in id order: %s" % [registry.get_ids(&"enemies")])
	_check(not registry.add(&"enemies", other.duplicate()), "an id the folder holds is refused")
	_check(not registry.add(&"enemies", Resource.new()), "a resource with no id is refused")
	_check(registry.add(&"props", other), "a new folder")
	_check(registry.get_folders().has(&"props"), "listed")
	registry.free()


func _test_nested_folders_and_skipped_files() -> void:
	var registry: Node = _registry()
	_check(registry.get_resource(&"spells", &"deep") != null,"a resource two folders down is found")
	_check(registry.get_ids(&"spells") == _names([&"deep", &"ember", &"spark"]),"ids are sorted; a .tres without an id is skipped: %s" % [registry.get_ids(&"spells")])
	registry.free()


func _test_duplicate_id_keeps_the_first() -> void:
	var registry: Node = _registry()
	var spark: FormBase = registry.get_resource(&"spells", &"spark") as FormBase
	_check(spark != null and spark.display_name == "Spark", "the first file in sorted order wins a duplicate id")
	registry.free()


func _test_every_resource_is_seen() -> void:
	# There is no demo subset (owner, 2026-11-05): every build sees every resource.
	var registry: Node = _registry()
	_check(not ("demo_only" in registry), "the registry has no demo filter")
	_check(registry.get_ids(&"spells") == _names([&"deep", &"ember", &"spark"]), "every spell id is listed")
	_check(registry.get_all(&"spells").size() == 3, "get_all gives every spell")
	_check(registry.get_resource(&"enemies", &"blob") != null, "every enemy is found")
	_check(registry.get_resource(&"rooms", &"hall") != null, "every room is found")
	registry.free()


func _test_unknown_folder_and_id() -> void:
	var registry: Node = _registry()
	_check(registry.get_resource(&"nope", &"spark") == null, "an unknown folder gives null")
	_check(registry.get_resource(&"spells", &"nope") == null, "an unknown id gives null")
	_check(registry.get_ids(&"nope").is_empty(), "an unknown folder has no ids")
	_check(registry.get_all(&"nope").is_empty(), "an unknown folder has no resources")
	registry.free()


func _test_sounds() -> void:
	var registry: Node = _registry()
	_check(registry.get_sound(&"zap") is AudioStream, "a known sound id returns the stream")
	_check(registry.get_sound(&"zap") == registry.get_sound(&"zap"), "a sound is loaded once and reused")
	_check(registry.get_sound(&"no_such_sound") == null, "an unknown sound id returns null")
	_check(registry.get_sound(&"") == null, "an empty sound id returns null")
	registry.free()


func _test_rescan_and_missing_roots() -> void:
	var registry: Node = _registry()
	registry.scan(FIXTURE + "/missing", FIXTURE + "/missing")
	_check(registry.get_folders().is_empty(), "a missing content root gives no folders")
	_check(registry.get_sound(&"zap") == null, "a missing audio root gives no sounds")
	_check(registry.get_resource(&"spells", &"spark") == null, "a rescan forgets the old content")
	registry.free()


func _test_export_suffixes_and_default_sounds() -> void:
	# An export lists `x.tres.remap` and `x.ogg.import`; only the names matter.
	var root: String = "user://registry_suffix_test"
	var files: PackedStringArray = ["content/spells/a.tres.remap", "content/spells/b.tres", "content/spells/b.tres.remap", "audio/sfx/boom.ogg.import", "audio/sfx/boom.ogg", "audio/sfx/pop.ogg.import", "audio/sfx/notes.txt"]
	DirAccess.make_dir_recursive_absolute(root + "/content/spells")
	DirAccess.make_dir_recursive_absolute(root + "/audio/sfx")
	for file_name: String in files:
		FileAccess.open(root + "/" + file_name, FileAccess.WRITE).close()
	var registry: Node = RegistryScript.new()
	var tres_files: PackedStringArray = registry._find_files(root + "/content", PackedStringArray(["tres"]))
	_check(tres_files == PackedStringArray([root + "/content/spells/a.tres", root + "/content/spells/b.tres"]), "a .remap suffix is stripped and not listed twice: %s" % [tres_files])
	var ogg_files: PackedStringArray = registry._find_files(root + "/audio", PackedStringArray(["ogg"]))
	_check(ogg_files == PackedStringArray([root + "/audio/sfx/boom.ogg", root + "/audio/sfx/pop.ogg"]), "an .import suffix is stripped and not listed twice: %s" % [ogg_files])
	# The content root is skipped on purpose: the .tres files above are empty, so loading
	# them would log errors. Scanning a real content root is covered by the fixture tests.
	registry.scan(root + "/no_content", root + "/audio")
	_check(registry._sound_paths.has(&"pop") and registry._sound_paths.has(&"boom"), "the default scan indexes .ogg names")
	registry.free()
	for file_name: String in files:
		DirAccess.remove_absolute(root + "/" + file_name)
