class_name PixelShape
extends RefCounted
## A small shape at the art's detail, baked once into runs of art pixels and drawn from them: the HUD's
## own icons and Feel's markers (ART4 part 3; docs/STYLE.md, "The picture and the art's detail" and
## "Outline"). A HUD or a marker layer is laid out in layout pixels and drawn at the picture's scale,
## so an art pixel is half a layout pixel (`ART_PIXEL`) and one picture pixel on screen.
##
## **Its parts:** a mask of filled art pixels (from rows of text, a polygon or a disc), then, as
## asked, its tones worked out from the mask by the style's rules, once, as it is baked:
## - `outline`: every empty art pixel beside a filled one (left, right, above or below) is the
##   Outline, so the outer corners are cut by a pixel, as a sprite's are;
## - `shade`: a filled pixel with nothing above it or left of it is lit (light from the top-left),
##   one with nothing under it or right of it is in shadow, the rest the base.
## Drawn, each run is one `draw_rect` in its tone's colour, whole art pixels, never a blur; a shape is
## drawn centred on a point snapped to the art pixel, so it never stands between two.
##
## **Display only.** Bake when the view is made (`from_rows`, `from_polygon`, `disc`, `ring`): that
## allocates. `draw` and `draw_at` allocate nothing, so a marker drawn every frame costs a rect a run.
## `target` is the CanvasItem drawn on, or anything with its `draw_rect(rect, color)` (the tests'
## pixel recorders).

## One art pixel, in layout pixels.
const ART_PIXEL: float = 0.5
## The tones a run is drawn in: the index into the colours `draw` is handed (not `Palette`'s shade
## indices, which run shadow, base, light: `Palette.shade_beside` takes those).
const OUTLINE: int = 0
const LIGHT: int = 1
const BASE: int = 2
const SHADOW: int = 3
const TONES: int = 4

## The shape's size in art pixels, its Outline included.
var width: int = 0
var height: int = 0
## Its runs: x, y, length (art pixels, from the top left) and tone, four ints a run, by rows.
var runs: PackedInt32Array = PackedInt32Array()


## A shape from rows of text, `#` filled and anything else empty, all rows as long as the first.
static func from_rows(rows: PackedStringArray, shade: bool = false, outline: bool = true) -> PixelShape:
	var wide: int = rows[0].length() if rows.size() > 0 else 0
	var mask := PackedByteArray()
	mask.resize(wide * rows.size())
	for y in rows.size():
		for x in mini(wide, rows[y].length()):
			mask[y * wide + x] = 1 if rows[y].unicode_at(x) == 35 else 0
	return _bake(mask, wide, rows.size(), shade, outline)


## A shape filling `points` (a polygon in art pixels about the origin): an art pixel is filled when its
## middle is inside it.
static func from_polygon(points: PackedVector2Array, shade: bool = true, outline: bool = true) -> PixelShape:
	var box := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		box = box.expand(point)
	var left: int = floori(box.position.x)
	var top: int = floori(box.position.y)
	var wide: int = ceili(box.end.x) - left
	var tall: int = ceili(box.end.y) - top
	var mask := PackedByteArray()
	mask.resize(wide * tall)
	for y in tall:
		for x in wide:
			var middle := Vector2(left + x + 0.5, top + y + 0.5)
			mask[y * wide + x] = 1 if Geometry2D.is_point_in_polygon(middle, points) else 0
	return _bake(mask, wide, tall, shade, outline)


## A round shape `across` art pixels wide: the pixels whose middles are inside its circle.
static func disc(across: int, shade: bool = true, outline: bool = true) -> PixelShape:
	return ring(across, across, shade, outline)


## A band round a middle, `across` art pixels wide outside and `thick` deep (`thick` >= across / 2
## is a whole disc): the pixels whose middles lie between its two circles.
static func ring(across: int, thick: int, shade: bool = false, outline: bool = true) -> PixelShape:
	var outer: float = across * 0.5
	var inner: float = maxf(outer - thick, 0.0)
	var mask := PackedByteArray()
	mask.resize(across * across)
	for y in across:
		for x in across:
			var gap: float = Vector2(x + 0.5 - outer, y + 0.5 - outer).length()
			mask[y * across + x] = 1 if gap <= outer and (inner <= 0.0 or gap >= inner) else 0
	return _bake(mask, across, across, shade, outline)


