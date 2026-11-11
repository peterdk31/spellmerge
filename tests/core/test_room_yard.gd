extends "res://tests/support/suite.gd"
## Where the prop yard stands its props (props W8, `RoomBase.yard_places`): rows filled left to
## right by each prop's `PropBase.extent`, YARD_GAP apart, each row centred in the yard, its props'
## feet on one line; whole pixels; a prop that does not fit at Vector2.INF, and the ones after it.
##
## godot --headless --path . --script res://tests/core/test_room_yard.gd


## A prop whose hurt circle is `radius` round `offset` from its feet.
func _prop(radius: float, offset: Vector2 = Vector2(0.0, -8.0)) -> PropBase:
	var prop := PropBase.new()
	prop.radius = radius
	prop.offset = offset
	return prop


func _room(yard: Rect2) -> RoomBase:
	var room := RoomBase.new()
	room.prop_yard = yard
	return room


func test_a_prop_takes_its_hurt_shape_and_its_ground() -> void:
	check_equal(_prop(8.0).extent(), Rect2(-8, -16, 16, 16), "a circle round its offset")
	var crate: PropBase = _prop(8.0)
	crate.size = Vector2(20, 12)
	check_equal(crate.extent(), Rect2(-10, -14, 20, 12), "a box, its radius unused")
	crate.footprint_size = Vector2(24, 4)
	crate.footprint_offset = Vector2(0, 1)
	check_equal(crate.extent(), Rect2(-12, -14, 24, 17), "with a wider ground under it, reaching below its feet")


func test_one_row_centred_feet_on_one_line() -> void:
	var room: RoomBase = _room(Rect2(100, 50, 200, 100))
	var props: Array[PropBase] = [_prop(8.0), _prop(8.0, Vector2(0, -16)), _prop(8.0)]
	var places: PackedVector2Array = room.yard_places(props)
	# 16 + 32 + 16 + 32 + 16 = 112 across, centred in 200: from x 144.
	check_equal(places, PackedVector2Array([Vector2(152, 74), Vector2(200, 74), Vector2(248, 74)]), "centred, the tallest sets the line")


func test_rows_wrap_and_a_full_yard_leaves_the_rest_out() -> void:
	var room: RoomBase = _room(Rect2(0, 0, 100, 80))
	var props: Array[PropBase] = [_prop(10.0), _prop(10.0), _prop(10.0), _prop(10.0), _prop(10.0)]
	var places: PackedVector2Array = room.yard_places(props)
	# Two of 20 across a row (20 + 32 + 20 = 72 of 100: from x 14); a prop reaches 18 over its feet
	# and 2 under, rows 32 apart: feet at 18, then 18 + 2 + 32 + 18 = 70; a third row would end at 124.
	check_equal(places[0], Vector2(24, 18), "first row")
	check_equal(places[1], Vector2(76, 18), "beside it")
	check_equal(places[2], Vector2(24, 70), "the second row")
	check_equal(places[3], Vector2(76, 70), "beside it")
	check_equal(places[4], Vector2.INF, "no third row fits")
	for place in places:
		check(place == Vector2.INF or place == place.floor(), "whole pixels: %s" % place)


func test_no_yard_no_places() -> void:
	check(RoomBase.new().yard_places([_prop(8.0)]).is_empty(), "none without a yard")
	var narrow: RoomBase = _room(Rect2(0, 0, 10, 100))
	check_equal(narrow.yard_places([_prop(8.0)]), PackedVector2Array([Vector2.INF]), "a prop wider than the yard")
