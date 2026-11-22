extends CanvasLayer
## The benchmark's results (D1, 2026-11-22), for the owner to screenshot: what it ran on
## (`machine_info.gd`), then a row a scenario (`benchmark.gd`'s `ROW_COLUMNS`), over an opaque
## panel above the game and the HUD, with where the text file was written. Its button, Esc or B
## calls `back` (the benchmark's way back to the main menu). Drawn with the project theme; a tool's
## screen, so it shows whole at once.

## Above every layer the game and the HUD draw on.
const LAYER: int = 128
## Margin round the panel, in the picture's pixels.
const MARGIN: int = 8

var _facts: PackedStringArray = PackedStringArray()
var _header: PackedStringArray = PackedStringArray()
var _rows: Array[PackedStringArray] = []
var _notes: PackedStringArray = PackedStringArray()
var _back: Callable = Callable()
var _button: Button = null


## `facts` as "Name: value" lines, `header` the columns, `rows` one a scenario, `notes` the lines
## under the table (where the file is, anything that went wrong), `back` what the button does.
func _init(facts: PackedStringArray, header: PackedStringArray, rows: Array[PackedStringArray], notes: PackedStringArray, back: Callable) -> void:
	name = "BenchmarkResults"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_facts = facts
	_header = header
	_rows = rows
	_notes = notes
	_back = back


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, MARGIN)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(_label("Spellmerge benchmark"))
	for line in _facts:
		box.add_child(_label(line))
	var grid := GridContainer.new()
	grid.columns = _header.size()
	for cell in _header:
		grid.add_child(_label(cell))
	for row in _rows:
		for cell in row:
			grid.add_child(_label(cell))
	box.add_child(grid)
	for line in _notes:
		box.add_child(_label(line))
	_button = Button.new()
	_button.name = "Back"
	_button.text = "Back to the main menu"
	_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_button.pressed.connect(_go_back)
	box.add_child(_button)
	_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()


func _go_back() -> void:
	if _back.is_valid():
		_back.call()
	queue_free()


static func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
