extends Label
## The room's code over the hub's multiplayer altar (online lobby L5c,
## docs/milestones/online-lobby.md): while this machine's party is open to other machines, the
## code they join by stands in the world over the altar, where the room was opened. It shows what
## the bus says and nothing else: the code is the open room's of `online_line_changed`
## (`OnlineWhy.LINE_ROOM`, shown only as a room's code may be, `OnlineWhy.room_code`), and the
## place is the altar's of `altar_placed`. With no open room or no altar it is hidden.
##
## A child of Feel, top level (world space), so it stays on the altar whatever the camera does.
## View only: never state, nothing in the game reads it, and its text changes only when the code
## or the place does.

const EventsScript := preload("res://core/events/events.gd")

## Over the damage numbers' labels, under the teammate markers.
const Z: int = 22
const FONT_SIZE: int = 16
const OUTLINE: int = 4
## How far over the altar's area the code's lower edge is, in pixels.
const LIFT: float = 2.0

## The open room's code ("" for none), and the altar: whether one stands, and the top middle of
## its area.
var _code: String = ""
var _stands: bool = false
var _at: Vector2 = Vector2.ZERO


func _ready() -> void:
	top_level = true
	z_index = Z
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_font_size_override(&"font_size", FONT_SIZE)
	add_theme_constant_override(&"outline_size", OUTLINE)
	add_theme_color_override(&"font_outline_color", Color.BLACK)
	visible = false


func bind(events: EventsScript) -> void:
	if events != null:
		events.online_line_changed.connect(_on_line_changed)
		events.altar_placed.connect(_on_altar_placed)


## The line about playing online: it names the open room, or (anything else) no room is open.
func _on_line_changed(facts: Dictionary, _counters: String) -> void:
	var code: String = OnlineWhy.room_code(facts.get(OnlineWhy.LINE_ROOM))
	if code != _code:
		_code = code
		_show()


func _on_altar_placed(standing: bool, at: Vector2) -> void:
	if standing != _stands or at != _at:
		_stands = standing
		_at = at
		_show()


func _show() -> void:
	visible = _stands and _code != ""
	if not visible:
		return
	text = _code
	reset_size()
	position = Vector2(roundf(_at.x - size.x * 0.5), roundf(_at.y - size.y - LIFT))
