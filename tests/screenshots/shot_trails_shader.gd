extends "res://tests/screenshots/shot_trails.gd"
## The trails sheet (`shot_trails.gd`) with the trail shader's own card particles instead of
## Feel's motes (spell spectacle P1d: what the trails looked like before, side by side with it):
## `trails_shader`, `trails_shader_4x`.


func _init() -> void:
	shader_particles = true
	sheet = "trails_shader"
