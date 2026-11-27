extends "res://tests/support/screenshot.gd"
## Beams drawn as one merged shape (the owner, 2026-11-27: "Beams should merge into each other (like
## the pool)", "Everything merges. Ideally beams should inherit colors from every source after a
## junction"; gameplay/feel/beam_union.gd): fans of +2, +3 and +2 +3 from the hand, two players'
## plain (arcane) beams crossing, fire meeting frost, and three colours through one point, each kept
## on with `hold`. Saves the whole screen (`beam_union`), 4x crops of each (`beam_union_*_4x`), and
## with `-- --mix` the crossings in each colour rule at a junction (`beam_union_mix_<rule>_*`,
## BeamUnion.MIX_*). Then it checks the union on the pixels drawn (`_check_union`): two beams side
## by side draw one rim round them and none inside, and where fire meets frost the dither interleaves
## their colours, far more than the nearest beam's colour alone. A check that fails fails the shots.

const ActorSeats := preload("res://tests/support/actor_seats.gd")
const STARTER := preload("res://content/wizard/staffs/curl/curl.tres")
const BeamUnionScript := preload("res://gameplay/feel/beam_union.gd")
const BEAM_CARD_SHADER: Shader = preload("res://content/spells/carriers/beam/beam.gdshader")
## Each cast: its cards, where it starts and the way it aims (a point it aims at), and its seat.
const CASTS: Array = [
	[[&"hold", &"plus_two", &"beam"], Vector2(40.0, 60.0), Vector2(280.0, 60.0), 0],
	[[&"hold", &"plus_three", &"beam"], Vector2(40.0, 170.0), Vector2(280.0, 170.0), 0],
	[[&"hold", &"plus_two", &"plus_three", &"beam"], Vector2(40.0, 285.0), Vector2(280.0, 285.0), 0],
	# Two players' plain beams crossing.
	[[&"hold", &"beam"], Vector2(340.0, 15.0), Vector2(520.0, 100.0), 1],
	[[&"hold", &"beam"], Vector2(340.0, 100.0), Vector2(520.0, 15.0), 2],
	# Fire meets frost.
	[[&"hold", &"fire", &"beam"], Vector2(340.0, 130.0), Vector2(520.0, 215.0), 1],
	[[&"hold", &"frost", &"beam"], Vector2(340.0, 215.0), Vector2(520.0, 130.0), 2],
	# Three colours through one point.
	[[&"hold", &"fire", &"beam"], Vector2(360.0, 300.0), Vector2(520.0, 300.0), 3],
	[[&"hold", &"frost", &"beam"], Vector2(430.0, 240.0), Vector2(520.0, 300.0), 3],
	[[&"hold", &"lightning", &"beam"], Vector2(610.0, 245.0), Vector2(520.0, 300.0), 3],
]
## Where the check's fan of six beams starts, and the most of its pixels by the hand that may be
## white-hot, in percent.
const FAN_HAND := Vector2(100.0, 320.0)
const WHITE_MOST: int = 50
## The crops: name, the world point they are round, and their half size.
const CROPS: Array = [
	["plus_two", Vector2(90.0, 60.0), Vector2i(50, 30)],
	["plus_three", Vector2(90.0, 170.0), Vector2i(50, 30)],
	["plus_both", Vector2(90.0, 285.0), Vector2i(50, 30)],
	["players", Vector2(430.0, 58.0), Vector2i(50, 30)],
	["fire_frost", Vector2(430.0, 172.0), Vector2i(50, 30)],
	["three", Vector2(515.0, 295.0), Vector2i(50, 30)],
]


func take() -> void:
	if not need(["Spells", "Projectiles", "Feel"]):
		return
	settle_frames = 8
	var spells: Node = root.get_node("Spells")
	var projectiles: Node = root.get_node("Projectiles")
	projectiles.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	var wizards: PackedInt32Array = ActorSeats.seat_wizards(actors, 4)
	# As the game draws it: the world at twice its size (a 640 x 360 view in a 1280 x 720 picture),
	# on the crypt's floor at the world's scale.
	var floor_sprite := Sprite2D.new()
	floor_sprite.texture = FLOOR
	floor_sprite.centered = false
	floor_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor_sprite.region_enabled = true
	floor_sprite.region_rect = Rect2(Vector2.ZERO, SCREEN * float(ArtDetail.of(FLOOR)))
	floor_sprite.scale = ArtDetail.draw_scale(FLOOR)
	floor_sprite.z_index = -10
	root.add_child(floor_sprite)
	var camera := Camera2D.new()
	camera.zoom = Vector2(2.0, 2.0)
	camera.position = SCREEN * 0.5
	root.add_child(camera)
	camera.make_current()
	var staff_of: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	for cast: Array in CASTS:
		var cards: Array[StringName] = []
		cards.assign(cast[0])
		var seat: int = cast[3]
		var staff: int = staff_of[seat]
		staff_of[seat] += 1
		spells.call("install_staff", wizards[seat], staff, spells.call("compile_staff", cards, STARTER))
		var from: Vector2 = cast[1]
		spells.call("cast_staff", wizards[seat], staff, from, from.direction_to(cast[2] as Vector2), 100.0)
	await settle()
	await shot("beam_union")
	var image: Image = await grab()
	for crop: Array in CROPS:
		save_crop(image, on_screen(crop[1] as Vector2), "beam_union_%s_4x" % crop[0], crop[2] as Vector2i, 4)
	var feel: Node = root.get_node("Feel")
	if OS.get_cmdline_user_args().has("--mix"):
		# Each colour rule at a junction, the crossings only.
		for rule: int in BeamUnionScript.MIX_NAMES.size():
			feel.call(&"set_beam_mix", rule)
			image = await grab()
			for crop: Array in CROPS.slice(3):
				save_crop(image, on_screen(crop[1] as Vector2), "beam_union_mix_%s_%s" % [BeamUnionScript.MIX_NAMES[rule], crop[0]], crop[2] as Vector2i, 4)
		feel.call(&"set_beam_mix", BeamUnionScript.MIX_DITHER)
	await _check_union(spells, wizards, feel)


