extends SceneTree
## Tests for the 4-bot hook in the main menu: the user argument `--four-bot` adds
## exactly one runner node to the root (never a second one), and no argument, or
## an unrelated one, adds none. The runner is a stub from `runner_factory` (the
## real one would play a whole run); a factory that returns nothing stands for a
## build without tests/, which must warn and add nothing.
##
## godot --headless --path . --script res://tests/hud/test_main_menu.gd

const MENU_SCENE_PATH: String = "res://hud/menus/main_menu/main_menu.tscn"
const RUNNER_NODE: String = "FourBotRunner"

var _failures: Array[String] = []
var _built: int = 0


func _initialize() -> void:
	await process_frame
	var menu: Control = (load(MENU_SCENE_PATH) as PackedScene).instantiate() as Control
	menu.set("runner_factory", Callable(self, "_make_stub"))
	root.add_child(menu)
	await process_frame
	_expect(_built == 0 and _count_runners() == 0, "the menu without the argument added a runner")

	_expect(not bool(menu.call("_start_four_bot_test", PackedStringArray())), "no arguments started the test")
	_expect(not bool(menu.call("_start_four_bot_test", PackedStringArray(["--other", "four-bot"]))), "an unrelated argument started the test")
	await process_frame
	_expect(_built == 0 and _count_runners() == 0, "no argument still added a runner")

	_expect(bool(menu.call("_start_four_bot_test", PackedStringArray(["--four-bot"]))), "--four-bot did not start the test")
	await process_frame
	_expect(_count_runners() == 1, "--four-bot added %d runners, expected 1" % _count_runners())

	# The menu entered again, or the argument handled twice in a frame: still one.
	menu.call("_start_four_bot_test", PackedStringArray(["--four-bot"]))
	menu.call("_start_four_bot_test", PackedStringArray(["--four-bot"]))
	await process_frame
	_expect(_count_runners() == 1, "a repeated start left %d runners, expected 1" % _count_runners())

	# The warning path: no runner can be made (the script is not in the build).
	root.get_node(RUNNER_NODE).free()
	menu.set("runner_factory", Callable(self, "_make_nothing"))
	_expect(not bool(menu.call("_start_four_bot_test", PackedStringArray(["--four-bot"]))), "a missing runner reported success")
	await process_frame
	_expect(_count_runners() == 0, "a missing runner still added a node")

	# The stress run and the projectile timings start the same way, each under its own
	# name, and an argument of one never starts another.
	var stress: PackedStringArray = PackedStringArray(["--stress"])
	var timing: PackedStringArray = PackedStringArray(["--projectile-timing"])
	_expect(not bool(menu.call("_start_stress_test", timing)), "--projectile-timing started the stress run")
	_expect(not bool(menu.call("_start_timing_test", stress)), "--stress started the timings")
	_expect(bool(menu.call("_start_stress_test", stress)), "--stress did not start the run")
	_expect(bool(menu.call("_start_timing_test", timing)), "--projectile-timing did not start the timings")
	menu.call("_start_stress_test", stress)
	await process_frame
	_expect(root.has_node("StressRunner") and root.has_node("ProjectileTimingRunner"), "a benchmark runner is missing from the root")
	_expect(_count_named("StressRunner") == 1 and _count_named("ProjectileTimingRunner") == 1, "a repeated start left a second benchmark runner")
	root.get_node("StressRunner").free()
	root.get_node("ProjectileTimingRunner").free()
	for constant in ["STRESS_RUNNER", "TIMING_RUNNER"]:
		_expect(ResourceLoader.exists(String(menu.get(constant))), "%s does not exist" % constant)
	_expect(menu.call("_make_runner", "Nothing") == null, "an unknown runner name made a node")

	# `_ready` is the only caller of the command line lookup, which merges the user
	# arguments (after "--") with the plain ones (the web page `args`). The test run
	# has the script path and no `--four-bot`, so the merge must hold the former only.
	var merged: PackedStringArray = menu.call("_cmdline_arguments") as PackedStringArray
	var expected: int = OS.get_cmdline_user_args().size() + OS.get_cmdline_args().size()
	_expect(merged.size() == expected, "the command line lookup lost arguments")
	_expect(not menu.get("FOUR_BOT_ARGUMENT") in merged, "the test run saw --four-bot")

	# The constant names a file that exists in this build, and the stub-free path loads it.
	_expect(ResourceLoader.exists(String(menu.get("FOUR_BOT_RUNNER"))), "FOUR_BOT_RUNNER does not exist")
	menu.free()
	if _failures.is_empty():
		print("TEST OK: hud/menus main menu 4-bot hook")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _make_stub() -> Node:
	_built += 1
	return Node.new()


func _make_nothing() -> Node:
	return null


func _count_runners() -> int:
	return _count_named(RUNNER_NODE)


func _count_named(node_name: String) -> int:
	var count: int = 0
	for child in root.get_children():
		if child.name == node_name:
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
