extends "res://tests/support/suite.gd"
## The shipped benchmark (bench/benchmark.gd; D1, 2026-11-22): every scenario it runs by default is a
## row of the play frames (the desktop's and the web's), the web's at the web's settings; its table
## has a cell a column and pastes as tab-separated text; the path it writes is its constant; the
## results screen calls its Back once and goes; the real devices leave their seats for the bots and
## are heard again after. What a frame costs is the benchmark's own run (in a window).

const BenchmarkScript := preload("res://bench/benchmark.gd")
const ResultsScreenScript := preload("res://bench/results_screen.gd")
const InputScript := preload("res://core/input/input_manager.gd")

var _backs: int = 0


func _labels() -> Dictionary:
	var out: Dictionary = {}
	for row in BenchmarkScript.play_rows():
		out[String(row["label"])] = row
	return out


func test_every_default_scenario_is_a_row() -> void:
	var rows: Dictionary = _labels()
	for label in BenchmarkScript.DEFAULT_LABELS:
		check(rows.has(label), "desktop scenario %s is a row" % label)
	for label in BenchmarkScript.WEB_LABELS:
		check(rows.has(label), "web scenario %s is a row" % label)


func test_the_web_scenarios_are_at_the_webs_settings() -> void:
	var rows: Dictionary = _labels()
	for label in BenchmarkScript.WEB_LABELS:
		var row: Dictionary = rows.get(label, {})
		check_equal(int(row.get("motes", 0)), MoteCap.DEFAULT_WEB, "%s at the web's mote ring" % label)
		check_equal(int(row.get("shots", 0)), BenchmarkScript.ProjectileManagerScript.DEFAULT_CAP_WEB, "%s at the web's shot cap" % label)
	for label in BenchmarkScript.DEFAULT_LABELS:
		check_equal(int((rows.get(label, {}) as Dictionary).get("motes", 0)), MoteCap.DEFAULT_DESKTOP, "%s at the desktop's mote ring" % label)


func test_a_row_has_a_cell_a_column() -> void:
	var summary: Dictionary = {"label": "1p near", "effects": "High", "frame_ms": 12.345, "p95_ms": 15.0, "worst_ms": 20.0, "sim_ms": 1.0, "feel_ms": 2.0, "gpu_ms": 3.0, "render_cpu_ms": 0.5, "draw_calls": 40.4, "primitives": 5000.0}
	var cells: PackedStringArray = BenchmarkScript.row_cells(summary)
	check_equal(cells.size(), BenchmarkScript.ROW_COLUMNS.size(), "a cell a column")
	check_equal(cells[0], "1p near", "the label first")
	check_equal(cells[1], "High", "the effects' row it ran at")
	check_equal(cells[2], "12.35", "ms to two places")
	check_equal(cells[9], "40", "draw calls whole")


## Every scenario at each row (`--quality=each`): the default labels named as the rows name them.
func test_each_row_names_the_default_labels_with_their_row() -> void:
	check(BenchmarkScript.labels_at(BenchmarkScript.DEFAULT_LABELS, PackedStringArray(["high"])) == BenchmarkScript.DEFAULT_LABELS, "one row: the labels as they are")
	var each: PackedStringArray = BenchmarkScript.labels_at(PackedStringArray(["1p near"]), BenchmarkScript.quality_asked(PackedStringArray(["--quality=each"])))
	check(each == PackedStringArray(["1p near low", "1p near medium", "1p near high"]), "each row: %s" % [each])
	var rows: Array[Dictionary] = BenchmarkScript.with_quality(BenchmarkScript.play_rows(), PackedStringArray(["low", "high"]))
	var labels: PackedStringArray = []
	for row in rows:
		labels.append(String(row["label"]))
	for label in BenchmarkScript.labels_at(BenchmarkScript.DEFAULT_LABELS, PackedStringArray(["low", "high"])):
		check(labels.has(label), "%s is a row" % label)
	check(BenchmarkScript.quality_asked(PackedStringArray()) == PackedStringArray(["high"]), "high unless told")


func test_the_table_text_is_the_facts_a_header_the_rows_and_the_notes() -> void:
	var summaries: Array[Dictionary] = [{"label": "1p near"}, {"label": "1p far"}]
	var text: String = BenchmarkScript.table_text(PackedStringArray(["GPU: test"]), summaries, PackedStringArray(["Note: n"]))
	var lines: PackedStringArray = text.strip_edges().split("\n")
	check_equal(lines.size(), 6, "title, a fact, the header, two rows, a note")
	check_equal(lines[2], "\t".join(BenchmarkScript.ROW_COLUMNS), "the header tab separated")
	check(lines[3].begins_with("1p near\t"), "a row tab separated")
	check_equal(lines[5], "Note: n", "the notes last")


func test_the_file_written_is_the_constant() -> void:
	# The rules want the user:// path written out where the file is opened.
	var source: String = FileAccess.get_file_as_string("res://bench/benchmark.gd")
	check(source.contains('FileAccess.open("%s"' % BenchmarkScript.RESULTS_FILE), "the literal is RESULTS_FILE")


func test_the_results_screen_calls_back_once_and_goes() -> void:
	_backs = 0
	var rows: Array[PackedStringArray] = [PackedStringArray(["1p near", "1.00"])]
	var screen: CanvasLayer = ResultsScreenScript.new(PackedStringArray(["GPU: test"]), PackedStringArray(["Scenario", "Frame ms"]), rows, PackedStringArray(), func() -> void: _backs += 1)
	root.add_child(screen)
	await process_frame
	var back: Button = screen.get_node("Panel/Scroll/Box/Back") as Button
	check(back != null and back.has_focus(), "Back has the focus (a gamepad's A presses it)")
	back.pressed.emit()
	back.pressed.emit()
	check_equal(_backs, 1, "Back called once")
	await process_frame
	check(not is_instance_valid(screen), "the screen went")


func test_the_real_devices_leave_their_seats_and_are_heard_again() -> void:
	var input: Node = root.get_node("PlayerInput")
	var keyboard: int = InputScript.KEYBOARD
	var had: int = int(input.call(&"player_of", keyboard))
	if had < 0:
		input.call(&"join", keyboard)
	var seat: int = int(input.call(&"player_of", keyboard))
	check(seat >= 0, "the keyboard holds a seat")
	BenchmarkScript.free_seats(input)
	check_equal(int(input.call(&"player_of", keyboard)), -1, "the keyboard left")
	check(not input.is_processing_input(), "no device is heard during the run")
	check(int(input.call(&"add_virtual_device", seat)) != InputScript.NO_DEVICE, "a bot takes the seat")
	input.call(&"leave", seat)
	BenchmarkScript.hear_seats(input)
	check(input.is_processing_input(), "devices heard again")
	if had >= 0:
		input.call(&"join_as", keyboard, had)
