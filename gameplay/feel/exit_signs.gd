extends Node2D
## What lies behind each lit exit of a run's room (run generation RG4,
## docs/milestones/run-generation.md, "Exits and the way on"): over each one the name of the kind of
## room it leads to (`RoomKind.shown_name`: "Fight", "Boss"), so the party picks its way by walking.
## It shows what the bus says and nothing else: the exits and their kinds of `room_exits_shown`.
##
## A child of Feel, top level (world space), so each name stays on its exit whatever the camera
## does. View only: never state, nothing in the game reads it, and its labels change only when the
## lit exits do.

const EventsScript := preload("res://core/events/events.gd")

## Over the damage numbers' labels, as the altar's code.
const Z: int = 22
const FONT_SIZE: int = 16
const OUTLINE: int = 4
## How far over an exit's area a name's lower edge is, in pixels.
const LIFT: float = 2.0

## A kind's name for people (`RoomKind.shown_name`; Feel reads it from the registry when it is shown).
var name_of: Callable = func(kind: StringName) -> String: return String(kind).capitalize()


func _ready() -> void:
	top_level = true
	z_index = Z


func bind(events: EventsScript, kind_name: Callable = Callable()) -> void:
	if kind_name.is_valid():
		name_of = kind_name
	if events != null:
		events.room_exits_shown.connect(_on_exits_shown)


## The names on show, left to right (for tests).
func shown() -> PackedStringArray:
	var found := PackedStringArray()
	for label: Node in get_children():
		if label is Label and not label.is_queued_for_deletion():
			found.append((label as Label).text)
	return found


func _on_exits_shown(at: PackedVector2Array, kinds: Array[StringName]) -> void:
	for old: Node in get_children():
		remove_child(old)
		old.queue_free()
	for i in mini(at.size(), kinds.size()):
		_label(String(name_of.call(kinds[i])), at[i])


## A name over the point `over`, sized once it is in the tree (its theme's font).
func _label(text: String, over: Vector2) -> void:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.add_theme_constant_override(&"outline_size", OUTLINE)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.text = text
	add_child(label)
	label.reset_size()
	label.position = Vector2(roundf(over.x - label.size.x * 0.5), roundf(over.y - label.size.y - LIFT))
