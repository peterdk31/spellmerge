@tool
class_name RoomZone
extends ReferenceRect
## An area of a room with a name (props W8c, docs/milestones/props.md, "W8c: a room foundation"):
## a place that is no thing (the hub's prop yard), drawn in the editor only, moved and sized by its
## handles. Found at any depth of a room's scene (`RoomPlaces.read`), taken out before play. Core
## knows a zone only by its name; what one means is the game's (Flow's `ZONE_PROP_YARD`). A thing
## that means something is a self-contained prop instead (its own `PropBase.area`).

## What the zone is to the game (`prop_yard`).
@export var zone_name: StringName = &"":
	set(value):
		zone_name = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Its name written in its corner, in the editor.
func _draw() -> void:
	if Engine.is_editor_hint() and zone_name != &"":
		draw_string(ThemeDB.fallback_font, Vector2(4.0, 14.0), String(zone_name), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, border_color)
