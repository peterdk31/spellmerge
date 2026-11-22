extends "res://tests/support/screenshot.gd"
## The shipped benchmark (D1, the owner's decision of 2026-11-22): `benchmark_menu`, the main menu
## with its Benchmark button; `benchmark_results`, the results screen after a short run of one
## two scenarios (`1p start`, `1p near`, a second measured each, so the shot stays quick; the real run measures 10 s a
## scenario); `benchmark_back`, the main menu again after the screen's Back.

const BenchmarkScript := preload("res://bench/benchmark.gd")
## How long the shot's run waits for the results screen, in frames.
const MOST_FRAMES: int = 3600


func _init() -> void:
	pin_room = false


func take() -> void:
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await settle()
	if current_scene == null or current_scene.get_node_or_null("%Benchmark") == null:
		fail("the main menu has no Benchmark button")
		return
	await shot("benchmark_menu")
	var runner: Node = BenchmarkScript.new()
	runner.set(&"scenarios", BenchmarkScript.scenarios_named(runner.get(&"scenarios"), PackedStringArray(["1p start", "1p near"]), runner.get(&"rows")))
	runner.set(&"warm_up", 0.5)
	runner.set(&"measure", 1.0)
	runner.name = "Benchmark"
	root.add_child(runner)
	for i in MOST_FRAMES:
		if root.has_node(^"BenchmarkResults"):
			break
		await process_frame
	if not root.has_node(^"BenchmarkResults"):
		fail("the benchmark did not end on its results screen")
		return
	await settle()
	await shot("benchmark_results")
	(root.get_node(^"BenchmarkResults/Panel/Scroll/Box/Back") as Button).pressed.emit()
	await settle(30)
	if root.has_node(^"BenchmarkResults") or root.has_node(^"Benchmark"):
		fail("Back left the results screen or the runner")
		return
	await shot("benchmark_back")
