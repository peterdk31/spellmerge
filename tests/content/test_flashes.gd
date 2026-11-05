extends "res://tests/support/suite.gd"
## The flash kinds in `content/flashes/` (FlashKind; docs/milestones/flash-kinds.md): each is valid
## (no `problems()`), named for its file and found by the registry; `problems()` names what a broken
## one gets wrong; and the kinds ported from the flash shader's code (F2) give, curve by curve, what
## its branches worked out (`_old`, the shader before F2 in GDScript), at every age and zoom.

const RegistryScript := preload("res://core/registry/registry.gd")
const FlashTableScript := preload("res://gameplay/feel/flash_table.gd")

var registry: RegistryScript


func before_each() -> void:
	registry = own(RegistryScript.new()) as RegistryScript
	registry.scan()


func _kind(id: StringName) -> FlashKind:
	return registry.get_resource(&"flashes", id) as FlashKind


func test_every_kind_is_valid_and_named_for_its_file() -> void:
	var ids: Array = registry.get_ids(&"flashes")
	check(ids.size() >= 14, "the kinds are found: %s" % [ids])
	for id: StringName in ids:
		var kind: FlashKind = _kind(id)
		check(kind != null, "%s is a FlashKind" % id)
		if kind == null:
			continue
		check_equal(kind.problems(), PackedStringArray(), "%s has no problems" % id)
		check_equal(kind.resource_path.get_file(), "%s.tres" % id, "%s is in its own file" % id)


func test_problems_names_what_is_wrong() -> void:
	var kind := FlashKind.new()
	kind.draw = &"sparkle"
	kind.metric = &"square"
	kind.seconds = 0.0
	kind.ring = [{"at": 0.5, "from": 1.0}, {"at": 0.2, "way": &"bounce"}, {"off": true, "from": 2.0}, {"x": 1}, {}]
	kind.first = [{"shade": &"pink"}]
	var found: PackedStringArray = kind.problems()
	# no id; draw; metric; seconds; ring: 5 segments, starts at 0, out of order, a way, at not after,
	# off with values, an unknown key and its order; a shade.
	check(found.size() >= 10, "it names each: %s" % [found])
	var plain := FlashKind.new()
	plain.id = &"plain"
	check_equal(plain.problems().size(), 1, "a shape draws something: %s" % [plain.problems()])
	plain.draw = &"arc"
	check_equal(plain.problems(), PackedStringArray(), "a kind drawn by its own shader needs no curves")
	plain.arm = [{"from": 1.0}]
	check_equal(plain.problems().size(), 1, "and has none")


## The table is a row a kind of TEXELS texels, in the kinds' order, its head the draw, metric and
## salt; the shader's layout is the script's.
func test_the_table_is_laid_out_as_the_shader_reads_it() -> void:
	var kinds: Array[FlashKind] = [_kind(&"burst"), _kind(&"rune_burst"), _kind(&"quake")]
	var image: Image = FlashTableScript.image_of(kinds)
	check_equal(image.get_width(), FlashTableScript.TEXELS, "TEXELS a row")
	check_equal(image.get_height(), 3, "a row a kind")
	check_equal(image.get_pixel(0, 1), Color(0.0, 1.0, 33.0, 6.0), "the rune's head: a shape, a diamond, salt 33, the spiral's gap")
	check_equal(image.get_pixel(1, 1), Color(4.0, 8.0, 12.0, 1.0), "and its counts: star points, rays, dots, spiral arms")
	check_equal(image.get_pixel(0, 2).r, 2.0, "the quake's cracks")
	var code: String = (load("res://core/projectiles/shot_flash.gdshader") as Shader).code
	check(code.contains("const int SEGMENTS = %d;" % FlashTableScript.MAX_SEGMENTS), "the shader's SEGMENTS")
	check(code.contains("const int HEADS = %d;" % FlashTableScript.HEADS), "the shader's HEADS")
	check(15 + 16 * FlashKind.MAX_RAYS < 512 and FlashKind.MAX_POINTS < 16 and FlashKind.MAX_DOTS < 128, "the counts pack into the shader's floats")
	for c in FlashTableScript.CURVES.size():
		check(code.contains("const int C_%s = %d;" % [String(FlashTableScript.CURVES[c]).to_upper(), c]), "the shader's C_%s" % String(FlashTableScript.CURVES[c]).to_upper())
	for draw: StringName in FlashTableScript.DRAW_CODES:
		check(code.contains("const float D_%s = %s;" % [String(draw).to_upper(), str(FlashTableScript.DRAW_CODES[draw]).pad_decimals(1)]), "the shader's D_%s" % String(draw).to_upper())


