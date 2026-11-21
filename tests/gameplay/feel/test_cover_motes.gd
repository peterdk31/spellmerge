extends "res://tests/support/suite.gd"
## Burning cover's motes (ground cover GC8, gameplay/feel/cover_motes.gd, docs/milestones/ground-cover.md
## rule 6): a cover state's `motes`, each a `MoteSource` read as if a cell were its node, given off
## by every cell Feel shows in that state, at its rate a cell; the cells kept as the state changes
## (`show_state`, the cover area's changes); none with the particles off, none from a cell far from
## the view, at most `MOST_A_FRAME` a frame; a stream that cannot be given off from a cell (a mask,
## a standing one) refused and the others given off; a frame of it allocates nothing.
const CoverScript := preload("res://gameplay/feel/cover.gd")
const CoverMotesScript := preload("res://gameplay/feel/cover_motes.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")
var fixture_grass: CoverKind = preload("res://tests/core/fixtures/cover_content/cover/test_grass/test_grass.tres")

const STEP: float = 1.0 / 60.0
const BURNING: int = 1
## The field of grass every test lays: cells (12, 12) to (15, 15) of a room 640×384, 16 cells.
const FIELD := Rect2(192, 192, 64, 64)


## The test grass, its burning state giving off `rate` motes of `source_test` a second a cell.
func _grass(rate: float = 6.0) -> CoverKind:
	var kind := fixture_grass.duplicate(true) as CoverKind
	kind.biomes = [] as Array[StringName]
	var image := Image.create_empty(16 * 6, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.5, 0.2))
	kind.sheet = ImageTexture.create_from_image(image)
	kind.states[BURNING].motes = [_look(rate)] as Array[MoteSource]
	return kind


func _look(rate: float, from: MoteSource.From = MoteSource.From.AREA) -> MoteSource:
	var look := MoteSource.new()
	look.kind = &"source_test"
	look.rate = rate
	look.from = from
	look.size = Vector2(12.0, 6.0)
	look.colours = [&"fire", &"spark"] as Array[StringName]
	return look


func _pool() -> MotesScript:
	var kind := MoteKind.new()
	kind.id = &"source_test"
	kind.gravity = -6.0
	kind.count = 1
	var motes: MotesScript = own(MotesScript.new(4096, 0, [kind] as Array[MoteKind])) as MotesScript
	root.add_child(motes)
	return motes


func _layout(kind: CoverKind) -> CoverLayout:
	var layout := own(Node2D.new()) as Node2D
	var walls := StaticBody2D.new()
	walls.collision_layer = RoomBase.WALL_LAYER
	layout.add_child(walls)
	for box: Rect2 in [Rect2(0, 0, 640, 32), Rect2(0, 352, 640, 32), Rect2(0, 0, 32, 384), Rect2(608, 0, 32, 384)]:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = box.size
		shape.shape = rect
		shape.position = box.get_center()
		walls.add_child(shape)
	var field := CoverField.new()
	field.kind = kind.id
	field.offset_left = FIELD.position.x
	field.offset_top = FIELD.position.y
	field.offset_right = FIELD.end.x
	field.offset_bottom = FIELD.end.y
	layout.add_child(field)
	var room := RoomBase.new()
	room.id = &"meadow"
	return CoverLayout.of(layout, room, [kind] as Array[CoverKind])


func _motes(kind: CoverKind) -> CoverMotesScript:
	var motes := CoverMotesScript.new()
	motes.ramp_table = RampTableScript.new()
	motes.lay(_layout(kind))
	return motes


func _cell(x: int, y: int) -> int:
	return y * 40 + x


## `frames` frames of STEP from `start`, into `pool`, seeing `view`.
func _frames(motes: CoverMotesScript, pool: MotesScript, frames: int, view: Rect2 = Rect2(), start: float = 1.0) -> void:
	for i in frames + 1:
		motes.give_off(start + i * STEP, pool, view)


func test_only_cells_in_a_state_with_motes_give_off() -> void:
	var kind: CoverKind = _grass()
	var motes: CoverMotesScript = _motes(kind)
	check_equal(motes.cells_giving_off(kind.id, 0), 0, "at rest: no motes")
	_frames(motes, _pool(), 60)
	check_equal(motes.given, 0, "and none given off")
	for x in [12, 13, 14]:
		motes.show(_cell(x, 12), BURNING)
	check_equal(motes.cells_giving_off(kind.id, BURNING), 3, "three cells burning")
	motes.show(_cell(13, 12), 2)
	check_equal(motes.cells_giving_off(kind.id, BURNING), 2, "one gone to ash")
	motes.show(_cell(12, 12), BURNING)
	check_equal(motes.cells_giving_off(kind.id, BURNING), 2, "shown again in the state it is in: no change")
	motes.show(_cell(14, 12), 0)
	motes.show(_cell(12, 12), 0)
	check_equal(motes.cells_giving_off(kind.id, BURNING), 0, "all out")
	motes.show(_cell(2, 2), BURNING)
	check_equal(motes.cells_giving_off(kind.id, BURNING), 0, "a bare cell gives off nothing")


func test_a_resting_state_with_motes_gives_off_from_every_cell_as_laid() -> void:
	var kind: CoverKind = _grass()
	kind.states[0].motes = [_look(1.0)] as Array[MoteSource]
	var motes: CoverMotesScript = _motes(kind)
	check_equal(motes.cells_giving_off(kind.id, 0), 16, "every cell of the field, at rest")


