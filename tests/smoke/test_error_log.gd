extends SceneTree
## Tests for the smoke tests' error logger (tests/smoke/error_log.gd): it catches
## an error, a line starting `ERROR:` and the "restart failed" warning, and ignores
## other warnings and other lines. The engine's calls are made by hand: a real
## `push_error` would also print an `ERROR:` line, which `build.sh` counts as a
## failure of this very test. The smoke test itself shows the engine reaches the
## logger only when it fails for real.
##
## godot --headless --path . --script res://tests/smoke/test_error_log.gd

const ErrorLogScript := preload("res://tests/smoke/error_log.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	_test_filter()
	if _failures.is_empty():
		print("TEST OK: tests/smoke/error_log")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_filter() -> void:
	var log: Logger = ErrorLogScript.new()
	var no_trace: Array[ScriptBacktrace] = []
	_check(log.call("get_lines").is_empty(), "a new logger has no lines")
	log.call("_log_error", "f", "a.gd", 1, "code", "a plain warning", false, Logger.ERROR_TYPE_WARNING, no_trace)
	log.call("_log_message", "just a line", false)
	log.call("_log_message", "WARNING: something", true)
	_check(log.call("get_lines").is_empty(), "plain warnings and other lines are ignored")
	log.call("_log_error", "f", "a.gd", 3, "code", "x", false, Logger.ERROR_TYPE_ERROR, no_trace)
	var lines: Array[String] = log.call("get_lines")
	_check(lines.size() == 1 and lines[0].contains("x"), "an error is caught with its text")
	log.call("_log_error", "f", "a.gd", 4, "the code text", "", false, Logger.ERROR_TYPE_SCRIPT, no_trace)
	lines = log.call("get_lines")
	_check(lines.size() == 2 and lines[1].contains("the code text"), "with no rationale the code text is used")
	log.call("_log_message", "ERROR: y", true)
	lines = log.call("get_lines")
	_check(lines.size() == 3 and lines[2] == "ERROR: y", "a line starting ERROR: is caught")
	log.call("_log_error", "f", "a.gd", 5, "code", "Flow: the restart failed (no room)", false, Logger.ERROR_TYPE_WARNING, no_trace)
	lines = log.call("get_lines")
	_check(lines.size() == 4, "the restart-failed warning is caught")
	lines.clear()
	var again: Array[String] = log.call("get_lines")
	_check(again.size() == 4, "get_lines returns a copy")
