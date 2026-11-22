extends "res://bench/play_frames_runner.gd"
## The benchmark mode of the shipped builds (D1, the owner's decision of 2026-11-22: the game is
## optimised for the Windows and Linux builds, measured on the owner's own PC): the play frames'
## scenarios on the fixed clock (play_frames_runner.gd, biome_frames_runner.gd, fixed_steps.gd: one
## tick a drawn frame, the fights from a fixed script, so every run plays the same), at the
## desktop's settings, then a results screen to screenshot (`results_screen.gd`) and the same table
## in `user://benchmark.txt`. Started from the main menu by the user argument `--benchmark`
## (hud/menus/main_menu): `Spellmerge.exe -- --benchmark` on Windows, `./Spellmerge.x86_64 --
## --benchmark` on Linux; `--only=` (labels, comma separated) and `--picture=1280x720` as the play
## frames take them (bench/README.md).
##
## A row a scenario: the frame's mean, 95th percentile and worst milliseconds, the simulation's
## (the Tick's steps), Feel's step, the GPU's and the renderer's CPU time where Godot reports them
## (0 where it does not), and the draw calls and primitives a frame. A scenario that did not reach
## its numbers (fewer foes or shots than asked, a bot that never cast) is noted under the table, not
## failed: the times are what is wanted here.

const MachineInfoScript := preload("res://bench/machine_info.gd")
const ResultsScreenScript := preload("res://bench/results_screen.gd")

## The scenarios run when `--only=` names none: one wizard at the start, near and far, then the
## split screen at its busiest in each mode (play_frames_runner.gd's labels).
const DEFAULT_LABELS: PackedStringArray = ["1p start", "1p near", "1p far", "2p apart dynamic", "4p apart equal"]
## Where the table is written (and its name shown on the results screen).
const RESULTS_FILE: String = "user://benchmark.txt"
## The table's columns, in the order of `row_cells`.
const ROW_COLUMNS: PackedStringArray = ["Scenario", "Frame ms", "p95", "Worst", "Sim", "Feel", "GPU", "Render CPU", "Calls", "Primitives"]


func _init() -> void:
	super()
	scenarios = scenarios_named(scenarios, DEFAULT_LABELS, rows)
	result_word = "BENCHMARK"


## One summary's cells, in `ROW_COLUMNS`' order.
static func row_cells(summary: Dictionary) -> PackedStringArray:
	return PackedStringArray([
		String(summary.get("label", "")),
		"%.2f" % float(summary.get("frame_ms", 0.0)),
		"%.2f" % float(summary.get("p95_ms", 0.0)),
		"%.2f" % float(summary.get("worst_ms", 0.0)),
		"%.2f" % float(summary.get("sim_ms", 0.0)),
		"%.2f" % float(summary.get("feel_ms", 0.0)),
		"%.2f" % float(summary.get("gpu_ms", 0.0)),
		"%.2f" % float(summary.get("render_cpu_ms", 0.0)),
		"%.0f" % float(summary.get("draw_calls", 0.0)),
		"%.0f" % float(summary.get("primitives", 0.0)),
	])


## The whole table as text: the machine's facts, a header and a row a scenario (tab separated, so
## it pastes into a spreadsheet), then `notes`.
static func table_text(facts: PackedStringArray, summaries: Array[Dictionary], notes: PackedStringArray) -> String:
	var lines := PackedStringArray(["Spellmerge benchmark"])
	lines.append_array(facts)
	lines.append("\t".join(ROW_COLUMNS))
	for summary in summaries:
		lines.append("\t".join(row_cells(summary)))
	lines.append_array(notes)
	return "\n".join(lines) + "\n"


## The run's end: the table printed, written to `RESULTS_FILE` and shown; the game stays open on it.
func _finished(failed: Array[String]) -> void:
	var facts: PackedStringArray = MachineInfoScript.lines(get_tree())
	var notes := PackedStringArray()
	for reason in failed:
		notes.append("Note: " + reason)
	var text: String = table_text(facts, summaries, notes)
	var file := FileAccess.open("user://benchmark.txt", FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
		notes.append("Written to %s" % ProjectSettings.globalize_path(RESULTS_FILE))
	else:
		notes.append("Could not write %s" % RESULTS_FILE)
	print(text)
	print("%s DONE: %d scenarios" % [result_word, summaries.size()])
	var rows_shown: Array[PackedStringArray] = []
	for summary in summaries:
		rows_shown.append(row_cells(summary))
	get_tree().root.add_child(ResultsScreenScript.new(facts, ROW_COLUMNS, rows_shown, notes))
