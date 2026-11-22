extends "res://tests/support/suite.gd"
## Tests for the main menu's test-runner hooks, one behaviour per test: the user argument
## `--four-bot` adds exactly one runner node to the root (never a second one), and no argument, or
## an unrelated one, adds none. The stress run (`--stress`) and the projectile timings
## (`--projectile-timing`) start the same way, each under its own name. The runner is a stub from
## `runner_factory` (the real one would play a whole run); a factory that returns nothing stands
## for a build without tests/, which must warn and add nothing. Each runner's literal `load` path
## is its constant, and one real runner is made (not added) through the real path. Play has the
## focus in every build (it is the menu's first button) and sends `hub_requested(0)`.
##
## Each test gets a menu of its own (its own event bus), freed after it with any runner it added.

const MENU_SCENE_PATH: String = "res://hud/menus/main_menu/main_menu.tscn"
const EventsScript := preload("res://core/events/events.gd")
const RUNNER_NODE: String = "FourBotRunner"
const RUNNER_NAMES: Array[String] = ["FourBotRunner", "StressRunner", "ProjectileTimingRunner", "HubStormRunner", "ReplayHashesRunner", "OnlineRunner"]
const FOUR_BOT: PackedStringArray = ["--four-bot"]
const STRESS: PackedStringArray = ["--stress"]
const TIMING: PackedStringArray = ["--projectile-timing"]

var _built: int = 0
var _menu: Control


func before_each() -> void:
	_built = 0
	var bus := own(EventsScript.new()) as EventsScript
	_menu = (load(MENU_SCENE_PATH) as PackedScene).instantiate() as Control
	_menu.set("events", bus)
	_menu.set("runner_factory", _make_stub)
	root.add_child(own(_menu))
	await process_frame


func after_each() -> void:
	for node_name in RUNNER_NAMES:
		var runner: Node = root.get_node_or_null(NodePath(node_name))
		if runner != null:
			runner.free()


func _make_stub() -> Node:
	_built += 1
	return Node.new()


func _make_nothing() -> Node:
	return null


func _start(method: StringName, args: PackedStringArray) -> bool:
	return bool(_menu.call(method, args))


func _count_named(node_name: String) -> int:
	var count: int = 0
	for child in root.get_children():
		if child.name == node_name:
			count += 1
	return count


func test_entering_the_menu_without_the_argument_adds_no_runner() -> void:
	check_equal(_built, 0, "no runner was made")
	check_equal(_count_named(RUNNER_NODE), 0, "no runner on the root")


func test_no_arguments_start_no_runner() -> void:
	check(not _start(&"_start_four_bot_test", PackedStringArray()), "no arguments started the test")
	await process_frame
	check(_built == 0 and _count_named(RUNNER_NODE) == 0, "no argument still added a runner")


func test_an_unrelated_argument_starts_no_runner() -> void:
	check(not _start(&"_start_four_bot_test", PackedStringArray(["--other", "four-bot"])), "an unrelated argument started the test")
	await process_frame
	check(_built == 0 and _count_named(RUNNER_NODE) == 0, "an unrelated argument still added a runner")


func test_four_bot_adds_one_runner_to_the_root() -> void:
	check(_start(&"_start_four_bot_test", FOUR_BOT), "--four-bot did not start the test")
	await process_frame
	check_equal(_count_named(RUNNER_NODE), 1, "--four-bot adds one runner")


func test_a_repeated_four_bot_start_leaves_one_runner() -> void:
	# The menu entered again, or the argument handled twice in a frame: still one.
	_start(&"_start_four_bot_test", FOUR_BOT)
	await process_frame
	_start(&"_start_four_bot_test", FOUR_BOT)
	_start(&"_start_four_bot_test", FOUR_BOT)
	await process_frame
	check_equal(_count_named(RUNNER_NODE), 1, "a repeated start leaves one runner")


func test_a_build_without_the_runner_ignores_the_argument() -> void:
	# The warning path: no runner can be made (the script is not in the build).
	_menu.set("runner_factory", _make_nothing)
	check(not _start(&"_start_four_bot_test", FOUR_BOT), "a missing runner reported success")
	await process_frame
	check_equal(_count_named(RUNNER_NODE), 0, "a missing runner still added a node")


func test_an_argument_of_one_benchmark_never_starts_another() -> void:
	check(not _start(&"_start_stress_test", TIMING), "--projectile-timing started the stress run")
	check(not _start(&"_start_timing_test", STRESS), "--stress started the timings")


