extends SceneTree
## Base class for small, isolated unit tests.
##
## A test script extends this file and holds one method per behaviour, named `test_*`. Each
## method is a test of its own: it builds what it needs (`before_each` is for the shared
## part), checks it, and the suite frees everything it was handed with `own()` afterwards. A
## failing test never stops or changes the next one, and the report names it:
## `TEST FAILED: test_name: what was wrong`.
##
## Keep a test short and about one thing. Assert on behaviour (what happens), not on
## incidental detail (a pixel size, a tuning number, the order of children), unless that
## detail is the contract. Share setup through a fixture file in `tests/support/` or next to
## the test, never through leftover state of an earlier test.
##
## Example (see tests/core/test_svg_art.gd):
##   extends "res://tests/support/suite.gd"
##   func test_something_holds() -> void:
##       check(1 + 1 == 2, "arithmetic works")
##
## godot --headless --path . --script res://tests/<area>/test_<name>.gd
##
## A long test file can be run in several processes side by side: a line `# unit-test-shards: N`
## in it makes the runner (ci/build/unit_tests.sh) start it N times, with the user argument
## `--shard=K/N` (K from 0), and each process runs every Nth test method (by name), from the Kth.
## A long matrix is split into several methods for it (tests/core/test_card_rules.gd).
##
##   godot --headless --path . --script res://tests/core/test_card_rules.gd -- --shard=0/6

const _SUITE_FRAMES := preload("res://core/sim/frames.gd")
const _SUITE_TICK := preload("res://core/sim/tick.gd")

var _failures: Array[String] = []
var _current: String = ""
var _owned: Array[Object] = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	var names: Array[String] = []
	for method: Dictionary in get_method_list():
		var method_name: String = method["name"]
		# A test that overrides one of the script it extends is listed for both: run it once.
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	names.sort()
	var label: String = String(get_script().resource_path).get_file().get_basename()
	if names.is_empty():
		_failures.append("%s: the script has no test_* method" % label)
	var shard: Vector2i = shard_of(OS.get_cmdline_user_args())
	if shard.y > 1:
		names = of_shard(names, shard)
		label += " (shard %d of %d)" % [shard.x + 1, shard.y]
	for method_name in names:
		_current = method_name
		var started: int = Time.get_ticks_msec()
		_still_chance()
		await before_each()
		await call(method_name)
		await after_each()
		_free_owned()
		# The slow ones show in the log (a test of seconds is a candidate for shards).
		print("TEST TIME: %s %d ms" % [method_name, Time.get_ticks_msec() - started])
	if _failures.is_empty():
		print("TEST OK: %s (%d tests)" % [label, names.size()])
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


## The shard a run's user arguments ask for, as (K, N) from `--shard=K/N`; (0, 1) (the whole file)
## without one, or with one that makes no sense.
static func shard_of(args: PackedStringArray) -> Vector2i:
	for arg in args:
		if not arg.begins_with("--shard="):
			continue
		var parts: PackedStringArray = arg.trim_prefix("--shard=").split("/")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			var k: int = parts[0].to_int()
			var n: int = parts[1].to_int()
			if n >= 1 and k >= 0 and k < n:
				return Vector2i(k, n)
	return Vector2i(0, 1)


## The test methods of `names` (sorted) that `shard` (K, N) runs: every Nth, from the Kth.
static func of_shard(names: Array[String], shard: Vector2i) -> Array[String]:
	var mine: Array[String] = []
	for i in names.size():
		if i % shard.y == shard.x:
			mine.append(names[i])
	return mine


## The game's chance starts each test at seed 0 (core/sim/sim.gd), as a fresh process has it: a run
## an earlier test started dealt the game's sim a random seed, and whatever this test makes rolls
## from that sim unless it hands its own. The machine's session rules start as its defaults too
## (core/sim/session_rules.gd, online-ready N11), whatever an earlier test set, and no replay deals.
## And the game goes (online-ready N4): no stop or hold an earlier test left on the game's sim stands
## this one still.
func _still_chance() -> void:
	SessionRules.reset_machine()
	var frames: _SUITE_FRAMES = root.get_node_or_null(^"Frames") as _SUITE_FRAMES
	if frames != null:
		frames.stop_recording()
		frames.stop_playing()
	var clock: _SUITE_TICK = root.get_node_or_null(^"Tick") as _SUITE_TICK
	var game: Sim = clock.sim if clock != null else null
	if game != null:
		game.run_seed = 0
		game.rules = SessionRules.defaults()
		game.hold_left = 0
		game.stops.clear()


## Runs before every test. Override it for setup the tests share.
func before_each() -> void:
	pass


## Runs after every test, before the objects handed to `own()` are freed.
func after_each() -> void:
	pass


## Records a failure, named after the running test, when `condition` is false.
func check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [_current, message])


## `check` for two values that must be equal; the message shows both.
func check_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s: %s (got %s, expected %s)" % [_current, message, str(actual), str(expected)])


## Waits until a command sent now through the game's bus (core/events: the builder's, the sandbox
## page's, the horde's picks) has applied: commands apply at the next tick's start (online-ready
## N2, the Frames autoload). A resume at `physics_frame` comes before that tick's nodes step, so
## it is the second one.
func commands_applied() -> void:
	await physics_frame
	await physics_frame


## Hands an object to the suite: it is freed after the test. Returns it for chaining.
func own(object: Object) -> Object:
	_owned.append(object)
	return object


func _free_owned() -> void:
	for object in _owned:
		if is_instance_valid(object):
			if object is Node and (object as Node).is_inside_tree():
				(object as Node).get_parent().remove_child(object as Node)
			object.free()
	_owned.clear()
