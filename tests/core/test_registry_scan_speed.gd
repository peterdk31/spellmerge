extends "res://tests/support/suite.gd"
## The registry's scan is quick (#972: on the web it took 1.4 to 1.8 s of the boot, before the menu,
## most of it the rooms, each `.tres` loading its whole scene with its art). A scan now lists the
## files and loads none; a folder loads when it is first asked for, or a few milliseconds a frame
## once the game runs (core/registry/registry.gd). A fresh registry's scan of the game's content is
## within `USUAL` times `SLACK` interpreted-GDScript references (tests/support/wall_clock.gd).
## Loading every folder at the scan, as before, measures 8 to 11 here (printed too), so it
## fails, though a test's game has every resource in the cache already: on the boot's first load the
## old scan cost far more.
# unit-test-alone
const WallClock := preload("res://tests/support/wall_clock.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## A scan in GDScript references, and the slack; and a scan that loads every folder, as before,
## measured 8.1 to 11.1. The usual is CI's runners' (godot-tests), where the scan, the file system's
## work more than the interpreter's, costs about 1.7 times what it does on a quiet 4-core container:
## the old scan, which walked the content twice and opened each directory twice a walk, measured 6.4
## to 6.6 there and 3.6 to 4.0 here (2026-11-28), at the budget's edge. The one walk measures
## 2.3 to 2.4 here, so about 4.0 there.
const USUAL: float = 4.0
const SLACK: float = 1.5
const RUNS: int = 3


func _scan() -> void:
	var fresh: Node = RegistryScript.new()
	fresh.scan()
	fresh.free()


func _scan_and_load_all() -> void:
	var fresh: Node = RegistryScript.new()
	fresh.scan()
	fresh.get_folders()
	fresh.free()


func test_a_scan_loads_nothing_and_is_quick() -> void:
	var timed: WallClock.Timed = WallClock.against(_scan, WallClock.gdscript_reference, RUNS)
	var all: WallClock.Timed = WallClock.against(_scan_and_load_all, WallClock.gdscript_reference, RUNS)
	print("BENCH: the registry's scan: %.1f GDScript references (%d us; a reference %d us); loading every folder too: %.1f" % [timed.multiple, timed.work_usec, timed.reference_usec, all.multiple])
	check(timed.multiple <= USUAL * SLACK, "a scan took %.1f GDScript references, within %.1f" % [timed.multiple, USUAL * SLACK])
	check(all.multiple > USUAL * SLACK, "loading every folder at the scan, as before, would fail the budget (%.1f)" % all.multiple)


func test_a_scan_of_the_game_loads_no_folder() -> void:
	var fresh: Node = own(RegistryScript.new()) as Node
	fresh.scan()
	check(fresh._resources.is_empty(), "a scan registers no folder")
	check(fresh._unloaded.has(&"rooms") and fresh._unloaded.has(&"spells"), "it lists the game's folders, the rooms and spells among them")


func test_the_one_walk_lists_what_the_two_walks_did() -> void:
	var fresh: Node = own(RegistryScript.new()) as Node
	fresh.scan()
	var sounds: PackedStringArray = PackedStringArray()
	RegistryScript._collect_sounds(RegistryScript.DEFAULT_CONTENT_ROOT, RegistryScript.SOUND_EXTENSIONS, false, sounds)
	sounds.sort()
	var walked: PackedStringArray = PackedStringArray()
	for folder: StringName in fresh._order:
		var tres: PackedStringArray = PackedStringArray()
		var seek: bool = String(folder) != RegistryScript.VARIANTS_FOLDER
		RegistryScript._walk_content(RegistryScript.DEFAULT_CONTENT_ROOT.path_join(String(folder)), RegistryScript.SOUND_EXTENSIONS, true, seek, seek and String(folder) == RegistryScript.SOUNDS_FOLDER, tres, walked)
		var before: PackedStringArray = RegistryScript._find_files(RegistryScript.DEFAULT_CONTENT_ROOT.path_join(String(folder)), PackedStringArray(["tres"]), RegistryScript.SOUNDS_FOLDER)
		check(fresh._unloaded[folder] == before, "the scan lists %s's .tres files as `_find_files` does" % folder)
	walked.sort()
	check(not sounds.is_empty() and walked == sounds, "the walk finds the content's sound files as `_collect_sounds` does (%d, %d)" % [walked.size(), sounds.size()])
