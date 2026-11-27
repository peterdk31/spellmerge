extends "res://tests/support/suite.gd"
## The HUD's frames, tiles and lines at the art's detail (ART4; `hud/widgets/hud_art.gd`): each
## part drawn into a recorder that paints an image an art pixel a pixel, so every rule of
## docs/STYLE.md the part keeps is read off its pixels: the Outline cut at the corners and closed
## diagonally, the lit top and left edge and the shaded bottom and right, palette colours only, and
## every rect on whole art pixels.
const HudArt := preload("res://hud/widgets/hud_art.gd")
const PlayerPanelScript := preload("res://hud/panels/player_panel/player_panel.gd")

const CLEAR: Color = Color(0.0, 0.0, 0.0, 0.0)


## Paints what a part draws into an image of art pixels (two a layout pixel), and notes a rect
## that is not on whole art pixels.
class Recorder extends RefCounted:
	var image: Image = null
	var off_grid: int = 0

	func _init(layout_size: Vector2i) -> void:
		image = Image.create(layout_size.x * 2, layout_size.y * 2, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.0, 0.0, 0.0, 0.0))

	func draw_rect(rect: Rect2, color: Color) -> void:
		var art := Rect2(rect.position * 2.0, rect.size * 2.0)
		if not art.position.is_equal_approx(art.position.round()) or not art.size.is_equal_approx(art.size.round()):
			off_grid += 1
		image.fill_rect(Rect2i(Vector2i(art.position.round()), Vector2i(art.size.round())), color)

	func at(x: int, y: int) -> Color:
		return image.get_pixel(x, y)


func _same(a: Color, b: Color) -> bool:
	return a.to_rgba32() == b.to_rgba32()


func _palette() -> Array[Color]:
	var out: Array[Color] = [HudArt.OUTLINE]
	for ramp: PackedColorArray in [HudArt.STONE, HudArt.SPARK, HudArt.FIRE, HudArt.MANA] + HudArt.PLAYERS:
		for color in ramp:
			out.append(color)
	return out


## The colours the image holds that are neither clear nor in `allowed`.
func _strays(image: Image, allowed: Array[Color]) -> int:
	var strays: int = 0
	for y in image.get_height():
		for x in image.get_width():
			var color: Color = image.get_pixel(x, y)
			if color.a == 0.0:
				continue
			if not allowed.any(func(c: Color) -> bool: return _same(c, color)):
				strays += 1
	return strays


## A thin frame (the owner, 2026-11-27: "The border is too much"): one art pixel of the ramp.
func test_a_frame_is_one_art_pixel_cut_at_its_corners_and_lit_top_left() -> void:
	var pen := Recorder.new(Vector2i(10, 8))
	var ramp: PackedColorArray = HudArt.player_ramp(0)
	HudArt.frame(pen, Rect2(0.0, 0.0, 10.0, 8.0), ramp)
	var w: int = 20
	var h: int = 16
	check_equal(pen.off_grid, 0, "every rect of the frame on whole art pixels")
	# The outer corners are cut, and the art pixel inside each closes the line.
	for corner: Vector2i in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
		check(_same(pen.at(corner.x, corner.y), CLEAR), "corner %s cut" % corner)
	check(_same(pen.at(1, 1), ramp[HudArt.LIGHT]), "the top-left corner closed in the light")
	for corner: Vector2i in [Vector2i(w - 2, 1), Vector2i(1, h - 2), Vector2i(w - 2, h - 2)]:
		check(_same(pen.at(corner.x, corner.y), ramp[HudArt.BASE]), "corner %s closed in the base" % corner)
	check(_same(pen.at(w / 2, 0), ramp[HudArt.LIGHT]), "the top edge lit")
	check(_same(pen.at(0, h / 2), ramp[HudArt.LIGHT]), "the left edge lit")
	check(_same(pen.at(w / 2, h - 1), ramp[HudArt.BASE]), "the bottom edge in the base")
	check(_same(pen.at(w - 1, h / 2), ramp[HudArt.BASE]), "the right edge in the base")
	# One art pixel deep: everything inside the line is left to the fill.
	check(pen.image.get_region(Rect2i(2, 1, w - 4, h - 2)).is_invisible(), "nothing inside the line")
	check(pen.image.get_region(Rect2i(1, 2, w - 2, h - 4)).is_invisible(), "nothing inside the line's sides")
	check_equal(_strays(pen.image, _palette()), 0, "only palette colours")


