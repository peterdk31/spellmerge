extends "res://tests/support/suite.gd"
## The render thread (the owner's decision of 2026-11-22; core/README.md, "The render thread"): the
## desktop builds draw on Godot's separate render thread, the web on the main thread as before. The
## desktop exports carry the feature `render_thread`, and project.godot sets the thread model for it
## alone, so the web, the editor and the build's own runs from the project stay on the safe model;
## `--render-thread safe` on a desktop build's command line switches it back for a run, and
## `--render-thread separate` tries it from the project.

const SETTING: String = "rendering/driver/threads/thread_model"
const FEATURE: String = "render_thread"
## Godot's separate thread model (the setting's value).
const SEPARATE: int = 2


## The `[rendering]` section's lines of project.godot.
func _rendering_lines() -> PackedStringArray:
	var text: String = FileAccess.get_file_as_string("res://project.godot")
	return text.get_slice("\n[rendering]\n", 1).get_slice("\n[", 0).split("\n", false)


func test_the_feature_draws_on_a_separate_render_thread_and_nothing_else_does() -> void:
	var lines: PackedStringArray = _rendering_lines()
	check(lines.has("driver/threads/thread_model.%s=%d" % [FEATURE, SEPARATE]), "project.godot sets %s.%s to separate (%d)" % [SETTING, FEATURE, SEPARATE])
	for line: String in lines:
		if line.begins_with("driver/threads/thread_model") and not line.begins_with("driver/threads/thread_model.%s=" % FEATURE):
			check(false, "only the render thread feature's override is set: %s" % line)


func test_every_desktop_export_has_the_feature_and_the_web_none() -> void:
	var presets := ConfigFile.new()
	check_equal(presets.load("res://export_presets.cfg"), OK, "the presets load")
	var desktops: int = 0
	for section: String in presets.get_sections():
		if section.ends_with(".options") or not presets.has_section_key(section, "platform"):
			continue
		var platform: String = String(presets.get_value(section, "platform"))
		var features: PackedStringArray = String(presets.get_value(section, "custom_features", "")).split(",", false)
		if platform == "Web":
			check(not features.has(FEATURE), "%s (the web) draws on the main thread" % section)
		else:
			desktops += 1
			check(features.has(FEATURE), "%s (%s) has the feature %s" % [section, platform, FEATURE])
	check(desktops >= 2, "the desktop presets are found: %d" % desktops)
