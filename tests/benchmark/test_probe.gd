extends SceneTree
## Tests for tests/benchmark/probe.gd: it counts frames, finds the percentile, and
## reports without failing.
##
## godot --headless --path . --script res://tests/benchmark/test_probe.gd

const ProbeScript := preload("res://tests/benchmark/probe.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	var probe: Node = ProbeScript.new()
	root.add_child(probe)
	_check(probe.call("percentile_95") == 0.0, "no samples: percentile 0")
	probe.call("report")
	for i in 10:
		await process_frame
	var frames: int = probe.call("frame_count")
	_check(frames > 0, "frames are counted (%d)" % frames)
	_check(float(probe.call("percentile_95")) >= 0.0, "a percentile exists after frames")
	_check(float(probe.call("steps_per_frame_average")) > 0.0, "physics steps per frame are counted")
	_check(int(probe.call("steps_per_frame_max")) >= 1, "at least one physics step ran in the busiest frame")
	_check(FeelScript.PARTICLE_LIMIT > 0, "the particle limit constant is readable")
	probe.call("report")
	probe.free()
	_check_known_samples()
	if _failures.is_empty():
		print("test_probe: OK")
		quit(0)
	else:
		for failure in _failures:
			printerr("test_probe FAILED: " + failure)
		quit(1)


## Known samples: 1..20 ms, then three more frames past a cap of 20.
func _check_known_samples() -> void:
	var probe: Node = ProbeScript.new()
	probe.set("max_samples", 20)
	root.add_child(probe)
	for i in range(1, 21):
		probe.call("record", float(i))
	_check(absf(float(probe.call("average_ms")) - 10.5) < 0.001, "average of 1..20 is 10.5")
	_check(float(probe.call("max_ms")) == 20.0, "max of 1..20 is 20")
	_check(float(probe.call("percentile_95")) == 20.0, "p95 of 1..20 is 20 (index 19)")
	for i in 3:
		probe.call("record", 100.0)
	_check(int(probe.call("frame_count")) == 23, "frames past the cap still count")
	_check(float(probe.call("max_ms")) == 100.0, "frames past the cap still feed the max")
	_check(float(probe.call("percentile_95")) == 20.0, "frames past the cap leave the percentile alone")
	probe.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