func test_a_tile_is_two_art_pixels_deep_and_leaves_its_inside_to_what_it_holds() -> void:
	var pen := Recorder.new(Vector2i(10, 10))
	var lit: Color = HudArt.SPARK[HudArt.LIGHT]
	var base: Color = HudArt.SPARK[HudArt.BASE]
	HudArt.tile(pen, Rect2(0.0, 0.0, 10.0, 10.0), lit, base)
	check_equal(pen.off_grid, 0, "every rect of the tile on whole art pixels")
	check(_same(pen.at(0, 0), CLEAR), "the corner cut")
	check(_same(pen.at(1, 1), HudArt.OUTLINE), "the corner closed")
	check(_same(pen.at(10, 0), HudArt.OUTLINE), "outline on top")
	check(_same(pen.at(10, 1), lit), "lit on top")
	check(_same(pen.at(1, 10), lit), "lit on the left")
	check(_same(pen.at(10, 18), base), "base on the bottom")
	check(_same(pen.at(18, 10), base), "base on the right")
	# The inside, `rect.grow(-TILE_DEPTH)`, where a card's icon goes at one layout pixel in.
	var inside: Image = pen.image.get_region(Rect2i(2, 2, 16, 16))
	check(inside.is_invisible(), "the tile draws nothing inside")
	check_equal(_strays(pen.image, _palette()), 0, "only palette colours")


func test_a_dashed_tile_keeps_its_outline_whole_and_breaks_its_edge() -> void:
	var pen := Recorder.new(Vector2i(10, 10))
	var lit: Color = HudArt.SPARK[HudArt.LIGHT]
	HudArt.dashed_tile(pen, Rect2(0.0, 0.0, 10.0, 10.0), lit, HudArt.SPARK[HudArt.BASE])
	check_equal(pen.off_grid, 0, "every rect on whole art pixels")
	for x in range(2, 18):
		check(_same(pen.at(x, 0), HudArt.OUTLINE), "the outline whole at %d" % x)
	# Along the lit top: two art pixels drawn, two left out.
	var drawn: Array[bool] = []
	for x in range(2, 10):
		drawn.append(_same(pen.at(x, 1), lit))
	check_equal(drawn, [true, true, false, false, true, true, false, false] as Array[bool], "the top edge dashed two on, two off")
	var down: Array[bool] = []
	for y in range(2, 10):
		down.append(_same(pen.at(1, y), lit))
	check_equal(down, [true, true, false, false, true, true, false, false] as Array[bool], "the left edge dashed the same")
	check(_same(pen.at(1, 1), HudArt.OUTLINE) and _same(pen.at(18, 18), HudArt.OUTLINE), "the corners closed, never dashed")
	var odd := Recorder.new(Vector2i(5, 5))
	HudArt.dashed_tile(odd, Rect2(0.0, 0.0, 5.0, 5.0), lit, HudArt.SPARK[HudArt.BASE])
	check_equal(odd.off_grid, 0, "a width not a whole number of dashes: still whole art pixels")
	check(_same(odd.at(8, 1), HudArt.OUTLINE), "its last dash stops short of the closed corner")


