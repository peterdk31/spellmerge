extends RefCounted
## The marks Feel draws on a wizard when a cast is more than a plain shot (#244, round 2): one
## flat white picture for each combo class (see `Spells.combo_class`), built here in code so
## there is no art file to ship. Feel tints the mark with the spell's element colour, so a mark
## is one palette colour with no partial transparency. Each picture is a different shape, so
## the classes read apart at 1x even in one colour: boosted is a ring of ticks (a sun), on_hit
## two chevrons that point toward the nearest of four directions to the aim, on_expire a diamond with a dot, timer a dashed ring
## with a hand, stacked a full ring over a diamond and ticks.

## Side of a picture in pixels and the radius its marks are drawn on.
const SIZE: int = 24
const RADIUS: float = 11.0
## Empty pixels round the texture's picture, room for the glow Feel draws round it.
const PAD: int = 6

const BOOSTED: StringName = &"boosted"
const ON_HIT: StringName = &"on_hit"
const ON_EXPIRE: StringName = &"on_expire"
const TIMER: StringName = &"timer"
const STACKED: StringName = &"stacked"
## Every class that has a mark, in the order the tests and sheets list them.
const CLASSES: Array[StringName] = [BOOSTED, ON_HIT, ON_EXPIRE, TIMER, STACKED]


## The picture of `combo_class` as a SIZE x SIZE image of white pixels, fully opaque or empty.
static func make_image(combo_class: StringName) -> Image:
	var image: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre: float = (SIZE - 1) / 2.0
	for y in SIZE:
		for x in SIZE:
			if _inside(combo_class, x - centre, y - centre):
				image.set_pixel(x, y, Color.WHITE)
	return image


## The picture with PAD empty pixels round it, as a texture.
static func make_texture(combo_class: StringName) -> ImageTexture:
	var padded: Image = Image.create(SIZE + 2 * PAD, SIZE + 2 * PAD, false, Image.FORMAT_RGBA8)
	padded.blit_rect(make_image(combo_class), Rect2i(0, 0, SIZE, SIZE), Vector2i(PAD, PAD))
	return ImageTexture.create_from_image(padded)


## Is the pixel at offset (dx, dy) from the centre part of the picture?
static func _inside(combo_class: StringName, dx: float, dy: float) -> bool:
	var r: float = sqrt(dx * dx + dy * dy)
	match combo_class:
		BOOSTED:
			# Eight ticks on a ring: at the compass points and the corners.
			return r >= RADIUS - 4.0 and r <= RADIUS and _sector_gap(dx, dy, 8) < 0.07
		ON_HIT:
			# Two chevrons pointing along +x (Feel turns them to the aim).
			return _chevron(dx - 5.0, dy) or _chevron(dx + 3.0, dy)
		ON_EXPIRE:
			var d: float = absf(dx) + absf(dy)
			return (d >= RADIUS - 1.5 and d <= RADIUS + 0.5) or (absf(dx) <= 1.0 and absf(dy) <= 1.0)
		TIMER:
			# A ring of dashes (every other sector of twenty-four) and a hand straight up.
			if r >= RADIUS - 2.0 and r <= RADIUS and int(_sector(dx, dy, 24)) % 2 == 0:
				return true
			return absf(dx) <= 0.6 and dy <= 0.0 and dy >= -(RADIUS - 5.0)
		STACKED:
			var diamond: float = absf(dx) + absf(dy)
			if r >= RADIUS - 1.5 and r <= RADIUS:
				return true
			if diamond >= 5.5 and diamond <= 7.0:
				return true
			return r < RADIUS - 1.5 and r >= 2.0 and _sector_gap(dx, dy, 4) < 0.04
	return false


## Is (dx, dy) on a chevron `>` whose tip is at x = 6, two pixels thick?
static func _chevron(dx: float, dy: float) -> bool:
	var edge: float = 6.0 - absf(dy)
	return absf(dy) <= 8.0 and dx >= edge - 2.5 and dx <= edge - 0.5


## The index (0 up to count - 1) of the sector of a circle cut in `count` that (dx, dy) lies in,
## counted from straight up (negative y), clockwise.
static func _sector(dx: float, dy: float, count: int) -> float:
	var turn: float = fposmod(atan2(dx, -dy), TAU) / TAU
	return floorf(turn * count)


## How far (a fraction of a turn) the direction of (dx, dy) is from the nearest of `count`
## evenly spaced directions that start straight up.
static func _sector_gap(dx: float, dy: float, count: int) -> float:
	var turn: float = fposmod(atan2(dx, -dy), TAU) / TAU * count
	return absf(turn - roundf(turn)) / count
