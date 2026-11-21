extends "res://tests/support/suite.gd"
## A run's camera is the current one even when the run starts inside a group call (gameplay/flow/
## flow.gd, `_make_current`; found on the benchmark's fixed clock, 2026-11-21: in some processes a
## run had no current camera, so the split and the party camera framed nothing). Godot skips, for the
## rest of a group call (or a processing pass), the nodes that left a group during it, by their
## address; a camera made where a node freed earlier in it was is skipped by its own `make_current` (a
## group call too), which then does nothing. Here a camera is freed and a new one made inside a group
## call; Flow's helper makes it current by the frame's end.

const FlowScript := preload("res://gameplay/flow/flow.gd")
const GROUP: StringName = &"test_camera_current_probe"
## Tries: a freed camera's memory is not always the next one's.
const TRIES: int = 8


class Probe extends Node:
	var holder: SubViewport = null
	var made: Camera2D = null
	## Whether the new camera's own `make_current` (without Flow's helper) took.
	var plain_took: bool = true
	var use_helper: bool = true

	func swap() -> void:
		var old: Camera2D = holder.get_camera_2d()
		if old != null:
			old.free()
		made = Camera2D.new()
		holder.add_child(made)
		made.make_current()
		plain_took = made.is_current()
		if use_helper:
			FlowScript._make_current(made)


func _round(use_helper: bool) -> Array[bool]:
	var holder := own(SubViewport.new()) as SubViewport
	holder.disable_3d = true
	root.add_child(holder)
	var first := Camera2D.new()
	holder.add_child(first)
	first.make_current()
	var probe := own(Probe.new()) as Probe
	probe.holder = holder
	probe.use_helper = use_helper
	probe.add_to_group(GROUP)
	root.add_child(probe)
	root.get_tree().call_group(GROUP, &"swap")
	await root.get_tree().process_frame
	var out: Array[bool] = [probe.plain_took, probe.made.is_current()]
	probe.remove_from_group(GROUP)
	return out


func test_a_camera_made_inside_a_group_call_is_current_by_the_frame_end() -> void:
	var skipped: int = 0
	for i in TRIES:
		var got: Array[bool] = await _round(true)
		if not got[0]:
			skipped += 1
		check(got[1], "try %d: the new camera is the current one by the frame's end (its own make_current took: %s)" % [i, got[0]])
	print("CAMERA CURRENT: the plain make_current was skipped in %d of %d tries" % [skipped, TRIES])
	# Else the swap showed nothing (the freed camera's memory never reused): the case is not tested.
	check(skipped > 0, "the swap reproduces the skipped make_current (%d of %d tries)" % [skipped, TRIES])
