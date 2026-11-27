extends "res://tests/support/suite.gd"
## Every beam as one merged shape (gameplay/feel/beam_union.gd; the owner, 2026-11-27): the data the
## union's shaders read is laid out as they read it, a path is cut into short pieces with its ends and
## cuts marked, a frame that outgrows the room keeps what it already added, a fading beam keeps its
## shape until it is nearly gone, and a beam's ramp and kind at a junction are its look's. (What the
## union draws is checked on drawn pixels by tests/screenshots/shot_beam_union.gd.)

const BeamUnionScript := preload("res://gameplay/feel/beam_union.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const PLAIN: Shader = preload("res://core/projectiles/shot_beam.gdshader")
const DATA := "res://core/projectiles/shot_beam_data.gdshaderinc"
const UNION := "res://core/projectiles/shot_beam_union.gdshaderinc"
const FIRE := Color(0.878, 0.349, 0.184)

var union: BeamUnion


func before_each() -> void:
	union = BeamUnionScript.new(PLAIN, 18, 8.0)


func after_each() -> void:
	union.node.free()


## A straight path from `from` to `to`, as Feel hands it (x, y and how far along).
func _path(from: Vector2, to: Vector2) -> PackedVector3Array:
	return PackedVector3Array([Vector3(from.x, from.y, 0.0), Vector3(to.x, to.y, from.distance_to(to))])


func _add(from: Vector2, to: Vector2, core: Color = Color.WHITE, fade: float = 1.0) -> int:
	return union.add(_path(from, to), 2, from, to, from.distance_to(to), core, 0, 0, PackedColorArray(), fade, 1.0, 16.0, 0.6)


## Piece `s`'s texel `k` in the data texture.
func _piece(s: int, k: int) -> Color:
	return union._image.get_pixel((s % BeamUnion.SEGS_A_ROW) * BeamUnion.SEG_TEXELS + k, union._beam_room + s / BeamUnion.SEGS_A_ROW)


func test_the_shaders_read_the_data_as_it_is_laid_out() -> void:
	var data: String = FileAccess.get_file_as_string(DATA)
	for pair: Array in [["ROW", BeamUnion.ROW], ["B_ENDS", BeamUnion.B_ENDS], ["B_SHAPE", BeamUnion.B_SHAPE], ["B_CORE", BeamUnion.B_CORE], ["B_LOOK", BeamUnion.B_LOOK], ["B_KIND", BeamUnion.B_KIND], ["B_INFUSIONS", BeamUnion.B_INFUSIONS], ["SEG_TEXELS", BeamUnion.SEG_TEXELS], ["SEGS_A_ROW", BeamUnion.SEGS_A_ROW], ["S_ENDS", BeamUnion.S_ENDS], ["S_SHAPE", BeamUnion.S_SHAPE], ["S_WHO", BeamUnion.S_WHO], ["S_WIDTH", BeamUnion.S_WIDTH], ["RAMP_PLAYER", BeamUnion.RAMP_PLAYER], ["RAMP_OWN", BeamUnion.RAMP_OWN], ["MIX_DITHER", BeamUnion.MIX_DITHER], ["MIX_SNAP", BeamUnion.MIX_SNAP], ["MIX_NEAREST", BeamUnion.MIX_NEAREST]]:
		check(data.contains("const int %s = %d;" % pair), "the shaders' %s is %d" % pair)
	for pair: Array in [["F_FIRST", BeamUnion.F_FIRST], ["F_LAST", BeamUnion.F_LAST], ["F_CUT_BEFORE", BeamUnion.F_CUT_BEFORE], ["F_CUT_AFTER", BeamUnion.F_CUT_AFTER]]:
		check(data.contains("const float %s = %d.0;" % pair), "the shaders' %s is %d" % pair)
	check(FileAccess.get_file_as_string(UNION).contains("const float SOFT = %.1f;" % BeamUnion.SOFT), "and the union's softness is the one a fading beam gives way by")
	check(BeamUnion.B_INFUSIONS + BeamUnion.INFUSIONS_MOST <= BeamUnion.ROW, "a beam's infusions fit its row")
	check_equal(BeamUnion.SEG_TEXELS * BeamUnion.SEGS_A_ROW, BeamUnion.ROW, "pieces fill a row")


func test_a_path_is_cut_into_short_pieces_with_its_ends_and_cuts_marked() -> void:
	union.begin()
	var b: int = _add(Vector2(0, 0), Vector2(200, 0))
	var pieces: int = ceili(200.0 / BeamUnion.PIECE_MOST)
	check_equal(union.segment_counts[b], pieces, "pieces of at most PIECE_MOST pixels")
	for s in pieces:
		var ends: Color = _piece(s, BeamUnion.S_ENDS)
		check(absf(ends.b - ends.r) <= BeamUnion.PIECE_MOST + 0.001, "piece %d is short" % s)
		check(is_equal_approx(_piece(s, BeamUnion.S_SHAPE).r, ends.r), "and says how far along the beam it starts")
		var flags: int = int(_piece(s, BeamUnion.S_WHO).g)
		check_equal(flags & BeamUnion.F_FIRST != 0, s == 0, "piece %d is the first only at the start" % s)
		check_equal(flags & BeamUnion.F_LAST != 0, s == pieces - 1, "and the last only at the end")
		check_equal(flags & BeamUnion.F_CUT_BEFORE != 0, s > 0, "a cut before every piece but the first")
		check_equal(flags & BeamUnion.F_CUT_AFTER != 0, s < pieces - 1, "and after every piece but the last")
		if s > 0:
			check(_piece(s - 1, BeamUnion.S_ENDS).b == ends.r, "each piece starts exactly where the one before ends")
	check(union.path_of(b) == _path(Vector2(0, 0), Vector2(200, 0)), "the path is kept as it was handed")


func test_a_bend_is_no_cut() -> void:
	union.begin()
	var path := PackedVector3Array([Vector3(0, 0, 0), Vector3(20, 0, 20), Vector3(20, 20, 40)])
	union.add(path, 3, Vector2.ZERO, Vector2(20, 20), 40.0, Color.WHITE, 0, 0, PackedColorArray(), 1.0, 1.0, 16.0, 0.6)
	check_equal(union.segments, 2, "a piece each side of the bend")
	check_equal(int(_piece(0, BeamUnion.S_WHO).g), BeamUnion.F_FIRST, "the first, no cut after it: its pixels round the bend look at the next")
	check_equal(int(_piece(1, BeamUnion.S_WHO).g), BeamUnion.F_LAST, "the last, no cut before it")


func test_a_frame_that_outgrows_the_room_keeps_what_it_added() -> void:
	union.begin()
	var room: int = union.segment_room()
	_add(Vector2(0, 7), Vector2(30, 7), FIRE)
	while union.segments < room:
		_add(Vector2(0, 100), Vector2(200, 100))
	var grown: int = _add(Vector2(0, 50), Vector2(30, 50))
	check(union.segment_room() > room, "the room grew")
	check(_piece(0, BeamUnion.S_ENDS).is_equal_approx(Color(0, 7, 30, 7)), "the first beam's piece is where it was")
	check(union._image.get_pixel(BeamUnion.B_CORE, 0).is_equal_approx(Color(FIRE.r, FIRE.g, FIRE.b, 0.0)), "and its row")
	var last: int = union.first_segments[grown]
	check(_piece(last, BeamUnion.S_ENDS).is_equal_approx(Color(0, 50, 30, 50)), "the beam that outgrew it is added after them")
	check_equal(int(_piece(last, BeamUnion.S_WHO).r), grown, "naming its own beam")
	union.publish(0.0)
	check_equal(union.material.get_shader_parameter(&"beam_rows"), union._beam_room, "the shader is told where the pieces start now")
	check_equal((union.node.mesh as ArrayMesh).surface_get_array_len(0), union.segment_room() * 4, "and its mesh has a quad a piece of room")


func test_a_frame_within_the_room_makes_nothing() -> void:
	for frame in 3:
		union.begin()
		for n in 6:
			_add(Vector2(0, n * 10), Vector2(200, n * 10))
		union.publish(float(frame))
	var mesh: Mesh = union.node.mesh
	var made: int = union._upload.made
	for frame in 5:
		union.begin()
		for n in 6:
			_add(Vector2(0, n * 10), Vector2(200, n * 10))
		union.publish(float(frame))
	check(union.node.mesh == mesh, "no new mesh")
	check_equal(union._upload.made, made, "no new image")
	union.begin()
	union.publish(0.0)
	check(not union.node.visible, "no beams: nothing drawn")


func test_a_fading_beam_keeps_its_shape_until_it_is_nearly_gone() -> void:
	check_equal(BeamUnion.give_of(1.0), 0.0, "a whole beam gives no way")
	check_equal(BeamUnion.give_of(BeamUnion.FADE_GIVES), 0.0, "nor one dissolving into pixels, down to FADE_GIVES")
	var last: float = 0.0
	for n in range(1, 30):
		var fade: float = BeamUnion.FADE_GIVES * (1.0 - n / 30.0)
		var give: float = BeamUnion.give_of(fade)
		check(give > last, "then more and more as it goes (%f at %f)" % [give, fade])
		last = give
	check(is_equal_approx(BeamUnion.give_of(BeamUnion.FADE_GIVES * 0.5), BeamUnion.SOFT * log(2.0)), "half of what was left: as much as a second beam as near draws it in")


func test_a_beams_ramp_and_kind_at_a_junction_are_its_looks() -> void:
	check_equal(BeamUnion.ramp_of(Color.WHITE, 2, 0), BeamUnion.RAMP_PLAYER + 2, "a plain beam: its player's ramp")
	check_equal(BeamUnion.ramp_of(Color.WHITE, -1, 0), BeamUnion.RAMP_PLAYER + 4, "an enemy's: the enemy ramp")
	check(BeamUnion.ramp_of(FIRE, 0, 0) < BeamUnion.RAMP_PLAYER, "an element's: its palette material")
	check_equal(BeamUnion.ramp_of(Color(0.2, 0.95, 0.3), 0, 0), BeamUnion.RAMP_OWN, "a tint no material holds: its own")
	check_equal(BeamUnion.ramp_of(FIRE, 0, BeamUnion.LOOK_EXACT), BeamUnion.RAMP_OWN, "an exact colour: its own")
	var infusions := PackedColorArray([Color(FIRE.r, FIRE.g, FIRE.b, 1.0 / 255.0)])
	check_equal(BeamUnion.first_kind_of(FIRE, 0, infusions), 1, "its first infusion's kind")
	var sparks: int = 1 << (ManagerScript.LOOK_SPARKS - 1)
	check_equal(BeamUnion.first_kind_of(FIRE, sparks, PackedColorArray()), ManagerScript.LOOK_SPARKS, "a shown beam's from its look")
	check_equal(BeamUnion.first_kind_of(Color.WHITE, sparks, PackedColorArray()), 0, "a plain one sways not")
