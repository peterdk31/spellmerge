extends "res://tests/support/suite.gd"
## Tests for the shared radial menu (hud/widgets/radial_menu.gd, items I5): the ring laid out from
## places and widths with the first entry at the top, picking with the stick and its hysteresis,
## the layers (enter, back), the hint row's glyphs and verbs, and that it knows no input it was not
## given. The radial builder on it is tested in test_radial_builder.gd and test_radial_rings.gd.
##
## godot --headless --path . --script res://tests/hud/test_radial_menu.gd

const InputManagerScript := preload("res://core/input/input_manager.gd")
const ActionGlyphScript := preload("res://hud/widgets/action_glyph.gd")
const RadialMenuScript := preload("res://hud/widgets/radial_menu.gd")

const NONE: int = RadialMenuScript.NONE

var _input: InputManagerScript
var _host: Control


func before_each() -> void:
	_input = own(InputManagerScript.new()) as InputManagerScript
	_host = own(Control.new()) as Control
	root.add_child(_host)


func _menu(player: int = 0) -> RadialMenuScript:
	var menu := RadialMenuScript.new(_host)
	menu.bind(_input, player)
	menu.center = Vector2(200.0, 100.0)
	return menu


## Four entries (10 to 13) with a gap of half a card before the last two.
func _four(menu: RadialMenuScript) -> void:
	menu.lay_out(PackedInt32Array([10, 11, NONE, 12, 13]), PackedFloat32Array([1.0, 1.0, 0.5, 1.0, 1.0]))


func test_the_first_entry_sits_at_the_top_and_the_widths_share_the_ring() -> void:
	var menu: RadialMenuScript = _menu()
	_four(menu)
	var angles: PackedFloat32Array = menu.place_angles()
	var widths: PackedFloat32Array = menu.place_widths()
	check(absf(angle_difference(angles[0], 0.0)) < 0.0001, "the first entry's middle is up")
	var total: float = 0.0
	for width in widths:
		total += width
	check(absf(total - TAU) < 0.0001, "the places fill the ring")
	check(is_equal_approx(widths[2], widths[0] * 0.5), "the gap is half a card wide")
	check(is_equal_approx(menu.place_room(), widths[0] * RadialMenuScript.RING_RADIUS), "a card's room on the ring, in pixels")
	check(menu.direction_to(10).is_equal_approx(Vector2.UP), "pointing up lands on the first entry")
	check_equal(menu.direction_to(99), Vector2.ZERO, "an entry not on the ring has no direction")
	check(menu.tile_center(PI * 0.5, 10.0).is_equal_approx(Vector2(210.0, 100.0)), "a quarter turn is to the right of the middle")


func test_a_gap_first_still_puts_the_first_entry_at_the_top() -> void:
	# The builder's ring with more than one kind starts with a gap.
	var menu: RadialMenuScript = _menu()
	menu.lay_out(PackedInt32Array([NONE, 10, 11]), PackedFloat32Array([0.6, 1.0, 1.0]))
	check(absf(angle_difference(menu.angle_of_entry(10), 0.0)) < 0.0001, "the first entry is up, not the gap")
	check(menu.direction_to(10).is_equal_approx(Vector2.UP), "pointing up lands on it")
	check(menu.angle_of_entry(11) > 0.0 and menu.angle_of_entry(11) < PI, "the next one clockwise")


func test_no_width_is_an_empty_ring() -> void:
	var menu: RadialMenuScript = _menu()
	_four(menu)
	menu.lay_out(PackedInt32Array(), PackedFloat32Array())
	check(menu.is_empty(), "nothing laid out")
	check_equal(menu.pick_on_ring(Vector2.UP), NONE, "nothing to pick")
	check_equal(menu.place_room(), 0.0, "no room")


func test_every_entry_is_picked_in_its_direction_and_a_gap_picks_nothing() -> void:
	var menu: RadialMenuScript = _menu()
	_four(menu)
	for entry in [10, 11, 12, 13]:
		check_equal(menu.pick_on_ring(menu.direction_to(entry)), entry, "entry %d" % entry)
	var gap: float = menu.place_angles()[2]
	check_equal(menu.pick_on_ring(RadialMenuScript.direction_of(gap)), NONE, "the gap")
	check_equal(menu.pick_on_ring(Vector2.ZERO), NONE, "no aim")
	for angle in [0.0, 1.0, 3.0, 5.5]:
		check(absf(angle_difference(RadialMenuScript.angle_of(RadialMenuScript.direction_of(angle)), angle)) < 0.0001, "angle %s round trip" % angle)


func test_the_pointed_entry_holds_a_little_past_its_border() -> void:
	var menu: RadialMenuScript = _menu()
	menu.lay_out(PackedInt32Array([0, 1, 2, 3]), PackedFloat32Array([1.0, 1.0, 1.0, 1.0]))
	var border: float = PI * 0.25
	var past: Vector2 = RadialMenuScript.direction_of(border + 0.03)
	check_equal(menu.pick_on_ring(past), 1, "nothing pointed: past the border is the neighbour")
	check(menu.point_at(0, 1.0), "pointing at the first changes what is pointed")
	check(not menu.point_at(0, 2.0), "pointing at it again does not")
	check(is_equal_approx(menu.pointed_for(1.5), 0.5), "pointed since the first time")
	check_equal(menu.pick_on_ring(past), 0, "pointed: it holds past its border")
	var far: Vector2 = RadialMenuScript.direction_of(border + RadialMenuScript.STICKY_ANGLE + 0.02)
	check_equal(menu.pick_on_ring(far), 1, "far enough past, the neighbour")
	check_equal(menu.pick_on_ring(menu.direction_to(1)), 1, "a neighbour's middle always picks the neighbour")


