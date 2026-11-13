extends "res://tests/support/suite.gd"
## The Pulses' rings as Feel draws them (gameplay/feel/pulse_rings.gd, props W9a): motes along each
## live ring's edge, none past a wall on its line from the centre (owner, 2026-11-12: "the ring
## should be 'individual' motes, that can be blocked individually") where its segment stopped; and
## its trail (owner, 2026-11-13), tail motes over the band its edge swept since the last frame.
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


## The places of the births the ring gave off in `frames` frames: of its edge, or of its trail.
func _given_off(ring: PulseView, frames: int, trail: bool = false, rings: RingsScript = null) -> PackedVector2Array:
	if rings == null:
		rings = RingsScript.new()
	var at: PackedVector2Array = PackedVector2Array()
	for row in _births(ring, frames, rings):
		if ProjectilesScript.is_tail_code(int(row[2])) == trail:
			at.append(Vector2(row[0], row[1]))
	return at


## Every birth the ring gave off in `frames` frames, each as [x, y, kind, way x, way y].
func _births(ring: PulseView, frames: int, rings: RingsScript) -> Array[PackedFloat32Array]:
	var births := BirthsScript.new()
	var out: Array[PackedFloat32Array] = []
	for n in frames:
		births.clear()
		rings.step(ring, 1.0 / 60.0, func(_actor: int) -> int: return 0, births)
		for i in births.count:
			var row: int = i * BirthsScript.STRIDE
			out.append(PackedFloat32Array([births.rows[row + ProjectilesScript.SPARK_X], births.rows[row + ProjectilesScript.SPARK_Y],
				births.rows[row + ProjectilesScript.SPARK_KIND], births.rows[row + ProjectilesScript.SPARK_BACK_X],
				births.rows[row + ProjectilesScript.SPARK_BACK_Y]]))
	return out


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


func test_its_trail_is_laid_over_the_band_its_edge_swept() -> void:
	var ring: PulseView = _one_ring()
	var rings := RingsScript.new()
	ring.radius[0] = 20.0
	_births(ring, 1, rings)
	ring.radius[0] = 40.0
	var tails: int = 0
	for row in _births(ring, 1, rings):
		if not ProjectilesScript.is_tail_code(int(row[2])):
			continue
		tails += 1
		var at := Vector2(row[0], row[1])
		check(at.length() >= 19.99 and at.length() <= 40.01, "a trail mote in the band swept: %.2f" % at.length())
		check(at.normalized().x <= 0.6, "none on the lines its segments stopped short on")
		check(at.dot(Vector2(row[3], row[4])) < 0.0, "thrown back toward its centre")
	# By area: half the ring's segments are open past 10 px, so about half of PI * (40^2 - 20^2) / TRAIL_AREA.
	var expected: float = PI * (1600.0 - 400.0) / RingsScript.TRAIL_AREA
	check(tails > expected * 0.3 and tails < expected * 0.8, "about its share of the band: %d of %.0f" % [tails, expected])


func test_a_still_ring_lays_no_more_trail() -> void:
	var ring: PulseView = _one_ring()
	var rings := RingsScript.new()
	check(_given_off(ring, 1, true, rings).size() > 0, "its first frame lays the band from its centre")
	check_equal(_given_off(ring, 10, true, rings).size(), 0, "a ring that has not moved lays nothing more")
	check(_given_off(ring, 1, false, rings).size() > 0, "but its edge still gives off motes")


func test_its_trail_is_as_whole_at_any_frame_rate() -> void:
	var fast: int = 0
	var slow: int = 0
	for n in 20:
		var ring: PulseView = _one_ring()
		var rings := RingsScript.new()
		ring.radius[0] = 0.0
		_births(ring, 1, rings)
		ring.radius[0] = 40.0
		slow += _given_off(ring, 1, true, rings).size()
		ring = _one_ring()
		rings = RingsScript.new()
		for step in 5:
			ring.radius[0] = 8.0 * float(step)
			fast += _given_off(ring, 1, true, rings).size()
		ring.radius[0] = 40.0
		fast += _given_off(ring, 1, true, rings).size()
	check(absf(float(fast - slow)) < 0.1 * float(slow), "one frame or five, the same trail: %d and %d" % [slow, fast])


func test_a_new_ring_starts_its_trail_at_its_centre() -> void:
	var ring: PulseView = _one_ring()
	var rings := RingsScript.new()
	_births(ring, 1, rings)
	ring.id[0] = 7
	var near: int = 0
	for at in _given_off(ring, 1, true, rings):
		if at.length() < 20.0:
			near += 1
	check(near > 0, "another ring's id is a new ring, laid from its centre: %d" % near)


func test_each_ring_takes_a_tail_kind_by_its_id() -> void:
	var ring: PulseView = _one_ring()
	for row in _births(ring, 1, RingsScript.new()):
		if ProjectilesScript.is_tail_code(int(row[2])):
			check_equal(int(row[2]), ProjectilesScript.tail_code(ring.id[0]), "its id's tail kind")
