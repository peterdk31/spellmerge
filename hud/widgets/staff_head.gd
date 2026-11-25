extends RefCounted
## A staff's head as a small icon (items I7: the inventory's and the builder's tiles): one frame of
## its head sheet (content/wizard/README.md: 48×48 frames, 16 columns of directions clockwise from
## pointing right, a row per player ramp), the one pointing up, cropped to the head above the grip
## and drawn 1:1 (scaled only into a smaller tile). Plain drawing on the canvas it is given.

## A frame of the sheet, the column pointing up, and the head's square in that frame, in world units
## (a sheet at 2x detail has twice as many of its own pixels: ArtDetail, so its icon is finer).
const FRAME: float = 48.0
const UP_COLUMN: int = 12
const RAMPS: int = 4
const HEAD: Rect2 = Rect2(15.0, 6.0, 16.0, 16.0)


## Draw `head` (a head sheet; nothing for null) into `rect` on `canvas`, in player ramp `ramp`.
static func draw(canvas: CanvasItem, head: Texture2D, rect: Rect2, ramp: int = 0) -> void:
	if head == null:
		return
	var source: Rect2 = source_of(head, ramp)
	if head.get_width() < source.end.x or head.get_height() < source.end.y:
		# Not a sheet: the whole picture.
		canvas.draw_texture_rect(head, rect, false)
		return
	var side: float = minf(minf(rect.size.x, rect.size.y), HEAD.size.x)
	var at: Vector2 = (rect.get_center() - Vector2(side, side) * 0.5).round()
	canvas.draw_texture_rect_region(head, Rect2(at, Vector2(side, side)), source)


## The head's square in `head`'s own pixels: the up column's frame of row `ramp`, at its art's detail.
static func source_of(head: Texture2D, ramp: int = 0) -> Rect2:
	var row: int = clampi(ramp, 0, RAMPS - 1)
	var detail: float = float(ArtDetail.of(head))
	return Rect2((Vector2(UP_COLUMN * FRAME, row * FRAME) + HEAD.position) * detail, HEAD.size * detail)
