extends "res://bench/play_frames_runner.gd"
## The benchmark mode of the shipped builds (D1, the owner's decision of 2026-11-22: the game is
## optimised for the Windows and Linux builds, measured on the owner's own PC): the play frames'
## scenarios on the fixed clock (play_frames_runner.gd, biome_frames_runner.gd, fixed_steps.gd: one
## tick a drawn frame, the fights from a fixed script, so every run plays the same), at the
## desktop's settings, then a results screen to screenshot (`results_screen.gd`) and the same table
## in `user://benchmark.txt`. Started by the main menu's Benchmark button in every build (the owner's
## decision of 2026-11-22), or by the user argument `--benchmark` (`Spellmerge.exe -- --benchmark`
## on Windows, `./Spellmerge.x86_64 -- --benchmark` on Linux), with `--only=` (labels, comma
## separated) and `--picture=1280x720` as the play frames take them (bench/README.md). The web build
## runs the web's rows (`WEB_LABELS`: its mote ring and shot cap) where it has them.
##
## A row a scenario: the frame's mean, 95th percentile and worst milliseconds, the simulation's
## (the Tick's steps), Feel's step, the GPU's and the renderer's CPU time where Godot reports them
## (0 where it does not), and the draw calls and primitives a frame. A scenario that did not reach
## its numbers (fewer foes or shots than asked, a bot that never cast) is noted under the table, not
## failed: the times are what is wanted here.

const ResultsScreenScript := preload("res://bench/results_screen.gd")
const InputScript := preload("res://core/input/input_manager.gd")

## The scenarios run when `--only=` names none: one wizard at the start, near and far, then the
## split screen at its busiest in each mode (play_frames_runner.gd's labels).
const DEFAULT_LABELS: PackedStringArray = ["1p start", "1p near", "1p far", "2p apart dynamic", "4p apart equal"]
## The same in the web build, at the web's settings (its mote ring and shot cap).
const WEB_LABELS: PackedStringArray = ["1p start web", "1p near web", "1p far web", "2p apart dynamic web", "4p apart equal web"]
## Where the table is written (and its name shown on the results screen).
const RESULTS_FILE: String = "user://benchmark.txt"
## The table's columns, in the order of `row_cells`.
const ROW_COLUMNS: PackedStringArray = ["Scenario", "Effects", "Frame ms", "p95", "Worst", "Sim", "Feel", "GPU", "Render CPU", "Calls", "Primitives"]


## What the run changes in the game, kept at its start and put back at its end (`_put_back`): the
## benchmark returns to the main menu, not out of the game. The seats the real devices held (they
## leave so the bots can take seats 0 to 3, and input is not heard until the end, so a press cannot
## join a seat into the run), the picture's size (`--picture=`), Feel's split mode and mote ring
## (each scenario sets its own), and the native module (`--no-native`). `--off=` and
## `--light-at-picture` are a developer's switches and stay as they were set.
var _kept_scale: Vector2i = Vector2i.ZERO
var _kept_split: int = SplitScreenSetting.DEFAULT
var _kept_motes: int = 0
var _kept_effects: int = EffectsSetting.DEFAULT
var _kept_native: bool = true
var _kept_wall_native: bool = true
var _put_back_done: bool = false


func _init() -> void:
	super()
	# `--only=` picks from every row (stress_runner.gd's `_ready`); else the defaults.
	var only_asked: bool = false
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		only_asked = only_asked or arg.begins_with("--only=")
	if not only_asked:
		var labels: PackedStringArray = WEB_LABELS if OS.has_feature("web") else DEFAULT_LABELS
		scenarios = scenarios_named(scenarios, labels_at(labels, quality_asked(OS.get_cmdline_user_args() + OS.get_cmdline_args())), rows)
	result_word = "BENCHMARK"


func _enter_tree() -> void:
	_kept_scale = get_tree().root.content_scale_size
	super()


