@tool
class_name PropStandIn
extends RoomPlacement
## A prop placed in a room's scene (props W8a/W8b, docs/milestones/props.md; content/rooms/README.md):
## add one anywhere in the scene (Add Child Node, "PropStandIn"; the hub keeps them under `Props`), pick its `prop` in the
## Inspector and move it where the prop's feet go. In the editor it draws the prop's look in the
## state picked in `state` (its first by default) exactly as the game draws it (`PropLayer.dress`,
## as `PropLook`), with its hurt shape (red), its ground (cyan) and where it is stood on (yellow, its `area`) outlined, so what you move is what
## stands there. The game never shows it: the game takes every placement out of the room (`RoomPlaces.strip`)
## and stands the real prop at its place, from `prop`.
##
## An editor script (the owner's decision of 2026-11-11), so it lives in tools/: nothing here runs
## in play but its fields being read (`RoomPlaces`).

## The prop that stands here (its feet at this node).
@export var prop: PropBase = null:
	set(value):
		prop = value
		state = &""
		notify_property_list_changed()
		_show_in_editor()
## Which of its states the editor shows (empty: the one it starts in). The game always starts it in
## its first.
@export var state: StringName = &"":
	set(value):
		state = value
		_show_in_editor()
## Outline its hurt shape and its ground in the editor.
@export var show_shapes: bool = true:
	set(value):
		show_shapes = value
		queue_redraw()

const HURT_COLOUR: Color = Color(0.88, 0.35, 0.18, 0.9)
const GROUND_COLOUR: Color = Color(0.31, 0.84, 0.86, 0.9)
const AREA_COLOUR: Color = Color(0.95, 0.76, 0.19, 0.9)


## What stands here (`RoomPlacement`).
func placed() -> Resource:
	return prop


func _ready() -> void:
	_show_in_editor()


## The state shown: `state` when the prop has it, else the one it starts in (&"" with no states).
func shown_state() -> StringName:
	if prop == null or prop.states == null or prop.states.list.is_empty():
		return &""
	if state != &"" and prop.states.state_at(state) >= 0:
		return state
	return prop.states.list[0].state_id


## Draw the prop's look in `shown_state()` as sprites of this node's own (made anew; internal, so
## the scene never saves them). The editor calls it; a test may too.
func show_look() -> void:
	for child in get_children(true):
		if child.get_meta(&"stand_in_part", false):
			remove_child(child)
			child.queue_free()
	var look: PropStateLook = prop.look_of(shown_state()) if prop != null else null
	if look != null:
		for layer in look.layers:
			if layer == null:
				continue
			var sprite := Sprite2D.new()
			sprite.set_meta(&"stand_in_part", true)
			layer.dress(sprite)
			add_child(sprite, false, Node.INTERNAL_MODE_BACK)
	queue_redraw()


## The sprites `show_look` made, in its layers' order.
func look_sprites() -> Array[Sprite2D]:
	var found: Array[Sprite2D] = []
	for child in get_children(true):
		if child is Sprite2D and child.get_meta(&"stand_in_part", false):
			found.append(child as Sprite2D)
	return found


func _show_in_editor() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		show_look()


func _draw() -> void:
	if not Engine.is_editor_hint() or not show_shapes or prop == null:
		return
	if prop.size.x > 0.0 and prop.size.y > 0.0:
		draw_rect(prop.hurt_rect(), HURT_COLOUR, false, 1.0)
	else:
		draw_arc(prop.offset, prop.radius, 0.0, TAU, 32, HURT_COLOUR, 1.0)
	if prop.has_footprint():
		draw_rect(prop.ground_rect(), GROUND_COLOUR, false, 1.0)
	var area: Rect2 = prop.area_rect()
	if area.has_area():
		draw_rect(area, AREA_COLOUR, false, 1.0)


## `state` picked from the prop's own states.
func _validate_property(property: Dictionary) -> void:
	if property.name != "state" or prop == null or prop.states == null:
		return
	var ids := PackedStringArray()
	for each in prop.states.list:
		if each != null:
			ids.append(String(each.state_id))
	property.hint = PROPERTY_HINT_ENUM
	property.hint_string = ",".join(ids)
