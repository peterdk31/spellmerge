extends "res://tests/support/suite.gd"
## A door's stone bar at the art's detail (gameplay/feel/stone_bars.gd; ART3): its base, its first art
## pixel across lit and, past two across, its last shaded; nothing for an empty bar.

const BarsScript := preload("res://gameplay/feel/stone_bars.gd")


func test_an_upright_bar_is_lit_on_its_left_and_shaded_on_its_right() -> void:
	var bar := Rect2i(10, 20, 4, 9)
	check_equal(BarsScript.count(bar, true), 3, "base, light, shadow")
	check_equal(BarsScript.part(bar, true, 0), bar, "its base, all of it")
	check_equal(BarsScript.shade_of(0), BarsScript.BASE, "in the base shade")
	check_equal(BarsScript.part(bar, true, 1), Rect2i(10, 20, 1, 9), "its left art pixel")
	check_equal(BarsScript.shade_of(1), BarsScript.LIGHT, "lit")
	check_equal(BarsScript.part(bar, true, 2), Rect2i(13, 20, 1, 9), "its right one")
	check_equal(BarsScript.shade_of(2), BarsScript.SHADOW, "shaded")


func test_a_lying_bar_is_lit_on_its_top_and_shaded_under() -> void:
	var bar := Rect2i(0, 0, 18, 4)
	check_equal(BarsScript.part(bar, false, 1), Rect2i(0, 0, 18, 1), "its top lit")
	check_equal(BarsScript.part(bar, false, 2), Rect2i(0, 3, 18, 1), "its bottom shaded")


func test_a_thin_or_empty_bar() -> void:
	check_equal(BarsScript.count(Rect2i(0, 0, 2, 6), true), 2, "two across: base and light only")
	check_equal(BarsScript.count(Rect2i(0, 0, 6, 2), false), 2, "lying, two across too")
	check_equal(BarsScript.count(Rect2i(0, 0, 4, 0), true), 0, "an empty bar draws nothing")
