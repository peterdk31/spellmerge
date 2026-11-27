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


func test_a_frame_is_cut_at_its_corners_lit_top_left_and_shaded_bottom_right() -> void:
	var pen := Recorder.new(Vector2i(10, 8))
	var ramp: PackedColorArray = HudArt.player_ramp(0)
	HudArt.frame(pen, Rect2(0.0, 0.0, 10.0, 8.0), ramp)
	var w: int = 20
	var h: int = 16
	check_equal(pen.off_grid, 0, "every rect of the frame on whole art pixels")
	# The outer corners are cut, and the art pixel inside each closes the outline.
	for corner: Vector2i in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
		check(_same(pen.at(corner.x, corner.y), CLEAR), "corner %s cut" % corner)
	for corner: Vector2i in [Vector2i(1, 1), Vector2i(w - 2, 1), Vector2i(1, h - 2), Vector2i(w - 2, h - 2)]:
		check(_same(pen.at(corner.x, corner.y), HudArt.OUTLINE), "corner %s closed by the outline" % corner)
	# The outline along each side, then the light top and left, the shade bottom and right, the
	# base, and the inner outline; the inside left alone.
	check(_same(pen.at(w / 2, 0), HudArt.OUTLINE), "outline on top")
	check(_same(pen.at(w - 1, h / 2), HudArt.OUTLINE), "outline on the right")
	check(_same(pen.at(w / 2, 1), ramp[HudArt.LIGHT]), "the top edge lit")
	check(_same(pen.at(1, h / 2), ramp[HudArt.LIGHT]), "the left edge lit")
	check(_same(pen.at(w / 2, h - 2), ramp[HudArt.SHADOW]), "the bottom edge shaded")
	check(_same(pen.at(w - 2, h / 2), ramp[HudArt.SHADOW]), "the right edge shaded")
	check(_same(pen.at(w / 2, 2), ramp[HudArt.BASE]), "the base inside the lit edge")
	check(_same(pen.at(w - 3, h / 2), ramp[HudArt.BASE]), "the base inside the shaded edge")
	check(_same(pen.at(w / 2, 3), HudArt.OUTLINE), "the inner outline")
	check(_same(pen.at(w / 2, h / 2), CLEAR), "the inside left to the fill")
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
	HudArt.frame(pen, Rect2(0.0, 0.0, 4.0, 4.0), HudArt.STONE)
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


func test_the_corner_panel_takes_the_framed_panel_fill_from_the_theme() -> void:
	var theme: Theme = load("res://hud/theme/spellmerge_theme.tres")
	var box := theme.get_stylebox("panel", PlayerPanelScript.FRAMED_PANEL) as StyleBoxFlat
	check(box != null, "the theme has the framed panel's fill")
	if box == null:
		return
	check(box.bg_color.a < 1.0, "the fill is see-through, as the panel's was")
	check_equal(box.border_width_left + box.border_width_top + box.border_width_right + box.border_width_bottom, 0, "no border of its own: the frame is drawn at the art's detail")
	check_equal(box.expand_margin_left, -HudArt.A, "the fill stops inside the frame's cut corners")
