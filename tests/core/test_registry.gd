extends "res://tests/support/suite.gd"
## Tests for core/registry, one rule per test, each on a registry of its own scanning a fixture
## folder (tests/core/fixtures/registry): lookup by folder and id, nested folders, skipped files
## and duplicate ids, every resource seen (no demo filter), unknown folders and ids, a content item's
## JSON (`get_data`), `add` for a
## test's own fixture, sounds by id (`null` for an unknown one), a rescan and missing roots, and an
## export's `.remap` and `.import` names (on empty files the test writes under user:// and takes
## out after).

const RegistryScript := preload("res://core/registry/registry.gd")
const FIXTURE: String = "res://tests/core/fixtures/registry"
## An export's file names, made empty under EXPORT_ROOT by `_export_files`.
const EXPORT_ROOT: String = "user://registry_suffix_test"
const EXPORT_FILES: Array[String] = ["content/spells/a.tres.remap", "content/spells/b.tres", "content/spells/b.tres.remap", "audio/sfx/boom.ogg.import", "audio/sfx/boom.ogg", "audio/sfx/pop.ogg.import", "audio/sfx/notes.txt"]

var registry: Node


func before_each() -> void:
	registry = own(RegistryScript.new()) as Node
	registry.scan(FIXTURE + "/content", FIXTURE + "/audio", PackedStringArray(["tres"]))


func after_each() -> void:
	for file_name in EXPORT_FILES:
		if FileAccess.file_exists(EXPORT_ROOT + "/" + file_name):
			DirAccess.remove_absolute(EXPORT_ROOT + "/" + file_name)


