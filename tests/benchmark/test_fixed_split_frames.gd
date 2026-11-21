extends SceneTree
## The split screen frames the same on the benchmark's fixed clock (the owner, 2026-11-21, on #901:
## runs of a scenario seemed to frame differently, one picture in one run and split in another):
## the play frames' runner (play_frames_runner.gd, on fixed_steps.gd's clock, one tick a drawn frame)
## plays two players apart in Dynamic, then in Equal, each twice in one process, and the frame's hash
## every HASH_EVERY measured frames, with the split's views mixed in (whether split, how many views,
## the seats, the zoom and the anchor of each: gameplay/feel/split_camera.gd's `views`, the shake
## left out, which is seeded once a process), must be the same in both runs of each. Headless and
## shortened, as test_fixed_fights.gd is. The unit test runner finds it by its name.

const RunnerScript := preload("res://tests/benchmark/play_frames_runner.gd")
const SPLIT_ROWS: Array[String] = ["2p apart dynamic", "2p apart equal"]
const HASH_EVERY: int = 10


class Runner extends "res://tests/benchmark/play_frames_runner.gd":
	## Frames hashed while split, by run.
	var split_frames: PackedInt32Array = PackedInt32Array()

	func _frame_hash() -> int:
		var feel: Node = get_tree().root.get_node_or_null("Feel")
		var screen: Object = feel.get("split_screen") as Object if feel != null else null
		var camera: Object = screen.get("camera") as Object if screen != null else null
		if camera == null:
			return super()
		if get_viewport().get_camera_2d() == null:
			# No current camera (Flow._make_current): both runs alike would still hash the same.
			var none: String = "%s: no current camera while measured" % rows[scenarios[_current]]["label"]
			if not _failures.has(none):
				_failures.append(none)
		var views: ScreenViews = camera.get("views") as ScreenViews
		var parts: Array = [super(), camera.get("split"), views.count]
		for view in views.count:
			parts.append_array([views.seats[view], views.to_screen[view].x.x, views.anchor[view]])
		if bool(camera.get("split")):
			while split_frames.size() < frame_hashes.size():
				split_frames.append(0)
			split_frames[frame_hashes.size() - 1] += 1
		return hash(parts)

	func _finish(failed: Array[String]) -> void:
		var found: Array[String] = failed.duplicate()
		if not fixed_frames:
			found.append("the play frames' runner is not on the fixed clock")
		if frame_hashes.size() != SPLIT_ROWS.size() * 2:
			found.append("%d runs, not %d" % [frame_hashes.size(), SPLIT_ROWS.size() * 2])
		else:
			for i in SPLIT_ROWS.size():
				var first: PackedInt64Array = frame_hashes[i * 2]
				var second: PackedInt64Array = frame_hashes[i * 2 + 1]
				var split: int = split_frames[i * 2] if split_frames.size() > i * 2 else 0
				if first.size() < 5:
					found.append("%s: only %d hashes taken in the first run" % [SPLIT_ROWS[i], first.size()])
				elif split == 0:
					found.append("%s: never split while measured" % SPLIT_ROWS[i])
				elif first != second:
					var at: int = 0
					while at < mini(first.size(), second.size()) and first[at] == second[at]:
						at += 1
					found.append("%s: the second run framed differently from measured frame %d on" % [SPLIT_ROWS[i], (at + 1) * HASH_EVERY])
				else:
					print("FIXED SPLIT FRAMES: %s: %d hashes (%d split) the same in both runs" % [SPLIT_ROWS[i], first.size(), split])
		super(found)


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	var runner := Runner.new()
	var rows: Array[Dictionary] = RunnerScript.play_rows()
	var picked: Array[int] = []
	for label in SPLIT_ROWS:
		for at in rows.size():
			if String(rows[at]["label"]) == label:
				picked.append(at)
				picked.append(at)
	if picked.size() != SPLIT_ROWS.size() * 2:
		printerr("TEST FAILED: a play frames scenario of %s is missing" % [SPLIT_ROWS])
		quit(1)
		return
	runner.scenarios = picked
	runner.warm_up = 1.0
	runner.measure = 2.0
	runner.hash_every = HASH_EVERY
	root.add_child(runner)
