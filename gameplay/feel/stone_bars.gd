extends RefCounted
## A stone bar as the doors' looks draw it at the art's detail (ART3; ArtDetail): a seal's bars at a
## bridge's mouth (`mouth_looks.gd`) and a key door's (`lock_looks.gd`). The canvas draws in art
## pixels (its transform scaled by 1 / ArtDetail.DETAIL); a bar is its stone's base, its first art
## pixel across lit and, when it is more than two across, its last shaded (light from the top-left).
## View only.

## The shades a part is drawn in (`shades`' indices: shadow, base, light).
const SHADOW: int = 0
const BASE: int = 1
const LIGHT: int = 2


## The parts of the bar `rect` (art pixels), in drawing order: [rect, shade] each, none for an empty
## bar; `upright`: it stands, and across is left to right, else it lies, and across is top to bottom.
static func parts(rect: Rect2i, upright: bool) -> Array[Array]:
	var out: Array[Array] = []
	if rect.size.x <= 0 or rect.size.y <= 0:
		return out
	out.append([rect, BASE])
	if upright:
		out.append([Rect2i(rect.position, Vector2i(1, rect.size.y)), LIGHT])
		if rect.size.x > 2:
			out.append([Rect2i(rect.end.x - 1, rect.position.y, 1, rect.size.y), SHADOW])
	else:
		out.append([Rect2i(rect.position, Vector2i(rect.size.x, 1)), LIGHT])
		if rect.size.y > 2:
			out.append([Rect2i(rect.position.x, rect.end.y - 1, rect.size.x, 1), SHADOW])
	return out


## The bar `rect` (art pixels) drawn on `canvas` in `shades` (shadow, base, light): its `parts`.
static func draw(canvas: CanvasItem, rect: Rect2i, upright: bool, shades: PackedColorArray) -> void:
	if shades.size() < 3:
		return
	for part: Array in parts(rect, upright):
		canvas.draw_rect(Rect2(part[0] as Rect2i), shades[part[1] as int])
