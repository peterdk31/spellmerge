extends "res://tests/support/screenshot.gd"
## Screenshots of motes (gameplay/feel/mote.gd; docs/milestones/spell-spectacle.md, P1a), as the
## game makes them: one column for each element card (a shot of its look layer and tint sheds
## its motes, `Motes.shed`, in their shapes), one for a plain shot of player 1, and the crypt arena's walls' chips
## in the colours sampled from its art (`RoomBase.surface_colors`). Each row is the same bursts
## 0.05, 0.12, 0.3, 0.8 and 1.8 s after they were thrown, at 2x (`motes_kinds`). The pool runs on a
## clock of its own, with the content's kinds.

const MotesScript := preload("res://gameplay/feel/mote.gd")
const TIMES: Array[float] = [0.05, 0.12, 0.3, 0.8, 1.8]
const ROW_TOP: int = 120
const ROW_HEIGHT: int = 110
const BORN: float = 1.0
const Y: float = 200.0
## Each burst this many times its kind's count, so the sheet shows its spread.
const SCALE: float = 4.0


func take() -> void:
	if not need(["Registry"]):
		return
	var registry: Node = root.get_node("Registry")
	lay_floor()
	var kinds: Array[MoteKind] = []
	for found: Resource in registry.call("get_all", &"motes"):
		kinds.append(found as MoteKind)
	var motes: MotesScript = MotesScript.new(8192, 0, kinds)
	root.add_child(motes)
	motes.step(BORN)
	var shots: Array[Array] = []
	for found: Resource in registry.call("get_all", &"spells"):
		var element := found as ElementBase
		if element != null and element.look_layer > 0:
			shots.append([element.tint, 1 << (element.look_layer - 1)])
	shots.append([Color.WHITE, 0])
	var column: float = SCREEN.x / float(shots.size() + 1)
	var x: float = column * 0.5
	for shot: Array in shots:
		motes.shed(Vector2(x, Y), Vector2.UP, shot[0] as Color, 0, int(shot[1]), SCALE)
		x += column
	# A wall to the right of a plain bolt of player 1: its motes and the wall's chips, back off it.
	var room := registry.call("get_resource", &"rooms", &"arena_01") as RoomBase
	if room == null:
		fail("the crypt arena is needed for its wall colours")
		return
	var source: int = motes.table_source(room.surface_colors())
	for k in motes.surface_kinds():
		motes.throw(k, Vector2(x, Y), Vector2.LEFT, source, Color.WHITE, SCALE * 0.5)
	motes.shed(Vector2(x, Y), Vector2.LEFT, Color.WHITE, 0, 0)
	var sheet := Image.create_empty(int(SCREEN.x), ROW_HEIGHT * TIMES.size(), false, Image.FORMAT_RGBA8)
	for i in TIMES.size():
		motes.step(BORN + TIMES[i])
		await settle(3)
		var image: Image = await grab()
		image.convert(Image.FORMAT_RGBA8)
		var scale_to_image: float = float(image.get_width()) / SCREEN.x
		var region: Image = image.get_region(Rect2i(0, int(ROW_TOP * scale_to_image), image.get_width(), int(ROW_HEIGHT * scale_to_image)))
		region.resize(int(SCREEN.x), ROW_HEIGHT, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(region, Rect2i(Vector2i.ZERO, region.get_size()), Vector2i(0, ROW_HEIGHT * i))
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	save(sheet, "motes_kinds")
