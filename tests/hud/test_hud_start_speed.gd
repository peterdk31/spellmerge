extends "res://tests/support/suite.gd"
## The HUD starts quickly (#972: its start, `Hud._ready`, took about 0.4 s on desktop and 0.18 s of
## the web's boot; tests/hud/test_pause_menu.gd starts one for each of its tests, 255 s on CI). Most
## of it was the action glyphs of the builders and the inventories (hud/widgets/action_glyph.gd), each
## baking its body twice; a body is now baked once for its shape and size and shared. A fresh HUD,
## added to the tree with its services, is ready within `USUAL` times `SLACK` interpreted-GDScript
## references (tests/support/wall_clock.gd); baking each glyph's body afresh, as before, measured
## 76 to 95.
# unit-test-alone
const WallClock := preload("res://tests/support/wall_clock.gd")
const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
const SAVE_PATH: String = "user://test_hud_start_speed_save.cfg"

## A HUD's start in GDScript references (measured on a quiet 4-core container, 2026-11-27: 5.3 to
## 5.5; before #972, 76 to 95), and the slack.
const USUAL: float = 5.5
const SLACK: float = 1.5
const RUNS: int = 3


func after_each() -> void:
	DirAccess.remove_absolute(SAVE_PATH)


## A HUD made and started on services of its own (as tests/hud/test_pause_menu.gd makes one), then freed.
func _start_one() -> void:
	var bus := EventsScript.new()
	var input := InputManagerScript.new()
	input.events = bus
	var focus := UIFocusScript.new()
	focus.input = input
	focus.events = bus
	focus._ready()
	input.add_virtual_device(0)
	var hud: Node = (load(HUD_SCENE_PATH) as PackedScene).instantiate()
	hud.set(&"events", bus)
	hud.set(&"ui_focus", focus)
	hud.set(&"input", input)
	hud.set(&"save", SaveFile.new(SAVE_PATH))
	root.add_child(hud)
	check(hud.is_node_ready(), "the HUD is ready")
	root.remove_child(hud)
	for node: Node in [hud, focus, input, bus]:
		node.free()


func test_a_hud_starts_quickly() -> void:
	# The first start loads the scene and bakes the glyphs once: the ones after are the ones timed.
	_start_one()
	var timed: WallClock.Timed = WallClock.against(_start_one, WallClock.gdscript_reference, RUNS)
	print("BENCH: a HUD's start: %.1f GDScript references (%d us; a reference %d us)" % [timed.multiple, timed.work_usec, timed.reference_usec])
	check(timed.multiple <= USUAL * SLACK, "a HUD started in %.1f GDScript references, within %.1f" % [timed.multiple, USUAL * SLACK])
