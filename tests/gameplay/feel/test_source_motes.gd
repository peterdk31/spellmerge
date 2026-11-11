extends "res://tests/support/suite.gd"
## Source motes (gameplay/feel/source_motes.gd, core/base/mote_source.gd; props W7): a node in the
## group `mote_source` with a `MoteSource` gives off its kind's motes at its rate, from a point, a
## line (thrown outward: the left of the way its points run; the hub's island edge), a box, an
## oval's rim or a mask's lit pixels, each in one of its ramps, else its art's colours; a standing
## mask places a mote on every lit pixel; from when to when it appeared; only near the view;
## nothing with no source, a broken one or the particles off; the tree followed as nodes come and go.

const MotesScript := preload("res://gameplay/feel/mote.gd")
const SourceMotesScript := preload("res://gameplay/feel/source_motes.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")
const PlacedMotesScript := preload("res://gameplay/feel/placed_motes.gd")
const MotePlaces := preload("res://gameplay/feel/mote_places.gd")

const STEP: float = 1.0 / 60.0

var table: RampTableScript


func before_each() -> void:
	table = RampTableScript.new()


func _pool() -> MotesScript:
	var kind := MoteKind.new()
	kind.id = &"source_test"
	kind.gravity = -6.0
	kind.drag = 2.0
	kind.count = 1
	kind.height = 0.0
	var motes: MotesScript = own(MotesScript.new(4096, 0, [kind] as Array[MoteKind])) as MotesScript
	root.add_child(motes)
	return motes


func _look(from: MoteSource.From = MoteSource.From.LINE, rate: float = 40.0) -> MoteSource:
	var look := MoteSource.new()
	look.kind = &"source_test"
	look.rate = rate
	look.from = from
	look.colours = [&"fire", &"ice"]
	return look


## A node with `look` in the tree (in the group unless not `group`): a square line 100 px a side,
## clockwise on screen, for a line; else a plain Node2D at `at`.
func _node(look: MoteSource, at: Vector2 = Vector2.ZERO, group: bool = true) -> Node2D:
	var node: Node2D
	if look.from == MoteSource.From.LINE:
		var line := Line2D.new()
		line.points = PackedVector2Array([Vector2(100, 100), Vector2(200, 100), Vector2(200, 200), Vector2(100, 200)])
		line.closed = true
		line.visible = false
		node = line
	else:
		node = Node2D.new()
		node.position = at
	own(node)
	if group:
		node.add_to_group(MoteSource.GROUP)
	node.set_meta(MoteSource.META, look)
	root.add_child(node)
	return node


## A 4x4 sprite with three lit pixels, (1,1), (2,1) and (1,3), in two colours, at `at` (its top
## left corner), and a mask source on it.
func _mask(look: MoteSource, at: Vector2) -> Node2D:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.set_pixel(1, 1, Color("7a7694"))
	image.set_pixel(2, 1, Color("7a7694"))
	image.set_pixel(1, 3, Color("2b2840"))
	var holder := own(Node2D.new()) as Node2D
	holder.position = at
	var art := Sprite2D.new()
	art.name = "Art"
	art.centered = false
	art.texture = ImageTexture.create_from_image(image)
	holder.add_child(art)
	var node := Node2D.new()
	MoteSource.put(node, look, NodePath("../Art"))
	holder.add_child(node)
	root.add_child(holder)
	return holder


## Give off for `seconds`, a frame at a time, from Feel's clock `start`; the clock after.
func _run(sources: SourceMotesScript, motes: MotesScript, seconds: float, start: float = 0.0, view: Rect2 = Rect2()) -> float:
	var now: float = start
	sources.give_off(now, motes, view)
	while now < start + seconds - 0.0001:
		now += STEP
		sources.give_off(now, motes, view)
		motes.step(now)
	return now


func _at(motes: MotesScript, row: int) -> Vector2:
	var data: PackedFloat32Array = motes.row_data(row)
	return Vector2(data[MotesScript.ROW_X], data[MotesScript.ROW_Y])


