class_name SaveFile
extends RefCounted
## The save (living staffs H6): what one player's copy of the game remembers between plays, in
## one ConfigFile under `user://` (`path`, by default DEFAULT_PATH). So far it holds flags only:
## `has_flag(key)` and `set_flag(key)`, written at once. A missing or unreadable file is a new
## save. Runs, unlocks and settings join it when they exist (M3).

const DEFAULT_PATH: String = "user://save.cfg"
const SECTION: String = "flags"

## Where the save lives; under `user://` only (AGENTS.md, hard rules).
var path: String = DEFAULT_PATH

var _config: ConfigFile = null


func _init(at: String = DEFAULT_PATH) -> void:
	path = at if at.begins_with("user://") else DEFAULT_PATH
	_config = ConfigFile.new()
	# A missing or broken file is a new save.
	if _config.load(path) != OK:
		_config = ConfigFile.new()


## True once `key` was set on this save.
func has_flag(key: StringName) -> bool:
	return bool(_config.get_value(SECTION, String(key), false))


## Set `key` on this save and write it. Returns false if it could not be written (it is still
## set for this session).
func set_flag(key: StringName) -> bool:
	_config.set_value(SECTION, String(key), true)
	return _config.save(path) == OK


## True when nothing was ever set: a new save.
func is_new() -> bool:
	return not _config.has_section(SECTION)
