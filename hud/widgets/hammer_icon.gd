extends Control
## A small hammer drawn in code, the sign of the build break. Display only: it takes
## no input and holds no state.

const ICON_SIZE: Vector2 = Vector2(12.0, 12.0)
const HEAD_COLOR: Color = Color(0.78, 0.8, 0.86)
const HANDLE_COLOR: Color = Color(0.6, 0.4, 0.22)
const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0)


func _init() -> void:
	custom_minimum_size = ICON_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var factor: float = minf(size.x / ICON_SIZE.x, size.y / ICON_SIZE.y)
	var scale_to_size := Vector2(factor, factor)
	var handle := Rect2(Vector2(5.0, 3.0) * scale_to_size, Vector2(2.0, 9.0) * scale_to_size)
	var head := Rect2(Vector2(1.0, 0.0) * scale_to_size, Vector2(10.0, 4.0) * scale_to_size)
	draw_rect(handle.grow(1.0), OUTLINE_COLOR)
	draw_rect(head.grow(1.0), OUTLINE_COLOR)
	draw_rect(handle, HANDLE_COLOR)
	draw_rect(head, HEAD_COLOR)
