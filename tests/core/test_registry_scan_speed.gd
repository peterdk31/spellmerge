extends "res://tests/support/suite.gd"
## The registry's scan is quick (#972: on the web it took 1.4 to 1.8 s of the boot, before the menu,
## most of it the rooms, each `.tres` loading its whole scene with its art). A scan now lists the
## files and loads none; a folder loads when it is first asked for, or a few milliseconds a frame
## once the game runs (core/registry/registry.gd). A fresh registry's scan of the game's content is
## within `USUAL` times `SLACK` interpreted-GDScript references (tests/support/wall_clock.gd).
## Loading every folder at the scan, as before, measures 10.0 to 10.4 here (printed too), so it
## fails, though a test's game has every resource in the cache already: on the boot's first load the
## old scan cost far more.
# unit-test-alone
const WallClock := preload("res://tests/support/wall_clock.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## A scan in GDScript references (measured on a quiet 4-core container, 2026-11-27: 3.9 to 4.3), and
## the slack; and a scan that loads every folder, as before, measured 10.0 to 10.4.
const USUAL: float = 4.1
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
