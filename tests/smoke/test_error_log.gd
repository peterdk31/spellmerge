extends "res://tests/support/suite.gd"
## Tests for the smoke tests' error logger (tests/smoke/error_log.gd), one kind of log line per
## test, each on a new logger: it catches an error (with its text, or its code text when it has no
## rationale), a line starting `ERROR:` and the "restart failed" warning, and ignores other
## warnings and other lines; `get_lines` hands out a copy. The engine's calls are made by hand: a
## real `push_error` would also print an `ERROR:` line, which `build.sh` counts as a failure of
## this very test. The smoke test itself shows the engine reaches the logger only when it fails
## for real.

const ErrorLogScript := preload("res://tests/smoke/error_log.gd")

var logger: Logger
var no_trace: Array[ScriptBacktrace] = []


func before_each() -> void:
	logger = ErrorLogScript.new()


func after_each() -> void:
	logger = null


func _lines() -> Array[String]:
	return logger.call("get_lines")


func _error(code: String, rationale: String, error_type: int) -> void:
	logger.call("_log_error", "f", "a.gd", 1, code, rationale, false, error_type, no_trace)


func test_a_new_logger_has_no_lines() -> void:
	check(_lines().is_empty(), "a new logger has no lines")


func test_a_plain_warning_is_ignored() -> void:
	_error("code", "a plain warning", Logger.ERROR_TYPE_WARNING)
	check(_lines().is_empty(), "a plain warning is ignored")


func test_a_printed_line_is_ignored() -> void:
	logger.call("_log_message", "just a line", false)
	check(_lines().is_empty(), "a plain printed line is ignored")


func test_a_printed_warning_line_is_ignored() -> void:
	logger.call("_log_message", "WARNING: something", true)
	check(_lines().is_empty(), "a printed WARNING: line is ignored")


func test_an_error_is_caught_with_its_text() -> void:
	_error("code", "x", Logger.ERROR_TYPE_ERROR)
	var lines: Array[String] = _lines()
	check(lines.size() == 1 and lines[0].contains("x"), "an error is caught with its text: %s" % [lines])


func test_an_error_without_rationale_is_caught_with_its_code_text() -> void:
	_error("the code text", "", Logger.ERROR_TYPE_SCRIPT)
	var lines: Array[String] = _lines()
	check(lines.size() == 1 and lines[0].contains("the code text"), "with no rationale the code text is used: %s" % [lines])


func test_a_printed_line_starting_error_is_caught() -> void:
	logger.call("_log_message", "ERROR: y", true)
	check_equal(_lines(), ["ERROR: y"] as Array[String], "a line starting ERROR: is caught as it is")


func test_the_restart_failed_warning_is_caught() -> void:
	_error("code", "Flow: the restart failed (no room)", Logger.ERROR_TYPE_WARNING)
	check_equal(_lines().size(), 1, "the restart-failed warning is caught")


func test_get_lines_returns_a_copy() -> void:
	_error("code", "x", Logger.ERROR_TYPE_ERROR)
	_lines().clear()
	check_equal(_lines().size(), 1, "clearing what get_lines returned leaves the logger's lines")