## F2's port: every curve of every kind the flash shader drew in code gives what its branch did, at
## ages through its life (off its edges, where a `<` and a `>` may differ) and zooms 1 to 4. The
## numbers the shader rounds are compared rounded as it does (the cross's arms, a column's width).
func test_the_ported_kinds_draw_as_the_shader_did() -> void:
	for id: StringName in [&"burst", &"cast", &"ring_out", &"ring_in", &"rune_burst", &"spray", &"puff", &"poof", &"quake", &"rise", &"fall"]:
		var kind: FlashKind = _kind(id)
		var wrong: int = 0
		for z in range(1, 5):
			for n in 97:
				var a: float = (float(n) + 0.37) / 98.0
				var old: Dictionary = _old(id, a, float(z))
				for curve: StringName in old:
					var value: float = FlashTableScript.value_at(kind, curve, a, float(z))
					var was: float = old[curve]
					if curve == &"arm":
						value = roundf(value)
					elif curve == &"column_width" and value >= 0.0:
						value = floorf(value + 0.5)
					if absf(value - was) > 0.0005 and not (value < 0.0 and was < 0.0):
						wrong += 1
						if wrong <= 3:
							check(false, "%s %s at age %.3f zoom %d: %f, was %f" % [id, curve, a, z, value, was])
		check_equal(wrong, 0, "%s is drawn as before" % id)
		for part: StringName in [&"star", &"rays", &"dots", &"spiral"]:
			check(FlashTableScript.value_at(kind, part, 0.5, 2.0) < 0.0, "%s draws no %s (F4's parts are off unless given)" % [id, part])


## F4's drawings: the example kinds draw them (a part on at a third of their life) with the counts
## they say, and a count past what the shader packs is a problem.
func test_the_drawings_kinds_draw_them() -> void:
	var parts: Dictionary = {&"star": &"star", &"star_six": &"star", &"rays_out": &"rays", &"rays_in": &"rays", &"dot_ring": &"dots", &"spiral": &"spiral"}
	for id: StringName in parts:
		var kind: FlashKind = _kind(id)
		check(kind != null and FlashTableScript.value_at(kind, parts[id], 0.33, 2.0) > 0.0, "%s draws its %s" % [id, parts[id]])
	check_equal(_kind(&"star_six").star_points, 6, "six points")
	check_equal(_kind(&"spiral").spiral_arms, 2, "two arms")
	var many := FlashKind.new()
	many.id = &"many"
	many.rays = [{"from": 10.0}]
	many.ray_count = 40
	check_equal(many.problems().size(), 1, "40 rays are too many: %s" % [many.problems()])


