class_name SaveFile
extends RefCounted
## The save (living staffs H6): what one player's copy of the game remembers between plays, in
## one ConfigFile under `user://` (`path`, by default DEFAULT_PATH). So far it holds flags only:
## `has_flag(key)` and `set_flag(key)`, and settings: `get_setting(key, fallback)` and
## `set_setting(key, value)`, each written at once. A missing or unreadable file is a new
## save. Runs and unlocks join it when they exist (M3).

const DEFAULT_PATH: String = "user://save.cfg"
const SECTION: String = "flags"
const SETTINGS_SECTION: String = "settings"

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


## The saved value of setting `key`, or `fallback` when it was never saved.
func get_setting(key: StringName, fallback: Variant) -> Variant:
	return _config.get_value(SETTINGS_SECTION, String(key), fallback)


## Save `value` as setting `key` and write it. Returns false if it could not be written (it is
## still set for this session). Settings never make a save "not new": only flags do.
func set_setting(key: StringName, value: Variant) -> bool:
	_config.set_value(SETTINGS_SECTION, String(key), value)
	return _config.save(path) == OK
