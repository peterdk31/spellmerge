extends "res://tests/support/suite.gd"
## Rim motes (gameplay/feel/rim_motes.gd, core/base/mote_rim.gd; online-lobby L1): a hidden `Line2D`
## in the group `mote_rim` with a `MoteRim` gives off its kind's motes along it at its rate, thrown
## outward (the left of the way its points run), each in one of its ramps; nothing with no rim, a
## broken rim or the particles off; the room's own rims only, read once when the room is entered.

const MotesScript := preload("res://gameplay/feel/mote.gd")
const RimMotesScript := preload("res://gameplay/feel/rim_motes.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")

const FIRE: PackedColorArray = [Color("f4f1ea"), Color("ffa23c"), Color("e0592f"), Color("8f2d2a")]
const ICE: PackedColorArray = [Color("f4f1ea"), Color("c4f6f2"), Color("4fd6dc"), Color("1f7080")]

var table: RampTableScript


func before_each() -> void:
	table = RampTableScript.new()


func _pool() -> MotesScript:
	var kind := MoteKind.new()
	kind.id = &"rim_test"
	kind.gravity = -6.0
	kind.drag = 2.0
	kind.count = 1
	kind.height = 0.0
	var motes: MotesScript = own(MotesScript.new(4096, 0, [kind] as Array[MoteKind])) as MotesScript
	root.add_child(motes)
	return motes


func _look(rate: float = 10.0) -> MoteRim:
	var look := MoteRim.new()
	look.kind = &"rim_test"
	look.rate = rate
	look.ramps = [FIRE, ICE]
	return look


## A square rim, 100 px a side, clockwise on screen, in the tree.
func _square(look: MoteRim, group: bool = true) -> Line2D:
	var line := own(Line2D.new()) as Line2D
	line.points = PackedVector2Array([Vector2(100, 100), Vector2(200, 100), Vector2(200, 200), Vector2(100, 200)])
	line.closed = true
	line.visible = false
	if group:
		line.add_to_group(MoteRim.GROUP)
	line.set_meta(MoteRim.META, look)
	root.add_child(line)
	return line


## Give off for `seconds`, a frame at a time.
func _run(rims: RimMotesScript, motes: MotesScript, seconds: float) -> void:
	var now: float = 0.0
	rims.give_off(now, motes, table)
	while now < seconds:
		now += 1.0 / 60.0
		rims.give_off(now, motes, table)
		motes.step(now)


func test_a_rim_gives_off_its_rate_along_it_thrown_outward() -> void:
	_square(_look(10.0))
	var rims := RimMotesScript.new()
	rims.take(self)
	check_equal(rims.rim_count(), 1, "the rim is read")
	var motes := _pool()
	var before: int = motes.next_row()
	_run(rims, motes, 2.0)
	var born: int = motes.next_row() - before
	# 400 px at 10 a second for every 100 px: 40 a second.
	check(born >= 76 and born <= 84, "about 80 motes in 2 s (%d)" % born)
	var fire: int = table.source(FIRE)
	var ice: int = table.source(ICE)
	var seen_fire: bool = false
	var seen_ice: bool = false
	var outward: int = 0
	for row in range(before, before + born):
		var data: PackedFloat32Array = motes.row_data(row)
		var at := Vector2(data[MotesScript.ROW_X], data[MotesScript.ROW_Y])
		var v := Vector2(data[MotesScript.ROW_VX], data[MotesScript.ROW_VY])
		check(absf(at.x - 100.0) <= 2.0 or absf(at.x - 200.0) <= 2.0 or absf(at.y - 100.0) <= 2.0 or absf(at.y - 200.0) <= 2.0, "mote %d is born on the rim: %s" % [row, at])
		# Out of the square: away from its middle.
		if v.dot(at - Vector2(150, 150)) > 0.0:
			outward += 1
		var source: int = roundi(data[MotesScript.ROW_SOURCE] * MotesScript.SOURCE_CODE)
		seen_fire = seen_fire or source == fire
		seen_ice = seen_ice or source == ice
	check(outward >= born * 9 / 10, "nearly all fly outward (%d of %d)" % [outward, born])
	check(seen_fire and seen_ice, "each in one of the rim's ramps, both used")


func test_nothing_without_a_sound_rim_or_with_the_particles_off() -> void:
	var motes := _pool()
	var rims := RimMotesScript.new()
	_square(_look(), false)
	rims.take(self)
	check_equal(rims.rim_count(), 0, "a line out of the group is no rim")
	var broken := _look()
	broken.ramps = []
	_square(broken)
	rims.take(self)
	check_equal(rims.rim_count(), 0, "a rim with no colours is left out")
	var unknown := _look()
	unknown.kind = &"no_such_kind"
	_square(unknown)
	rims.take(self)
	var before: int = motes.next_row()
	_run(rims, motes, 1.0)
	check_equal(motes.next_row(), before, "a kind the pool lacks throws nothing")
	_square(_look())
	rims.take(self)
	rims.give_off(0.0, null, table)
	rims.give_off(0.5, null, table)
	check_equal(motes.next_row(), before, "the particles off: nothing")
	rims.take(null)
	check_equal(rims.rim_count(), 0, "out of a tree: no rims")


func test_a_rim_is_read_once_and_holds_no_node() -> void:
	var line := _square(_look())
	var rims := RimMotesScript.new()
	rims.take(self)
	root.remove_child(line)
	line.free()
	var motes := _pool()
	var before: int = motes.next_row()
	_run(rims, motes, 0.5)
	check(motes.next_row() > before, "it gives off from what it read, the node gone")


func test_the_problems_of_a_rim() -> void:
	check(_look().problems().is_empty(), "a sound rim")
	var none := MoteRim.new()
	check(not none.problems().is_empty(), "no colours is a problem")
	var short := _look()
	short.ramps = [PackedColorArray([Color.WHITE, Color.BLACK])]
	check(not short.problems().is_empty(), "a ramp of two colours is a problem")