func test_a_trough_is_sunk_under_an_outline_lip_and_its_fill_shaded_below() -> void:
	var pen := Recorder.new(Vector2i(8, 2))
	var track := Rect2(0.0, 0.0, 8.0, 2.0)
	HudArt.trough(pen, track, HudArt.STONE[HudArt.SHADOW])
	HudArt.line_fill(pen, HudArt.under_lip(Rect2(0.0, 0.0, 4.0, 2.0)), HudArt.MANA[HudArt.LIGHT], HudArt.MANA[HudArt.BASE])
	check_equal(pen.off_grid, 0, "every rect on whole art pixels")
	check(_same(pen.at(2, 0), HudArt.OUTLINE), "the lip over the fill")
	check(_same(pen.at(12, 0), HudArt.OUTLINE), "the lip over the track")
	check(_same(pen.at(2, 1), HudArt.MANA[HudArt.LIGHT]), "the fill under the lip")
	check(_same(pen.at(2, 3), HudArt.MANA[HudArt.BASE]), "the fill's bottom art row in its shade")
	check(_same(pen.at(12, 2), HudArt.STONE[HudArt.SHADOW]), "the track past the fill")


func test_a_part_too_small_for_its_depth_draws_nothing() -> void:
	var pen := Recorder.new(Vector2i(4, 4))
	HudArt.frame(pen, Rect2(0.0, 0.0, 1.0, 1.0), HudArt.STONE)
	HudArt.tile(pen, Rect2(0.0, 0.0, 1.5, 1.5), HudArt.STONE[HudArt.LIGHT], HudArt.STONE[HudArt.BASE])
	check_equal(_strays(pen.image, []), 0, "nothing drawn")


func test_every_seat_has_its_own_ramp_and_out_of_range_seats_are_clamped() -> void:
	var bases: Array[int] = []
	for seat in 4:
		var base: int = HudArt.player_ramp(seat)[HudArt.BASE].to_rgba32()
		check(not bases.has(base), "seat %d's base is its own" % seat)
		bases.append(base)
	check(HudArt.player_ramp(9) == HudArt.player_ramp(3), "a seat past 3 takes the last ramp")
	check(HudArt.player_ramp(-1) == HudArt.player_ramp(0), "a seat under 0 takes the first ramp")


## No background (the owner, 2026-11-27): the panel's style draws nothing, only keeps its margins.
func test_the_corner_panel_has_no_background_only_its_margins() -> void:
	var theme: Theme = load("res://hud/theme/spellmerge_theme.tres")
	var box: StyleBox = theme.get_stylebox("panel", PlayerPanelScript.OPEN_PANEL)
	check(box is StyleBoxEmpty, "the open panel's style draws nothing")
	check(box.get_content_margin(SIDE_LEFT) > 0.0 and box.get_content_margin(SIDE_TOP) > 0.0, "it keeps the panel's margins")


func test_a_corner_mark_is_an_outlined_l_in_the_players_ramp() -> void:
	var pen := Recorder.new(Vector2i(8, 8))
	var ramp: PackedColorArray = HudArt.player_ramp(1)
	HudArt.corner_mark(pen, Vector2.ZERO, ramp)
	var arm: int = int(HudArt.MARK_ARM * 2.0)
	check_equal(pen.off_grid, 0, "every rect on whole art pixels")
	check(_same(pen.at(0, 0), CLEAR), "its outer corner cut")
	check(_same(pen.at(arm / 2, 0), HudArt.OUTLINE) and _same(pen.at(0, arm / 2), HudArt.OUTLINE), "outlined on its outer edges")
	check(_same(pen.at(arm / 2, 1), ramp[HudArt.LIGHT]) and _same(pen.at(1, arm / 2), ramp[HudArt.LIGHT]), "lit on its top and left")
	check(_same(pen.at(arm / 2, 2), ramp[HudArt.BASE]) and _same(pen.at(2, arm / 2), ramp[HudArt.BASE]), "its base under and right of the light")
	check(_same(pen.at(arm / 2, 3), HudArt.OUTLINE) and _same(pen.at(arm - 1, 1), HudArt.OUTLINE), "closed inside and at its ends")
	check(_same(pen.at(arm / 2, arm / 2), CLEAR), "an L, nothing in its crook")
	check(_same(pen.at(arm, 1), CLEAR), "no longer than its arm")
	check_equal(_strays(pen.image, _palette()), 0, "only palette colours")


