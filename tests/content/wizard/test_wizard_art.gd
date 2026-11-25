extends "res://tests/support/suite.gd"
## The player's art is wired so the game can use it (living staffs H3): the wizard scene draws a
## floating staff (`StaffLook`, with a default head) and wears a `Face`; each starter head
## (content/wizard/staffs/curl, star, moon, crystal) has a head sheet of 48 world px frames (96 art px
## for a sheet at 2x detail, `ArtDetail`: the curl's since ART0), one column
## per direction and one row per ramp, with the player colour on the head only, so the four rows
## differ; and each brings its own personality and tip. The `dev` staff (owner,
## 2026-11-01: a head of its own, the cog) has a sheet of the same shape and a tip; its face style
## is free, as the four starters take the four player styles. How a head looks is free to change; these
## checks only hold the contract the look relies on.

const WizardScene := preload("res://content/wizard/base/wizard.tscn")
const RegistryScript := preload("res://core/registry/registry.gd")
const HEADS: Array[StringName] = [&"curl", &"star", &"moon", &"crystal"]
## Every staff with a head sheet: the starters and the dev staff (the premade builds').
const SHEETS: Array[StringName] = [&"curl", &"star", &"moon", &"crystal", &"dev"]
const OUTLINE: Color = Color("14121f")

var wizard: Node
var look: StaffLook


func before_each() -> void:
	wizard = own(WizardScene.instantiate()) as Node
	look = wizard.get_node_or_null(^"StaffLook") as StaffLook


func _heads(ids: Array[StringName] = HEADS) -> Array[StaffBase]:
	var registry: RegistryScript = own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var out: Array[StaffBase] = []
	for id in ids:
		out.append(registry.get_resource(&"wizard", id) as StaffBase)
	return out


func test_the_scene_draws_a_floating_staff_with_a_face() -> void:
	check(look != null, "the player's art is on its StaffLook node")
	check(look != null and look.default_head != null, "with a head for a staff that has none")
	check(wizard.get_node_or_null(^"Face") is Face, "the scene wears a Face")
	check(wizard.get_node_or_null(^"Sprite") is Sprite2D, "the body is the Sprite node")
	check(wizard.get_node_or_null(^"Sprite/Hat") == null, "and wears no hat")
	if look != null and wizard.get_node_or_null(^"Face") != null:
		check(look.get_index() < wizard.get_node(^"Face").get_index(), "the body's look steps (and draws) before the face")


func test_every_head_is_a_sheet_of_directions_by_ramp() -> void:
	for staff in _heads(SHEETS):
		check(staff != null and staff.head != null, "the staff has a head sheet")
		if staff == null or staff.head == null:
			continue
		var frame: int = StaffLook.FRAME_SIZE * ArtDetail.of(staff.head)
		check_equal(staff.head.get_width(), frame * StaffLook.DIRECTIONS, "%s: one column per direction" % staff.id)
		check_equal(staff.head.get_height(), frame * StaffLook.RAMPS, "%s: one row per ramp" % staff.id)


## The most common colour of a frame of `size` px (the outline apart).
func _main_colour(image: Image, column: int, row: int, size: int) -> Color:
	var counts: Dictionary = {}
	for y in size:
		for x in size:
			var pixel: Color = image.get_pixel(column * size + x, row * size + y)
			if pixel.a > 0.0 and not pixel.is_equal_approx(OUTLINE):
				counts[pixel] = int(counts.get(pixel, 0)) + 1
	var best: Color = Color.BLACK
	var most: int = 0
	for pixel: Color in counts:
		if int(counts[pixel]) > most:
			most = int(counts[pixel])
			best = pixel
	return best


## Rows differ only in the player colour: comparing each row's pixels with row 0's, some differ
## (the head) and most do not (the shaft, the grip).
func test_the_rows_differ_only_on_the_head() -> void:
	for staff in _heads(SHEETS):
		if staff == null or staff.head == null:
			continue
		var image: Image = staff.head.get_image()
		var size: int = StaffLook.FRAME_SIZE * ArtDetail.of(staff.head)
		for row in range(1, StaffLook.RAMPS):
			var same: int = 0
			var differ: int = 0
			for y in size:
				for x in size:
					var a: Color = image.get_pixel(x, y)
					var b: Color = image.get_pixel(x, row * size + y)
					if a.a == 0.0 and b.a == 0.0:
						continue
					if a.is_equal_approx(b):
						same += 1
					else:
						differ += 1
			check(differ > 0, "%s: ramp %d has its own colour" % [staff.id, row])
			check(same > differ, "%s: ramp %d shares the shaft with ramp 0" % [staff.id, row])
		check(_main_colour(image, 0, 0, size).a > 0.0, "%s: the first frame is drawn" % staff.id)


func test_the_dev_staff_brings_a_tip() -> void:
	var dev: StaffBase = _heads([&"dev"] as Array[StringName])[0]
	check(dev != null and dev.tip > 0.0, "dev: a tip")


func test_each_head_brings_a_tip_and_its_own_personality() -> void:
	var styles: Array[int] = []
	for staff in _heads():
		if staff == null:
			continue
		check(staff.tip > 0.0, "%s: a tip" % staff.id)
		check(not styles.has(staff.face_style), "%s: a face style of its own" % staff.id)
		styles.append(staff.face_style)


## The 64x64 redraw (ART0's pilot, ART1): every head is drawn at 2x detail; the curl wears its own
## face (the Optimist's at 2x), the others the shared face, itself at 2x since ART1.
func test_every_head_is_drawn_at_2x_and_the_curl_wears_a_face_of_its_own() -> void:
	var staffs: Array[StaffBase] = _heads()
	for staff in staffs:
		if staff == null:
			continue
		check_equal(ArtDetail.of(staff.head), 2, "%s: its head at 2x detail" % staff.id)
		if staff.id == &"curl":
			check(staff.face != null and staff.face.problems().is_empty(), "curl: a face of its own that can be drawn")
			if staff.face != null:
				check_equal(ArtDetail.of(staff.face.eyes), 2, "curl: its eyes at 2x")
				check_equal(ArtDetail.of(staff.face.brows), 2, "curl: its brows at 2x")
				check_equal(staff.face.frame, Face.FRAME, "curl: its face's frames the shared ones' (both at 2x)")
		else:
			check(staff.face == null, "%s: the shared face" % staff.id)