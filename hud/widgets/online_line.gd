extends Label
## The online line (netcode spike S4, docs/milestones/netcode-spike.md): one line of small type at
## the top middle while a run is played with another machine. It shows the text of
## `online_line_changed` as it is (the run's counters, written by net/), and what
## `online_changed` says when the run starts or the other machine leaves. It knows nothing of a
## network and reads no input; with nothing to say it is hidden.

const EventsScript := preload("res://core/events/events.gd")

const FONT_SIZE: int = 8
const OUTLINE: int = 3


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override(&"font_size", FONT_SIZE)
	add_theme_constant_override(&"outline_size", OUTLINE)
	add_theme_color_override(&"font_outline_color", Color.BLACK)
	visible = false


func bind(events: EventsScript) -> void:
	if events != null:
		events.online_line_changed.connect(show_line)
		events.online_changed.connect(_on_online_changed)


func show_line(line: String) -> void:
	text = line
	visible = line != ""


func _on_online_changed(phase: StringName, _code: String, note: String) -> void:
	if phase == EventsScript.ONLINE_PLAYING:
		show_line("Online")
	elif phase == EventsScript.ONLINE_ENDED:
		show_line(note)