## The flash shader's numbers before F2 (its vertex stage's branches, kind by kind) at age `a` and
## zoom `z`: a part below 0 is not drawn; the shades as FlashTable's numbers (-1 none).
static func _old(id: StringName, a: float, z: float) -> Dictionary:
	var ease: float = 1.0 - (1.0 - a) * (1.0 - a)
	var shade: float = -1.0
	var ramp: float = 0.0 if a < 0.15 else (1.0 if a < 0.4 else (2.0 if a < 0.7 else 3.0))
	var o: float = 12.0 * z
	match id:
		&"burst", &"cast":
			return {&"arm": roundf((1.5 if id == &"cast" else 2.0) * z * (1.0 - a * 2.5)), &"disc": -1.0, &"ring": -1.0,
				&"column_width": -1.0, &"first": 0.0, &"second": 1.0, &"glow": (1.0 - a) * (1.0 - a),
				&"glow_ring": 0.9, &"glow_ring_reach": 4.0 * z, &"glow_middle": 0.4, &"glow_middle_reach": 10.0 * z}
		&"ring_out", &"ring_in":
			var ring: float = lerpf(2.0 * z, 10.0 * z, ease) if id == &"ring_out" else lerpf(10.0 * z, 2.0 * z, ease)
			return {&"arm": -1.0, &"disc": -1.0, &"ring": ring, &"column_width": -1.0, &"first": shade, &"second": ramp,
				&"glow": 1.0 - a, &"glow_ring": 0.5, &"glow_ring_reach": 3.0 * z, &"glow_middle": 0.0, &"glow_middle_reach": 1.0}
		&"rune_burst":
			return {&"arm": -1.0, &"disc": 14.4 if a < 0.2 else -1.0, &"ring": lerpf(14.4, 14.4 * 2.2, ease), &"column_width": -1.0,
				&"first": 0.0 if a < 0.1 else 1.0, &"second": ramp, &"glow": 1.0 - a, &"glow_ring": 0.5, &"glow_ring_reach": 6.0,
				&"glow_middle": 0.8 if a < 0.25 else 0.0, &"glow_middle_reach": 14.4}
		&"poof":
			return {&"arm": -1.0, &"disc": -1.0, &"ring": -1.0, &"column_width": -1.0, &"glow": 1.0 - a,
				&"glow_ring": 0.3, &"glow_ring_reach": 6.0 * z, &"glow_middle": 0.0, &"glow_middle_reach": 1.0}
		&"spray", &"puff":
			var puff: bool = id == &"puff"
			return {&"arm": -1.0 if puff else (1.0 if a < 0.2 else -1.0), &"disc": (2.0 * z if a < 0.18 else -1.0) if puff else -1.0,
				&"ring": -1.0, &"column_width": -1.0, &"first": (0.0 if a < 0.09 else 1.0) if puff else 0.0, &"second": shade if puff else 0.0,
				&"glow": (1.0 - a) * (1.0 - a), &"glow_ring": 0.7, &"glow_ring_reach": 3.0 * z, &"glow_middle": 0.3, &"glow_middle_reach": 9.0 * z}
		&"quake":
			var k: float = maxf(1.0 - a * 2.5, 0.0)
			return {&"arm": -1.0, &"disc": -1.0, &"ring": -1.0, &"column_width": -1.0, &"glow": k * k,
				&"glow_ring": 0.8, &"glow_ring_reach": 8.0 * z * 0.6, &"glow_middle": 0.0, &"glow_middle_reach": 1.0}
		&"rise":
			var top: float = 1.0 - o
			var wide: float = a / 0.15 if a < 0.15 else maxf(1.0 - (a - 0.15) / 0.6, 0.0)
			var foot: float = 2.0 * z if a < 0.5 else lerpf(2.0 * z, top, (a - 0.5) / 0.35)
			var out: Dictionary = {&"arm": -1.0, &"disc": -1.0, &"ring": lerpf(9.0 * z, z, ease) if a < 0.7 else -1.0,
				&"column_width": floorf(1.5 * z * wide + 0.5) if a < 0.85 else -1.0, &"first": 0.0, &"second": 1.0 if a < 0.4 else 2.0,
				&"glow": 1.0 - a, &"glow_ring": 0.7, &"glow_ring_reach": 2.0 * z, &"glow_middle": 0.45, &"glow_middle_reach": 7.0 * z}
			if a < 0.85:
				out[&"column_top"] = top
				out[&"column_foot"] = foot
				out[&"column_dotted"] = 1.0 if a > 0.5 else 0.0
			return out
		&"fall":
			var top: float = 1.0 - o
			var strike: float = minf(a / 0.18, 1.0)
			var t: float = maxf(a - 0.18, 0.0) / 0.82
			var foot: float = lerpf(top, 2.0 * z, strike * strike)
			var out: Dictionary = {&"disc": -1.0,
				&"arm": roundf(2.0 * z * (1.0 - t / 0.25)) if a >= 0.18 and t < 0.25 else -1.0,
				&"ring": lerpf(2.0 * z, 11.0 * z, 1.0 - (1.0 - t) * (1.0 - t)) if a >= 0.18 else -1.0,
				&"first": 0.0, &"second": 0.0 if t < 0.15 else (1.0 if t < 0.4 else (2.0 if t < 0.7 else 3.0)),
				&"glow": 0.5 * strike if a < 0.18 else (1.0 - t) * (1.0 - t),
				&"glow_ring": 0.9, &"glow_ring_reach": 2.0 * z, &"glow_middle": 0.5, &"glow_middle_reach": 8.0 * z}
			if a < 0.18:
				out[&"column_width"] = 0.0
				out[&"column_foot"] = foot
				out[&"column_dotted"] = 0.0
			elif t < 0.5:
				out[&"column_width"] = floorf(2.0 * z * (1.0 - t / 0.5) + 0.5)
				out[&"column_top"] = top
				out[&"column_foot"] = foot
				out[&"column_dotted"] = 1.0 if t > 0.25 else 0.0
			else:
				out[&"column_width"] = -1.0
			return out
	return {}


## A fall's streak: before it strikes, the column is the streak's last 8 zoom steps above its foot
## (`column_length`), the top of the square where that is past it, as the shader did with a max.
func test_a_falls_streak_is_its_length_above_its_foot() -> void:
	var fall: FlashKind = _kind(&"fall")
	for z in range(1, 5):
		for n in 17:
			var a: float = (float(n) + 0.5) / 17.0 * 0.18
			var top: float = FlashTableScript.value_at(fall, &"column_top", a, float(z))
			var foot: float = FlashTableScript.value_at(fall, &"column_foot", a, float(z))
			var longest: float = FlashTableScript.value_at(fall, &"column_length", a, float(z))
			var old_top: float = maxf(foot - 8.0 * z, 1.0 - 12.0 * z)
			check(is_equal_approx(maxf(foot - longest, top), old_top), "its top at age %.3f zoom %d" % [a, z])
