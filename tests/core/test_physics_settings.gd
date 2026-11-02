extends "res://tests/support/suite.gd"
## The physics clock's settings in project.godot (performance, 2026-11-02). When a physics step
## costs more than a frame, the engine runs catch-up steps in the next frame, each as slow, so
## the frame gets slower still: at Godot's default of 8 a frame, the desktop stress scene sat at
## 8 steps and 343 ms a frame. With a few at most, a frame that slow plays in slow motion instead
## and comes back as soon as the load drops.
##
## godot --headless --path . --script res://tests/core/test_physics_settings.gd


func test_few_catch_up_steps() -> void:
	var steps: int = ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame", 8)
	check(steps >= 2 and steps <= 4, "at most a few physics steps a frame (real time down to 15-30 FPS): %d" % steps)
	check_equal(Engine.max_physics_steps_per_frame, steps, "the engine runs with it")


func test_sixty_steps_a_second() -> void:
	check_equal(Engine.physics_ticks_per_second, 60, "the game's numbers are tuned at 60 steps a second")
