@tool
class_name ItemStandIn
extends RoomPlacement
## An item lying in a room's scene (items I6, docs/milestones/items.md, "The ground"): add one
## anywhere in the scene (Add Child Node, "ItemStandIn"; the hub keeps its rack under `Items`), pick
## its `item` in the Inspector (a premade staff, a `StaffItem` of content/items/, or a card) and move
## it where it lies. In the editor it draws the item (a staff's head, a card's icon). The game never
## shows it: the game takes every placement out of the room (`RoomPlaces.strip`) and the Items area
## lays one copy of the item there (`room_items_placed`, `ItemKinds.stack_of`).
##
## An editor script (the owner's decision of 2026-11-11), so it lives in tools/: nothing here runs
## in play but its field being read (`RoomPlaces`).

## The item that lies here: a `StaffItem`, a staff or a card (anything `ItemKinds.stack_of` takes).
@export var item: Resource = null:
	set(value):
		item = value
		queue_redraw()

## The size of one frame of a staff's head sheet; its first column points right.
const HEAD_FRAME: Vector2 = Vector2(48.0, 48.0)
## Where the grip is in a head frame (the item lies by its grip).
const HEAD_GRIP: Vector2 = Vector2(24.0, 27.0)
const MISSING_COLOUR: Color = Color(0.88, 0.35, 0.18, 0.9)


## What lies here (`RoomPlacement`).
func placed() -> Resource:
	return item


## The picture the editor draws: a staff's head sheet or a card's icon; null for none.
func picture() -> Texture2D:
	var staff: StaffBase = null
	if item is StaffItem:
		staff = (item as StaffItem).staff
	elif item is StaffBase:
		staff = item as StaffBase
	if staff != null:
		return staff.head
	if item is SpellComponent:
		return (item as SpellComponent).icon
	return null


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var texture: Texture2D = picture()
	if texture == null:
		draw_circle(Vector2.ZERO, 4.0, MISSING_COLOUR, false, 1.0)
		return
	if item is StaffItem or item is StaffBase:
		draw_texture_rect_region(texture, Rect2(-HEAD_GRIP, HEAD_FRAME), Rect2(Vector2.ZERO, HEAD_FRAME))
	else:
		var size: Vector2 = texture.get_size()
		draw_texture(texture, -size * 0.5)
