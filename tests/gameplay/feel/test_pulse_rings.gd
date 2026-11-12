extends "res://tests/support/suite.gd"
## The Pulses' rings as Feel draws them (gameplay/feel/pulse_rings.gd, props W9a): motes along each
## live ring's edge, none past a wall on its line from the centre (owner, 2026-11-12: "the ring
## should be 'individual' motes, that can be blocked individually") where its segment stopped.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_pulse_rings.gd

const RingsScript := preload("res://gameplay/feel/pulse_rings.gd")
const BirthsScript := preload("res://gameplay/feel/births.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")


## A view of one live ring round the origin, 40 px out, as `CarrierPulse.read_view` fills it: its
## segments to the right (x above half) stopped 10 px out (a wall or a body), the rest open.
func _one_ring() -> PulseView:
	var view := PulseView.new()
	view.hold(1)
	view.rings = 1
	view.centre[0] = Vector2.ZERO
	view.radius[0] = 40.0
	view.core[0] = Color.ORANGE
	for k in PulseView.SEGMENTS:
		var way: Vector2 = Vector2.RIGHT.rotated(TAU * float(k) / float(PulseView.SEGMENTS))
		view.stop[k] = 10.0 if way.x > 0.5 else INF
	return view


## The places of every birth the ring gave off in `frames` frames.
func _given_off(ring: PulseView, frames: int) -> PackedVector2Array:
	var rings := RingsScript.new()
	var births := BirthsScript.new()
	var at: PackedVector2Array = PackedVector2Array()
	for n in frames:
		births.clear()
		rings.step(ring, 1.0 / 60.0, func(_actor: int) -> int: return 0, births)
		for i in births.count:
			var row: int = i * BirthsScript.STRIDE
			at.append(Vector2(births.rows[row + ProjectilesScript.SPARK_X], births.rows[row + ProjectilesScript.SPARK_Y]))
	return at


func test_no_mote_is_given_off_where_its_segment_stopped() -> void:
	var ring: PulseView = _one_ring()
	var at: PackedVector2Array = _given_off(ring, 60)
	check(at.size() > 20, "motes along its edge: %d" % at.size())
	var stopped: int = 0
	var left: int = 0
	for point in at:
		if ring.stop_toward(0, point.normalized()) < 40.0 or point.normalized().x > 0.6:
			stopped += 1
		if point.x < 0.0:
			left += 1
	check_equal(stopped, 0, "none on the lines its segments stopped short on")
	check(left > 0, "and the open side has its share: %d" % left)