func test_it_gives_off_its_rate_a_cell_round_each_cell() -> void:
	var kind: CoverKind = _grass(6.0)
	var motes: CoverMotesScript = _motes(kind)
	var pool: MotesScript = _pool()
	for x in 4:
		motes.show(_cell(12 + x, 13), BURNING)
	_frames(motes, pool, 60)
	check(motes.given >= 22 and motes.given <= 24, "6 a second from each of 4 cells, for a second (%d)" % motes.given)


func test_none_with_the_particles_off_nor_far_from_the_view() -> void:
	var kind: CoverKind = _grass(20.0)
	var motes: CoverMotesScript = _motes(kind)
	motes.show(_cell(12, 12), BURNING)
	_frames(motes, null, 60)
	check_equal(motes.given, 0, "no pool: none")
	_frames(motes, _pool(), 60, Rect2(2000, 2000, 320, 180), 3.0)
	check_equal(motes.given, 0, "a view far away: none")
	_frames(motes, _pool(), 60, Rect2(100, 100, 320, 180), 5.0)
	check(motes.given > 0, "a view over it: some")


func test_a_room_far_from_the_view_rolls_nothing_and_comes_back_at_its_rate() -> void:
	# The performance pass of 2026-11-21: a room whose every cell is far from the view rolls no dice
	# (they were rolled and every mote passed by), keeping only the part of a mote it owes, so
	# nothing it saved up bursts out when the view comes back.
	var kind: CoverKind = _grass(20.0)
	var motes: CoverMotesScript = _motes(kind)
	var pool: MotesScript = _pool()
	for x in 4:
		motes.show(_cell(12 + x, 13), BURNING)
	var rolled: int = motes._rng.state
	_frames(motes, pool, 120, Rect2(2000, 2000, 320, 180))
	check_equal(motes.given, 0, "far away: none given off")
	check_equal(motes._rng.state, rolled, "and no dice rolled")
	for stream in motes._streams:
		check(stream.owed >= 0.0 and stream.owed < 1.0, "owing less than a mote (%f)" % stream.owed)
	_frames(motes, pool, 1, Rect2(0, 0, 640, 360), 3.0)
	check(motes.given <= 2, "back in view: a frame's worth, no burst (%d)" % motes.given)
	_frames(motes, pool, 60, Rect2(0, 0, 640, 360), 3.0 + STEP)
	check(motes.given >= 76 and motes.given <= 84, "then its rate, 20 a second from 4 cells (%d)" % motes.given)


func test_at_most_a_frames_worth_at_once() -> void:
	var kind: CoverKind = _grass(2000.0)
	var motes: CoverMotesScript = _motes(kind)
	var pool: MotesScript = _pool()
	for y in 4:
		for x in 4:
			motes.show(_cell(12 + x, 12 + y), BURNING)
	motes.give_off(1.0, pool)
	motes.give_off(1.1, pool)
	check_equal(motes.given, CoverMotesScript.MOST_A_FRAME, "a whole field catching: a frame's worth")
	motes.give_off(1.2, pool)
	check_equal(motes.given, 2 * CoverMotesScript.MOST_A_FRAME, "and the next frame no more")


func test_a_stream_a_cell_cannot_give_off_is_refused_and_the_rest_go_on() -> void:
	var kind: CoverKind = _grass(6.0)
	var standing := _look(6.0, MoteSource.From.MASK)
	standing.stand = true
	kind.states[BURNING].motes.append(standing)
	check(not CoverMotesScript.stream_problems(standing).is_empty(), "a standing mask is named")
	check_equal(CoverMotesScript.stream_problems(_look(6.0)), PackedStringArray(), "an area is fine")
	var motes: CoverMotesScript = _motes(kind)
	motes.show(_cell(12, 12), BURNING)
	_frames(motes, _pool(), 60)
	check(motes.given >= 5 and motes.given <= 6, "the area's motes only (%d)" % motes.given)


func test_feels_cover_tells_it_each_cells_state() -> void:
	var kind: CoverKind = _grass()
	var cover: CoverScript = own(CoverScript.new(RoomBase.FLOOR_Z + 1)) as CoverScript
	root.add_child(cover)
	cover.lay(_layout(kind))
	cover.show_state(_cell(13, 13), BURNING)
	check_equal(cover.motes.cells_giving_off(kind.id, BURNING), 1, "a burning cell")
	cover.show_state(_cell(13, 13), 2)
	check_equal(cover.motes.cells_giving_off(kind.id, BURNING), 0, "gone to ash")
	cover.show_state(_cell(13, 13), BURNING)
	cover.lay(_layout(kind))
	check_equal(cover.motes.cells_giving_off(kind.id, BURNING), 0, "a room laid again starts at rest")


func test_a_frame_of_it_allocates_nothing() -> void:
	var kind: CoverKind = _grass(30.0)
	var motes: CoverMotesScript = _motes(kind)
	var pool: MotesScript = _pool()
	for x in 4:
		motes.show(_cell(12 + x, 14), BURNING)
	_frames(motes, pool, 10)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	_frames(motes, pool, 200, Rect2(), 2.0)
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "200 frames of a burning patch make no object")
	check(motes.given > 100, "while it gave off (%d)" % motes.given)