func test_on_a_crowded_ring_the_hold_is_at_most_a_share_of_the_entry() -> void:
	# 100 entries: each is narrower than STICKY_ANGLE / STICKY_SHARE, so the share caps the hold.
	var entries := PackedInt32Array()
	var widths := PackedFloat32Array()
	for at in 100:
		entries.append(at)
		widths.append(1.0)
	var menu: RadialMenuScript = _menu()
	menu.lay_out(entries, widths)
	var width: float = menu.place_widths()[0]
	check(width * RadialMenuScript.STICKY_SHARE < RadialMenuScript.STICKY_ANGLE, "the share is the smaller")
	menu.point_at(0, 0.0)
	var border: float = width * 0.5
	check_equal(menu.pick_on_ring(RadialMenuScript.direction_of(border + width * RadialMenuScript.STICKY_SHARE * 0.5)), 0, "within the share it holds")
	check_equal(menu.pick_on_ring(RadialMenuScript.direction_of(border + width * RadialMenuScript.STICKY_SHARE * 1.5)), 1, "past the share, the neighbour, well short of STICKY_ANGLE")


func test_layers_go_in_and_back_out_to_the_entry_entered() -> void:
	var menu: RadialMenuScript = _menu()
	check_equal(menu.depth(), 0, "the first ring")
	check(not menu.back(), "nothing to go back to")
	menu.point_at(2, 0.0)
	menu.enter(2)
	check_equal(menu.depth(), 1, "one layer in")
	check_equal(menu.entered(), 2, "the entry entered")
	check_equal(menu.pointed, NONE, "pointing starts afresh")
	menu.enter(5)
	check_equal(menu.entered(), 5, "two layers in")
	check(menu.back(), "back one")
	check_equal(menu.pointed, 5, "pointing at the entry it came from")
	check_equal(menu.entered(), 2, "in the first layer again")
	menu.leave_layers()
	check_equal(menu.depth(), 0, "left every layer")
	check_equal(menu.pointed, NONE, "pointing at nothing")


func test_the_hint_row_lays_out_its_glyphs_and_dims_a_button_that_does_nothing() -> void:
	var menu := RadialMenuScript.new(_host)
	var actions: Array[StringName] = [&"staff_2", &"back"]
	menu.make_hints(actions)
	menu.bind(_input, 0)
	menu.hints_at = Vector2(50.0, 80.0)
	var verbs: Array[String] = ["Put in", "Close"]
	var live: Array[bool] = [false, true]
	menu.set_hints(verbs, live)
	var first := _host.get_node("Hint_staff_2") as ActionGlyphScript
	var second := _host.get_node("Hint_back") as ActionGlyphScript
	check(first != null and second != null, "one glyph a button, the host's children")
	check_equal(first.action(), &"staff_2", "the first glyph shows its button")
	check_equal(first.position, Vector2(50.0, 80.0), "the row starts at its place")
	check(second.position.x > first.position.x + first.custom_minimum_size.x + menu.text_width("Put in"), "the second glyph after the first verb")
	check(is_equal_approx(first.modulate.a, RadialMenuScript.DIM_ALPHA), "a button that does nothing now is dimmed")
	check(is_equal_approx(second.modulate.a, 1.0), "a live one is not")
	check_equal(menu.hint_verbs(), verbs, "the verbs as shown")
	var row: Rect2 = menu.hints_rect()
	check_equal(row.position, Vector2(50.0, 80.0), "the row's place")
	check(is_equal_approx(row.end.x, second.position.x + second.custom_minimum_size.x + RadialMenuScript.GLYPH_GAP + menu.text_width("Close")), "it ends with the last verb")


func test_it_points_with_its_own_players_stick_only() -> void:
	_input.add_virtual_device(1)
	var menu: RadialMenuScript = _menu(1)
	check_equal(menu.aim(), Vector2.ZERO, "no push, no aim")
	_input.send_virtual_aim(1, Vector2.RIGHT)
	check(menu.aim().is_equal_approx(Vector2.RIGHT), "its player's stick")
	check(menu.follow(menu.aim()), "the pointer line moves")
	check(not menu.follow(Vector2.RIGHT), "and not again for the same aim")
	var other: RadialMenuScript = _menu(0)
	check(not other.uses_mouse(), "player 1 has no device here, so no mouse either")
	check_equal(other.aim(), Vector2.ZERO, "another player's menu does not hear it")
	check(not menu.uses_mouse(), "a pad player has no mouse")
	var unbound := RadialMenuScript.new(_host)
	check_equal(unbound.aim(), Vector2.ZERO, "no input, no aim")
	check_equal(unbound.stick_tilt(), Vector2.ZERO, "and no tilt")
