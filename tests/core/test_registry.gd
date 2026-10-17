extends SceneTree
## Tests for core/registry: lookup by folder and id, the demo flag, duplicate
## ids, and sounds by id (`null` for an unknown one), on a fixture folder.
##
## godot --headless --path . --script res://tests/core/test_registry.gd

const RegistryScript := preload("res://core/registry/registry.gd")
const FIXTURE: String = "res://tests/core/fixtures/registry"

var _failures: Array[String] = []


func _initialize() -> void:
	_test_lookup()
	_test_nested_folders_and_skipped_files()
	_test_duplicate_id_keeps_the_first()
	_test_demo_flag()
	_test_unknown_folder_and_id()
	_test_sounds()
	_test_rescan_and_missing_roots()
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


func _registry() -> Node:
	var registry: Node = RegistryScript.new()
	registry.scan(FIXTURE + "/content", FIXTURE + "/audio", PackedStringArray(["tres"]))
	return registry


func _test_lookup() -> void:
	var registry: Node = _registry()
	var spark: Resource = registry.get_resource(&"spells", &"spark")
	_check(spark is SpellBase, "spark is a SpellBase")
	_check(registry.get_resource(&"enemies", &"blob") is EnemyBase, "blob is an EnemyBase")
	_check(registry.get_resource(&"rooms", &"hall") is RoomBase, "hall is a RoomBase")
	_check(registry.get_folders() == [&"enemies", &"rooms", &"spells"], "folders are found, sorted")
	_check(registry.get_resource(&"enemies", &"spark") == null, "ids are per folder")
	registry.free()


func _test_nested_folders_and_skipped_files() -> void:
	var registry: Node = _registry()
	_check(registry.has_resource(&"spells", &"deep"), "a resource two folders down is found")
	_check(registry.get_ids(&"spells") == [&"deep", &"hidden", &"spark"], "ids are sorted; a .tres without an id is skipped")
	registry.free()


func _test_duplicate_id_keeps_the_first() -> void:
	var registry: Node = _registry()
	var spark: SpellBase = registry.get_resource(&"spells", &"spark") as SpellBase
	_check(spark != null and spark.display_name == "Spark", "the first file in sorted order wins a duplicate id")
	registry.free()


func _test_demo_flag() -> void:
	var registry: Node = _registry()
	_check(registry.get_ids(&"spells").has(&"hidden"), "everything is visible when demo_only is off")
	_check(registry.has_resource(&"enemies", &"blob"), "a non-demo enemy is visible when demo_only is off")
	registry.demo_only = true
	_check(registry.get_resource(&"spells", &"hidden") == null, "a non-demo resource is hidden by demo_only")
	_check(registry.get_ids(&"spells") == [&"deep", &"spark"], "get_ids leaves out non-demo ids")
	_check(registry.get_all(&"spells").size() == 2, "get_all leaves out non-demo resources")
	_check(registry.get_ids(&"enemies").is_empty(), "a folder with only non-demo content is empty")
	_check(registry.has_resource(&"rooms", &"hall"), "demo content stays visible")
	registry.demo_only = false
	_check(registry.has_resource(&"spells", &"hidden"), "turning demo_only off shows everything again")
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
	_check(registry.has_sound(&"zap"), "the fixture sound is indexed by its file name")
	_check(registry.get_sound(&"zap") is AudioStream, "a known sound id returns the stream")
	_check(registry.get_sound(&"zap") == registry.get_sound(&"zap"), "a sound is loaded once and reused")
	_check(registry.get_sound(&"no_such_sound") == null, "an unknown sound id returns null")
	_check(not registry.has_sound(&"no_such_sound"), "has_sound is false for an unknown id")
	_check(registry.get_sound(&"") == null, "an empty sound id returns null")
	registry.free()


func _test_rescan_and_missing_roots() -> void:
	var registry: Node = _registry()
	registry.scan(FIXTURE + "/missing", FIXTURE + "/missing")
	_check(registry.get_folders().is_empty(), "a missing content root gives no folders")
	_check(registry.get_sound(&"zap") == null, "a missing audio root gives no sounds")
	_check(registry.get_resource(&"spells", &"spark") == null, "a rescan forgets the old content")
	registry.free()