func _ready() -> void:
	var root: Node = get_tree().root
	var input: Node = root.get_node_or_null("PlayerInput")
	if input != null:
		free_seats(input)
	var feel: Node = root.get_node_or_null("Feel")
	if feel != null and feel.has_method(&"set_mote_cap"):
		_kept_split = int(feel.get(&"split_mode"))
		_kept_motes = int(feel.get(&"mote_cap"))
		_kept_effects = int(feel.get(&"effects_mode"))
	var projectiles: Node = root.get_node_or_null("Projectiles")
	if projectiles != null:
		_kept_native = bool(projectiles.get(&"native"))
	_kept_wall_native = WallSlide.native_on()
	super()


## Every seat a real device holds left, and `input` (the PlayerInput autoload) deaf to devices until
## `hear_seats`: the bots play seats 0 to 3 (`add_virtual_device` takes a free seat only), and a
## press during the run would join a seat into it. A device joins again as it always does once heard.
static func free_seats(input: Node) -> void:
	for player in InputScript.MAX_PLAYERS:
		var device: int = int(input.call(&"device_of", player))
		if device != InputScript.NO_DEVICE and not InputScript.is_virtual(device):
			input.call(&"leave", player)
	input.set_process_input(false)


static func hear_seats(input: Node) -> void:
	input.set_process_input(true)


## The game as it was before the run (see `_kept_scale`); once.
func _put_back() -> void:
	if _put_back_done:
		return
	_put_back_done = true
	var root: Window = get_tree().root
	root.content_scale_size = _kept_scale
	var input: Node = root.get_node_or_null("PlayerInput")
	if input != null:
		hear_seats(input)
	if _feel != null and _feel.has_method(&"set_mote_cap"):
		_feel.call(&"set_split_mode", _kept_split)
		_feel.call(&"set_mote_cap", _kept_motes)
		_feel.call(&"set_effects_mode", _kept_effects)
	if _projectiles != null:
		_projectiles.set(&"native", _kept_native)
	WallSlide.use_native(_kept_wall_native)


func _exit_tree() -> void:
	_put_back()
	super()


## `labels` as `with_quality` names them at `qualities` (each label once a row when there are several).
static func labels_at(labels: PackedStringArray, qualities: PackedStringArray) -> PackedStringArray:
	if qualities.size() < 2:
		return labels
	var out := PackedStringArray()
	for label in labels:
		for quality in qualities:
			out.append("%s %s" % [label, quality])
	return out


## One summary's cells, in `ROW_COLUMNS`' order.
static func row_cells(summary: Dictionary) -> PackedStringArray:
	return PackedStringArray([
		String(summary.get("label", "")),
		String(summary.get("effects", "")),
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


## The run's end: the table printed, written to `RESULTS_FILE` (where the platform has files) and
## shown; the game stays on it until its Back.
func _finished(failed: Array[String]) -> void:
	_put_back()
	var facts: PackedStringArray = MachineInfoScript.lines(get_tree())
	var notes := PackedStringArray()
	for summary in summaries:
		summary["effects"] = effects_drawn.get(String(summary.get("label", "")), "")
	for reason in failed:
		notes.append("Note: " + reason)
	var text: String = table_text(facts, summaries, notes)
	# The literal is RESULTS_FILE (the rules want a written-out user:// path; test_benchmark.gd).
	var file := FileAccess.open("user://benchmark.txt", FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
		notes.append("Written to %s" % ("the browser's storage (%s)" % RESULTS_FILE if OS.has_feature("web") else ProjectSettings.globalize_path(RESULTS_FILE)))
	else:
		notes.append("Could not write %s" % RESULTS_FILE)
	print(text)
	print("%s DONE: %d scenarios" % [result_word, summaries.size()])
	var rows_shown: Array[PackedStringArray] = []
	for summary in summaries:
		rows_shown.append(row_cells(summary))
	get_tree().root.add_child(ResultsScreenScript.new(facts, ROW_COLUMNS, rows_shown, notes, _back_to_menu))


## The results screen's Back: the main menu again (`main_menu_requested`, as the pause menu's Main
## menu asks it), and this runner goes.
func _back_to_menu() -> void:
	if _events != null:
		_events.emit_signal(&"main_menu_requested", 0)
	queue_free()
