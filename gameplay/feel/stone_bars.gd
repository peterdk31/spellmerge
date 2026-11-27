extends RefCounted
## A stone bar as the doors' looks draw it at the art's detail (ART3; ArtDetail): a seal's bars at a
## bridge's mouth (`mouth_looks.gd`) and a key door's (`lock_looks.gd`). The caller's canvas draws in
## art pixels (its transform scaled by 1 / ArtDetail.DETAIL, set and restored by the caller round its
## bars); a bar is its stone's base, its first art pixel across lit and, when it is more than two
## across, its last shaded (light from the top-left). View only; nothing is allocated (a part is a
## Rect2i, a value).

## The shades a part is drawn in (`shades`' indices: shadow, base, light).
const SHADOW: int = 0
const BASE: int = 1
const LIGHT: int = 2


## How many parts the bar `rect` (art pixels) has: 0 for an empty bar, else base and light, and its
## shadow when it is more than two across (`upright`: across is left to right, else top to bottom).
static func count(rect: Rect2i, upright: bool) -> int:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return 0
	return 3 if (rect.size.x if upright else rect.size.y) > 2 else 2


## Part `n` (0 base, 1 light, 2 shadow) of the bar `rect`: its rect, art pixels.
static func part(rect: Rect2i, upright: bool, n: int) -> Rect2i:
	if n == 1:
		return Rect2i(rect.position, Vector2i(1, rect.size.y)) if upright else Rect2i(rect.position, Vector2i(rect.size.x, 1))
	if n == 2:
		return Rect2i(rect.end.x - 1, rect.position.y, 1, rect.size.y) if upright else Rect2i(rect.position.x, rect.end.y - 1, rect.size.x, 1)
	return rect


## Part `n`'s shade index (BASE, LIGHT, SHADOW).
static func shade_of(n: int) -> int:
	return BASE if n == 0 else (LIGHT if n == 1 else SHADOW)


## The bar `rect` (art pixels) drawn on `canvas` in `shades` (shadow, base, light): its parts in order.
static func draw(canvas: CanvasItem, rect: Rect2i, upright: bool, shades: PackedColorArray) -> void:
	if shades.size() < 3:
		return
	for n in count(rect, upright):
		canvas.draw_rect(Rect2(part(rect, upright, n)), shades[shade_of(n)])
