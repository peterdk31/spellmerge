extends Label
## The stone line (docs/milestones/online-lobby.md, L1): one line of small type at the top middle
## while the party is in the hub, saying how to start a run from the teleporter stone. It shows
## what `start_stone_changed` says, as words: how many of the wizards stand on the stone, or, once
## it is lit, that A starts the run. Out of the hub (no wizards) it is hidden. Display only: it
## reads no input (the HUD's panels send A as `run_requested`).

const EventsScript := preload("res://core/events/events.gd")

const FONT_SIZE: int = 8
const OUTLINE: int = 3
## The two lines: while some are still off the stone, and once every wizard is on it.
const GATHER_TEXT: String = "Everyone onto the stone to start: %d of %d"
## One line for every player, so it names the button on a pad and on the keyboard (`accept`).
const LIT_TEXT: String = "Everyone is on the stone: A (Enter) starts the run"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override(&"font_size", FONT_SIZE)
	add_theme_constant_override(&"outline_size", OUTLINE)
	add_theme_color_override(&"font_outline_color", Color.BLACK)
	visible = false


func bind(events: EventsScript) -> void:
	if events != null:
		events.start_stone_changed.connect(show_stone)


## The line for `standing` of `wizards` on the stone, `lit` or not; hidden for no wizards (the hub
## was left).
func show_stone(standing: int, wizards: int, lit: bool) -> void:
	visible = wizards > 0
	if not visible:
		text = ""
	elif lit:
		text = LIT_TEXT
	else:
		text = GATHER_TEXT % [standing, wizards]