## Draw it with its middle at `middle` (layout pixels, snapped to the art pixel), each art pixel
## `pixel` layout pixels, in `tones` (indexed OUTLINE, LIGHT, BASE, SHADOW).
func draw(target: Object, middle: Vector2, tones: PackedColorArray, pixel: float = ART_PIXEL) -> void:
	var corner: Vector2 = middle - Vector2(width, height) * (pixel * 0.5)
	draw_at(target, (corner / pixel).round() * pixel, tones, pixel)


## Draw it with its top left at `corner` (layout pixels), as `draw`.
func draw_at(target: Object, corner: Vector2, tones: PackedColorArray, pixel: float = ART_PIXEL) -> void:
	for at in range(0, runs.size(), 4):
		var rect := Rect2(corner.x + runs[at] * pixel, corner.y + runs[at + 1] * pixel, runs[at + 2] * pixel, pixel)
		target.draw_rect(rect, tones[runs[at + 3]])


## The tone of art pixel (`x`, `y`), or -1 where nothing is drawn (for tests).
func tone_at(x: int, y: int) -> int:
	for at in range(0, runs.size(), 4):
		if runs[at + 1] == y and x >= runs[at] and x < runs[at] + runs[at + 2]:
			return runs[at + 3]
	return -1


## The mask (`wide` × `tall`, 1 filled) padded by the Outline if asked, its tones worked out and cut
## into runs.
static func _bake(mask: PackedByteArray, wide: int, tall: int, shade: bool, outline: bool) -> PixelShape:
	var pad: int = 1 if outline else 0
	var shape := PixelShape.new()
	shape.width = wide + pad * 2
	shape.height = tall + pad * 2
	for y in shape.height:
		var run_x: int = 0
		var run_tone: int = -1
		for x in shape.width + 1:
			var tone: int = -1
			if x < shape.width:
				tone = _tone(mask, wide, tall, x - pad, y - pad, shade, outline)
			if tone != run_tone:
				if run_tone >= 0:
					shape.runs.append_array([run_x, y, x - run_x, run_tone])
				run_x = x
				run_tone = tone
	return shape


static func _tone(mask: PackedByteArray, wide: int, tall: int, x: int, y: int, shade: bool, outline: bool) -> int:
	if _filled(mask, wide, tall, x, y):
		if not shade:
			return BASE
		if not _filled(mask, wide, tall, x, y - 1) or not _filled(mask, wide, tall, x - 1, y):
			return LIGHT
		if not _filled(mask, wide, tall, x, y + 1) or not _filled(mask, wide, tall, x + 1, y):
			return SHADOW
		return BASE
	if outline and (_filled(mask, wide, tall, x - 1, y) or _filled(mask, wide, tall, x + 1, y) \
			or _filled(mask, wide, tall, x, y - 1) or _filled(mask, wide, tall, x, y + 1)):
		return OUTLINE
	return -1


static func _filled(mask: PackedByteArray, wide: int, tall: int, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < wide and y < tall and mask[y * wide + x] != 0


## An arrowhead pointing along each of `ways` directions (the first along +x, then turning clockwise
## on screen), `length` art pixels from tip to back, `half_width` from its middle line to each barb,
## its back cut in by `notch` between them (0: a plain triangle), shaded and outlined: the markers'
## heads, baked once so a marker turning by whole steps never stands between two pixels.
static func arrows(length: float, half_width: float, notch: float, ways: int) -> Array[PixelShape]:
	var shapes: Array[PixelShape] = []
	for step in ways:
		var way := Vector2.from_angle(TAU * step / ways)
		var side := Vector2(-way.y, way.x) * half_width
		var back: Vector2 = -way * (length * 0.5)
		var points := PackedVector2Array([way * (length * 0.5), back + side])
		if notch > 0.0:
			points.append(back + way * notch)
		points.append(back - side)
		shapes.append(from_polygon(points))
	return shapes


## Which of `ways` arrows (`arrows`) points nearest along `way`.
static func way_index(way: Vector2, ways: int) -> int:
	return posmod(roundi(way.angle() / TAU * ways), ways)
