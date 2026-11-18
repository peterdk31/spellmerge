extends "res://tests/support/suite.gd"
## Tests for the row of tabs (hud/widgets/menu_tabs.gd): the tabs left to right without overlap
## between the paging glyphs, the box on the selected tab, a switch sliding it there over at least
## 3 frames by whole pixels and easing in, the names stepping through their three shades, a switch
## during a slide starting from where the box is, `snap` putting it in place at once, and the glyphs
## following the player's device.

const InputManagerScript := preload("res://core/input/input_manager.gd")
const MenuTabsScript := preload("res://hud/widgets/menu_tabs.gd")

const NAMES: Array[String] = ["Graphics", "Performance", "Audio", "Interface"]
const FRAME: float = 1.0 / 60.0

var _input: InputManagerScript


func before_each() -> void:
	_input = own(InputManagerScript.new()) as InputManagerScript


## A row of NAMES for player 0, laid out at its least width.
func _tabs() -> MenuTabsScript:
	var tabs: MenuTabsScript = own(MenuTabsScript.new()) as MenuTabsScript
	tabs.bind(_input)
	root.add_child(tabs)
	tabs.set_tabs(NAMES)
	tabs.show_for(0)
	tabs.size = tabs.custom_minimum_size
	return tabs


## The box's left edge each frame until the slide ends, the first as it starts.
func _slide(tabs: MenuTabsScript) -> Array[float]:
	var lefts: Array[float] = [tabs.box().position.x]
	for _frame in 30:
		if not tabs.is_sliding():
			break
		tabs.step(FRAME)
		lefts.append(tabs.box().position.x)
	return lefts


func test_the_tabs_sit_left_to_right_between_the_glyphs() -> void:
	var tabs: MenuTabsScript = _tabs()
	for at in range(1, NAMES.size()):
		check(tabs.tab_rect(at).position.x >= tabs.tab_rect(at - 1).end.x, "%s right of %s" % [NAMES[at], NAMES[at - 1]])
	check(tabs.prev_glyph().position.x + tabs.prev_glyph().size.x <= tabs.tab_rect(0).position.x, "the left glyph before the first tab")
	check(tabs.next_glyph().position.x >= tabs.tab_rect(NAMES.size() - 1).end.x, "the right glyph after the last")
	check(tabs.next_glyph().position.x + tabs.next_glyph().size.x <= tabs.size.x, "inside the row")


func test_the_first_tab_is_selected_with_the_box_on_it() -> void:
	var tabs: MenuTabsScript = _tabs()
	check(tabs.selected() == 0 and tabs.box() == tabs.tab_rect(0), "the box on the first tab")
	check(not tabs.is_sliding() and tabs.shade_of(0) == 2 and tabs.shade_of(1) == 0, "bright on it, dim on the others")


func test_a_switch_slides_the_box_over_at_least_three_frames_by_whole_pixels() -> void:
	var tabs: MenuTabsScript = _tabs()
	tabs.select(1)
	var lefts: Array[float] = _slide(tabs)
	check(lefts.size() >= 5, "at least 3 frames between the two tabs: %s" % [lefts])
	for at in range(1, lefts.size()):
		check(lefts[at] >= lefts[at - 1], "only forward: %s" % [lefts])
		check_equal(lefts[at], roundf(lefts[at]), "a whole pixel")
	check(tabs.box() == tabs.tab_rect(1), "it ends on the tab")


func test_the_slide_is_short() -> void:
	var tabs: MenuTabsScript = _tabs()
	tabs.select(3)
	check(_slide(tabs).size() - 1 <= 8, "it is over within 8 frames")


func test_the_slide_eases_in() -> void:
	var tabs: MenuTabsScript = _tabs()
	tabs.select(3)
	var lefts: Array[float] = _slide(tabs)
	check(lefts[1] - lefts[0] > lefts[-1] - lefts[-2], "the first step longer than the last: %s" % [lefts])


func test_the_names_step_through_three_shades() -> void:
	var tabs: MenuTabsScript = _tabs()
	tabs.select(1)
	var reached: Array[int] = [tabs.shade_of(1)]
	var left: Array[int] = [tabs.shade_of(0)]
	while tabs.is_sliding():
		tabs.step(FRAME)
		if tabs.shade_of(1) != reached.back():
			reached.append(tabs.shade_of(1))
		if tabs.shade_of(0) != left.back():
			left.append(tabs.shade_of(0))
	check_equal(reached, [0, 1, 2] as Array[int], "the tab reached: dim, plain, bright")
	check_equal(left, [2, 1, 0] as Array[int], "the tab left: bright, plain, dim")


func test_a_switch_during_a_slide_starts_from_where_the_box_is() -> void:
	var tabs: MenuTabsScript = _tabs()
	tabs.select(2)
	tabs.step(FRAME)
	tabs.step(FRAME)
	var there: Rect2 = tabs.box()
	tabs.select(3)
	check(tabs.box() == there, "no jump: it goes on from %s" % [there])
	_slide(tabs)
	check(tabs.box() == tabs.tab_rect(3), "and ends on the new tab")


func test_snap_puts_the_box_in_place_at_once() -> void:
	var tabs: MenuTabsScript = _tabs()
	tabs.select(2)
	tabs.snap()
	check(not tabs.is_sliding() and tabs.box() == tabs.tab_rect(2) and tabs.remaining() == 0.0, "in place")


func test_remaining_runs_from_one_to_none_and_is_sent() -> void:
	var tabs: MenuTabsScript = _tabs()
	var heard: Array[float] = []
	tabs.slide_stepped.connect(func(left: float) -> void: heard.append(left))
	tabs.select(1)
	check_equal(tabs.remaining(), 1.0, "all of it left as it starts")
	_slide(tabs)
	check(not heard.is_empty() and heard.back() == 0.0, "the last step sends none left: %s" % [heard])


func test_the_glyphs_page_on_a_pad_and_on_the_keyboard() -> void:
	_input.add_virtual_device(0)
	var tabs: MenuTabsScript = _tabs()
	check(tabs.prev_glyph().current_glyph()["label"] == "LB" and tabs.next_glyph().current_glyph()["label"] == "RB", "LB and RB on a pad")
	_input.leave(0)
	_input.join(InputManagerScript.KEYBOARD)
	check(tabs.prev_glyph().current_glyph()["label"] == "Z" and tabs.next_glyph().current_glyph()["label"] == "C", "Z and C on the keyboard")


func test_the_rows_width_holds_whatever_the_glyphs() -> void:
	_input.add_virtual_device(0)
	var tabs: MenuTabsScript = _tabs()
	var wide: float = tabs.custom_minimum_size.x
	_input.leave(0)
	_input.join(InputManagerScript.KEYBOARD)
	check_equal(tabs.custom_minimum_size.x, wide, "the same least width with the keys")
