extends SceneTree
## The benchmark's fights play from a fixed script (the owner, 2026-11-21: "so each run is the same
## and the fight rows stop jumping"): the play frames' runner (play_frames_runner.gd, on the fixed
## clock of fixed_steps.gd, one tick a drawn frame) plays one fight scenario twice in one process, the
## first behind the first Play's load, and the frame's hash (the game's state, the camera's place and
## zoom) every HASH_EVERY measured frames must be the same in both: the same frames twice. Headless
## and shortened (a second's warm-up, two measured); the frame times are the full run's
## (play_frames.gd, in a window). The unit test runner finds it by its name, as every test_*.gd.

const RunnerScript := preload("res://tests/benchmark/play_frames_runner.gd")
## A fight: one wizard and its bot among a room's foes, at the web's load.
const SCENARIO: String = "1p far web"
const HASH_EVERY: int = 10


class Runner extends "res://tests/benchmark/play_frames_runner.gd":
	func _finish(failed: Array[String]) -> void:
		var found: Array[String] = failed.duplicate()
		if not fixed_frames:
			found.append("the play frames' runner is not on the fixed clock")
		if frame_hashes.size() != 2:
			found.append("the scenario ran %d times, not 2" % frame_hashes.size())
		else:
			var first: PackedInt64Array = frame_hashes[0]
			var second: PackedInt64Array = frame_hashes[1]
			if first.size() < 5:
				found.append("only %d hashes taken in the first run" % first.size())
			elif first != second:
				var at: int = 0
				while at < mini(first.size(), second.size()) and first[at] == second[at]:
					at += 1
				found.append("the second run differs from the first from measured frame %d on (%d and %d hashes)" % [(at + 1) * HASH_EVERY, first.size(), second.size()])
			else:
				print("FIXED FIGHTS: %d hashes the same in both runs" % first.size())
		super(found)


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	var runner := Runner.new()
	var rows: Array[Dictionary] = RunnerScript.play_rows()
	var index: int = -1
	for at in rows.size():
		if String(rows[at]["label"]) == SCENARIO:
			index = at
	if index < 0:
		printerr("TEST FAILED: no play frames scenario %s" % SCENARIO)
		quit(1)
		return
	runner.scenarios = [index, index] as Array[int]
	runner.warm_up = 1.0
	runner.measure = 2.0
	runner.hash_every = HASH_EVERY
	root.add_child(runner)