## The union on the pixels drawn: two plain beams of one player at most 6 px apart, side by side, are
## one body with one rim (no pixel of the rim's two shades between their white-hot cores, which two
## beams drawn apart have: the one on top's rim over the other); where fire crosses frost, the dither
## interleaves their colours pixel by pixel far more often than the nearest beam's colour alone (one
## seam between them); six beams from one hand are white-hot only along their own cores, their stack
## the ramp's light.
func _check_union(spells: Node, wizards: PackedInt32Array, feel: Node) -> void:
	spells.call("clear")
	var plain: Array[StringName] = [&"hold", &"beam"]
	var fire: Array[StringName] = [&"hold", &"fire", &"beam"]
	var frost: Array[StringName] = [&"hold", &"frost", &"beam"]
	spells.call("install_staff", wizards[0], 0, spells.call("compile_staff", plain, STARTER))
	spells.call("install_staff", wizards[0], 1, spells.call("compile_staff", plain, STARTER))
	spells.call("install_staff", wizards[1], 0, spells.call("compile_staff", fire, STARTER))
	spells.call("install_staff", wizards[2], 0, spells.call("compile_staff", frost, STARTER))
	var fan: Array[StringName] = [&"hold", &"plus_two", &"plus_three", &"beam"]
	spells.call("install_staff", wizards[3], 0, spells.call("compile_staff", fan, STARTER))
	spells.call("cast_staff", wizards[0], 0, Vector2(100.0, 100.0), Vector2.RIGHT, 100.0)
	spells.call("cast_staff", wizards[0], 1, Vector2(100.0, 105.0), Vector2.RIGHT, 100.0)
	spells.call("cast_staff", wizards[1], 0, Vector2(100.0, 250.0), Vector2.RIGHT, 100.0)
	spells.call("cast_staff", wizards[2], 0, Vector2(200.0, 200.0), Vector2.DOWN, 100.0)
	spells.call("cast_staff", wizards[3], 0, FAN_HAND, Vector2.RIGHT, 100.0)
	await settle()
	var image: Image = await grab()
	save_crop(image, on_screen(Vector2(170.0, 102.0)), "beam_union_side_by_side_4x", Vector2i(50, 20), 4)
	save_crop(image, on_screen(FAN_HAND + Vector2(45.0, 0.0)), "beam_union_fan_hand_4x", Vector2i(50, 30), 4)
	# Six beams from one hand: their stack is the ramp's light, never white-hot of itself (the owner,
	# 2026-11-27: the colour reads near the hand), so only their own cores are white there.
	var white: int = 0
	var drawn: int = 0
	var from: Vector2 = on_screen(FAN_HAND + Vector2(8.0, -10.0))
	var to: Vector2 = on_screen(FAN_HAND + Vector2(28.0, 10.0))
	for y in range(int(from.y), int(to.y)):
		for x in range(int(from.x), int(to.x)):
			var c: Color = image.get_pixel(x, y)
			if c.get_luminance() > 0.6:
				drawn += 1
				white += 1 if c.get_luminance() > 0.88 else 0
	print("BEAM UNION: white-hot share of the fan by the hand: %d of %d" % [white, drawn])
	if drawn == 0 or white * 100 > drawn * WHITE_MOST:
		fail("six beams by the hand are white-hot more than %d%% (%d of %d): their stack must stop at the ramp's light" % [WHITE_MOST, white, drawn])
		return
	# Where the two are at most 6 px apart (the aim spreads them a little as they go).
	var union: BeamUnion = feel.call(&"beam_union", BEAM_CARD_SHADER) as BeamUnion
	var columns: Array[float] = []
	for x: float in [112.0, 116.0, 120.0, 124.0, 128.0, 132.0, 136.0, 140.0]:
		if union != null and union.beams >= 2 and absf(_beam_y(union, 1, x) - _beam_y(union, 0, x)) <= 6.0:
			columns.append(x)
	if columns.size() < 3:
		fail("the two beams side by side are not side by side (%d columns 6 px apart or less)" % columns.size())
		return
	# Player 0's ramp: its rim's shadow and base (shot_palette.gdshaderinc's P_SHADOW[0], P_BASE[0]).
	var rim: Array[Color] = [Color(0.114, 0.227, 0.420), Color(0.231, 0.451, 0.788)]
	var inner_rims: int = 0
	for x: float in columns:
		# The column's pixels across both beams; between their white-hot cores, the inside of the two.
		var column: Array[Color] = []
		for y in range(int(on_screen(Vector2(x, 88.0)).y), int(on_screen(Vector2(x, 118.0)).y)):
			column.append(image.get_pixel(int(on_screen(Vector2(x, 0.0)).x), y))
		var first: int = -1
		var last: int = -1
		for n in column.size():
			if column[n].get_luminance() > 0.85:
				first = n if first < 0 else first
				last = n
		for n in range(maxi(first, 0), last + 1):
			if _is_rim(column[n], rim):
				inner_rims += 1
	print("BEAM UNION: rim pixels inside two beams side by side: %d" % inner_rims)
	if inner_rims > 0:
		fail("two beams side by side draw a rim inside them (%d pixels of it)" % inner_rims)
		return
	# Where frost (the beam going down) crosses fire (the one going right from (100, 250)).
	var crossing := Vector2(-1.0, -1.0)
	for b in union.beams:
		var path: PackedVector3Array = union.path_of(b)
		var way: Vector3 = path[path.size() - 1] - path[0]
		if absf(way.y) > absf(way.x) and path[0].y < 210.0:
			var fire_y: float = _fire_y(union, path[0].x)
			crossing = Vector2(path[0].x + way.x * (fire_y - path[0].y) / way.y, fire_y)
	if crossing.x < 0.0:
		fail("fire and frost do not cross")
		return
	save_crop(image, on_screen(crossing), "beam_union_check_fire_frost_4x", Vector2i(30, 20), 4)
	# Over a few frames each (the beams' pulses and ripples move).
	var dithered: int = 0
	for frame in 4:
		dithered += _interleaved(await grab(), crossing)
	feel.call(&"set_beam_mix", BeamUnionScript.MIX_NEAREST)
	var nearest: int = 0
	for frame in 4:
		nearest += _interleaved(await grab(), crossing)
	feel.call(&"set_beam_mix", BeamUnionScript.MIX_DITHER)
	print("BEAM UNION: fire's and frost's colours meeting pixel to pixel at the junction: %d dithered, %d by the nearest beam" % [dithered, nearest])
	if dithered * 2 < nearest * 3:
		fail("where fire meets frost, the dither interleaves their colours half as often again as the nearest beam's colour alone, at least (%d dithered, %d nearest)" % [dithered, nearest])


