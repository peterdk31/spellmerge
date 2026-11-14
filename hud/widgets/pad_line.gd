extends Label
## The pad line (owner, 2026-11-13): shown while the game stands stopped for a seat whose gamepad
## is unplugged, saying whose controller is gone and how to go on. It shows what `pad_wait_changed`
## says (co-op's: the waiting seats, a bit each), so every machine of a party and a replay show
## the same; hidden for none. Display only: it reads no input (`core/input` gives the seat its
## gamepad back, and the pause menu lets a waiting seat leave).

const EventsScript := preload("res://core/events/events.gd")

const SEATS: int = 4
const FONT_SIZE: int = 8
const OUTLINE: int = 3
## A line for each waiting seat, then what to do.
const SEAT_TEXT: String = "P%d: controller disconnected"
## `join` on a gamepad is A (or Start).
const HINT_TEXT: String = "The game waits: plug it back in, or press A on another controller (Enter for P1)"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override(&"font_size", FONT_SIZE)
	add_theme_constant_override(&"outline_size", OUTLINE)
	add_theme_color_override(&"font_outline_color", Color.BLACK)
	visible = false


func bind(events: EventsScript) -> void:
	if events != null:
		events.pad_wait_changed.connect(show_seats)


## The lines for the waiting `seats` (a bit each); hidden for none.
func show_seats(seats: int) -> void:
	var lines: PackedStringArray = PackedStringArray()
	for seat in SEATS:
		if seats & (1 << seat) != 0:
			lines.append(SEAT_TEXT % (seat + 1))
	visible = not lines.is_empty()
	if visible:
		lines.append(HINT_TEXT)
	text = "\n".join(lines)
