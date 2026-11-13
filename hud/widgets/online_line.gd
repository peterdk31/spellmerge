extends Label
## The online line (netcode spike S4, docs/milestones/netcode-spike.md): one line of small type at
## the top middle about playing with other machines. It says what `online_changed` gives a reason
## for (why opening a room failed, who left: the words are `online_words.gd`'s, online lobby L5b)
## and, after it, the line of `online_line_changed`: its facts worded (an open room's code, who
## is in) and the run's counters as they come. It knows nothing of a network and reads no input;
## with nothing to say it is hidden.

const EventsScript := preload("res://core/events/events.gd")
const OnlineWords := preload("res://hud/widgets/online_words.gd")

const FONT_SIZE: int = 8
const OUTLINE: int = 3
## Shown while a run plays and nothing else was said yet.
const PLAYING: String = "Online"

## The group the line is in, for `hush`.
const GROUP: StringName = &"online_line"

## What the last `online_changed` gave a reason for, the last line, and whether a run plays.
var _hushed: bool = false
var _said: String = ""
var _line: String = ""
var _playing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override(&"font_size", FONT_SIZE)
	add_theme_constant_override(&"outline_size", OUTLINE)
	add_theme_color_override(&"font_outline_color", Color.BLACK)
	add_to_group(GROUP)
	visible = false


func bind(events: EventsScript) -> void:
	if events != null:
		events.online_line_changed.connect(_on_line_changed)
		events.online_changed.connect(_on_online_changed)
		events.run_started.connect(_on_run_started)


func _on_line_changed(facts: Dictionary, counters: String) -> void:
	_line = OnlineWords.line(facts, counters)
	_show()


func _on_online_changed(phase: StringName, _code: String, reason: StringName, facts: Dictionary) -> void:
	_said = OnlineWords.said(reason, facts)
	_playing = phase == EventsScript.ONLINE_PLAYING
	if phase == EventsScript.ONLINE_OFF or phase == EventsScript.ONLINE_FAILED:
		# Nothing is held online any more: a line of before says nothing true.
		_line = ""
	_show()


## While something else on the screen says what `online_changed` gives a reason for (the main
## menu's online box, which this line is drawn over), the line does not say it too.
func hush(on: bool) -> void:
	_hushed = on
	_show()


## A new run: what was said before it (a room that failed to open, who left the last run) is old.
func _on_run_started(_player_count: int) -> void:
	_said = ""
	_show()


func _show() -> void:
	var parts: PackedStringArray = PackedStringArray()
	if _said != "" and not _hushed:
		parts.append(_said)
	if _line != "":
		parts.append(_line)
	text = " ".join(parts)
	if text == "" and _playing:
		text = PLAYING
	visible = text != ""
