extends "res://tests/support/suite.gd"
## Where each seat's HUD sits (hud/panels/seat_corners.gd; the owner, 2026-11-20): unsplit every
## corner panel on its own corner as the scene lays it; a spot changed by `hud_corners_changed` (the
## equal split's panes, gameplay/feel/equal_panes.gd) slides the panel there by whole pixels over at
## least three frames, never jumping, and moves the seat's builder, inventory and reward menu with
## its quarter; P3's panel to the bottom right with P1 and P3 on the halves, and back.

const EventsScript := preload("res://core/events/events.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const SeatCornersScript := preload("res://hud/panels/seat_corners.gd")
const HudScript := preload("res://hud/panels/panels.gd")
## Loaded when needed (the scene is the "Hud" autoload, test_panels.gd says why).
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
const NO_SAVE: String = "user://test_no_save.cfg"

const VIEW := Vector2(640.0, 360.0)
const SIZE := Vector2(96.0, 34.0)


func _make_hud(joined: Array[int]) -> Array:
	var bus := own(EventsScript.new()) as EventsScript
	var focus := own(UIFocusScript.new()) as UIFocusScript
	var hud := (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	hud.events = bus
	hud.save = SaveFile.new(NO_SAVE)
	hud.ui_focus = focus
	root.add_child(own(hud))
	for player in joined:
		bus.player_joined.emit(player)
	bus.room_entered.emit(&"arena_01", 0)
	return [hud, bus]


func test_unsplit_every_panel_is_on_its_own_corner_as_the_scene_lays_it() -> void:
	var corners := SeatCornersScript.new()
	var expected: Array[Vector2] = [Vector2(4.0, 4.0), Vector2(540.0, 4.0), Vector2(4.0, 322.0), Vector2(540.0, 322.0)]
	for seat in 4:
		corners.step(seat, VIEW, SIZE)
		check_equal(corners.panel_at(seat), expected[seat], "seat %d's panel on its corner" % seat)
		check_equal(corners.quarter_at(seat), SeatCornersScript.quarter_origin(seat, VIEW), "seat %d's quarter its own" % seat)
	# A spot's inner side: toward the screen's middle line.
	check_equal(SeatCornersScript.panel_spot(1, VIEW, SIZE), Vector2(220.0, 4.0), "the top left quarter's inner side")
	check_equal(SeatCornersScript.panel_spot(7, VIEW, SIZE), Vector2(324.0, 322.0), "the bottom right quarter's inner side")


func test_a_changed_spot_slides_by_whole_pixels_over_at_least_three_frames() -> void:
	var corners := SeatCornersScript.new()
	corners.step(2, VIEW, SIZE)
	var from: Vector2 = corners.panel_at(2)
	corners.set_spots(PackedInt32Array([0, 2, 6, 6]))
	var target: Vector2 = SeatCornersScript.panel_spot(6, VIEW, SIZE)
	var frames: int = 0
	var last: Vector2 = from
	while corners.panel_at(2) != target and frames < 200:
		corners.step(2, VIEW, SIZE)
		frames += 1
		var at: Vector2 = corners.panel_at(2)
		check_equal(at, at.round(), "whole pixels (%s)" % at)
		check(at.distance_to(last) <= SeatCornersScript.SLIDE_MOST + 0.01, "never more than %d px a frame (%.1f)" % [SeatCornersScript.SLIDE_MOST, at.distance_to(last)])
		check(at.distance_to(target) < last.distance_to(target), "always nearer")
		last = at
	check_equal(corners.panel_at(2), target, "P3's panel reached the bottom right")
	check(frames >= 3, "over at least three frames (%d)" % frames)
	check_equal(corners.quarter_at(2), SeatCornersScript.quarter_origin(3, VIEW), "its quarter is the bottom right's")
	check(not corners.is_sliding(2), "and settled")
	# Settled, it follows its spot at once (a panel growing a row).
	corners.step(2, VIEW, SIZE + Vector2(0.0, 15.0))
	check_equal(corners.panel_at(2), SeatCornersScript.panel_spot(6, VIEW, SIZE + Vector2(0.0, 15.0)), "settled, a taller panel stays on its spot")
	# A short slide still takes three frames.
	check_equal(SeatCornersScript.slide(Vector2.ZERO, Vector2(3.0, 0.0)), Vector2(1.0, 0.0), "three pixels: one a frame")


func test_the_hud_moves_p3s_panel_and_menus_into_the_right_half_and_back() -> void:
	var made: Array = _make_hud([0, 2])
	var hud: HudScript = made[0]
	var bus: EventsScript = made[1]
	var view: Vector2 = (hud.get_node("Root") as Control).size
	var panel: Control = hud.get_panel(2)
	hud.step_corners()
	var home: Vector2 = panel.position
	check_equal(home.x, 4.0, "P3's panel starts on the left")
	bus.hud_corners_changed.emit(PackedInt32Array([0, 2, 6, 6]))
	var frames: int = 0
	var last: Vector2 = home
	while hud.get_corners().is_sliding(2) and frames < 200:
		hud.step_corners()
		frames += 1
		check(panel.position.distance_to(last) <= SeatCornersScript.SLIDE_MOST + 0.01, "the panel never jumps")
		last = panel.position
	check(frames >= 3, "it slid over at least three frames (%d)" % frames)
	check_equal(panel.position.x, view.x - 4.0 - panel.size.x, "P3's panel at the right edge")
	check_equal(panel.position.y, home.y, "on its own row")
	check_equal(hud.get_panel(0).position, Vector2(4.0, 4.0), "P1's panel where it was")
	var quarter: Vector2 = SeatCornersScript.quarter_origin(3, view)
	check_equal(hud.get_radial(2).quarter_at, quarter, "P3's builder lays out in the bottom right quarter")
	check_equal(hud.get_inventory(2).quarter_at, quarter, "and its inventory")
	var room: Rect2 = hud.reward_room(2)
	check(room.position.x >= quarter.x and room.end.x <= view.x + 0.5 and room.position.y >= quarter.y, "and its reward menu (%s)" % room)
	# Back to one picture: its own corner again.
	bus.hud_corners_changed.emit(PackedInt32Array([0, 2, 4, 6]))
	for i in 200:
		hud.step_corners()
	check_equal(panel.position, home, "back on its own corner")
	check_equal(hud.get_radial(2).quarter_at, SeatCornersScript.quarter_origin(2, view), "its builder too")


## Regression (review): the reward menu's room jumped back by the panels' band (32 px) as its quarter
## slid from the bottom row to the top.
func test_the_reward_room_slides_with_its_quarter_never_jumping() -> void:
	var made: Array = _make_hud([0, 1, 2])
	var hud: HudScript = made[0]
	var bus: EventsScript = made[1]
	hud.step_corners()
	var last: Rect2 = hud.reward_room(2)
	bus.hud_corners_changed.emit(PackedInt32Array([0, 2, 1, 6]))
	for i in 60:
		hud.step_corners()
		var room: Rect2 = hud.reward_room(2)
		check(room.position.distance_to(last.position) <= SeatCornersScript.SLIDE_MOST + 0.01, "the room moves no more than a slide's step (%s to %s)" % [last.position, room.position])
		check(room.position.y <= last.position.y + 0.01, "always up, never back")
		last = room
	check_equal(last.position.y, 32.0, "it ends under the top band")


## Regression: a slanted slide rounded to whole pixels came out longer than SLIDE_MOST (16.1 px), a
## menus' quarter moving from the top right to the bottom left (the owner, 2026-11-20).
func test_a_slanted_slide_never_steps_past_the_most() -> void:
	var at := Vector2(320.0, 0.0)
	var to := Vector2(0.0, 180.0)
	for i in 100:
		var next: Vector2 = SeatCornersScript.slide(at, to)
		check(next.distance_to(at) <= SeatCornersScript.SLIDE_MOST, "at most %d px a frame (%s to %s)" % [SeatCornersScript.SLIDE_MOST, at, next])
		at = next
	check_equal(at, to, "it arrives")


## The menus' quarter told apart from the spot: the panel stays, the quarter slides.
func test_the_menus_quarter_is_its_own() -> void:
	var corners := SeatCornersScript.new()
	corners.step(1, VIEW, SIZE)
	corners.set_spots(PackedInt32Array([0, 1, 7, 6]), PackedInt32Array([0, 2, 1, 3]))
	for i in 60:
		corners.step(1, VIEW, SIZE)
	check_equal(corners.panel_at(1), SeatCornersScript.panel_spot(1, VIEW, SIZE), "P2's panel at the top left quarter's inner side")
	check_equal(corners.quarter_at(1), SeatCornersScript.quarter_origin(2, VIEW), "P2's menus in the bottom left quarter")
	corners.set_spots(PackedInt32Array([0, 1, 7, 6]))
	for i in 60:
		corners.step(1, VIEW, SIZE)
	check_equal(corners.quarter_at(1), SeatCornersScript.quarter_origin(0, VIEW), "no menus told: its spot's quarter")