func test_a_line_gives_off_its_rate_along_it_thrown_outward() -> void:
	_node(_look(MoteSource.From.LINE, 40.0))
	var sources := SourceMotesScript.new(table)
	sources.take(self)
	check_equal(sources.source_count(), 1, "the line is read")
	var motes := _pool()
	var before: int = motes.next_row()
	_run(sources, motes, 2.0)
	var born: int = motes.next_row() - before
	check(born >= 76 and born <= 84, "about 80 motes in 2 s at 40 a second (%d)" % born)
	var fire: int = table.source(Palette.ramp_of(&"fire"))
	var ice: int = table.source(Palette.ramp_of(&"ice"))
	var seen_fire: bool = false
	var seen_ice: bool = false
	var outward: int = 0
	for row in range(before, before + born):
		var data: PackedFloat32Array = motes.row_data(row)
		var at: Vector2 = _at(motes, row)
		var v := Vector2(data[MotesScript.ROW_VX], data[MotesScript.ROW_VY])
		check(absf(at.x - 100.0) <= 2.0 or absf(at.x - 200.0) <= 2.0 or absf(at.y - 100.0) <= 2.0 or absf(at.y - 200.0) <= 2.0, "mote %d is born on the line: %s" % [row, at])
		if v.dot(at - Vector2(150, 150)) > 0.0:
			outward += 1
		var source: int = roundi(data[MotesScript.ROW_SOURCE] * MotesScript.SOURCE_CODE)
		seen_fire = seen_fire or source == fire
		seen_ice = seen_ice or source == ice
	check(outward >= born * 9 / 10, "nearly all fly outward (%d of %d)" % [outward, born])
	check(seen_fire and seen_ice, "each in one of the source's palette materials, both used")


func test_a_point_a_box_and_a_rim_give_off_where_they_say() -> void:
	var point := _look(MoteSource.From.POINT, 30.0)
	point.at = Vector2(4, -6)
	_node(point, Vector2(400, 400))
	var box := _look(MoteSource.From.AREA, 30.0)
	box.size = Vector2(20, 10)
	_node(box, Vector2(600, 400))
	var oval := _look(MoteSource.From.RIM, 30.0)
	oval.size = Vector2(40, 20)
	_node(oval, Vector2(800, 400))
	var sources := SourceMotesScript.new(table)
	sources.take(self)
	check_equal(sources.source_count(), 3, "three sources read")
	var motes := _pool()
	var before: int = motes.next_row()
	_run(sources, motes, 1.0)
	var counts := [0, 0, 0]
	for row in range(before, motes.next_row()):
		var at: Vector2 = _at(motes, row)
		if at.distance_to(Vector2(404, 394)) <= 0.5:
			counts[0] += 1
		elif absf(at.x - 600.0) <= 10.5 and absf(at.y - 400.0) <= 5.5:
			counts[1] += 1
		else:
			var off: Vector2 = (at - Vector2(800, 400)) / Vector2(20, 10)
			check(absf(off.length() - 1.0) <= 0.15, "a rim mote on the oval: %s" % at)
			counts[2] += 1
	for i in 3:
		check(counts[i] >= 27 and counts[i] <= 33, "source %d gives off about 30 in a second (%s)" % [i, counts])


