extends Node2D
## The items on the ground (items I6, docs/milestones/items.md, "The ground"): each one Items says
## lies somewhere (`ground_item_changed`) is drawn there, on the floor under the bodies, with a soft
## shadow, bobbing a pixel so it reads as something to take: a staff as its head lying on its side
## (the first frame of its head sheet, pointing right, in the first ramp), a card as its icon. Gone
## (an empty view), it is drawn no more.
##
## A child of Feel, in world space. View only, on real time: never state, nothing in the game reads
## it. It allocates only as items come and go.

const EventsScript := preload("res://core/events/events.gd")

## Under the bodies (drawn before the world at the same z), over the floor's marks.
const Z: int = 0
## A frame of a staff's head sheet, and where its grip is in it (content/wizard/README.md).
const HEAD_FRAME: Vector2 = Vector2(48.0, 48.0)
const HEAD_GRIP: Vector2 = Vector2(24.0, 27.0)
## A card's icon is drawn this big, in pixels.
const ICON_SIZE: Vector2 = Vector2(12.0, 12.0)
## How high it floats over its shadow, how far it bobs and how fast (a second each way).
const LIFT: float = 6.0
const BOB: float = 1.0
const BOB_RATE: float = 1.2
const SHADOW: Color = Color(0.05, 0.04, 0.08, 0.35)
const SHADOW_HALF: Vector2 = Vector2(7.0, 2.5)

## By item number: [where, the view] (`ground_item_changed`).
var _items: Dictionary = {}
var _clock: float = 0.0
var _shadow: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	z_index = Z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for i in 12:
		var turn: float = TAU * float(i) / 12.0
		_shadow.append(Vector2(cos(turn) * SHADOW_HALF.x, sin(turn) * SHADOW_HALF.y))


func bind(events: EventsScript) -> void:
	if events != null:
		events.ground_item_changed.connect(_on_ground_item_changed)


## How many items it draws (for tests).
func count() -> int:
	return _items.size()


## The view it draws item `item` by, empty for none (for tests).
func view_of(item: int) -> Dictionary:
	return (_items[item] as Array)[1] if _items.has(item) else {}


func _on_ground_item_changed(item: int, at: Vector2, view: Dictionary) -> void:
	if view.is_empty():
		_items.erase(item)
	else:
		_items[item] = [at, view]
	queue_redraw()


func _process(delta: float) -> void:
	if _items.is_empty():
		return
	_clock += delta
	queue_redraw()


func _draw() -> void:
	for item: int in _items:
		var row: Array = _items[item]
		var at: Vector2 = row[0]
		var view: Dictionary = row[1]
		# Each one bobs a little out of step with the next.
		var lift: float = LIFT + roundf(sin((_clock * BOB_RATE + float(item) * 0.37) * PI) * BOB)
		draw_set_transform(at)
		draw_colored_polygon(_shadow, SHADOW)
		var head: Texture2D = view.get("head") as Texture2D
		var icon: Texture2D = view.get("icon") as Texture2D
		if head != null:
			draw_texture_rect_region(head, Rect2(Vector2(-HEAD_GRIP.x, -HEAD_GRIP.y - lift + 4.0), HEAD_FRAME), Rect2(Vector2.ZERO, HEAD_FRAME))
		elif icon != null:
			draw_texture_rect(icon, Rect2(Vector2(-ICON_SIZE.x * 0.5, -ICON_SIZE.y - lift + 4.0), ICON_SIZE), false)
	draw_set_transform(Vector2.ZERO)
