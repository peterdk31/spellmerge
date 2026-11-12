extends "res://tests/support/suite.gd"
## The Pulses' rings as Feel draws them (gameplay/feel/pulse_rings.gd, props W9a): motes along each
## live ring's edge, none past a wall on its line from the centre (owner, 2026-11-12: "the ring
## should be 'individual' motes, that can be blocked individually") where its segment stopped.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_pulse_rings.gd

const RingsScript := preload("res://gameplay/feel/pulse_rings.gd")
const BirthsScript := preload("res://gameplay/feel/births.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")


## One live ring round the origin, 40 px out, as `CarrierPulse` tells it: its segments to the
## right (x above half) stopped 10 px out (a wall or a body), the rest open.
class OneRing:
	extends RefCounted

	func pulse_slots() -> int:
		return 1

	func pulse_on(_at: int) -> bool:
		return true

	func pulse_radius(_at: int) -> float:
		return 40.0

	func pulse_centre(_at: int) -> Vector2:
		return Vector2.ZERO

	func pulse_tint(_at: int) -> Color:
		return Color.ORANGE

	func pulse_look(_at: int) -> int:
		return 0

	func pulse_tag(_at: int) -> int:
		return 0

	func pulse_actor(_at: int) -> int:
		return 0

	func pulse_stop_toward(_at: int, way: Vector2) -> float:
		return 10.0 if way.x > 0.5 else INF


## The places of every birth the ring gave off in `frames` frames.
func _given_off(ring: OneRing, frames: int) -> PackedVector2Array:
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
	var at: PackedVector2Array = _given_off(OneRing.new(), 60)
	check(at.size() > 20, "motes along its edge: %d" % at.size())
	var stopped: int = 0
	var left: int = 0
	for point in at:
		if point.normalized().x > 0.5:
			stopped += 1
		if point.x < 0.0:
			left += 1
	check_equal(stopped, 0, "none on the lines its segments stopped short on")
	check(left > 0, "and the open side has its share: %d" % left)
