extends "res://tests/support/screenshot.gd"
## The flash kinds drawn with flash kinds F4's drawings (docs/milestones/flash-kinds.md): a star,
## rays, a ring of dots and a spiral, as data (content/flashes), for the owner to pick from. A row
## per infusion (plain, fire, frost, lightning; the real cards' colours and looks), a column per
## kind at an age (a third and two thirds of its life), at zoom 2:
##   1-2  `star` (4 points)       3-4  `star_six`
##   5-6  `rays_out`              7-8  `rays_in`
##   9-10 `dot_ring`             11-12 `spiral`
## `flash_drawings_sheet` at 1x, `flash_drawings_sheet_4x` (the stars and rays out, plain and fire)
## and `flash_drawings_sheet_4x_b` (rays in, the dots and the spiral).

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ELEMENTS: Array[Resource] = [
	preload("res://content/spells/elements/fire/fire.tres"),
	preload("res://content/spells/elements/frost/frost.tres"),
	preload("res://content/spells/elements/lightning/lightning.tres"),
]
const KINDS: Array[StringName] = [&"star", &"star_six", &"rays_out", &"rays_in", &"dot_ring", &"spiral"]
## Where in its life each column shows its kind.
const AGES: Array[float] = [0.33, 0.66]
const COLUMN: float = 50.0
const ROW: float = 56.0
const ZOOM: int = 2


func take() -> void:
	if not need(["Feel"]):
		return
	var feel: Node = root.get_node("Feel")
	# On game time each frame is 1/60 s, so the ages are exact however slow the display is.
	feel.set("drive_engine", false)
	lay_floor()
	await settle()
	var image: Image = await _sheet(feel)
	if image == null:
		return
	save(image, "flash_drawings_sheet")
	save_crop(image, Vector2(40.0 + 2.5 * COLUMN, 40.0 + 0.5 * ROW), "flash_drawings_sheet_4x", Vector2i(int(3.0 * COLUMN), int(ROW)))
	save_crop(image, Vector2(40.0 + 8.5 * COLUMN, 40.0 + 0.5 * ROW), "flash_drawings_sheet_4x_b", Vector2i(int(3.0 * COLUMN), int(ROW)))


## Show every column (each kind started so it is its age in the same frame) and grab it.
func _sheet(feel: Node) -> Image:
	var frames: Array[int] = []
	var oldest: int = 0
	for kind: StringName in KINDS:
		var seconds: float = (feel.call("flash_kind", kind) as FlashKind).seconds
		for age: float in AGES:
			frames.append(maxi(roundi(seconds * age * 60.0), 1))
			oldest = maxi(oldest, frames.back())
	for left in range(oldest, 0, -1):
		for c in frames.size():
			if frames[c] != left:
				continue
			var kind: StringName = KINDS[c / AGES.size()]
			var seconds: float = (feel.call("flash_kind", kind) as FlashKind).seconds
			for e in ELEMENTS.size() + 1:
				var tint: Color = Color.WHITE if e == 0 else ELEMENTS[e - 1].get("tint") as Color
				var look: int = 0 if e == 0 else ManagerScript.pack_look(PackedInt32Array([int(ELEMENTS[e - 1].get("look_layer"))]))
				var at := Vector2(40.0 + c * COLUMN, 40.0 + e * ROW)
				feel.call("show_flash", kind, at, Vector2.RIGHT, tint, e % 4, look, ZOOM, seconds)
		await process_frame
	var image: Image = await grab()
	if int(feel.call("live_flashes")) < frames.size() * (ELEMENTS.size() + 1):
		fail("only %d flashes are showing" % int(feel.call("live_flashes")))
		return null
	return image
