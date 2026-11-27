extends "res://tests/support/suite.gd"
## A door's stone bar at the art's detail (gameplay/feel/stone_bars.gd; ART3): its base, its first art
## pixel across lit and, past two across, its last shaded; nothing for an empty bar.

const BarsScript := preload("res://gameplay/feel/stone_bars.gd")


func test_an_upright_bar_is_lit_on_its_left_and_shaded_on_its_right() -> void:
	var bar := Rect2i(10, 20, 4, 9)
	var parts: Array[Array] = BarsScript.parts(bar, true)
	check_equal(parts.size(), 3, "base, light, shadow")
	check_equal(parts[0], [bar, BarsScript.BASE], "its base, all of it")
	check_equal(parts[1], [Rect2i(10, 20, 1, 9), BarsScript.LIGHT], "its left art pixel lit")
	check_equal(parts[2], [Rect2i(13, 20, 1, 9), BarsScript.SHADOW], "its right one shaded")


func test_a_lying_bar_is_lit_on_its_top_and_shaded_under() -> void:
	var bar := Rect2i(0, 0, 18, 4)
	var parts: Array[Array] = BarsScript.parts(bar, false)
	check_equal(parts[1], [Rect2i(0, 0, 18, 1), BarsScript.LIGHT], "its top lit")
	check_equal(parts[2], [Rect2i(0, 3, 18, 1), BarsScript.SHADOW], "its bottom shaded")


func test_a_thin_or_empty_bar() -> void:
	check_equal(BarsScript.parts(Rect2i(0, 0, 2, 6), true).size(), 2, "two across: base and light only")
	check(BarsScript.parts(Rect2i(0, 0, 4, 0), true).is_empty(), "an empty bar draws nothing")
