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
	_check(frames >= 8 and frames <= 10, "frames are counted (%d)" % frames)
	_check(float(probe.call("percentile_95")) >= 0.0, "a percentile exists after frames")
	_check(FeelScript.PARTICLE_LIMIT > 0, "the particle limit constant is readable")
	probe.call("report")
	probe.free()
	if _failures.is_empty():
		print("test_probe: OK")
		quit(0)
	else:
		for failure in _failures:
			printerr("test_probe FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
