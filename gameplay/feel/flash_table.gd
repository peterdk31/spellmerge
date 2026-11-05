extends RefCounted
## The flash kinds as Feel's flash shader reads them (`shot_flash.gdshader`'s `flash_table`;
## docs/milestones/flash-kinds.md): a texture of a row a kind, in the kinds' order, so a new kind
## (content/flashes) needs no shader edit. A row is TEXELS texels (RGBAF):
##   texel 0             its draw (DRAW_*), metric (0 round, 1 diamond, 2 flat) and salt
##   then each curve     (FlashKind.NUMBER_CURVES, then SHADE_CURVES) as MAX_SEGMENTS segments of two
##                       texels: (start, end of its way, WAY_*, 0) and (from, from_z, to, to_z); a
##                       segment past the last starts at 2 (never). The shader takes the last
##                       segment started, `t` its way from its start to its end, and the value
##                       mix(from, to, e) + mix(from_z, to_z, e) x zoom, `e` its way of `t`.
## A curve a kind does not give is its default (DEFAULTS: off for a part, so it is not drawn).

const MAX_SEGMENTS: int = FlashKind.MAX_SEGMENTS
const CURVES: Array[StringName] = [
	&"arm", &"disc", &"ring", &"column_width", &"column_top", &"column_foot", &"column_length",
	&"column_dotted", &"glow", &"glow_ring", &"glow_ring_reach", &"glow_middle", &"glow_middle_reach",
	&"first", &"second",
]
## Texels a row: the head, then two a segment of each curve (the shader's TEXELS).
const TEXELS: int = 1 + 15 * MAX_SEGMENTS * 2
## The draws the shader knows (its D_*); a kind drawn by another shader has no row worth reading.
const DRAW_CODES: Dictionary = {&"shape": 0.0, &"clouds": 1.0, &"cracks": 2.0}
const METRIC_CODES: Dictionary = {&"round": 0.0, &"diamond": 1.0, &"flat": 2.0}
const WAY_CODES: Dictionary = {&"linear": 0.0, &"out": 1.0, &"in": 2.0, &"hold": 3.0}
## A shade's number (the shader's `shade_of`); none is -1 (black).
const SHADE_CODES: Dictionary = {&"hot": 0.0, &"hi": 1.0, &"mid": 2.0, &"lo": 3.0}
## A part that is off (not drawn), as a value: any part below 0 is not drawn.
const OFF: float = -1.0
## Each curve's value when a kind gives none: the parts off, the column's numbers 0, the glow as
## bright as it is (1) with no light round its ring or middle, the reaches 1 px, the shades none.
const DEFAULTS: Dictionary = {
	&"arm": OFF, &"disc": OFF, &"ring": OFF, &"column_width": OFF, &"column_top": 0.0,
	&"column_foot": 0.0, &"column_length": OFF, &"column_dotted": 0.0, &"glow": 1.0,
	&"glow_ring": 0.0, &"glow_ring_reach": 1.0, &"glow_middle": 0.0, &"glow_middle_reach": 1.0,
	&"first": -1.0, &"second": -1.0,
}
## Where a segment that never starts starts.
const NEVER: float = 2.0


## The table of `kinds` (a row each, in their order; one blank row when there are none).
static func image_of(kinds: Array[FlashKind]) -> Image:
	var image: Image = Image.create_empty(TEXELS, maxi(kinds.size(), 1), false, Image.FORMAT_RGBAF)
	for row in kinds.size():
		var texels: Array[Color] = row_of(kinds[row])
		for x in TEXELS:
			image.set_pixel(x, row, texels[x])
	return image


## The texels of `kind`'s row.
static func row_of(kind: FlashKind) -> Array[Color]:
	var texels: Array[Color] = [Color(float(DRAW_CODES.get(kind.draw, -1.0)), float(METRIC_CODES.get(kind.metric, 0.0)), float(kind.salt), 0.0)]
	for curve: StringName in CURVES:
		texels.append_array(_curve_texels(kind.curve_of(curve), float(DEFAULTS[curve]), FlashKind.SHADE_CURVES.has(curve)))
	return texels


static func _curve_texels(curve: Array[Dictionary], default: float, shade: bool) -> Array[Color]:
	var texels: Array[Color] = []
	if curve.is_empty():
		curve = [{"from": default, "way": &"hold"}]
	for i in MAX_SEGMENTS:
		if i >= curve.size():
			texels.append(Color(NEVER, NEVER, 0.0, 0.0))
			texels.append(Color(0.0, 0.0, 0.0, 0.0))
			continue
		var segment: Dictionary = curve[i]
		var at: float = float(segment.get("at", 0.0))
		var next: float = float(curve[i + 1].get("at", 1.0)) if i + 1 < curve.size() else 1.0
		var end: float = float(segment.get("over", next))
		if shade:
			var code: float = float(SHADE_CODES.get(StringName(segment.get("shade", "")), -1.0))
			texels.append(Color(at, end, WAY_CODES[&"hold"], 0.0))
			texels.append(Color(code, 0.0, code, 0.0))
			continue
		if bool(segment.get("off", false)):
			texels.append(Color(at, end, WAY_CODES[&"hold"], 0.0))
			texels.append(Color(OFF, 0.0, OFF, 0.0))
			continue
		var from: float = float(segment.get("from", 0.0))
		var from_z: float = float(segment.get("from_z", 0.0))
		texels.append(Color(at, end, float(WAY_CODES.get(StringName(segment.get("way", "linear")), 0.0)), 0.0))
		texels.append(Color(from, from_z, float(segment.get("to", from)), float(segment.get("to_z", from_z))))
	return texels


## `kind`'s curve `curve` at `age` (0 to 1) and `zoom`, as the shader works it out (for tests).
static func value_at(kind: FlashKind, curve: StringName, age: float, zoom: float) -> float:
	var texels: Array[Color] = _curve_texels(kind.curve_of(curve), float(DEFAULTS[curve]), FlashKind.SHADE_CURVES.has(curve))
	var head: Color = texels[0]
	var values: Color = texels[1]
	for s in range(1, MAX_SEGMENTS):
		if texels[s * 2].r <= age:
			head = texels[s * 2]
			values = texels[s * 2 + 1]
	var t: float = clampf((age - head.r) / maxf(head.g - head.r, 0.000001), 0.0, 1.0)
	var e: float = t
	if head.b > 2.5:
		e = 0.0
	elif head.b > 1.5:
		e = t * t
	elif head.b > 0.5:
		e = 1.0 - (1.0 - t) * (1.0 - t)
	return lerpf(values.r, values.b, e) + lerpf(values.g, values.a, e) * zoom