func test_a_trough_casts_a_hard_shadow_one_art_pixel_under_it() -> void:
	var pen := Recorder.new(Vector2i(8, 4))
	HudArt.trough(pen, Rect2(0.0, 0.0, 6.0, 2.0), HudArt.STONE[HudArt.SHADOW])
	check_equal(pen.off_grid, 0, "every rect on whole art pixels")
	check(_same(pen.at(0, 4), CLEAR), "no shadow under the first art pixel: it starts an art pixel in")
	check(_same(pen.at(6, 4), HudArt.OUTLINE) and _same(pen.at(12, 4), HudArt.OUTLINE), "the shadow under the trough and one past its end")
	check(_same(pen.at(6, 5), CLEAR), "one art pixel deep")


func test_a_drop_shadow_of_nothing_draws_nothing() -> void:
	var pen := Recorder.new(Vector2i(4, 4))
	HudArt.drop_shadow(pen, Rect2(1.0, 1.0, 0.0, 2.0))
	HudArt.drop_shadow(pen, Rect2(1.0, 1.0, 2.0, 0.0))
	check_equal(pen.off_grid, 0, "nothing off the grid")
	check(pen.image.is_invisible(), "nothing drawn")


## A meter (the menus' and the boss bar's lines, ART4 part 2): a trough filled to its share by
## whole layout pixels, the rest the track.
func test_a_meter_fills_its_trough_to_its_share_by_whole_layout_pixels() -> void:
	var pen := Recorder.new(Vector2i(12, 4))
	HudArt.meter(pen, Rect2(0.0, 0.0, 10.0, 3.0), 0.44, HudArt.FIRE[HudArt.BASE], HudArt.FIRE[HudArt.SHADOW])
	check_equal(pen.off_grid, 0, "every rect on whole art pixels")
	check(_same(pen.at(0, 0), HudArt.OUTLINE), "the lip")
	check(_same(pen.at(7, 1), HudArt.FIRE[HudArt.BASE]), "the fill to 4 layout pixels (0.44 of 10, rounded)")
	check(_same(pen.at(7, 5), HudArt.FIRE[HudArt.SHADOW]), "the fill's bottom art row in its shade")
	check(_same(pen.at(8, 1), HudArt.OUTLINE), "the track past the fill")
	check(_same(pen.at(5, 6), HudArt.OUTLINE), "the hard shadow under the trough")
	var empty := Recorder.new(Vector2i(12, 4))
	HudArt.meter(empty, Rect2(0.0, 0.0, 10.0, 3.0), -1.0, HudArt.FIRE[HudArt.BASE], HudArt.FIRE[HudArt.SHADOW])
	check(_same(empty.at(1, 2), HudArt.OUTLINE), "a share under 0 fills nothing")
	var full := Recorder.new(Vector2i(12, 4))
	HudArt.meter(full, Rect2(0.0, 0.0, 10.0, 3.0), 2.0, HudArt.FIRE[HudArt.BASE], HudArt.FIRE[HudArt.SHADOW])
	check(_same(full.at(19, 1), HudArt.FIRE[HudArt.BASE]), "a share over 1 fills it whole and no further")
	check(full.at(20, 1).a == 0.0, "nothing past the trough")


## A rule (where a box round a heading or a note was): one art pixel tall.
func test_a_rule_is_one_art_pixel_tall_and_nothing_when_it_has_no_width() -> void:
	var pen := Recorder.new(Vector2i(6, 2))
	HudArt.rule(pen, Vector2(1.0, 1.0), 4.0, HudArt.STONE[HudArt.BASE])
	check_equal(pen.off_grid, 0, "on whole art pixels")
	check(_same(pen.at(2, 2), HudArt.STONE[HudArt.BASE]) and _same(pen.at(9, 2), HudArt.STONE[HudArt.BASE]), "its art row")
	check(pen.at(2, 3).a == 0.0 and pen.at(10, 2).a == 0.0, "one art pixel tall, 4 layout pixels long")
	var none := Recorder.new(Vector2i(2, 2))
	HudArt.rule(none, Vector2.ZERO, 0.0, HudArt.STONE[HudArt.BASE])
	check_equal(_strays(none.image, []), 0, "a rule of no width draws nothing")