func test_a_mask_gives_off_from_its_lit_pixels_in_its_art_colours() -> void:
	var look := _look(MoteSource.From.MASK, 60.0)
	look.colours = []
	var holder: Node2D = _mask(look, Vector2(300, 300))
	var sources := SourceMotesScript.new(table)
	sources.take(self)
	check_equal(sources.source_count(), 1, "the mask is read")
	var motes := _pool()
	var before: int = motes.next_row()
	_run(sources, motes, 1.0)
	var lit: Array[Vector2] = [Vector2(301.5, 301.5), Vector2(302.5, 301.5), Vector2(301.5, 303.5)]
	var art: int = table.source(ArtPixels.colours_of((holder.get_node("Art") as Sprite2D).texture))
	var hits: Dictionary = {}
	for row in range(before, motes.next_row()):
		var at: Vector2 = _at(motes, row)
		var near: int = 0
		for i in lit.size():
			if at.distance_to(lit[i]) < at.distance_to(lit[near]):
				near = i
		check(at.distance_to(lit[near]) <= 0.75, "a mote on a lit pixel: %s" % at)
		hits[near] = true
		var source: int = roundi(motes.row_data(row)[MotesScript.ROW_SOURCE] * MotesScript.SOURCE_CODE)
		check_equal(source, art, "in its art's colours")
	check_equal(hits.size(), 3, "every lit pixel gives off")
	var unlit := _look(MoteSource.From.MASK)
	check(not unlit.problems(false).is_empty(), "a mask with no art is a problem")


func test_a_standing_mask_places_a_mote_on_every_lit_pixel_each_frame() -> void:
	var look := _look(MoteSource.From.MASK)
	look.stand = true
	look.rate = 0.0
	look.life = 1.0
	_mask(look, Vector2(300, 300))
	var sources := SourceMotesScript.new(table)
	sources.take(self)
	var motes := _pool()
	var stand := own(PlacedMotesScript.new(16, "Standing")) as PlacedMotesScript
	root.add_child(stand)
	var before: int = motes.next_row()
	sources.give_off(0.0, motes, Rect2(), stand)
	sources.give_off(0.5, motes, Rect2(), stand)
	check_equal(stand.rows, 3, "a standing mote on each lit pixel this frame")
	check_equal(motes.next_row(), before, "none is given off")
	var ages: Array[float] = []
	for row in 3:
		var data: PackedFloat32Array = stand.row_data(row)
		var at := Vector2(data[MotesScript.ROW_X], data[MotesScript.ROW_Y])
		check(at.x >= 301.0 and at.x <= 303.0 and at.y >= 301.0 and at.y <= 304.0, "on its pixel: %s" % at)
		ages.append(0.5 - data[MotesScript.ROW_BORN])
	check(ages[0] != ages[1] or ages[1] != ages[2], "each cools in its own turn: %s" % [ages])
	sources.give_off(1.0, null, Rect2(), stand)
	check_equal(stand.rows, 0, "the particles off: none placed")
	var moving := _look(MoteSource.From.POINT)
	moving.stand = true
	check(not moving.problems().is_empty(), "only a mask stands")


func test_it_gives_off_from_start_to_stop_after_it_appeared() -> void:
	var look := _look(MoteSource.From.POINT, 60.0)
	look.start = 0.5
	look.stop = 1.0
	_node(look, Vector2(400, 400))
	var sources := SourceMotesScript.new(table)
	sources.take(self)
	var motes := _pool()
	var before: int = motes.next_row()
	var now: float = _run(sources, motes, 0.45, 10.0)
	check_equal(motes.next_row(), before, "nothing before its start")
	now = _run(sources, motes, 0.6, now)
	var given: int = motes.next_row() - before
	check(given >= 27 and given <= 33, "half a second's worth between start and stop (%d)" % given)
	_run(sources, motes, 1.0, now)
	check_equal(motes.next_row() - before, given, "nothing after its stop")


func test_only_sources_near_the_view_give_off() -> void:
	_node(_look(MoteSource.From.POINT, 60.0), Vector2(100, 100))
	_node(_look(MoteSource.From.POINT, 60.0), Vector2(3000, 100))
	var sources := SourceMotesScript.new(table)
	sources.take(self)
	var motes := _pool()
	var before: int = motes.next_row()
	_run(sources, motes, 1.0, 0.0, Rect2(0, 0, 640, 360))
	var given: int = motes.next_row() - before
	check(given >= 55 and given <= 65, "one source's worth (%d)" % given)
	for row in range(before, motes.next_row()):
		check(_at(motes, row).x < 700.0, "only the one in view gives off")