func test_each_benchmark_argument_adds_its_runner_under_its_own_name() -> void:
	check(_start(&"_start_stress_test", STRESS), "--stress did not start the run")
	check(_start(&"_start_timing_test", TIMING), "--projectile-timing did not start the timings")
	await process_frame
	check(root.has_node("StressRunner"), "the stress runner is on the root")
	check(root.has_node("ProjectileTimingRunner"), "the timing runner is on the root")
	check(root.has_node("StressRunner") and root.get_node("StressRunner").get_class() == "Node", "the stub was used for the stress run")


func test_a_repeated_benchmark_start_leaves_one_runner() -> void:
	_start(&"_start_stress_test", STRESS)
	_start(&"_start_stress_test", STRESS)
	await process_frame
	check_equal(_count_named("StressRunner"), 1, "a repeated start leaves one stress runner")


func test_every_runner_constant_names_a_file_in_the_build() -> void:
	for constant: String in ["FOUR_BOT_RUNNER", "STRESS_RUNNER", "TIMING_RUNNER", "STORM_RUNNER", "SPLIT_VIEWS_RUNNER", "REPLAY_HASHES_RUNNER", "ONLINE_RUNNER", "BENCHMARK_RUNNER"]:
		check(ResourceLoader.exists(String(_menu.get(constant))), "%s does not exist" % constant)


func test_an_unknown_runner_name_makes_nothing() -> void:
	check(_menu.call("_make_runner", "Nothing") == null, "an unknown runner name made a node")


func test_each_runner_loads_the_file_its_constant_names() -> void:
	# Each literal path in the menu is its constant (the real runners are not made here).
	for pair: Array in [["StressRunner", "STRESS_RUNNER"], ["ProjectileTimingRunner", "TIMING_RUNNER"], ["HubStormRunner", "STORM_RUNNER"], ["SplitViewsRunner", "SPLIT_VIEWS_RUNNER"], ["ReplayHashesRunner", "REPLAY_HASHES_RUNNER"], ["OnlineRunner", "ONLINE_RUNNER"], ["Benchmark", "BENCHMARK_RUNNER"], [RUNNER_NODE, "FOUR_BOT_RUNNER"]]:
		var script: GDScript = _menu.call("_runner_script", pair[0]) as GDScript
		check(script != null and script.resource_path == String(_menu.get(pair[1])), "%s does not load %s" % [pair[0], pair[1]])


func test_a_real_runner_is_made_through_the_real_path() -> void:
	# Freed before it enters the tree (it starts its work only once added), so a typo in a `load`
	# literal fails here.
	var real: Node = _menu.call("_make_runner", "ProjectileTimingRunner") as Node
	check(real != null, "the real timing runner was not made")
	if real != null:
		real.free()


func test_the_command_line_lookup_holds_the_user_and_the_plain_arguments() -> void:
	# `_ready` is the only caller of the lookup, which merges the user arguments (after "--") with
	# the plain ones (the web page `args`). The test run has no `--four-bot`, so the merge must not
	# hold one.
	var merged: PackedStringArray = _menu.call("_cmdline_arguments") as PackedStringArray
	check_equal(merged.size(), OS.get_cmdline_user_args().size() + OS.get_cmdline_args().size(), "the lookup holds every argument")
	check(not _menu.get("FOUR_BOT_ARGUMENT") in merged, "the test run saw --four-bot")


func test_play_has_the_focus_and_takes_everyone_to_the_hub() -> void:
	var play := _menu.get_node("%Play") as Button
	check(play.has_focus(), "Play has the focus in every build, so one press starts the game")
	var asked: Array[int] = []
	(_menu.get("events") as EventsScript).hub_requested.connect(func(player: int) -> void: asked.append(player))
	play.pressed.emit()
	check_equal(asked, [0] as Array[int], "Play sends hub_requested(0)")


func test_its_sounds_a_silent_move_a_choice_and_cancel_a_back() -> void:
	var sounds: Array[StringName] = []
	(_menu.get("events") as EventsScript).ui_sound_requested.connect(func(id: StringName) -> void: sounds.append(id))
	await process_frame
	(_menu.get_node("%Join") as Button).grab_focus()
	check_equal(sounds, [] as Array[StringName], "the focus moving to Join makes no sound")
	sounds.clear()
	await process_frame
	(_menu.get_node("%Join") as Button).pressed.emit()
	check_equal(sounds, [UiSounds.CHOOSE], "Join pressed is a choice, and the box it focuses no move")
	sounds.clear()
	await process_frame
	(_menu.get_node("%Cancel") as Button).pressed.emit()
	check_equal(sounds, [UiSounds.BACK], "Cancel is a back, and Host's focus after it no move")
