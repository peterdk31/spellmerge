extends Logger
## Collects every error the engine logs, for the smoke tests: `push_error` and
## script errors arrive in _log_error (warnings have type ERROR_TYPE_WARNING and
## are ignored, except FAILED_RESTART), and a plain printed line counts as an error
## if it starts with `ERROR:`. It sees only what is logged after OS.add_logger, so
## errors while the autoloads load are not covered.

## The text of the one warning that counts as a failure: Flow gives up a restart
## with a warning, not an error (docs/DECISIONS.md, "Flow").
const FAILED_RESTART: String = "the restart failed"

var _lines: Array[String] = []
var _mutex: Mutex = Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	var text: String = rationale if not rationale.is_empty() else code
	if error_type == ERROR_TYPE_WARNING and not text.contains(FAILED_RESTART):
		return
	_add("%s (%s:%d in %s)" % [text, file, line, function])


func _log_message(message: String, _error: bool) -> void:
	if message.begins_with("ERROR:"):
		_add(message.strip_edges())


## A copy of the lines logged so far.
func get_lines() -> Array[String]:
	_mutex.lock()
	var copy: Array[String] = _lines.duplicate()
	_mutex.unlock()
	return copy


func _add(text: String) -> void:
	_mutex.lock()
	_lines.append(text)
	_mutex.unlock()
