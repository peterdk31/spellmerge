extends "res://tests/support/suite.gd"
## Feel draws the art its preset names, so art is swapped without touching `feel.gd`: a preset
## with other textures puts those textures on the projectile manager. Which pictures ship is
## free to change; this checks only that the preset decides.

const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const EventsScript := preload("res://core/events/events.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")


func _texture() -> Texture2D:
	return ImageTexture.create_from_image(Image.create_empty(8, 8, false, Image.FORMAT_RGBA8))


## Feel wired to a fresh manager and bus, in the tree so `_ready` runs. Freed by the suite.
func _start(preset: FeelPresetScript, projectiles: Node) -> Node:
	var feel: Node = own(FeelScript.new()) as Node
	feel.events = own(EventsScript.new())
	feel.projectiles = projectiles
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)
	return feel


func test_preset_textures_reach_the_projectile_manager() -> void:
	var preset := FeelPresetScript.new()
	preset.bolt_texture = _texture()
	preset.hostile_texture = _texture()
	var projectiles: Node = own(ProjectilesScript.new()) as Node
	_start(preset, projectiles)
	check(projectiles.texture == preset.bolt_texture, "the player's shots use the preset's bolt")
	check(projectiles.hostile_texture == preset.hostile_texture, "enemy shots use the preset's own art")
	check(projectiles.texture != projectiles.hostile_texture, "the two kinds of shot are different art")


func test_a_default_preset_ships_art_for_every_slot() -> void:
	var preset := FeelPresetScript.new()
	check(preset.spark_texture != null, "spark art")
	check(preset.bolt_texture != null, "bolt art")
	check(preset.hostile_texture != null, "hostile shot art")


func test_a_manager_that_already_has_art_keeps_it() -> void:
	var art: Texture2D = _texture()
	var projectiles: Node = own(ProjectilesScript.new()) as Node
	projectiles.texture = art
	_start(FeelPresetScript.new(), projectiles)
	check(projectiles.texture == art, "feel does not overwrite art set by someone else")
