extends Label
## The stone line (docs/milestones/online-lobby.md, L1): one line of small type at the top middle
## while the party is in the hub, saying how to start a run from the teleporter stone. It shows
## what `start_stone_changed` says, as words: how many of the wizards stand on the stone, or, once
## it is lit, that A starts the run. Out of the hub (no wizards) it is hidden. Display only: it
## reads no input (the HUD's panels send A as `run_requested`).
##
## Where the run starts (run generation RG7, `start_depth_changed`): once the lectern's pick is past
## the first room, a second line names it ("Starts in: Room 3", "Starts in: The boss", `DepthWords`).

const EventsScript := preload("res://core/events/events.gd")

const FONT_SIZE: int = 8
const OUTLINE: int = 3
## The two lines: while some are still off the stone, and once every wizard is on it.
const GATHER_TEXT: String = "Everyone onto the stone to start: %d of %d"
## One line for every player, so it names the button on a pad and on the keyboard (`accept`).
const LIT_TEXT: String = "Everyone is on the stone: A (Enter) starts the run"
## The second line, for a run that starts past its first room.
const START_TEXT: String = "Starts in: %s"

## What was last told: the stone's count and where the run starts.
var _standing: int = 0
var _wizards: int = 0
var _lit: bool = false
var _depth: int = 0
var _depths: int = 0


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
		events.start_depth_changed.connect(show_start)


## The line for `standing` of `wizards` on the stone, `lit` or not; hidden for no wizards (the hub
## was left).
func show_stone(standing: int, wizards: int, lit: bool) -> void:
	_standing = standing
	_wizards = wizards
	_lit = lit
	_show()


## The run from the stone starts at `depth` of the `depths` the lectern offers.
func show_start(depth: int, depths: int) -> void:
	_depth = depth
	_depths = depths
	_show()


func _show() -> void:
	visible = _wizards > 0
	if not visible:
		text = ""
		return
	text = LIT_TEXT if _lit else GATHER_TEXT % [_standing, _wizards]
	if _depth > 0 and _depths > 0:
		text += "\n" + START_TEXT % DepthWords.of(_depth, _depths)