func test_it_follows_the_tree_and_holds_no_node() -> void:
	var sources := SourceMotesScript.new(table)
	sources.watch(self)
	var motes := _pool()
	sources.give_off(0.0, motes)
	check_equal(sources.source_count(), 0, "none yet")
	var node := _node(_look(MoteSource.From.POINT, 60.0), Vector2(400, 400))
	check_equal(sources.source_count(), 0, "a node that enters is read at the next frame")
	sources.give_off(STEP, motes)
	check_equal(sources.source_count(), 1, "read")
	var mask := _look(MoteSource.From.MASK, 60.0)
	_mask(mask, Vector2(200, 200))
	sources.give_off(STEP * 2.0, motes)
	check_equal(sources.source_count(), 2, "a mask whose art entered after it is read whole")
	root.remove_child(node)
	check_equal(sources.source_count(), 1, "a node that leaves is let go")
	node.free()
	var before: int = motes.next_row()
	_run(sources, motes, 0.5, STEP * 3.0)
	check(motes.next_row() > before, "the rest give off")
	sources.watch(null)
	_node(_look(MoteSource.From.POINT), Vector2(10, 10))
	sources.give_off(1.0, motes)
	check_equal(sources.source_count(), 0, "followed no more")


func test_nothing_without_a_sound_source_or_with_the_particles_off() -> void:
	var motes := _pool()
	var sources := SourceMotesScript.new(table)
	_node(_look(), Vector2.ZERO, false)
	sources.take(self)
	check_equal(sources.source_count(), 0, "a node out of the group is no source")
	var broken := _look()
	broken.colours = []
	_node(broken)
	sources.take(self)
	check_equal(sources.source_count(), 0, "a source with no colours is left out")
	var unknown := _look()
	unknown.kind = &"no_such_kind"
	_node(unknown)
	sources.take(self)
	var before: int = motes.next_row()
	_run(sources, motes, 1.0)
	check_equal(motes.next_row(), before, "a kind the pool lacks throws nothing")
	_node(_look())
	sources.take(self)
	sources.give_off(0.0, null)
	sources.give_off(0.5, null)
	check_equal(motes.next_row(), before, "the particles off: nothing")
	sources.take(null)
	check_equal(sources.source_count(), 0, "out of a tree: none")


func test_the_problems_of_a_source() -> void:
	check(_look().problems(false).is_empty(), "a sound source")
	var none := MoteSource.new()
	check(not none.problems(false).is_empty(), "no kind and no colours is a problem")
	var unknown := _look()
	unknown.colours = [&"teal"]
	check(not unknown.problems(false).is_empty(), "a colour the palette lacks is a problem")
	var owned := _look()
	owned.colours = [&"player_1"]
	check(not owned.problems(false).is_empty(), "a player's colour is a problem")
	var flat := _look(MoteSource.From.AREA)
	check(not flat.problems(false).is_empty(), "a box of no size is a problem")
	var late := _look()
	late.start = 2.0
	late.stop = 1.0
	check(not late.problems(false).is_empty(), "stopping before it starts is a problem")
	var bare := _look()
	bare.colours = []
	check(bare.problems(true).is_empty(), "with art, no ramps is fine (its art's colours)")


## The places within an oval (`mote_places.gd`), shared with a still card's motes: in it, on its rim,
## and on the world's grid.
func test_the_shared_places_in_an_oval() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 200:
		var inside: Vector2 = MotePlaces.in_oval(rng, Vector2(10, 4), 0.9)
		check((inside / Vector2(10, 4)).length() <= 0.9001, "in the oval: %s" % inside)
		var rim: Vector2 = MotePlaces.on_oval(rng, Vector2(10, 4), 0.0)
		check(rim == rim.round() and absf((rim / Vector2(10, 4)).length() - 1.0) <= 0.3, "on its rim, whole pixels: %s" % rim)
	check_equal(MotePlaces.on_grid(3.0, 10.0, 4.0), 2.0, "on the world's grid of 4: 13 to 12")
	check_equal(MotePlaces.on_grid(3.3, 10.0, 0.0), 3.3, "no spacing: as it is")
