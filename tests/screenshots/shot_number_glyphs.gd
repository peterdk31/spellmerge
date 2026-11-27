extends SceneTree
## The damage numbers drawn from their glyph sheets (`gameplay/feel/number_glyphs.gd`) against the
## font drawing them glyph by glyph, as they were drawn before (the performance pass, 2026-11-23):
## the same numbers (apart and over each other, three sizes, a heal, a spared hit, half faded) in two
## viewports, compared pixel for pixel (each glyph on a whole pixel in both, as the drawer puts
## them). Prints `NUMBER GLYPHS: N px differ` (by more than the blend's rounding) and saves both
## (`user://number_glyphs_sheet.png`, `user://number_glyphs_font.png`); quits 1 when any differ.
##
## Both are drawn at the font's art detail (the views ArtDetail.DETAIL times SIZE, their canvases
## scaled: the world at zoom 1), so every art pixel of a glyph is a pixel of each.
##
## godot --path . --script res://tests/screenshots/shot_number_glyphs.gd   (it needs a window)

const DrawerScript := preload("res://gameplay/feel/damage_number_drawer.gd")
const EventsScript := preload("res://core/events/events.gd")
const SIZE := Vector2i(480, 270)
const BACK := Color(0.2, 0.3, 0.25)
## A channel may differ by the rounding of the premultiplied blend (two steps of 255), no more.
const WITHIN: float = 2.5 / 255.0


## The numbers as the font draws them one by one: a number's outlines, then its glyphs and line.
class FontNumbers:
	extends Node2D
	var drawer: Node2D = null

	func _draw() -> void:
		var font: Font = ThemeDB.fallback_font
		var left: PackedFloat32Array = drawer.get(&"_left")
		var texts: PackedStringArray = drawer.get(&"_text")
		var sizes: PackedInt32Array = drawer.get(&"_font_size")
		var colours: PackedColorArray = drawer.get(&"_colour")
		var spared: PackedByteArray = drawer.get(&"_spared")
		var widths: PackedFloat32Array = drawer.get(&"_width")
		for slot in left.size():
			if left[slot] <= 0.0:
				continue
			var at: Vector2 = drawer.call(&"_at_of", slot)
			var alpha: float = drawer.call(&"_alpha_of", slot)
			var x: float = at.x
			for i in texts[slot].length():
				draw_char_outline(font, Vector2(roundf(x), at.y), texts[slot][i], sizes[slot], DrawerScript.OUTLINE, Color(DrawerScript.OUTLINE_COLOR, alpha))
				x += font.get_char_size(texts[slot].unicode_at(i), sizes[slot]).x
			var colour: Color = colours[slot]
			colour.a = alpha
			x = at.x
			for i in texts[slot].length():
				draw_char(font, Vector2(roundf(x), at.y), texts[slot][i], sizes[slot], colour)
				x += font.get_char_size(texts[slot].unicode_at(i), sizes[slot]).x
			if spared[slot] == 1:
				var y: float = at.y - roundf(float(sizes[slot]) * 0.35)
				draw_line(Vector2(at.x - 1.0, y), Vector2(at.x + widths[slot] + 1.0, y), colour, 1.0)


func _initialize() -> void:
	await process_frame
	var views: Array[SubViewport] = []
	for n in 2:
		var view := SubViewport.new()
		view.size = SIZE * ArtDetail.DETAIL
		view.canvas_transform = Transform2D.IDENTITY.scaled(Vector2.ONE * float(ArtDetail.DETAIL))
		view.disable_3d = true
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var back := ColorRect.new()
		back.color = BACK
		back.size = Vector2(SIZE)
		view.add_child(back)
		root.add_child(view)
		views.append(view)
	var drawer: DrawerScript = DrawerScript.new()
	views[0].add_child(drawer)
	var plain := FontNumbers.new()
	plain.drawer = drawer
	plain.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	views[1].add_child(plain)
	var kinds: Array[StringName] = [EventsScript.NUMBER_HIT, EventsScript.NUMBER_HEAL, EventsScript.NUMBER_SPARED]
	for n in 60:
		var size: float = [1.0, 1.5, 2.0][n % 3]
		var at := Vector2(30.0 + float(n % 12) * 36.0 + float(n % 5) * 3.0, 50.0 + float(n / 12) * 44.0 + float(n % 7))
		drawer.show_number(0, at, [12.0, 0.3, 1234.5, 7.0, 88.0][n % 5], &"", kinds[n % 3], 16.0, 0.4 + 0.1 * float(n % 6), size)
	drawer.step(0.0)
	# The sheets are drawn in the first frames; then the numbers part faded.
	for n in 3:
		await process_frame
	drawer.step(0.15)
	plain.queue_redraw()
	for n in 3:
		await process_frame
	var sheet: Image = views[0].get_texture().get_image()
	var font: Image = views[1].get_texture().get_image()
	sheet.save_png("user://number_glyphs_sheet.png")
	font.save_png("user://number_glyphs_font.png")
	var differ: int = 0
	var worst: float = 0.0
	var drawn: int = 0
	for y in SIZE.y:
		for x in SIZE.x:
			var a: Color = sheet.get_pixel(x, y)
			var b: Color = font.get_pixel(x, y)
			if absf(b.r - BACK.r) + absf(b.g - BACK.g) + absf(b.b - BACK.b) > 0.02:
				drawn += 1
			var d: float = maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
			if d > WITHIN:
				differ += 1
				worst = maxf(worst, d)
	print("NUMBER GLYPHS: %d px differ (worst %.1f of 255) of %d drawn" % [differ, worst * 255.0, drawn])
	quit(1 if differ > 0 or drawn == 0 else 0)