## A typed copy: the registry returns Array[StringName], which never equals an untyped array.
func _names(values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(values)
	return result


## Writes EXPORT_FILES, empty, under EXPORT_ROOT (taken out in after_each).
func _export_files() -> void:
	DirAccess.make_dir_recursive_absolute(EXPORT_ROOT + "/content/spells")
	DirAccess.make_dir_recursive_absolute(EXPORT_ROOT + "/audio/sfx")
	for file_name in EXPORT_FILES:
		FileAccess.open(EXPORT_ROOT + "/" + file_name, FileAccess.WRITE).close()


# Lookup.

func test_a_resource_is_found_by_folder_and_id() -> void:
	check(registry.get_resource(&"spells", &"spark") is CarrierCard, "spark is a CarrierCard")
	check(registry.get_resource(&"enemies", &"blob") is EnemyBase, "blob is an EnemyBase")
	check(registry.get_resource(&"rooms", &"hall") is RoomBase, "hall is a RoomBase")


func test_folders_are_found_sorted() -> void:
	check_equal(registry.get_folders(), _names([&"enemies", &"rooms", &"spells"]), "folders are found, sorted")


func test_ids_are_per_folder() -> void:
	check(registry.get_resource(&"enemies", &"spark") == null, "a spell's id is not an enemy's")


func test_a_resource_two_folders_down_is_found() -> void:
	check(registry.get_resource(&"spells", &"deep") != null, "a resource two folders down is found")


func test_ids_are_sorted_and_a_tres_without_an_id_is_skipped() -> void:
	check_equal(registry.get_ids(&"spells"), _names([&"deep", &"ember", &"spark"]), "the spells' ids, sorted, with no entry for the .tres that has no id")


func test_a_duplicate_id_keeps_the_first_file() -> void:
	var spark: CarrierCard = registry.get_resource(&"spells", &"spark") as CarrierCard
	check(spark != null and spark.display_name == "Spark", "the first file in sorted order wins a duplicate id")


func test_the_registry_has_no_demo_filter() -> void:
	# There is no demo subset (owner, 2026-11-05): every build sees every resource.
	check(not ("demo_only" in registry), "the registry has no demo filter")


func test_get_all_gives_every_resource_of_a_folder() -> void:
	check_equal(registry.get_all(&"spells").size(), 3, "get_all gives every spell")


func test_an_unknown_folder_gives_nothing() -> void:
	check(registry.get_resource(&"nope", &"spark") == null, "an unknown folder gives null")
	check(registry.get_ids(&"nope").is_empty(), "an unknown folder has no ids")
	check(registry.get_all(&"nope").is_empty(), "an unknown folder has no resources")


func test_an_unknown_id_gives_null() -> void:
	check(registry.get_resource(&"spells", &"nope") == null, "an unknown id gives null")


func test_a_content_items_json_is_read_by_folder_id_and_file() -> void:
	var data: Dictionary = registry.get_data(&"edges", &"rough", "edge.json")
	check(float(data.get("full_width", 0)) == 9.0, "a content item's JSON is read, parsed")
	check(registry.get_data(&"edges", &"rough", "edge.json") == data, "and kept")
	check(registry.get_data(&"edges", &"smooth", "edge.json").is_empty(), "an item with no such file gives nothing")
	check(registry.get_data(&"edges", &"../rough", "edge.json").is_empty(), "an id that is not one plain name gives nothing")
	check(registry.get_data(&"edges", &"rough", "edge.tres").is_empty(), "nor a file that is not JSON")


# Add (a test's fixture beside the content).

func _aardvark() -> EnemyBase:
	var other: EnemyBase = (registry.get_resource(&"enemies", &"blob") as EnemyBase).duplicate() as EnemyBase
	other.id = &"aardvark"
	return other


func test_an_added_resource_is_found_by_its_id() -> void:
	var other: EnemyBase = _aardvark()
	check(registry.add(&"enemies", other), "a new id is added")
	check(registry.get_resource(&"enemies", &"aardvark") == other, "and found")


func test_an_added_id_is_listed_in_order() -> void:
	registry.add(&"enemies", _aardvark())
	check_equal(registry.get_ids(&"enemies"), _names([&"aardvark", &"blob"]), "in id order")


func test_add_refuses_an_id_the_folder_holds() -> void:
	var other: EnemyBase = _aardvark()
	registry.add(&"enemies", other)
	check(not registry.add(&"enemies", other.duplicate()), "an id the folder holds is refused")


func test_add_refuses_a_resource_with_no_id() -> void:
	check(not registry.add(&"enemies", Resource.new()), "a resource with no id is refused")


func test_add_to_a_new_folder_lists_the_folder() -> void:
	check(registry.add(&"props", _aardvark()), "added to a new folder")
	check(registry.get_folders().has(&"props"), "the new folder is listed")


# Sounds.

func test_a_known_sound_id_gives_its_stream() -> void:
	check(registry.get_sound(&"zap") is AudioStream, "a known sound id returns the stream")


func test_a_sound_is_loaded_once_and_reused() -> void:
	check(registry.get_sound(&"zap") == registry.get_sound(&"zap"), "a sound is loaded once and reused")


func test_an_unknown_sound_id_gives_null() -> void:
	check(registry.get_sound(&"no_such_sound") == null, "an unknown sound id returns null")


func test_an_empty_sound_id_gives_null() -> void:
	check(registry.get_sound(&"") == null, "an empty sound id returns null")


# A rescan.

func test_a_missing_content_root_gives_no_folders() -> void:
	registry.scan(FIXTURE + "/missing", FIXTURE + "/missing")
	check(registry.get_folders().is_empty(), "a missing content root gives no folders")


func test_a_missing_audio_root_gives_no_sounds() -> void:
	registry.scan(FIXTURE + "/missing", FIXTURE + "/missing")
	check(registry.get_sound(&"zap") == null, "a missing audio root gives no sounds")


func test_a_rescan_forgets_the_old_content() -> void:
	registry.scan(FIXTURE + "/missing", FIXTURE + "/missing")
	check(registry.get_resource(&"spells", &"spark") == null, "a rescan forgets the old content")


# An export's names (`x.tres.remap`, `x.ogg.import`): only the names matter.

func test_a_remap_suffix_is_stripped_and_listed_once() -> void:
	_export_files()
	var found: PackedStringArray = registry._find_files(EXPORT_ROOT + "/content", PackedStringArray(["tres"]))
	check_equal(found, PackedStringArray([EXPORT_ROOT + "/content/spells/a.tres", EXPORT_ROOT + "/content/spells/b.tres"]), "a .remap suffix is stripped and not listed twice")


func test_an_import_suffix_is_stripped_and_listed_once() -> void:
	_export_files()
	var found: PackedStringArray = registry._find_files(EXPORT_ROOT + "/audio", PackedStringArray(["ogg"]))
	check_equal(found, PackedStringArray([EXPORT_ROOT + "/audio/sfx/boom.ogg", EXPORT_ROOT + "/audio/sfx/pop.ogg"]), "an .import suffix is stripped and not listed twice")


func test_the_default_scan_indexes_ogg_names() -> void:
	_export_files()
	# The content root is skipped on purpose: the .tres files above are empty, so loading them
	# would log errors. Scanning a real content root is covered by the fixture tests.
	var fresh: Node = own(RegistryScript.new()) as Node
	fresh.scan(EXPORT_ROOT + "/no_content", EXPORT_ROOT + "/audio")
	check(fresh._sound_paths.has(&"pop") and fresh._sound_paths.has(&"boom"), "the default scan indexes .ogg names")


# Sounds with variants (docs/milestones/sound.md, section 3): `<id>.tres`, a content item's
# `sounds/`, and an `.ogg` and a `.tres` of one id.

const SOUNDS_FIXTURE: String = "res://tests/core/fixtures/registry_sounds"
const THUD: String = SOUNDS_FIXTURE + "/content/props/heap/sounds/thud/thud.tres"
const CLASH_ROOT: String = "user://registry_clash_test"


func test_a_tres_sound_is_its_variants_and_they_are_no_ids_of_their_own() -> void:
	var fresh: Node = own(RegistryScript.new()) as Node
	fresh.scan(SOUNDS_FIXTURE + "/content", SOUNDS_FIXTURE + "/audio")
	var whoosh := fresh.get_sound(&"whoosh") as AudioStreamRandomizer
	check(whoosh != null, "the .tres is the sound `whoosh`, a randomizer")
	check(whoosh != null and whoosh.streams_count == 2, "of its two variants")
	check(fresh.get_sound(&"1") == null and fresh.get_sound(&"2") == null, "a file under variants/ is never an id")
	check(is_equal_approx(AudioLength.of(whoosh), 0.2), "as long as its longest variant (0.2 s), got %s" % AudioLength.of(whoosh))
	check(fresh.sound_clashes().is_empty(), "no clash")


func test_a_content_items_sounds_are_found_and_loaded_only_when_asked() -> void:
	var fresh: Node = own(RegistryScript.new()) as Node
	fresh.scan(SOUNDS_FIXTURE + "/content", SOUNDS_FIXTURE + "/audio")
	check(fresh.get_resource(&"props", &"heap") != null, "the item itself is content")
	check(not ResourceLoader.has_cached(THUD), "its sounds/ folder is not loaded by the content scan")
	check(fresh.get_sound(&"thud") is AudioStreamRandomizer, "its sound `thud` is found under its sounds/ folder")
	check(fresh.get_ids(&"props") == ([&"heap"] as Array[StringName]), "and is no content id")


func test_sound_ids_are_every_sound_with_a_file_in_id_order() -> void:
	var fresh: Node = own(RegistryScript.new()) as Node
	fresh.scan(SOUNDS_FIXTURE + "/content", SOUNDS_FIXTURE + "/audio")
	check_equal(fresh.sound_ids(), [&"thud", &"whoosh"] as Array[StringName], "audio's and a content item's, no variant")


func test_an_ogg_and_a_tres_of_one_id_clash() -> void:
	DirAccess.make_dir_recursive_absolute(CLASH_ROOT + "/audio/sfx/bang/variants")
	for file_name: String in ["audio/sfx/bang.ogg", "audio/sfx/bang/bang.tres", "audio/sfx/bang/variants/1.ogg"]:
		FileAccess.open(CLASH_ROOT + "/" + file_name, FileAccess.WRITE).close()
	var fresh: Node = own(RegistryScript.new()) as Node
	fresh.scan(CLASH_ROOT + "/no_content", CLASH_ROOT + "/audio")
	var clashes: PackedStringArray = fresh.sound_clashes()
	check_equal(clashes.size(), 1, "one clash")
	check(clashes.size() == 1 and clashes[0].contains("bang.ogg") and clashes[0].contains("bang.tres"), "naming both files: %s" % [clashes])
	check(not fresh._sound_paths.has(&"1"), "a baked variant (variants/1.ogg) is no sound id `1`")
	for file_name: String in ["audio/sfx/bang/variants/1.ogg", "audio/sfx/bang.ogg", "audio/sfx/bang/bang.tres"]:
		DirAccess.remove_absolute(CLASH_ROOT + "/" + file_name)


func test_the_games_sounds_have_no_clash() -> void:
	var game: Node = root.get_node("Registry")
	check_equal(game.sound_clashes(), PackedStringArray(), "no sound id is two files in audio/ and content/")


# A folder loads when it is first asked for (#972): the menu's start does not wait for content it
# does not show, such as the rooms' scenes.

const LAZY_ROOT: String = "user://registry_lazy_test"
const LAZY_ROOM: String = LAZY_ROOT + "/content/rooms/hall.tres"
const LAZY_SPELL: String = LAZY_ROOT + "/content/spells/spark.tres"


## A content root under user:// of one room and one spell, files no test has loaded yet (checked:
## a file still in the resource cache would make the checks of what a scan loads mean nothing).
func _lazy_content() -> void:
	check(not ResourceLoader.has_cached(LAZY_ROOM) and not ResourceLoader.has_cached(LAZY_SPELL), "no test left the fixture's files loaded")
	DirAccess.make_dir_recursive_absolute(LAZY_ROOT + "/content/rooms")
	DirAccess.make_dir_recursive_absolute(LAZY_ROOT + "/content/spells")
	var room := RoomBase.new()
	room.id = &"hall"
	ResourceSaver.save(room, LAZY_ROOM)
	var spell := CarrierCard.new()
	spell.id = &"spark"
	ResourceSaver.save(spell, LAZY_SPELL)


func _remove_lazy_content() -> void:
	for path: String in [LAZY_ROOM, LAZY_SPELL]:
		DirAccess.remove_absolute(path)


func test_a_scan_loads_no_folder_until_it_is_asked_for() -> void:
	_lazy_content()
	var fresh: Node = own(RegistryScript.new()) as Node
	fresh.scan(LAZY_ROOT + "/content", LAZY_ROOT + "/audio")
	check(not ResourceLoader.has_cached(LAZY_ROOM) and not ResourceLoader.has_cached(LAZY_SPELL), "a scan loads no content file")
	check_equal(fresh.get_ids(&"spells"), _names([&"spark"]), "asking for a folder finds its ids")
	check(ResourceLoader.has_cached(LAZY_SPELL), "the folder asked for is loaded")
	check(not ResourceLoader.has_cached(LAZY_ROOM), "a folder not asked for is not")
	check(fresh.get_resource(&"rooms", &"hall") is RoomBase, "and loads when it is")
	_remove_lazy_content()


func test_folders_lists_every_folder_none_asked_for_before() -> void:
	_lazy_content()
	var fresh: Node = own(RegistryScript.new()) as Node
	fresh.scan(LAZY_ROOT + "/content", LAZY_ROOT + "/audio")
	check_equal(fresh.get_folders(), _names([&"rooms", &"spells"]), "every folder with an id is listed, none asked for before")
	_remove_lazy_content()


func test_a_rescan_before_a_folder_is_asked_for_forgets_it() -> void:
	registry.scan(FIXTURE + "/missing", FIXTURE + "/missing")
	check_equal(registry.get_ids(&"spells"), _names([]), "the first scan's folders, never asked for, are gone")
	check(registry.get_folders().is_empty(), "and none is listed")


func test_warming_loads_every_folder_none_asked_for() -> void:
	_lazy_content()
	var fresh: Node = own(RegistryScript.new()) as Node
	fresh.scan(LAZY_ROOT + "/content", LAZY_ROOT + "/audio")
	check(not fresh.warm_step(0), "one file a step: two folders are not loaded by one step")
	check(ResourceLoader.has_cached(LAZY_ROOM) and not ResourceLoader.has_cached(LAZY_SPELL), "a step loads the next file, in folder order")
	var steps: int = 1
	while not fresh.warm_step(0) and steps < 10:
		steps += 1
	check(fresh._unloaded.is_empty(), "every folder is loaded in a few steps (%d)" % steps)
	check(ResourceLoader.has_cached(LAZY_SPELL), "the last folder's file too")
	check_equal(fresh.get_ids(&"rooms"), _names([&"hall"]), "a warmed folder gives its ids")
	check(fresh.get_resource(&"spells", &"spark") is CarrierCard, "and its resources")
	_remove_lazy_content()


func test_a_folder_asked_for_while_warming_is_the_same() -> void:
	_lazy_content()
	var fresh: Node = own(RegistryScript.new()) as Node
	fresh.scan(LAZY_ROOT + "/content", LAZY_ROOT + "/audio")
	fresh.warm_step(0)
	check_equal(fresh.get_ids(&"spells"), _names([&"spark"]), "a folder after the one being warmed loads when asked")
	check_equal(fresh.get_ids(&"rooms"), _names([&"hall"]), "the one being warmed too")
	check(fresh.warm_step(0), "and nothing is left to warm")
	_remove_lazy_content()


func test_the_folder_being_warmed_asked_for_is_loaded_and_warming_goes_on() -> void:
	_lazy_content()
	var fresh: Node = own(RegistryScript.new()) as Node
	fresh.scan(LAZY_ROOT + "/content", LAZY_ROOT + "/audio")
	fresh.warm_step(0)
	check_equal(fresh.get_ids(&"rooms"), _names([&"hall"]), "the folder being warmed loads when asked")
	check(fresh._warmed.is_empty(), "its warmed files are let go once it is registered")
	check(not ResourceLoader.has_cached(LAZY_SPELL), "the next folder is not loaded yet")
	fresh.warm_step(0)
	check(ResourceLoader.has_cached(LAZY_SPELL), "warming goes on with the next folder's first file")
	check(fresh.warm_step(0), "and then everything is loaded")
	_remove_lazy_content()
