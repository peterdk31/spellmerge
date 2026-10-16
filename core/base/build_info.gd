class_name BuildInfo
extends RefCounted
## Version, channel and commit of this build.
##
## The release pipeline overwrites build_info.json before exporting; in the
## editor it says "dev".

const _PATH := "res://core/base/build_info.json"

static var _info: Dictionary = {}


static func version() -> String:
	return str(_load().get("version", "dev"))


static func channel() -> String:
	return str(_load().get("channel", "dev"))


static func commit() -> String:
	return str(_load().get("commit", ""))


## One line for menus and bug reports, e.g. "v0.20261017 nightly (a1b2c3d)".
static func describe() -> String:
	if channel() == "dev":
		return "development build"
	var text := "%s %s" % [version(), channel()]
	if not commit().is_empty():
		text += " (%s)" % commit().left(7)
	return text


static func _load() -> Dictionary:
	if _info.is_empty():
		var raw := FileAccess.get_file_as_string(_PATH)
		var parsed: Variant = JSON.parse_string(raw)
		_info = parsed if parsed is Dictionary else {"version": "dev", "channel": "dev"}
	return _info