## Where beam `b` of `union` (a straight one) is at `x` (world pixels).
func _beam_y(union: BeamUnion, b: int, x: float) -> float:
	var path: PackedVector3Array = union.path_of(b)
	var from: Vector3 = path[0]
	var to: Vector3 = path[path.size() - 1]
	return lerpf(from.y, to.y, (x - from.x) / maxf(to.x - from.x, 0.001))


## Where the fire beam (the one going right from (100, 250)) is at `x`.
func _fire_y(union: BeamUnion, x: float) -> float:
	for b in union.beams:
		var path: PackedVector3Array = union.path_of(b)
		if absf(path[0].y - 250.0) < 1.0 and absf(path[0].x - 100.0) < 1.0:
			return _beam_y(union, b, x)
	return -1.0


## How often fire's colours (red over blue) and frost's (blue over red) meet pixel to pixel within 5
## px of `crossing`, where the two cross: a dither interleaves them, the nearest beam's colour alone
## meets the other's only along a seam.
func _interleaved(image: Image, crossing: Vector2) -> int:
	var found: int = 0
	var from: Vector2 = on_screen(crossing - Vector2(5.0, 5.0))
	var to: Vector2 = on_screen(crossing + Vector2(5.0, 5.0))
	for y in range(int(from.y), int(to.y)):
		for x in range(int(from.x), int(to.x)):
			var here: int = _hue(image.get_pixel(x, y))
			if here != 0 and (_hue(image.get_pixel(x + 1, y)) == -here or _hue(image.get_pixel(x, y + 1)) == -here):
				found += 1
	return found


## 1 for fire's colours (red over blue), -1 for frost's (blue over red), 0 for neither.
func _hue(c: Color) -> int:
	if c.r > c.b + 0.25 and c.g < 0.8:
		return 1
	if c.b > c.r + 0.15:
		return -1
	return 0


## True when `c` is one of the rim's shades.
func _is_rim(c: Color, rim: Array[Color]) -> bool:
	for shade: Color in rim:
		if absf(c.r - shade.r) + absf(c.g - shade.g) + absf(c.b - shade.b) < 0.06:
			return true
	return false
