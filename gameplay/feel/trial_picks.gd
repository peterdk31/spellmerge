extends Node2D
## Each wizard's pick over the hub's trial gate (boss OB2, docs/milestones/boss-old-broom.md,
## decision 27): the name of the room each seat picked at the lectern, in that seat's light shade
## (docs/STYLE.md, Player 1-4), one line a seat with a pick, stacked upwards over the gate from its
## area's top middle, so the party sees at a glance whether everyone picked the same room. It shows
## what the bus says and nothing else (`trial_picks_changed`); with no gate, or no pick, nothing.
##
## A child of Feel, top level (world space), so it stays on the gate whatever the camera does.
## View only: never state, nothing in the game reads it, and its labels change only when the picks
## or the gate's place do.

const EventsScript := preload("res://core/events/events.gd")

const SEATS: int = 4
## Over the damage numbers' labels, under the teammate markers (as the altar's code).
const Z: int = 22
const FONT_SIZE: int = 12
const OUTLINE: int = 4
## Pixels from one line's lower edge to the next one's, and from the gate's area to the first.
const LINE: float = 14.0
const LIFT: float = 2.0

## One label a seat, made once.
var _labels: Array[Label] = []


func _ready() -> void:
	top_level = true
	z_index = Z
	for seat in SEATS:
		var label := Label.new()
		label.name = "Seat%d" % (seat + 1)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		label.add_theme_font_size_override(&"font_size", FONT_SIZE)
		label.add_theme_constant_override(&"outline_size", OUTLINE)
		label.add_theme_color_override(&"font_outline_color", Color.BLACK)
		var shades: PackedColorArray = Palette.shades_of(StringName("player_%d" % (seat + 1)))
		label.add_theme_color_override(&"font_color", shades[shades.size() - 1] if not shades.is_empty() else Color.WHITE)
		label.visible = false
		add_child(label)
		_labels.append(label)


func bind(events: EventsScript) -> void:
	if events != null:
		events.trial_picks_changed.connect(show_picks)


## Show `names` (by seat; "" for none) over the gate whose area's top middle is `at`, while one
## stands.
func show_picks(names: PackedStringArray, standing: bool, at: Vector2) -> void:
	var line: int = 0
	for seat in _labels.size():
		var label: Label = _labels[seat]
		var name_shown: String = names[seat] if seat < names.size() else ""
		label.visible = standing and name_shown != ""
		if not label.visible:
			continue
		label.text = name_shown
		label.reset_size()
		label.position = Vector2(roundf(at.x - label.size.x * 0.5), roundf(at.y - LIFT - LINE * float(line) - label.size.y))
		line += 1


## The label of seat `seat` (for tests).
func label_of(seat: int) -> Label:
	return _labels[seat] if seat >= 0 and seat < _labels.size() else null
