class_name GroundWalls
extends RefCounted
## A wall's own art where a room's void is wall (connected biomes CB4; content/edges/README.md, `top`
## and `face`): the twin of `tools/ground_walls.py`, line by line. Its face, on the wall the camera
## looks at (the floor below it), in courses of masonry; its top, rough stone falling into the dark
## away from the floor. Drawn on whatever floor it is handed, so a mirrored room's faces still stand
## above the floor's top edges. Static only.

const N := preload("res://gameplay/feel/ground/ground_noise.gd")


## The wall art as RGBA (clear where nothing is drawn): `floor` marks the pixels a body stands on,
## `wall` the pixels of wall to draw (1), `style` the edge style (its `top` and `face`).
static func draw(w: int, h: int, floor_mask: PackedByteArray, wall: PackedByteArray, style: Dictionary, palette: Dictionary, seed: int) -> PackedByteArray:
	var image := PackedByteArray()
	image.resize(w * h * 4)
	var top: Dictionary = style.get("top", {})
	var face: Dictionary = style.get("face", {})
	if top.is_empty() and face.is_empty():
		return image
	var rows := PackedByteArray()
	if not face.is_empty():
		rows = _face_rows(w, h, floor_mask, wall, int(face["height"]))
		_draw_face(image, w, h, rows, face, palette, seed)
	else:
		rows.resize(w * h)
	if not top.is_empty():
		_draw_top(image, w, h, floor_mask, wall, rows, top, palette, seed)
	return image


static func _face_rows(w: int, h: int, floor_mask: PackedByteArray, wall: PackedByteArray, face_height: int) -> PackedByteArray:
	var rows := PackedByteArray()
	rows.resize(w * h)
	for p in range(w, w * h):
		if floor_mask[p] == 0 or wall[p - w] == 0:
			continue
		var x: int = p % w
		var y: int = p / w
		for k in range(1, face_height + 2):
			var yy: int = y - k
			if yy < 0 or wall[yy * w + x] == 0:
				break
			rows[yy * w + x] = k
	return rows


static func _draw_face(image: PackedByteArray, w: int, h: int, rows: PackedByteArray, face: Dictionary, palette: Dictionary, seed: int) -> void:
	var face_height: int = int(face["height"])
	var course: int = int(face["course"])
	var block: int = int(face["block"])
	var shades: Array = face["shades"]
	var low: int = N.colour(shades[0], palette)
	var high: int = N.colour(shades[1], palette)
	var joint: int = N.colour(face["joint"], palette)
	var light: int = N.colour(face["light"], palette)
	var cap: int = N.colour(face["cap"], palette)
	for p in w * h:
		var k: int = rows[p]
		if k == 0:
			continue
		var x: int = p % w
		var rgb: int
		if k == face_height + 1:
			rgb = cap
		elif k == face_height:
			rgb = light
		else:
			var row: int = (k - 1) / course
			if (k - 1) % course == course - 1 or (x + row * (block / 2)) % block == 0:
				rgb = joint
			else:
				# Each block a shade of its own, the face darker toward its top.
				var n: float = N.noise2(float(x / block * block + row * 7), float(row), 3.0, seed + 41)
				rgb = N.mix(low, high, minf(1.0, float(k - 1) / float(face_height) * 0.8 + n * 0.3))
		put(image, p, rgb)


static func _draw_top(image: PackedByteArray, w: int, h: int, floor_mask: PackedByteArray, wall: PackedByteArray, rows: PackedByteArray, top: Dictionary, palette: Dictionary, seed: int) -> void:
	var shades: Array = top["shades"]
	var dark: int = N.colour(shades[0], palette)
	var stone: int = N.colour(shades[1], palette)
	var joint: int = N.colour(top["joint"], palette)
	var rim: int = N.colour(top["rim"], palette)
	var deep: int = N.colour(top["deep"], palette)
	var fade_range: Array = top["fade"]
	var near: float = float(fade_range[0])
	var far: float = float(fade_range[1])
	# How far each wall pixel is from the floor, by a walk out from the floor's edge.
	var dist := PackedInt32Array()
	dist.resize(w * h)
	var frontier := PackedInt32Array()
	for p in w * h:
		if wall[p] != 0 and _touches(floor_mask, w, h, p):
			frontier.append(p)
			dist[p] = 1
	var d: int = 1
	while not frontier.is_empty() and float(d) < far + 2.0:
		d += 1
		var next := PackedInt32Array()
		for q: int in frontier:
			var x: int = q % w
			var y: int = q / w
			for way in 4:
				var nx: int = x + (1 if way == 0 else (-1 if way == 1 else 0))
				var ny: int = y + (1 if way == 2 else (-1 if way == 3 else 0))
				if nx >= 0 and nx < w and ny >= 0 and ny < h:
					var r: int = ny * w + nx
					if wall[r] != 0 and dist[r] == 0:
						dist[r] = d
						next.append(r)
		frontier = next
	for p in w * h:
		if wall[p] == 0 or rows[p] != 0:
			continue
		var x: int = p % w
		var y: int = p / w
		var dd: int = dist[p] if dist[p] != 0 else int(far) + 2
		var rgb: int
		if dd == 1:
			rgb = rim
		else:
			var fine: float = N.noise2(float(x), float(y), 3.0, seed + 51)
			var rough: float = N.noise2(float(x), float(y), 9.0, seed + 52)
			rgb = joint if fine < 0.28 else N.mix(dark, stone, rough)
		var fade: float = minf(1.0, maxf(0.0, (float(dd) - near) / maxf(1.0, far - near)))
		put(image, p, N.mix(rgb, deep, fade))


static func _touches(floor_mask: PackedByteArray, w: int, h: int, p: int) -> bool:
	var x: int = p % w
	var y: int = p / w
	return (x + 1 < w and floor_mask[p + 1] != 0) or (x > 0 and floor_mask[p - 1] != 0) \
		or (y + 1 < h and floor_mask[p + w] != 0) or (y > 0 and floor_mask[p - w] != 0)


## One opaque pixel of `rgb` at `p`.
static func put(image: PackedByteArray, p: int, rgb: int, alpha: int = 255) -> void:
	image[p * 4] = (rgb >> 16) & 0xFF
	image[p * 4 + 1] = (rgb >> 8) & 0xFF
	image[p * 4 + 2] = rgb & 0xFF
	image[p * 4 + 3] = alpha
