extends "res://tests/support/suite.gd"
## A staff's head as an icon (hud/widgets/staff_head.gd): the head's square of the up column, in
## the sheet's own pixels, so a sheet at 2x detail (ART1) shows the same part, twice as finely.

const StaffHead := preload("res://hud/widgets/staff_head.gd")


func test_the_head_s_square_is_taken_at_the_sheet_s_detail() -> void:
	var star: Texture2D = preload("res://content/wizard/staffs/star/head@2x.png")
	check_equal(StaffHead.source_of(star, 0), Rect2(1182.0, 12.0, 32.0, 32.0), "2x: the up column's head, 32x32")
	check_equal(StaffHead.source_of(star, 2), Rect2(1182.0, 204.0, 32.0, 32.0), "2x: ramp 3's row")
	var made := ImageTexture.create_from_image(Image.create(768, 192, false, Image.FORMAT_RGBA8))
	check_equal(StaffHead.source_of(made, 1), Rect2(591.0, 54.0, 16.0, 16.0), "1x: as it was")
